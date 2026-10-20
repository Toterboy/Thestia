-- 145: get_match_partner_profile - Ueberladung aus 144 entfernen
--
-- BEFUND (Push-Vorpruefung, 2026-10-20):
--   "get_match_partner_profile ist 2x ueberladen, aber (bigint, integer)
--    wird NICHT revokt - diese Variante bleibt aufrufbar"
--
-- URSACHE: Migration 144 hat die Funktion mit
--
--     einer Variante mit zusaetzlichem Parameter `p_level integer`
--     (die App ruft die EINE-Parameter-Variante)
--
-- angelegt. Das ist KEINE Ersetzung, sondern eine NEUE Ueberladung:
-- "CREATE OR REPLACE" kann die Signatur nicht aendern (42P13 /
-- 42804). Die urspruengliche, von der App gerufene Variante
--
--     get_match_partner_profile(bigint)
--
-- blieb unveraendert - OHNE der in 144 beabsichtigten Erweiterung
-- um 'verification_state'.
--
-- ZWEI FOLGEN:
--
-- 1) Die von der App gerufene Funktion hatte den Dreifachzustand
--    weiterhin NICHT. Die Erweiterung aus 144 kam in einer Variante an,
--    die niemand aufruft.
--
-- 2) Die ueberzaehlige Variante (bigint, integer) war fuer `anon`
--    aufrufbar - Migration 123 hatte den Entzug nur fuer die damals
--    vorhandenen Ueberladungen vorgenommen, eine spaeter hinzugekommene
--    blieb unberuehrt. Ein anonymer Aufrufer konnte damit die
--    Profildaten eines Match-Partners abrufen.
--
-- LOESUNG:
--   * Die ueberzaehlige Variante wird DROPPED. Damit entfaellt das
--     Aufrufbarkeitsproblem und die Zweideutigkeit.
--   * Die von der App genutzte Variante (bigint) wird mit der
--     beabsichtigten Erweiterung neu definiert - diesmal mit der
--     RICHTIGEN Signatur.
--
-- Der Level wird wie in der Ursprungsfassung (Migration 139) INTERN
-- berechnet. Die (bigint, integer)-Variante nahm den Level dagegen
-- vom Aufrufer entgegen - das waere ein weiterer Grund, sie zu
-- entfernen: sie haette einem Aufrufer erlaubt, sich einen beliebigen
-- Unlock-Level selbst zu setzen.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Die ueberzaehlige Variante entfernen
-- ---------------------------------------------------------------------------
-- DROP verlangt die Argumenttypen, nicht die Parameternamen.
DROP FUNCTION IF EXISTS public.get_match_partner_profile(bigint, integer);

-- ---------------------------------------------------------------------------
-- 2) Die von der App gerufene Variante richtig definieren
-- ---------------------------------------------------------------------------
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
    --
    -- v0.10.0 (Migration 144/145): 'verification_state' ergaenzt. Die
    -- Unterscheidung "nicht verifiziert" vs. "wird geprueft" wird auch
    -- am Match-Partner angezeigt - vorher war der Status dort
    -- unsichtbar.
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
        'is_verified',           coalesce(p.is_verified, false),
        'verification_state',    CASE
          WHEN coalesce(p.is_verified, false) THEN 'verified'
          WHEN p.verification_status IN ('pending', 'pending_minor') THEN 'under_review'
          ELSE 'unverified'
        END
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

-- Der Entzug fuer `anon` wird hier ausdruecklich wiederholt. Migration
-- 123 hat ihn nur fuer die damals vorhandenen Ueberladungen vorgenommen
-- (es wurde ueber pg_proc dynamisch geschwungen, also nach Namen, und
-- eine spaeter hinzugekommene Ueberladung blieb unberuehrt).
REVOKE ALL ON FUNCTION public.get_match_partner_profile(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_match_partner_profile(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_match_partner_profile(bigint)
  TO authenticated;

COMMENT ON FUNCTION public.get_match_partner_profile(bigint) IS
  'Das Profil des Match-Partners, abhaengig vom Quiz-Fortschritt. '
  'Der Unlock-Level wird INTERN aus match_quiz_state berechnet - eine '
  'Uebernahme vom Aufrufer waere eine Rechteausweitung. Migration 145 '
  'entfernte die Variante (bigint, integer) aus Migration 144, die fuer '
  'anon aufrufbar war und den Level vom Aufrufer entgegennahm.';

COMMIT;
