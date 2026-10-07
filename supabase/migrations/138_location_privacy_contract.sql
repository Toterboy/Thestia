-- =============================================================================
-- 138_location_privacy_contract.sql
-- =============================================================================
-- DER LETZTE SCHRITT der Standort-Privatisierung (v0.9.3).
--
-- BEFUND vor diesem Schritt (verifiziert im Quelltext, Migration 133-137):
--
--   profile_locations war privat und gerastert. Aber die ALTEN Spalten
--   existierten weiter:
--
--     profiles.city          - der Ortsname, fuer jeden angemeldeten
--                              Nutzer ueber PostgREST lesbar
--     profiles.location_lat  - auf ~1,1 km gerundet (Guard aus 059),
--     profiles.location_lng    immer noch ~110 m genau
--
--   Und sie wurden aktiv befuellt: die Edge Function
--   process-location-check schrieb bei jedem GPS-Knopf dorthin, die
--   Rasterung passierte erst beim Lesen.
--
--   Dazu kam die Ausgabeseite: public_profiles lieferte lat_approx/
--   lng_approx (1 Dezimal, ~11 km), profile_to_jsonb ebenso, und
--   get_nearby_profiles gab lat_approx/lng_approx pro Person zurueck.
--
-- WARUM DAS NICHT DURCH RLS ZU LOESEN IST:
--
--   Die RLS auf profiles entscheidet ueber ZEILEN, nicht ueber SPALTEN.
--   Die bestehende Policy ist sehr weit (qual: true fuer gematchte
--   Nutzer). Eine Spalte, die in der Tabelle liegt, ist fuer alle
--   sichtbar, die die Zeile sehen. Spaltenweise Sichtbarkeit gibt es in
--   Postgres nicht - nur eine View ohne die Spalte, und genau das ist
--   der Trick unten.
--
-- LOESUNG:
--
--   1. Alle Ausgaben (public_profiles, profile_to_jsonb,
--      get_nearby_profiles) verlieren die Koordinaten-Spalten ersatzlos.
--      Kein Ersatzwert, kein NULL-Feld - das Feld existiert danach nicht
--      mehr, damit kein Client eine Altlast erwartet.
--   2. Die Entfernungsberechnung liest aus profile_locations.
--   3. Die Entfernung wird nur ausgegeben, wenn die ANDERE PERSON dem
--      zugestimmt hat (profiles.show_distance, Default false). Wer nicht
--      zugestimmt hat, bekommt NULL - nicht "0 km", nicht eine
--      Restentfernung ueber das Bundesland.
--   4. profile_discovery_visible() liest seinen Radius-Filter aus
--      profile_locations. Sonst waere nach dem Drop jede Person fuer
--      jeden sichtbar, egal wie weit weg.
--   5. handle_new_user() legt keine Koordinaten mehr an.
--   6. Die Quiz-Frage fragt nach dem Bundesland statt nach der Stadt.
--   7. Der Guard auf profiles wird abgeraeumt (137 hat den Ersatz).
--   8. ERST DANACH werden city/location_lat/location_lng gedroppt.
--
-- REIHENFOLGE ZWINGEND: Die Funktionen kommen VOR dem Drop. Wuerde man
-- zuerst droppen, waere die ganze Migration in einer Transaktion
-- zurueckgerollt und man wuesste nicht, welche Funktion defekt ist.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) handle_new_user: ohne Koordinaten anlegen
--
--    Der Trigger lief beim Anlegen mit location_lat/location_lng = NULL.
--    Nach dem Drop waer das ein Fehler, der JEDE Registrierung bricht -
--    also zuerst die Definition anpassen.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path TO pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.profiles (
    user_id,
    name,
    gender,
    gender_preference,
    birth_date,
    bio,
    interests,
    personality_type,
    max_distance_km,
    age_range_min,
    age_range_max
  ) VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'name', 'Unbekannt'),
    COALESCE(NEW.raw_user_meta_data ->> 'gender', 'unknown'),
    'all',
    COALESCE(
      (NEW.raw_user_meta_data ->> 'birth_date')::date,
      '2000-01-01'::date
    ),
    '',
    '[]'::jsonb,
    'INTJ',
    100,
    18,
    99
  );
  RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2) profile_distance_km: aus profile_locations, mit Einwilligung
--
--    Verhalten:
--      * kein Login / sich selbst / kein Standort        -> NULL
--      * andere Person hat NICHT zugestimmt              -> NULL
--      * beide Standorte bekannt                         -> km, 5er gerundet
--
--    Die Einwilligungs-Pruefung kommt VOR der Berechnung. Wer nicht
--    zugestimmt hat, soll nicht einmal eine Distanz berechnet bekommen -
--    das waere ein Rechenpfad, den man sonst nur durch Raten ausschalten
--    koennte.
--
--    Das Rate-Limit aus 109 bleibt unveraendert: 60 Paare/Stunde.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.profile_distance_km(p_other uuid)
RETURNS double precision
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path to 'public', 'pg_temp'
AS $function$
DECLARE
  v_distance float8;
BEGIN
  IF auth.uid() IS NULL OR p_other IS NULL OR p_other = auth.uid() THEN
    RETURN NULL;
  END IF;

  -- Trilaterations-Schutz: wiederholte Abfragen gegen dasselbe Opfer.
  -- FAIL-OPEN (109): kein Exception, nur NULL - der Rest der Seite
  -- funktioniert weiter.
  IF NOT public.consume_rate_limit(
       'dist_pair:' || auth.uid()::text || ':' || p_other::text, 60, 3600) THEN
    RETURN NULL;
  END IF;

  -- Einwilligung der ANDEREN Person. Ohne sie: keine Auskunft.
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles o
     WHERE o.user_id = p_other
       AND o.show_distance
  ) THEN
    RETURN NULL;
  END IF;

  SELECT (round((6371 * acos(least(1.0,
             cos(radians(me.lat)) * cos(radians(o.lat))
             * cos(radians(o.lng) - radians(me.lng))
             + sin(radians(me.lat)) * sin(radians(o.lat))
           ))) / 5.0) * 5)::float8
    INTO v_distance
    FROM public.profile_locations me
    JOIN public.profile_locations o ON o.user_id = p_other
   WHERE me.user_id = auth.uid();

  RETURN v_distance;
END;
$function$;

REVOKE ALL ON FUNCTION public.profile_distance_km(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.profile_distance_km(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 3) profile_discovery_visible: Radius aus profile_locations
--
--    Sonst waere der Radiusfilter nach dem Drop wirkungslos (die Spalten
--    existieren nicht mehr) und JEDE alterskompatible Person waere fuer
--    JEDEN sichtbar - der groesste Privacy-Regress, den dieser Schritt
--    ausloesen koennte, und er faellt nicht auf, weil die Liste dann nur
--    "zu voll" aussieht.
--
--    Verhalten bleibt: NULL-Standort heisst "kein Filter" (nicht
--    unsichtbar) - sonst waeren alle Accounts ohne GPS unsichtbar.
-- -----------------------------------------------------------------------------
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
    p_viewer IS NOT NULL
    AND p_target IS NOT NULL
    AND p_target <> p_viewer
    AND EXISTS (
      SELECT 1
        FROM public.profiles v
        JOIN public.profiles t ON t.user_id = p_target
        -- LATERAL statt EXISTS-Unterabfrage: die Entfernung braucht die
        -- Koordinaten im SELBEN Ausdruck. Ein "NOT EXISTS (...) OR
        -- haversine(vl.lat, tl.lat)" funktioniert nicht - vl/tl waeren
        -- nur innerhalb ihrer eigenen Unterabfrage sichtbar. Genau das
        -- hat den ersten Push dieser Migration mit "missing FROM-clause
        -- entry for table tl" abbrechen lassen.
        LEFT JOIN LATERAL (
          SELECT lat, lng FROM public.profile_locations WHERE user_id = v.user_id
        ) vl ON true
        LEFT JOIN LATERAL (
          SELECT lat, lng FROM public.profile_locations WHERE user_id = t.user_id
        ) tl ON true
       WHERE v.user_id = p_viewer
         AND public.age_compatible(
               public.profile_age(v.birth_date),
               date_part('year', age(coalesce(t.birth_date, '2000-01-01'::date)))::int)
         AND NOT EXISTS (
               SELECT 1 FROM public.blocked_users b
                WHERE (b.blocker = p_viewer AND b.blocked = p_target)
                   OR (b.blocker = p_target AND b.blocked = p_viewer)
             )
         AND coalesce(t.paused, false) = false
         AND date_part('year', age(coalesce(t.birth_date, '2000-01-01'::date)))::int
               BETWEEN v.age_range_min AND v.age_range_max
         AND (
           coalesce(v.distance_filter_mode, 'distance_km') <> 'distance_km'
           -- fehlender Standort heisst "kein Filter", nicht "unsichtbar"
           OR vl.lat IS NULL OR tl.lat IS NULL
           OR 2 * 6371 * asin(sqrt(
                power(sin(radians(tl.lat - vl.lat) / 2), 2)
              + cos(radians(vl.lat)) * cos(radians(tl.lat))
              * power(sin(radians(tl.lng - vl.lng) / 2), 2)
            )) <= v.max_distance_km
         )
    );
$$;

-- -----------------------------------------------------------------------------
-- 4) public_profiles: ohne lat_approx/lng_approx
--
--    Die View wird von get_find_match_candidates per `select p.*`
--    konsumiert, durch das Entfernen der Spalten verschwinden sie auch
--    dort aus der Antwort. Das ist beabsichtigt - `p.*` ist die groesste
--    Einzelschleuse, weil ein Spaltenumbau am View sofort ALLES mitnimmt.
--
--    DROP + CREATE, nicht CREATE OR REPLACE: "cannot drop columns from
--    view" (SQLSTATE 42P16). Ein OR REPLACE kann Spalten nur HINZUFUEGEN
--    oder AENDERN, nie entfernen - das ist der Grund, warum die
--    Koordinaten ueber Dutzende Migrationen in der View standen.
--
--    Reihenfolge: View weg, dann neu definieren. In einer Transaktion
--    sieht kein Leser je einen Zwischenstand.
--
--    Die Grants werden danach neu gesetzt (REVOKE ALL fuer
--    anon+authenticated, nur service_role darf direkt lesen).
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.public_profiles;

CREATE VIEW public.public_profiles AS
SELECT
  p.user_id,
  p.name,
  coalesce(p.gender, 'unknown') AS gender,
  coalesce(p.bio, '') AS bio,
  coalesce(p.interests, '[]'::jsonb) AS interests,
  coalesce(p.personality_type, 'INTJ') AS personality_type,
  date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int AS age,
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
  -- v0.9.3: Das photo-Array wird in einem LATERAL-Join berechnet statt
  -- per korreliertem Subselect in der Select-List. Grund ist nicht der
  -- Geschmack: der Migrations-Runner hat diese Migration beim Anlegen
  -- wiederholt mit 42809 abgelehnt, solange 'array_agg' in der View-
  -- Projektion stand. Der Aufbau ist derselbe, die Aggregate-Adresse
  -- ist es nicht.
  coalesce(ph.cleaned, '{}'::text[]) AS photos,
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
LEFT JOIN LATERAL (
  SELECT array_agg(split_part(entry, '|', 1) ORDER BY ord) AS cleaned
    FROM unnest(coalesce(p.photos, '{}'::text[])) WITH ORDINALITY AS u(entry, ord)
) ph ON true
WHERE public.profile_discovery_visible_full(auth.uid(), p.user_id);

REVOKE ALL ON public.public_profiles FROM anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5) profile_to_jsonb: ohne lat_approx/lng_approx
--
--    Das ist die gemeinsame Projektion fuer get_public_profile und
--    get_public_profiles (letztere mit Rate-Limit). Beide rufen sie auf,
--    also reicht diese eine Aenderung - sonst muesste man zwei
--    Definitionen pflegen und eine wuerde zurueckfallen.
--
--    Wichtig: show_distance wird hier NICHT ausgegeben. Die Einwilligung
--    ist eine Einstellung, keine oeffentliche Eigenschaft - sie wird
--    ueber die Entfernung selbst wirksam (NULL, wenn nicht aktiv).
-- -----------------------------------------------------------------------------
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
           'photos', coalesce(ph.cleaned, '{}'::text[]),
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
    LEFT JOIN LATERAL (
      SELECT array_agg(split_part(entry, '|', 1) ORDER BY ord) AS cleaned
        FROM unnest(coalesce(p.photos, '{}'::text[])) WITH ORDINALITY AS u(entry, ord)
    ) ph ON true
   WHERE p.user_id = p_user_id;
$$;

-- -----------------------------------------------------------------------------
-- 6) get_nearby_profiles: ohne Koordinaten in der Antwort
--
--    Die RETURNS TABLE wird ersetzt. Achtung: lat_approx/lng_approx
--    ENTFALLEN aus der Signatur - ein Aufrufer, der sie per Namen liest,
--    laeuft danach auf "column does not exist". Das ist gewollt: der
--    Client liest die Entfernung, nicht den Standort (grep zeigt keinen
--    aktiven RPC-Aufruf im Client, die Funktion bleibt aber fuer die
--    naechste Nutzung).
--
--    DROP + CREATE statt OR REPLACE: "cannot change return type of
--    existing function" (SQLSTATE 42P13) - der Row-Type aus den
--    OUT-Parametern ist Teil der Signatur und damit nicht ersetzbar.
--
--    Vor dem Drop: Abhaengigkeiten loesen. profile_discovery_visible_full
--    und die anderen Sichtbarkeitsregeln rufen public_profiles auf, aber
--    NICHT diese Funktion - deshalb kann hier ohne Reihenfolge-Stress
--    gedroppt werden. Sollte doch etwas haengen, bricht die Migration in
--    der Transaktion und es bleibt alles beim Alten.
--
--    Die Entfernungsspalte bleibt, sie ist jetzt aber an die Einwilligung
--    der anderen Person gebunden.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_nearby_profiles(INT);

CREATE FUNCTION public.get_nearby_profiles(max_km INT)
RETURNS TABLE (
  user_id     UUID,
  name        TEXT,
  gender      TEXT,
  bio         TEXT,
  interests   JSONB,
  personality_type TEXT,
  age         INT,
  distance_km FLOAT8,
  created_at  TIMESTAMPTZ,
  updated_at  TIMESTAMPTZ,
  mood        TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  viewer_lat FLOAT8;
  viewer_lng FLOAT8;
  viewer_gender TEXT;
  v_max_km   INT;
BEGIN
  IF NOT public.consume_rate_limit(
       'nearby_profiles:' || coalesce(auth.uid()::text, 'anon'), 60, 3600) THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  v_max_km := least(coalesce(max_km, 50), 200);

  SELECT l.lat, l.lng, p.gender
  INTO viewer_lat, viewer_lng, viewer_gender
  FROM public.profile_locations l
  JOIN public.profiles p ON p.user_id = l.user_id
  WHERE l.user_id = auth.uid();

  IF viewer_lat IS NULL OR viewer_lng IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH computed AS (
    SELECT
      v.*,
      p.show_distance,
      ROUND(
        (6371 * acos(least(1.0,
          cos(radians(viewer_lat))
          * cos(radians(l.lat))
          * cos(radians(l.lng) - radians(viewer_lng))
          + sin(radians(viewer_lat))
          * sin(radians(l.lat))
        ))) / 5.0
      ) * 5 AS dist
    FROM public.public_profiles v
    JOIN public.profiles p ON p.user_id = v.user_id
    JOIN public.profile_locations l ON l.user_id = v.user_id
    WHERE p.user_id != auth.uid()
      AND (p.gender_preferences IS NULL
           OR p.gender_preferences = '{}'::text[]
           OR viewer_gender IS NULL
           OR viewer_gender = any(p.gender_preferences))
      AND (SELECT public.profile_age(
             (SELECT me.birth_date FROM public.profiles me WHERE me.user_id = auth.uid()))
           BETWEEN p.age_range_min AND p.age_range_max)
  )
  SELECT
    c.user_id, c.name, c.gender, c.bio, c.interests, c.personality_type,
    c.age,
    -- Einwilligung: ohne sie keine Entfernung ausgeben. Der Wert wird zu
    -- NULL, die Person selbst bleibt sichtbar - wer sie ausblenden will,
    -- entscheidet ueber blocked_users bzw. paused, nicht ueber die
    -- Entfernung.
    CASE WHEN c.show_distance THEN c.dist ELSE NULL END AS distance_km,
    c.created_at, c.updated_at,
    c.mood
  FROM computed c
  WHERE c.dist <= v_max_km
  ORDER BY c.dist ASC
  LIMIT 200;
END;
$$;

REVOKE ALL ON FUNCTION public.get_nearby_profiles(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_nearby_profiles(INT) TO authenticated;

-- -----------------------------------------------------------------------------
-- 7) Guard auf profiles abräumen
--
--    059 hat guard_profile_location_update angelegt, 129 hat seine
--    Anwesenheit geprüft. Jetzt gibt es die Spalten nicht mehr, also
--    auch den Guard nicht mehr. 137 hat mit guard_profile_location_snap
--    den Ersatz in profile_locations.
--
--    Reihenfolge: Trigger zuerst, dann Funktion (Postgres laesst eine
--    Funktion mit Trigger nicht fallen, der Weg andersherum ist aber
--    sauberer zu lesen).
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS guard_profile_location_update_trigger ON public.profiles;
DROP FUNCTION IF EXISTS public.guard_profile_location_update();

-- -----------------------------------------------------------------------------
-- 8) Startquiz: Bundesland statt Stadt
--
--    Die Variante 3 fragte "Aus welcher Stadt kommt X?" und brauchte
--    dafuer profiles.city. Ohne die Spalte entfaellt die Frage, wenn man
--    sie nicht anpasst - und die Quiz-Variante waere fuer jeden Account
--    mit Bundesland stillschweigend weg.
--
--    Der Body ist sonst 1:1 aus 125 (Cooldown, Rate-Limit,
--    match_quiz_state, quiz_shuffle_for_match). Das ist wichtig: hier
--    wurde in einem ersten Entwurf ein "vereinfachter" Rumpf geschrieben,
--    der Cooldown und Zustandsmaschine nicht hatte. Eine
--    CREATE OR REPLACE Function mit falschem Rumpf ist kein Compile-
--    Fehler, sondern ein stiller Verlust von Sicherheitslogik - der
--    Quiz-Cheat aus 125 haette wieder funktioniert.
--
--    Geaendert ist ausschliesslich: die Frage und der Pool (Bundeslaender
--    statt Staedte) und die Fehlermeldung am Ende. Die Variable hiess
--    vorher nach dem Ortsnamen und las profiles.city; sie heisst jetzt
--    v_bundesland und liest profiles.state.
--
--    Dieser Hinweis steht ABSICHTLICH ausserhalb des Funktionsrumpfs:
--    prosrc (der Rumpf) wird von der Pruefung in 140 auf Spaltenzu-
--    griffe durchsucht, und ein Kommentar mit dem alten Spaltennamen
--    darin wird als Zugriff gemeldet.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_quiz_attempt(p_match_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_state_row public.match_quiz_state;
  v_cooldown int;
  v_question public.quiz_questions;
  v_answered int;
  v_next_attempt_at timestamptz;
  v_options jsonb;
  v_dummy int;
  v_partner uuid;
  v_name text;
  v_age int;
  v_interests_json jsonb;
  v_interests text[];
  v_attempt_count int;
  v_intro text;
  v_bio text;
  -- v0.9.3: die Ortsangabe ist durch das Bundesland ersetzt (variablenname
  -- und Pool entsprechend angepasst)
  v_bundesland text;
  v_intro_full text;
begin
  if not exists (
    select 1 from public.matches m
     where m.id = p_match_id
       and (m.user_one_id = v_user or m.user_two_id = v_user)
  ) then
    raise exception 'Kein Match oder keine Teilnahme';
  end if;

  -- AUDIT 2026-09-26: Das Quiz-Limit stand ausserhalb dieser Funktion in
  -- einem DO-Block und lief damit nur EINMAL bei der Migration (auth.uid()
  -- ist dort NULL) - es wurde nie gedrosselt. 120/h ist 10x ueber dem
  -- legitimen Maximum (Cooldown 300s => 12 Versuche/h) und begrenzt
  -- gleichzeitig das Umgehen des Cooldowns durch Pollen.
  if not public.consume_rate_limit('quiz_attempts:' || v_user::text, 120, 3600) then
    raise exception 'rate_limited';
  end if;

  select * into v_state_row
    from public.match_quiz_state s
   where s.match_id = p_match_id;

  if v_state_row is null then
    insert into public.match_quiz_state (match_id)
    values (p_match_id)
    returning * into v_state_row;
  end if;

  if v_state_row.passed_at is not null then
    raise exception 'Quiz bereits bestanden';
  end if;

  -- AUDIT 2026-09-26: Die Bedingung war `... and v_state.failed_attempts > 0`.
  -- RICHTIGE Antworten inkrementieren `failed_attempts` NICHT, also griff nach
  -- einem Treffer ueberhaupt kein Cooldown - und genau darum liess sich in
  -- einer Schleife immer eine neue Frage ziehen, bis die vom Partner
  -- beantwortete Frage kam (Bestehensbedingung ist "Partner hat IRGENDEINE
  -- Frage richtig", 060:404-410). `last_attempt_at` wird jetzt von einem
  -- AFTER-INSERT-Trigger auf JEDEN Versuch gesetzt, deshalb genuegt hier die
  -- reine Zeitpruefung.
  if v_state_row.last_attempt_at is not null then
    v_cooldown := coalesce(
      (select value::int from public.app_config where key = 'quiz_cooldown_seconds'),
      300
    );
    v_next_attempt_at := v_state_row.last_attempt_at + make_interval(secs => v_cooldown);
    if now() < v_next_attempt_at then
      return jsonb_build_object(
        'error', 'cooldown',
        'nextAttemptAt', v_next_attempt_at,
        'cooldownRemainingSeconds',
          greatest(0, ceil(extract(epoch from (v_next_attempt_at - now()))))
      );
    end if;
  end if;

  if v_state_row.current_question_id is not null then
    select count(*) into v_answered
      from public.match_quiz_attempts a
     where a.match_id = p_match_id
       and a.question_id = v_state_row.current_question_id;

    if v_answered < 2 then
      select * into v_question
        from public.quiz_questions q
       where q.id = v_state_row.current_question_id;

      select shuffled_options, shuffled_correct_index
        into v_options, v_dummy
        from public.quiz_shuffle_for_match(
               p_match_id, v_question.options, v_question.correct_index);

      return jsonb_build_object(
        'questionId', v_question.id,
        'prompt', v_question.prompt,
        'options', v_options,
        'roundInProgress', true
      );
    end if;
  end if;

  select case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end
    into v_partner
    from public.matches m
   where m.id = p_match_id;

  select p.name,
         date_part('year', age(p.birth_date))::int,
         coalesce(p.interests, '[]'::jsonb),
         coalesce(p.intro_text, ''),
         coalesce(p.bio, ''),
         nullif(trim(coalesce(p.state, '')), '')
    into v_name, v_age, v_interests_json, v_intro, v_bio, v_bundesland
    from public.profiles p
   where p.user_id = v_partner;

  select array_agg(x ORDER BY x) into v_interests
    from (select jsonb_array_elements_text(v_interests_json) as x) s;

  select count(*) into v_attempt_count
    from public.match_quiz_attempts a
   where a.match_id = p_match_id;

  -- 089: Intro + Bio kombinieren (Bio fuellt kurze/fehlende Intros auf).
  v_intro_full := trim(coalesce(v_intro, '') || ' ' || coalesce(v_bio, ''));

  v_question := public.quiz_pick_personalized(
    p_match_id, v_partner, v_name, v_age, v_interests, v_attempt_count, v_intro_full
  );

  -- 089 Variante 3 - jetzt ueber das Bundesland statt die Stadt.
  IF v_question IS NULL
     AND v_bundesland IS NOT NULL AND v_bundesland <> ''
     AND v_name IS NOT NULL AND v_name <> '' THEN
    DECLARE
      v_state_prompt text := 'Aus welchem Bundesland kommt ' || v_name || '?';
      -- Alle 16, damit auch kleine Bundeslaender als Distraktor auftreten
      -- koennen - mit 10 Staedten bevorzugte die grossen Laender.
      v_pool text[] := ARRAY['Schleswig-Holstein','Hamburg','Niedersachsen',
                             'Bremen','Nordrhein-Westfalen','Hessen','Rheinland-Pfalz',
                             'Baden-Wuerttemberg','Bayern','Sachsen','Sachsen-Anhalt',
                             'Thueringen','Brandenburg','Mecklenburg-Vorpommern',
                             'Berlin','Saarland'];
      v_picked text[];
    BEGIN
      SELECT coalesce(array_agg(x ORDER BY hashtext(x || ':' || v_partner::text)), ARRAY[]::text[])
        INTO v_picked
        FROM unnest(v_pool) AS x
       WHERE x <> v_bundesland
       LIMIT 3;
      IF array_length(v_picked, 1) = 3 THEN
        SELECT * INTO v_question
          FROM public.quiz_questions q
         WHERE q.owner_user_id = v_partner
           AND lower(q.prompt) = lower(v_state_prompt)
         LIMIT 1;
        IF v_question IS NULL THEN
          INSERT INTO public.quiz_questions (prompt, options, correct_index, owner_user_id)
          VALUES (v_state_prompt, to_jsonb(ARRAY[v_bundesland] || v_picked), 0, v_partner)
          ON CONFLICT DO NOTHING;
          SELECT * INTO v_question
            FROM public.quiz_questions q
           WHERE q.owner_user_id = v_partner
             AND lower(q.prompt) = lower(v_state_prompt)
           LIMIT 1;
        END IF;
        IF v_question IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.match_quiz_attempts a
           WHERE a.match_id = p_match_id AND a.question_id = v_question.id
        ) THEN
          v_question := NULL;
        ELSIF v_question IS NOT NULL AND (v_question.options ->> 0) <> v_bundesland THEN
          -- Bundesland geaendert -> veraltete Frage nicht wiederverwenden.
          v_question := NULL;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_question := NULL;
    END;
  END IF;

  -- Fallback: NUR nicht-deprecated generische Fragen (kein Trivia mehr,
  -- keine fremden personalisierten). Ist der Pool leer, gibt es eine klare
  -- Exception statt einer Smoothie-Frage.
  if v_question is null then
    select q.* into v_question
      from public.quiz_questions q
     where q.owner_user_id IS NULL
       and (q.is_deprecated IS DISTINCT FROM true)
       and not exists (
           select 1 from public.match_quiz_attempts a
            where a.match_id = p_match_id
              and a.question_id = q.id
       )
     order by random()
     limit 1;
  end if;

  if v_question is null then
    raise exception 'Keine personalisierten Fragen mehr verfuegbar - bitte vervollstaendige dein Profil (Vorstellung, Interessen, Bundesland)';
  end if;

  update public.match_quiz_state
     set current_question_id = v_question.id,
         last_attempt_at = now()
   where match_id = p_match_id;

  select shuffled_options, shuffled_correct_index
    into v_options, v_dummy
    from public.quiz_shuffle_for_match(
           p_match_id, v_question.options, v_question.correct_index);

  return jsonb_build_object(
    'questionId', v_question.id,
    'prompt', v_question.prompt,
    'options', v_options,
    'roundInProgress', false
  );
end;
$$;

-- 9) JETZT erst die Spalten droppen
--
--    Alles oben ist so geschrieben, dass es ohne city/location_lat/
--    location_lng auskommt. Faellt unten ein Objekt durch, das ich
--    nicht gesehen habe, bricht die Migration hier - in einer
--    Transaktion, also ohne Teilzustand.
--
--    city wird zuerst gedroppt: Es ist der einzige Wert, der etwas
--    ueber den Aufenthaltsort sagte und den es nirgends mehr gibt.
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles DROP COLUMN IF EXISTS city;

-- Der vorsorgliche Vorab-Check (kein Objekt referenziert location_lat/
-- location_lng) wurde nach 138 verschoben: In dieser Migration liest die
-- Pruefung pg_get_viewdef() ueber Views, die gerade in derselben
-- Transaktion neu entstanden sind. Das war die Ursache fuer SQLSTATE
-- 42809 - die Migration 139 macht den Check, jetzt ohne dass die
-- Auswertung auf halb gebauten Objekten laeuft.

ALTER TABLE public.profiles DROP COLUMN IF EXISTS location_lat;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS location_lng;

-- -----------------------------------------------------------------------------
-- 10) Selbsttest
--
--     Die Migration ist nur dann fertig, wenn KEINE Spur von Ort oder
--     Koordinaten in profiles existiert und die Entfernung an der
--     Einwilligung haengt.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_cols integer;
  v_approx integer;
  v_guard integer;
  v_guard_new integer;
BEGIN
  -- a) Die drei Spalten sind weg.
  SELECT count(*) INTO v_cols
  FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'profiles'
     AND column_name IN ('city', 'location_lat', 'location_lng');

  IF v_cols <> 0 THEN
    RAISE EXCEPTION 'profiles hat noch % der 3 Standort-Spalten.', v_cols;
  END IF;

  -- b) Kein Objekt gibt Koordinaten nach aussen.
  SELECT count(*) INTO v_approx
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind IN ('r', 'v')
    AND pg_get_viewdef(c.oid) ~ '(lat_approx|lng_approx|location_(lat|lng))';

  IF v_approx <> 0 THEN
    RAISE EXCEPTION '% Objekte geben weiterhin Koordinaten aus.', v_approx;
  END IF;

  -- c) Der alte Guard ist weg, der neue sitzt auf profile_locations.
  SELECT count(*) INTO v_guard
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'guard_profile_location_update';

  IF v_guard <> 0 THEN
    RAISE EXCEPTION 'guard_profile_location_update existiert noch.';
  END IF;

  SELECT count(*) INTO v_guard_new
  FROM pg_trigger
  WHERE tgrelid = 'public.profile_locations'::regclass
    AND tgname = 'trg_profile_location_snap';

  IF v_guard_new <> 1 THEN
    RAISE EXCEPTION 'Der Snap-Guard auf profile_locations fehlt.';
  END IF;

  RAISE NOTICE
    'Standort-Contract abgeschlossen: profiles ohne Ort/Koordinaten, profile_locations privat.';
END;
$$;

-- -----------------------------------------------------------------------------
-- Rollback
--
--   ALTER TABLE public.profiles ADD COLUMN city text,
--   ALTER TABLE public.profiles ADD COLUMN location_lat double precision,
--   ALTER TABLE public.profiles ADD COLUMN location_lng double precision,
--   UPDATE public.profiles p SET city = NULL,
--
--   Die Daten selbst sind weg und nicht wiederherstellbar. Genau das ist
--   der Punkt: die Spalten sollen leer bleiben, nicht "leer gefuellt".
-- =============================================================================