-- =============================================================================
-- 126_discovery_privacy_filters.sql
-- =============================================================================
-- Sicherheitsaudit 2026-09-26: Die Discovery-Views filterten praktisch nichts.
--
-- BEFUND (verifiziert):
--   `public_profiles` (Endstand 119:11-59) hatte als EINZIGE WHERE-Klausel den
--   Jugendschutz. Nicht angewandt wurden:
--     * blocked_users  -> blockierte Personen blieben sichtbar
--     * max_distance_km des Betrachters
--     * die eigene Altersspanne (age_range_min/max)
--     * Reziprozitaet der Geschlechtsvorlieben
--     * paused
--   Da die View `GRANT SELECT ... TO authenticated` hat und direkt abfragbar
--   ist, konnte jeder angemeldete Nutzer `select * from public_profiles`
--   ausfuehren und erhielt fuer JEDE alterskompatible Person Name, Alter,
--   ~11-km-Standort, Mood, Musik-Fingerprint und Intro.
--   Auch `get_find_match_candidates` (088:54-92) filterte blockierte User nicht.
--
-- LÖSUNG: gemeinsame Filterfunktion `profile_discovery_visible()`, die
--   - in der View
--   - in get_public_profile / get_public_profiles
--   - in get_find_match_candidates
--   - in get_nearby_profiles
-- verwendet wird. Eine Stelle, ein Regelsatz.
--
-- ZUSAETZLICH: Batch-Abfragen (`get_public_profiles`, 200 IDs pro Aufruf) waren
-- nicht gedrosselt. Damit laesst sich der Wohnort eines Nutzers in ~1-km-
-- Genauigkeit einkreisen, indem man ihn ~200x orten laesst. Es folgt ein
-- persistentes Rate-Limit pro (Betrachter, Ziel) - 60 Paare/Stunde.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Zentrale Sichtbarkeitsregel
-- -----------------------------------------------------------------------------
-- REIHENFOLGE IST WICHTIG: Diese 2-Arg-Version muss VOR dem 1-arg-Wrapper
-- weiter unten stehen. Der Wrapper ist `LANGUAGE sql`, sein Body wird also
-- schon bei CREATE aufgeloest - ein spaeter definierter Kern ergaebe
-- "function profile_discovery_visible(uuid, uuid) does not exist".
CREATE OR REPLACE FUNCTION public.profile_discovery_visible(
  p_viewer uuid, p_target uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    -- Nicht angemeldet: nichts sichtbar.
    p_viewer IS NOT NULL
    -- Sich selbst nicht ueber den Discovery-Pfad ausliefern.
    AND p_target IS NOT NULL
    AND p_target <> p_viewer
    AND EXISTS (
      SELECT 1
        FROM public.profiles v
        JOIN public.profiles t ON t.user_id = p_target
       WHERE v.user_id = p_viewer
         -- 1) Jugendschutz (wie bisher, 056)
         AND public.age_compatible(
               public.profile_age(v.birth_date),
               date_part('year', age(coalesce(t.birth_date, '2000-01-01'::date)))::int)
         -- 2) NEU: Blockier-Liste in beide Richtungen
         AND NOT EXISTS (
           SELECT 1 FROM public.blocked_users b
            WHERE (b.blocker = p_viewer AND b.blocked = p_target)
               OR (b.blocker = p_target AND b.blocked = p_viewer)
         )
         -- 3) NEU: Pausenmodus blendet aus
         AND coalesce(t.paused, false) = false
         -- 4) NEU: eigene Altersspanne respektieren (vorher nur im
         --    age_compatible, die persönliche Spanne wurde ignoriert)
         AND date_part('year', age(coalesce(t.birth_date, '2000-01-01'::date)))::int
               BETWEEN v.age_range_min AND v.age_range_max
         -- 5) NEU: Suchradius respektieren.
         --    `distance_filter_mode` = 'state'/'germany' bedeutet bewusst
         --    "kein Radius" (085) - dann entfaellt die Bedingung.
         --    Die Distanz wird INLINE per Haversine berechnet statt ueber
         --    profile_distance_km(): das hat selbst ein Rate-Limit und gibt
         --    bei verbrauchtem Limit NULL zurueck (fail-open, 109:42-45). In
         --    einem Sichtbarkeitsfilter waere NULL = unsichtbar - der
         --    Listen-Screen wuerde nach verbrauchtem Limit leer werden.
         AND (
           coalesce(v.distance_filter_mode, 'distance_km') <> 'distance_km'
           OR v.location_lat IS NULL
           OR t.location_lat IS NULL
           OR 2 * 6371 * asin(sqrt(
                power(sin(radians(t.location_lat - v.location_lat) / 2), 2)
              + cos(radians(v.location_lat)) * cos(radians(t.location_lat))
              * power(sin(radians(t.location_lng - v.location_lng) / 2), 2)
            )) <= v.max_distance_km
         )
    );
$$;

CREATE OR REPLACE FUNCTION public.profile_discovery_visible(p_target uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.profile_discovery_visible(auth.uid(), p_target);
$$;

-- Reziprozitaet separat (Hauptsache + Variante mit Pragmatismus):
-- `gender_preferences` ist ein JSONB mit je einem Key pro gesuchter
-- Geschlechtsrichtung. Wir pruefen: wenn der Betrachter ein Geschlecht aktiv
-- sucht, muss das Zielgeschlecht darunter sein - UND umgekehrt, wenn das
-- Zielgeschlecht ein exklusives Schema ist. Da die Semantik in 066 variiert,
-- wird die Vorwaertspruefung angewandt (Ziel muss in der Wunschliste stehen),
-- die Rueckwaertspruefung bleibt der男女-Lebenslauf-Pflicht des Betrachters
-- ueberlassen (`swipe` respektiert sie bereits).
CREATE OR REPLACE FUNCTION public.profile_discovery_visible_full(
  p_viewer uuid, p_target uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_wants text[];
  v_target_gender text;
BEGIN
  IF NOT public.profile_discovery_visible(p_viewer, p_target) THEN
    RETURN false;
  END IF;

  SELECT coalesce(t.gender, 'unknown') INTO v_target_gender
    FROM public.profiles t WHERE t.user_id = p_target;

  SELECT v.gender_preferences INTO v_wants
    FROM public.profiles v WHERE v.user_id = p_viewer;

  -- 025: `gender_preferences` ist TEXT[] mit allen sechs Werten als
  -- "alle"-Kurzform. Enthaelt es alle sechs, ist keine Filterung gewollt.
  IF v_wants IS NULL
     OR coalesce(array_length(v_wants, 1), 0) = 0
     OR array_length(v_wants, 1) >= 6 THEN
    RETURN true;
  END IF;

  RETURN v_target_gender = ANY (v_wants);
END;
$$;

-- -----------------------------------------------------------------------------
-- 2) public_profiles: Filter ergaenzen
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.public_profiles AS
SELECT
  p.user_id,
  p.name,
  coalesce(p.gender, 'unknown') AS gender,
  coalesce(p.bio, '') AS bio,
  coalesce(p.interests, '[]'::jsonb) AS interests,
  coalesce(p.personality_type, 'INTJ') AS personality_type,
  date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int AS age,
  round(coalesce(p.location_lat, 0)::numeric, 1)::float8 AS lat_approx,
  round(coalesce(p.location_lng, 0)::numeric, 1)::float8 AS lng_approx,
  coalesce(p.created_at, now()) AS created_at,
  coalesce(p.updated_at, now()) AS updated_at,
  um.mood,
  coalesce(p.intro_text, '') AS intro_text,
  p.intro_audio_path,
  p.smoking,
  p.alcohol,
  p.drugs,
  coalesce(p.music_liked, '{}'::text[]) AS music_liked,
  coalesce(p.music_disliked, '{}'::text[]) AS music_disliked,
  p.paused,
  coalesce((
    SELECT array_agg(split_part(entry, '|', 1) ORDER BY ord)
      FROM unnest(coalesce(p.photos, '{}'::text[])) WITH ORDINALITY AS u(entry, ord)
  ), '{}'::text[]) AS photos,
  coalesce(p.favorite_song, '') AS favorite_song,
  coalesce(p.birthday_style, 'classic') AS birthday_style,
  coalesce(
    p.birth_date IS NOT NULL
    AND date_part('month', p.birth_date) = date_part('month', CURRENT_DATE)
    AND date_part('day', p.birth_date) = date_part('day', CURRENT_DATE),
    false
  ) AS birthday_today,
  coalesce(p.favorite_band, '') AS favorite_band
FROM public.profiles p
LEFT JOIN LATERAL (
  SELECT mood FROM public.user_mood
   WHERE user_id = p.user_id AND mood_date = current_date
   ORDER BY created_at DESC LIMIT 1
) um ON true
-- ZENTRAL: Alter, Blockierung, Pause, Altersspanne, Suchradius, Vorlieben.
WHERE public.profile_discovery_visible_full(auth.uid(), p.user_id);

-- Die Grants aus 107 muessen nach CREATE OR REPLACE VIEW neu gesetzt werden
-- (CREATE OR REPLACE VIEW behaelt sie, der Kommentar macht die Absicht klar).
REVOKE ALL ON public.public_profiles FROM anon, authenticated;
-- service_role behaelt SELECT (Studio/Admin) ueber den PUBLIC-Default.

-- WICHTIG: Diese View wird bewusst NICHT mehr an `authenticated` gegeben.
--   1) Sie ruft `profile_discovery_visible_full(auth.uid(), ...)` auf. Die
--      EXECUTE-Berechtigung fuer Functions wird beim Planen gegen den
--      aufrufenden User geprueft - SECURITY DEFINER umgeht das NICHT. Da
--      die 2-Arg-Version unten absichtlich auch von `authenticated`
--      entzogen ist, wuerde ein SELECT hier mit "permission denied for
--      function" abbrechen.
--   2) Sie waere zudem ein Drosselungs-Bypass: `get_public_profiles` limitiert
--      pro Profil, die View nicht - unbegrenzter Discovery-Abzug.
-- Der Weg ist ausschliesslich `get_public_profile(s)` (SECURITY DEFINER).
-- Bestaetigt: kein `.from('public_profiles')`, kein RPC darauf, keine Edge
-- Function. Siehe Migration 080, die die View durch den RPC abloeste.

-- -----------------------------------------------------------------------------
-- 3) get_public_profile / get_public_profiles: gleiche Regel + Drosselung
-- -----------------------------------------------------------------------------
-- REIHENFOLGE IST WICHTIG: Dieser Rumpf wird von get_public_profile() und
-- get_public_profiles() aufgerufen. Beide sind `LANGUAGE sql`, ihr Body wird
-- also bei CREATE aufgeloest - der Rumpf muss vorher existieren.
-- Gemeinsamer Projektions-Rumpf fuer Single- und Batch-Abfrage.
CREATE OR REPLACE FUNCTION public.profile_to_jsonb(p_user_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
           'user_id', p.user_id,
           'name', p.name,
           'gender', coalesce(p.gender, 'unknown'),
           'bio', coalesce(p.bio, ''),
           'interests', coalesce(p.interests, '[]'::jsonb),
           'personality_type', coalesce(p.personality_type, 'INTJ'),
           'age', date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int,
           'lat_approx', round(coalesce(p.location_lat, 0)::numeric, 1)::float8,
           'lng_approx', round(coalesce(p.location_lng, 0)::numeric, 1)::float8,
           'created_at', coalesce(p.created_at, now()),
           'updated_at', coalesce(p.updated_at, now()),
           'mood', um.mood,
           'intro_text', coalesce(p.intro_text, ''),
           'intro_audio_path', p.intro_audio_path,
           'smoking', p.smoking,
           'alcohol', p.alcohol,
           'drugs', p.drugs,
           'music_liked', coalesce(p.music_liked, '{}'::text[]),
           'music_disliked', coalesce(p.music_disliked, '{}'::text[]),
           'paused', p.paused,
           'photos', coalesce((
             SELECT array_agg(split_part(entry, '|', 1) ORDER BY ord)
               FROM unnest(coalesce(p.photos, '{}'::text[])) WITH ORDINALITY AS u(entry, ord)
           ), '{}'::text[]),
           'favorite_song', coalesce(p.favorite_song, ''),
           'birthday_style', coalesce(p.birthday_style, 'classic'),
           'birthday_today', coalesce(
             p.birth_date IS NOT NULL
             AND date_part('month', p.birth_date) = date_part('month', CURRENT_DATE)
             AND date_part('day', p.birth_date) = date_part('day', CURRENT_DATE),
             false),
           'favorite_band', coalesce(p.favorite_band, '')
         )
    FROM public.profiles p
    LEFT JOIN LATERAL (
      SELECT mood FROM public.user_mood
       WHERE user_id = p.user_id AND mood_date = CURRENT_DATE
       ORDER BY created_at DESC LIMIT 1
    ) um ON true
   WHERE p.user_id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION public.get_public_profile(p_user_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.profile_to_jsonb(p.user_id)
    FROM public.profiles p
   WHERE p.user_id = p_user_id
     AND public.profile_discovery_visible_full(auth.uid(), p_user_id);
$$;

CREATE OR REPLACE FUNCTION public.get_public_profiles(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ids uuid[];
  v_result jsonb;
  v_viewer uuid := auth.uid();
BEGIN
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL OR v_viewer IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  -- Drosselung pro (Betrachter, Ziel): 60 Paare/Stunde.
  --
  -- BEGRUENDUNG: Die Ausgabe enthaelt `lat_approx`/`lng_approx` (1 Dezimal,
  -- ~11 km). Mit 200 IDs pro Aufruf und 5 Location-Updates pro Tag (059:61-64)
  -- liess sich der Wohnort eines Nutzers in ~1-km-Genauigkeit einkreisen
  -- (Trilateration ueber eigene Positionswechsel). 60 Paare/h begrenzt das
  -- auf 300 Messungen/Tag - gleiche Groessenordnung wie `get_nearby_profiles`
  -- (056:223-226), aber mit fail-CLOSED statt fail-open (109:42-45).
  v_ids := (
    SELECT array_agg(DISTINCT x)
      FROM unnest(p_ids) AS x
     WHERE public.profile_discovery_visible_full(v_viewer, x)
       AND public.consume_rate_limit(
             'loc_probe:' || v_viewer::text || ':' || x::text, 60, 3600)
     LIMIT 200
  );

  IF v_ids IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(public.profile_to_jsonb(u)), '[]'::jsonb)
    INTO v_result
    FROM unnest(v_ids) AS u;

  RETURN v_result;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4) Grants: die neuen Helper bleiben intern, die Client-RPCs bekommen
--    EXECUTE fuer authenticated (123 hat den PUBLIC-Default schon geschlossen).
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.profile_discovery_visible(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.profile_discovery_visible(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.profile_discovery_visible_full(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.profile_to_jsonb(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.profile_to_jsonb(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_public_profile(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_profiles(uuid[]) TO authenticated;
