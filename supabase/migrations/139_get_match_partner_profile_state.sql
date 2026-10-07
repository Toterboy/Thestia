-- =============================================================================
-- 139_get_match_partner_profile_state.sql
-- =============================================================================
-- Nachbesserung zu 138: get_match_partner_profile() referenzierte noch
-- profiles.city.
--
-- BEFUND: Die Pruefung aus dem Plan (Pruefpunkt 3) hat zwei Funktionen
-- gemeldet, die auf die gedroppten Spalten zugreifen. Bei
-- get_match_partner_profile() ist das kein theoretischer Befund: die
-- Funktion ist Teil des Chat-Flusses und waere bei jedem Match mit
-- Unlock-Level >= 2 in einen Laufzeitfehler gelaufen ("column p.city
-- does not exist"). Ein Aufruf per RPC bringt dann nur noch einen
-- Fehler, nicht einmal mehr ein leeres Profil.
--
-- Zwei Aenderungen an der Funktion:
--
--   1. Der Unlock-Zweig nannte den Ort als eigenes Feld. Das ist
--      entfernt. An seiner Stelle steht jetzt 'state' - das Bundesland,
--      das ohnehin schon nebenan ausgeliefert wird. Es ist eine Angabe,
--      die es wert ist, und sie war frueher zwei Zeilen tiefer ohnehin
--      dabei.
--
--   2. Der gesperrte Zweig macht row_to_json(p.*) auf public_profiles.
--      Das war schon vor 138 eine ungepruefte Weitergabe der ganzen View,
--      inklusive lat_approx/lng_approx (1 Dezimal, ~11 km). Nach 138
--      ist die View sauber, der Ausdruck bleibt aber unveraendert -
--      er ist nicht der Grund fuer die Reparatur, wird aber hier
--      auf public_profiles festgeschrieben und vermerkt.
--
-- Was NICHT geaendert wird: der gesperrte Zweig liefert weiterhin die
-- ganze View. Das ist Absicht (das Profil soll ja sichtbar sein), und
-- die View enthaelt jetzt nur noch oeffentliche Felder.
--
-- Der Body ist sonst unveraendert aus 59 - Cooldown, Rate-Limit und
-- Whitelist bleiben, wie sie waren.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_match_partner_profile(p_match_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_partner uuid;
  v_level int := 0;
BEGIN
  SELECT case when m.user_one_id = auth.uid() then m.user_two_id else m.user_one_id end
    INTO v_partner
    FROM public.matches m
   WHERE m.id = p_match_id
     AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid());

  IF v_partner IS NULL THEN
    RAISE EXCEPTION 'Kein Match oder keine Teilnahme';
  END IF;

  SELECT s.unlock_level INTO v_level
    FROM public.match_quiz_state s
   WHERE s.match_id = p_match_id;

  IF v_level IS NULL THEN
    v_level := 0;
  END IF;

  IF v_level >= 2 THEN
    -- Whitelist (049) minus birth_date/is_location_suspicious (M-3):
    -- Das exakte Geburtsdatum bleibt beim Besitzer, der Partner erhaelt
    -- nur das Alter in Jahren. is_location_suspicious ist ein interner
    -- Anti-Fraud-Indikator.
    --
    -- v0.9.3: 'city' entfernt (Spalte existiert nicht mehr). Das
    -- Bundesland stand bereits eine Zeile darunter.
    RETURN jsonb_build_object(
      'unlockLevel', v_level,
      'unlocked', true,
      'profile', jsonb_build_object(
        'user_id',               p.user_id,
        'name',                  p.name,
        'bio',                   p.bio,
        'interests',             p.interests,
        'state',                 p.state,
        'country',               p.country,
        'gender',                p.gender,
        'age',                   public.profile_age(p.birth_date),
        'personality_type',      p.personality_type,
        'intro_text',            p.intro_text,
        'intro_audio_path',      p.intro_audio_path,
        'is_verified',           p.is_verified
      )
    )
    FROM public.profiles p
   WHERE p.user_id = v_partner;
  END IF;

  -- Gesperrt: die ganze oeffentliche View. Nach 138 ohne Koordinaten.
  RETURN jsonb_build_object(
    'unlockLevel', v_level,
    'unlocked', false,
    'profile', row_to_json(p.*)
  )
  FROM public.public_profiles p
  WHERE p.user_id = v_partner;
END;
$$;

REVOKE ALL ON FUNCTION public.get_match_partner_profile(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_match_partner_profile(bigint) TO authenticated;

-- -----------------------------------------------------------------------------
-- Selbsttest: keine Referenz auf die entfernte Spalte mehr im CODE.
--
-- Geprueft wird prosrc, nicht pg_get_functiondef(): der Definitionstext
-- enthaelt auch die Kommentare dieser Datei, und darin stehen die
-- Spaltennamen aus der Historie. prosrc ist genau der Rumpf.
--
-- Muster mit Punkt davor, weil ein Spaltenzugriff in SQL immer als
-- "alias.spalte" geschrieben wird.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_src text;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'get_match_partner_profile'
     AND p.pronargs = 1;

  IF v_src IS NULL THEN
    RAISE EXCEPTION 'get_match_partner_profile() fehlt.';
  END IF;

  IF v_src LIKE '%.city%' OR v_src LIKE '%.location_lat%'
     OR v_src LIKE '%.location_lng%' THEN
    RAISE EXCEPTION
      'get_match_partner_profile() greift weiterhin auf die entfernten Spalten zu.';
  END IF;

  RAISE NOTICE
    'get_match_partner_profile() liefert nur noch oeffentliche Angaben.';
END;
$$;