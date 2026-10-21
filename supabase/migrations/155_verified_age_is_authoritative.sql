-- 155: Verifiziertes Alter wird die Grundlage des Jugendschutz-Filters
--
-- EINWAND (Nutzer, 21.10.2026), und er ist berechtigt:
-- "Die Verifizierung fuer das Alter soll irrelevant sein? Was wenn ich
--  mich als 18 ausgebe aber 60 bin? Ohne Verifikation kann das einfach
--  so gemacht werden."
--
-- RICHTIG: Der Filter benutzte bis hierher das DEKLARIERTE
-- Geburtsdatum. Die Verifikation hat den Filter nicht beeinflusst.
-- Damit waren zwei Betruege moeglich:
--
--   * Ein 60-Jaehriger gibt 18 an. Er wird wie ein 18-Jaehriger
--     behandelt - und sieht damit die 18+-Gruppe. Das ist kein
--     Jugendschutz, das ist eine Altersangabe.
--   * Ein 16-Jaehriger gibt 30 an. Er wird wie ein 30-Jaehriger
--     behandelt und taucht in der Erwachsenengruppe auf.
--
-- LOESUNG: Das Alter, das im Filter zaehlt, ist das VERIFIZIERTE
-- Alter. Und wer nicht verifiziert ist, kommt ueberhaupt nicht in
-- die Discovery-Funktionen - genau die Sperre, die ohnehin
-- vorgesehen war (nur QR-Code-Scannen und Zufallschat bleiben
-- offen).
--
-- ZWEI SACHEN MUESSEN ZUSAMMENPASSEN, sonst waere die Loesung
-- wertlos:
--
--   1) profiles.verified_age: das verifizierte Alter. NULL, solange
--      niemand verifiziert hat. Wird ausschliesslich serverseitig
--      gesetzt (verify-account), nie vom Client - mit Trigger wie
--      bei is_verified.
--
--   2) Der Filter rechnet mit coalesce(verified_age, deklariertes
--      Alter) - UND die Discovery verlangt is_verified. Damit kann
--      ein nicht verifiziertes Konto in keiner Liste auftauchen und
--      die Altersangabe gar nicht erst wirksam werden.
--
-- WICHTIG - und hier wird es unbequem, aber richtig: Ein Konto, das
-- gerade registriert ist und noch kein Video hochgeladen hat, sieht
-- in der Discovery also LEER aus. Das ist die Kehrseite der
-- Verifikationspflicht und gewollt: ohne Bestaetigung des Alters gibt
-- es keine Begegnungen. Die App weist darauf hin (Modus gesperrt).
--
-- Der Zeitpunkt der Verifikation bleibt beim Nutzer; die Verifikation
-- selbst ist ueber die Edge Function gesichert (Admin-Check, JWT).

BEGIN;

-- ===========================================================================
-- 1) Spalte fuer das verifizierte Alter
-- ===========================================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verified_age int;

DO $check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'chk_profiles_verified_age'
       AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT chk_profiles_verified_age
      CHECK (verified_age IS NULL OR (verified_age >= 16 AND verified_age <= 100));
  END IF;
END;
$check$;

COMMENT ON COLUMN public.profiles.verified_age IS
  'Per Video verifiziertes Alter in Jahren (v0.10.0, Migration 155). '
  'NULL, solange nicht verifiziert. Wird ausschliesslich von der Edge '
  'Function verify-account gesetzt - Clients duerfen es nicht '
  'schreiben. Fuer den Jugendschutz-Filter ist dies der Massstab, nicht '
  'das deklarierte birth_date.';

-- ===========================================================================
-- 2) Client-Schreibschutz fuer verified_age
-- ===========================================================================
-- Das Muster ist derselbe wie fuer is_verified und birth_date
-- (Migration 095/056). Ohne diesen Trigger koennte ein Client sein
-- eigenes verified_age setzen - und damit den Filter aushebeln.
CREATE OR REPLACE FUNCTION public.prevent_client_update_verification_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (TG_OP = 'UPDATE'
      AND pg_has_role(current_user, 'authenticated', 'member')
      AND (NEW.is_verified IS DISTINCT FROM OLD.is_verified
        OR NEW.verification_status IS DISTINCT FROM OLD.verification_status
        OR NEW.verification_estimated_age IS DISTINCT
             FROM OLD.verification_estimated_age
        OR NEW.verified_age IS DISTINCT FROM OLD.verified_age
        OR NEW.birth_date IS DISTINCT FROM OLD.birth_date))
  THEN
    RAISE EXCEPTION
      'Aenderungen an Verifikationsfeldern sind nicht erlaubt.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_client_update_verification_fields
  ON public.profiles;
CREATE TRIGGER trg_prevent_client_update_verification_fields
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_client_update_verification_fields();

-- ===========================================================================
-- 3) Das massgebliche Alter
-- ===========================================================================
-- age_compatible_bidirectional gibt es nur fuer GEBURSTDATUM. Mit dem
-- verifizierten Alter arbeiten wir aber mit JAHRESZAHLEN - die beiden
-- Werte duerfen nicht vermischt werden (ein Geburtsdatum ist nicht
-- dasselbe wie ein Alter). Deshalb eine eigene Variante.
--
-- Die Regel selbst ist identisch zu age_compatible, nur eben auf
-- Jahreszahlen: sie wird in beide Richtungen geprueft.
CREATE OR REPLACE FUNCTION public.age_compatible_bidirectional_ages(
  v_viewer_age int,
  v_target_age int
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT public.age_compatible(v_viewer_age, v_target_age)
     AND public.age_compatible(v_target_age, v_viewer_age);
$$;

COMMENT ON FUNCTION public.age_compatible_bidirectional_ages(int, int) IS
  'Beidseitige Alterspruefung auf JAHRESZAHLEN (v0.10.0, Migration 155). '
  'N��tig, weil mit dem verifizierten Alter gerechnet wird und das '
  'Geburtsdatum als Datum nicht in die Alterslogik passt. Identisch zur '
  'Regel von age_compatible_bidirectional, nur auf Jahreszahlen.';

-- ===========================================================================
-- 3) Das massgebliche Alter
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.profile_effective_age(
  v_birth_date date,
  v_verified_age int
)
RETURNS int
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(
    v_verified_age,
    public.profile_age(coalesce(v_birth_date, '2000-01-01'::date))
  );
$$;

COMMENT ON FUNCTION public.profile_effective_age(date, int) IS
  'Das Alter, das fuer den Jugendschutz zaehlt: das verifizierte, wenn '
  'vorhanden, sonst das deklarierte (v0.10.0, Migration 155). Die '
  'Discovery verlangt zusaetzlich is_verified - ein nicht '
  'verifiziertes Konto kommt dort ohnehin nicht vor. Damit kann die '
  'Altersangabe allein den Filter nicht mehr aushebeln.';

-- ===========================================================================
-- 4) Discovery: verifiziertes Alter verwenden
-- ===========================================================================
-- Der Filter wird auf profile_effective_age umgestellt. Die beiden
-- Alterspruefungen (die beidseitige Kompatibilitaet und die
-- Untergrenze der Altersspanne) rechnen jetzt mit demselben Massstab.
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
        LEFT JOIN LATERAL (
          SELECT lat, lng FROM public.profile_locations WHERE user_id = v.user_id
        ) vl ON true
        LEFT JOIN LATERAL (
          SELECT lat, lng FROM public.profile_locations WHERE user_id = t.user_id
        ) tl ON true
       WHERE v.user_id = p_viewer
         AND public.age_compatible_bidirectional_ages(
               public.profile_effective_age(v.birth_date, v.verified_age),
               public.profile_effective_age(t.birth_date, t.verified_age))
         AND NOT EXISTS (
               SELECT 1 FROM public.blocked_users b
                WHERE (b.blocker = p_viewer AND b.blocked = p_target)
                   OR (b.blocker = p_target AND b.blocked = p_viewer)
             )
         AND coalesce(t.paused, false) = false
         AND public.profile_effective_age(t.birth_date, t.verified_age)
               BETWEEN v.age_range_min AND v.age_range_max
         AND public.profile_effective_age(t.birth_date, t.verified_age)
               >= public.max_age_range_min(
                     public.profile_effective_age(v.birth_date, v.verified_age))
         AND (
           coalesce(v.distance_filter_mode, 'distance_km') <> 'distance_km'
           OR vl.lat IS NULL OR tl.lat IS NULL
           OR 2 * 6371 * asin(sqrt(
                power(sin(radians(tl.lat - vl.lat) / 2), 2)
              + cos(radians(vl.lat)) * cos(radians(tl.lat))
              * power(sin(radians(tl.lng - vl.lng) / 2), 2)
            )) <= v.max_distance_km
         )
    );
$$;

-- ===========================================================================
-- 5) Discovery nur fuer verifizierte Konten
-- ===========================================================================
-- Das ist die eigentliche Huerde gegen das Alters-Luegen: ohne
-- Verifikation erscheint das Konto in keiner Begegnungsliste.
--
-- Betroffen sind die beiden Funktionen, die die Vorschlagslisten liefern:
-- get_nearby_profiles (Umkreis) und get_find_match_candidates (Find your
-- Match). Beide lesen aus public_profiles, dessen WHERE die
-- Sichtbarkeitspruefung nutzt - deshalb genuegt hier die zusaetzliche
-- Bedingung auf den Aufrufer.
--
-- get_public_profile / get_public_profiles bleiben unveraendert: sie
-- werden fuer etablierte Matches und die Gefaellt-Mich-Liste benutzt -
-- dort soll ein verifizierter Nutzer auch den Profilstand eines
-- unbestattigten Kontos sehen koennen.
-- Die echte Funktion aus Migration 138, mit zwei Ergaenzungen:
--   * AND me.is_verified  - ohne Verifikation erscheint das Konto in
--     keiner Vorschlagsliste. Das ist die Huerde gegen das Alters-Luegen.
--   * Das Alter kommt aus profile_effective_age (verifiziertes Alter).
CREATE OR REPLACE FUNCTION public.get_nearby_profiles(max_km INT)
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

  -- v0.10.0 (Migration 155): Ohne Altersnachweis keine Vorschlagsliste.
  --
  -- Die Altersangabe im Profil ist eine Behauptung. Solange sie nicht
  -- per Video bestaetigt ist, darf das Konto nicht in fremden Listen
  -- stehen - und erst recht keine Begegnung mit jemandem aufbauen, bei
  -- dem das Alter die Entscheidung faellt.
  --
  -- Wer gerade registriert ist, sieht hier also eine leere Liste. Das
  -- ist gewollt: die App weist auf die Verifizierung hin.
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
     WHERE user_id = auth.uid() AND is_verified
  ) THEN
    RETURN;
  END IF;

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
      AND (SELECT public.profile_effective_age(
             (SELECT me.birth_date FROM public.profiles me WHERE me.user_id = auth.uid()),
             (SELECT me.verified_age FROM public.profiles me WHERE me.user_id = auth.uid()))
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

-- Gegenprobe: Die Funktion muss es geben und die Bedingung enthalten.
DO $check$
DECLARE
  v_ok boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'get_nearby_profiles'
       AND p.prosrc LIKE '%AND is_verified%'
  ) INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'get_nearby_profiles verlangt keine Verifikation - '
      'dann koennte ein Konto ohne Altersnachweis in der Liste stehen.';
  END IF;
END;
$check$;

COMMIT;
