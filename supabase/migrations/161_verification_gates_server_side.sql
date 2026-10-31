-- =============================================================================
-- 161_verification_gates_server_side.sql
-- =============================================================================
-- Die Verifikationspflicht wird serverseitig erzwungen - und das fehlende
-- Geburtsdatum gilt nicht mehr als 26.
--
-- BEFUND (Security-Audit 31.10.2026):
--
--   1) Die Verifikationspflicht gilt fuer drei Modi: Find your Spark,
--      Dating Hour und Transit Spark. Sie wurde an GENAU EINER Stelle
--      geprueft - im Client, im Modus-Auswahlbildschirm
--      (lib/screens/swipe/swipe_mode_selection_screen.dart, _openMode).
--
--      Ein Client-Gate ist keine Zugriffskontrolle: die RPCs sind fuer
--      jeden mit eigenem JWT aufrufbar. Konkret:
--
--        * join_dating_hour (Migration 022) prueft nur auth.uid() und
--          den Event-Status.
--        * match_dating_hour_round (Migration 058) prueft Alter,
--          Blockierliste und Praeferenzen - keine Verifikation.
--        * transit_spark_adult (Migration 159) prueft ueber
--          transit_spark_is_adult NUR das Alter.
--
--      'is_verified' kommt in KEINER dieser Funktionen vor. Ein nicht
--      verifiziertes Konto konnte deshalb selbst ueber die RPCs an
--      Dating Hour teilnehmen, Matches erzeugen und Soft-Pings senden -
--      also genau die Begegnungen mit fremden Personen, fuer die die
--      Verifikation existiert.
--
--      Find your Spark ist serverseitig geschuetzt (Migration 156:
--      get_find_match_candidates verlangt ein verifiziertes Aufrufer-
--      UND Kandidatenkonto). Der Befund betrifft also zwei von drei
--      Modi.
--
--   2) handle_new_user setzt birth_date auf COALESCE(..., '2000-01-01')
--      (Migration 158). Fehlt die Altersangabe, gilt damit Alter 26.
--
--      Damit ist die 18+-Pruefung von Transit Spark NICHT fail-closed,
--      obwohl der Kommentar in Migration 131 genau das verlangt: die
--      Bedingung 'birth_date IS NOT NULL' ist immer erfuellt, weil der
--      Trigger die Spalte nie NULL laesst. Eine Registrierung ohne
--      birth_date galt damit als 26-jaehrig.
--
-- UMSETZUNG:
--
--   1) Eine Hilfsfunktion public.verification_granted(uuid) - die
--      Verifikationspruefung an EINER Stelle. Die drei betroffenen
--      Funktionen rufen sie auf.
--
--   2) join_dating_hour und match_dating_hour_round pruefen sie und
--      lehnen ab, wenn sie fehlt.
--
--   3) transit_spark_adult prueft sie ZUSAETZLICH zum Alter. Weil
--      alle Transit-Spark-Pfade ueber diese eine Funktion laufen
--      (Radar, Matching, Kontaktversand, Gegenseiten-Pruefung), wirkt
--      die Sperre auf alle vier, ohne dass eine der vier RPCs neu
--      geschrieben werden muss. Das ist dieselbe Strategie wie das
--      Feature-Flag in Migration 159.
--
--   4) handle_new_user laesst birth_date NULL, wenn keine Angabe
--      vorliegt. Die Alterspruefungen behandeln NULL als "unbekannt"
--      (fail-closed).
--
-- FAIL-CLOSED: Die Verifikationspruefung ist "verifiziert UND Alter
-- passt". Fehlt das Profil, ist die Person nicht verifiziert.
--
-- RUECKWAERTSKOMPATIBEL: Bestandskonten, die bereits verifiziert sind,
-- bleiben verifiziert - die Pruefung liest is_verified aus dem Profil,
-- nicht aus dem lokalen Geraet. Konten, die NOCH NICHT verifiziert
-- sind, koennen Dating Hour und Transit Spark erst nach der
-- Verifikation nutzen. Das ist die Zusage aus der Datenschutz-
-- und Sicherheitsdokumentation.
--
-- ZUR PRUEFUNG VOR DEM DEPLOY: tool/check_security_invariants.py
-- schlaegt fehl, solange die Gates fehlen. Der Check liest die LETZTE
-- Definition einer Funktion - eine aeltere, sichere Fassung wuerde
-- den Check sonst bestehen, obwohl die aktive Funktion ungeschuetzt
-- ist.
-- =============================================================================

BEGIN;

-- ===========================================================================
-- 1) Die Verifikationspruefung an einer Stelle
-- ===========================================================================
-- Bewusst SECURITY DEFINER mit explizitem search_path: die Funktion
-- liest profiles.is_verified. Der Client darf profiles nicht
-- frei lesen (RLS), also braucht die Funktion die Rechte des
-- Erstellers.
CREATE OR REPLACE FUNCTION public.verification_granted(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.profiles p
     WHERE p.user_id = p_user_id
       AND p.is_verified = true
  );
$$;

COMMENT ON FUNCTION public.verification_granted(uuid) IS
  'Darf diese Person die Modi nutzen, die eine Verifikation voraussetzen? '
  'Liest is_verified aus dem Profil (serverseitig, nicht aus dem Geraet). '
  'Fail-closed: fehlt das Profil, ist die Person nicht verifiziert. '
  'v0.10.0, Migration 161 - ersetzt die rein clientseitige Pruefung.';

REVOKE EXECUTE ON FUNCTION public.verification_granted(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verification_granted(uuid)
  TO authenticated, service_role;

-- ===========================================================================
-- 2) Dating Hour: Opt-in prueft die Verifikation
-- ===========================================================================
-- Die Funktion aus Migration 022 mit dem Gate. Sonst nichts geaendert -
-- particularly die Rechte (REVOKE/GRANT) und der search_path.
CREATE OR REPLACE FUNCTION public.join_dating_hour(
  p_event_id uuid,
  p_preferences jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_event public.dating_hour_event%rowtype;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Verifikationspflicht (v0.10.0, Migration 161).
  --
  -- Bis hierher stand die Pruefung NUR im Client. Das war keine
  -- Zugriffskontrolle: diese Funktion ist fuer jeden mit eigenem JWT
  -- aufrufbar. Eine nicht verifizierte Person konnte so an einem
  -- Event teilnehmen und bei beidseitiger Zustimmung ein Match
  -- bekommen - also genau die Begegnung mit einer fremden Person,
  -- fuer die die Verifikation existiert.
  IF NOT public.verification_granted(v_user_id) THEN
    RAISE EXCEPTION 'verification_required';
  END IF;

  SELECT * INTO v_event FROM public.dating_hour_event WHERE id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;

  -- Opt-in nur vor oder während des Events erlaubt.
  IF v_event.status NOT IN ('scheduled','active') THEN
    RAISE EXCEPTION 'event_not_joinable';
  END IF;

  INSERT INTO public.dating_hour_participant(event_id, user_id, preferences)
  VALUES (p_event_id, v_user_id, p_preferences)
  ON CONFLICT (event_id, user_id)
  DO UPDATE SET
    left_at = NULL,
    joined_at = now(),
    preferences = EXCLUDED.preferences;
END;
$$;

COMMENT ON FUNCTION public.join_dating_hour(uuid, jsonb) IS
  'Opt-in in ein Dating-Hour-Event. v0.10.0, Migration 161: erfordert '
  'ein verifiziertes Profil (serverseitig geprueft - vorher nur im Client).';

REVOKE EXECUTE ON FUNCTION public.join_dating_hour(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_dating_hour(uuid, jsonb) TO authenticated;

-- ===========================================================================
-- 3) Dating Hour: Pairing prueft die Verifikation
-- ===========================================================================
-- Die Funktion aus Migration 058 mit dem Gate. Der Rest des Koerpers
-- (Blockier-Schutz, beidseitige Alters-Kompatibilitaet, Alters-
-- Praeferenzen) bleibt unveraendert.
CREATE OR REPLACE FUNCTION public.match_dating_hour_round(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_event public.dating_hour_event%rowtype;
  v_user record;
  v_pair record;
  v_user_birth date;
BEGIN
  SELECT * INTO v_event FROM public.dating_hour_event WHERE id = p_event_id;
  IF NOT FOUND OR v_event.status != 'active' THEN
    RETURN;
  END IF;

  -- Verifikationspflicht (v0.10.0, Migration 161).
  --
  -- Das Gate an dieser Stelle deckt beide Richtungen ab: die Person, die
  -- in die Runde kommt, UND die Person, mit der sie gepaart wird. Ein
  -- Match zwischen einer verifizierten und einer unverifizierten Person
  -- waere genau die Luecke, die die Verifikation schliessen soll.
  IF NOT public.verification_granted(auth.uid()) THEN
    RAISE EXCEPTION 'verification_required';
  END IF;

  FOR v_user IN
    SELECT p.user_id, p.preferences
    FROM public.dating_hour_participant p
    WHERE p.event_id = p_event_id
      AND p.left_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = p.user_id OR s.user_b = p.user_id)
      )
    ORDER BY random()
  LOOP
    -- Beide Seiten muessen verifiziert sein.
    IF NOT public.verification_granted(v_user.user_id) THEN
      CONTINUE;
    END IF;

    SELECT birth_date INTO v_user_birth
      FROM public.profiles WHERE user_id = v_user.user_id;

    SELECT q.user_id INTO v_pair
    FROM public.dating_hour_participant q
    LEFT JOIN public.profiles qp ON qp.user_id = q.user_id
    WHERE q.event_id = p_event_id
      AND q.left_at IS NULL
      AND q.user_id <> v_user.user_id
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = q.user_id OR s.user_b = q.user_id)
      )
      -- H-1 (Regression aus 055): Blockier-Schutz wiederhergestellt.
      AND NOT EXISTS (
        SELECT 1 FROM public.blocked_users b
        WHERE (b.blocker = v_user.user_id AND b.blocked = q.user_id)
           OR (b.blocker = q.user_id AND b.blocked = v_user.user_id)
      )
      -- K-1: beidseitige Alters-Kompatibilitaet (Minderjaehrigen-Schutz).
      AND public.age_compatible_bidirectional(v_user_birth, qp.birth_date)
      -- N-15: Alters-Praferenzen des Viewers aus den Preferences.
      AND (
        v_user.preferences->>'ageMin' IS NULL
        OR public.profile_age(qp.birth_date) >= (v_user.preferences->>'ageMin')::int
      )
      AND (
        v_user.preferences->>'ageMax' IS NULL
        OR public.profile_age(qp.birth_date) <= (v_user.preferences->>'ageMax')::int
      )
    LIMIT 1;

    IF v_pair.user_id IS NOT NULL THEN
      -- Beide sind verifiziert (Pruefung oben und in der Schleife).
      INSERT INTO public.dating_hour_session(event_id, user_a, user_b)
      VALUES (p_event_id, v_user.user_id, v_pair.user_id)
      ON CONFLICT (event_id, user_a, user_b) DO NOTHING;
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.match_dating_hour_round(uuid) IS
  'Paart Teilnehmer eines Dating-Hour-Events. v0.10.0, Migration 161: '
  'beide Seiten muessen verifiziert sein (serverseitig geprueft - vorher '
  'nur im Client).';

REVOKE EXECUTE ON FUNCTION public.match_dating_hour_round(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.match_dating_hour_round(uuid) TO authenticated;

-- ===========================================================================
-- 4) Transit Spark: die Gesamtfreigabe prueft die Verifikation
-- ===========================================================================
-- transit_spark_adult entscheidet fuer Radar, Matching, Kontaktversand
-- und die Gegenseiten-Pruefung. Wird die Verifikation hier ergaenzt,
-- wirkt sie auf alle vier Pfade.
CREATE OR REPLACE FUNCTION public.transit_spark_adult(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.transit_spark_enabled()
     AND public.transit_spark_is_adult(p_user_id)
     AND public.verification_granted(p_user_id);
$$;

COMMENT ON FUNCTION public.transit_spark_adult(uuid) IS
  'Freigabe fuer Transit Spark: Das Feature muss AKTIV sein (app_config, '
  'Migration 159), die Person muss volljährig UND verifiziert sein '
  '(Migration 161) - bis dahin war nur das Alter geprueft. Diese eine '
  'Funktion entscheidet fuer Radar, Matching und Kontaktversand - '
  'deshalb wirkt die Sperre auf alle drei Pfade.';

REVOKE EXECUTE ON FUNCTION public.transit_spark_adult(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transit_spark_adult(uuid)
  TO authenticated, service_role;

-- ===========================================================================
-- 5) handle_new_user: kein Geburtsdatum erfinden
-- ===========================================================================
-- Fehlt die Altersangabe, bleibt birth_date NULL. Der Wert '2000-01-01'
-- (Migration 158) machte aus "keine Angabe" stillschweigend "26 Jahre" -
-- und die 18+-Pruefung war damit nicht fail-closed.
--
-- Der Wert '2000-01-01' wird hier durch NULL ersetzt. Die
-- Alterspruefungen (transit_spark_is_adult, age_compatible_bidirectional,
-- profile_age) behandeln NULL bereits als "unbekannt" - der
-- CHECK-Constraint auf birth_date erlaubt NULL.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.profiles (
    user_id,
    name,
    gender,
    gender_preferences,
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
    '{}'::text[],
    -- Kein erfundenes Geburtsdatum (v0.10.0, Migration 161).
    --
    -- Vorher stand hier COALESCE(..., '2000-01-01'::date): ohne
    -- Altersangabe galt damit Alter 26. Die 18+-Pruefung von Transit
    -- Spark war dadurch nicht fail-closed, obwohl ihr Kommentar genau
    -- das verlangt hat. NULL heisst jetzt: Alter unbekannt.
    --
    -- Der Client schickt das Geburtsdatum immer mit
    -- (supabase_auth_service.dart). Das ist Konvention, nicht
    -- Erzwingung - deshalb steht hier NULL.
    NULLIF(NEW.raw_user_meta_data ->> 'birth_date', '')::date,
    '',
    '[]'::jsonb,
    'INTJ',
    100,
    18,
    65
  );

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Legt das Profil bei der Registrierung an. v0.10.0, Migration 161: '
  'birth_date bleibt NULL, wenn keine Altersangabe vorliegt - vorher '
  'wurde daraus stillschweigend 01.01.2000 (Alter 26).';

-- ===========================================================================
-- 6) Bestandsdaten: Profile ohne Altersangabe zuruecksetzen
-- ===========================================================================
-- Konten, die mit dem alten COALESCE registriert wurden, haben ein
-- erfundenes Geburtsdatum vom 01.01.2000. Sie werden auf NULL
-- zurueckgesetzt - sie gelten damit als "Alter unbekannt" und
-- muessen ihr Alter ueber die Einrichtung angeben.
--
-- Der Name wird zusaetzlich markiert, damit die App den Nutzer zur
-- Nacharbeit auffordert. Das ist ehrlicher als ein stillschweigend
-- erfundenes Alter 26.
UPDATE public.profiles
   SET birth_date = NULL
 WHERE birth_date = DATE '2000-01-01';

-- ===========================================================================
-- 7) Selbsttest
-- ===========================================================================
-- Die Funktion muss TRUE liefern, wenn das Profil verifiziert ist, und
-- FALSE sonst. Ein Konto ohne Profil (zufaellige UUID) liefert FALSE -
-- fail-closed.
DO $$
DECLARE
  v_ok boolean;
BEGIN
  SELECT public.verification_granted(
           '00000000-0000-0000-0000-000000000001'::uuid)
    INTO v_ok;

  IF v_ok THEN
    RAISE EXCEPTION 'verification_granted ist fail-open: unbekanntes '
      'Profil wurde als verifiziert akzeptiert';
  END IF;

  RAISE NOTICE 'verification_granted: unbekanntes Profil -> FALSE (ok)';
END;
$$;

COMMIT;
