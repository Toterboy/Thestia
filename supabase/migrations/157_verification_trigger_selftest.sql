-- =============================================================================
-- 157_verification_trigger_selftest.sql
-- =============================================================================
-- Beweis, dass der Client-Schreibschutz fuer die Verifikationsfelder
-- wirklich greift - ausgefuehrt bei JEDEM Deploy.
--
-- Warum das noetig ist:
--
-- Der Schutz ist eine Trigger-Funktion, die an `UPDATE public.profiles`
-- haengt. Ein Trigger ist unsichtbar: er liegt in der Datenbank, nicht
-- im App-Code, und ein Fehler darin faellt erst dann auf, wenn jemand
-- die Werte manipuliert, die er nicht manipulieren darf.
--
-- Genau das ist passiert. Migration 155 hat die Trigger-Funktion mit
-- `pg_has_role(current_user, 'authenticated', 'member')` neu definiert.
-- Im SECURITY DEFINER-Kontext ist current_user der OWNER der Funktion,
-- die Bedingung war deshalb immer falsch, und die RAISE EXCEPTION wurde
-- nie ausgeloest. Die Funktion sah intakt aus, die Migration war
-- fehlerfrei deployt - und die Sperre lief ins Leere. Die Migration 156
-- hat die Funktion repariert; dieser Selbsttest verhindert, dass so
-- etwas unbemerkt zurueckkommt.
--
-- Der Test braucht kein Testkonto und keine Captcha-Loesung: er
-- simuliert den JWT-Role-Claim, den die Datenbank sieht, und laeuft
-- komplett in der Transaktion der Migration. Ein Fehler wuerde den
-- Deploy abbrechen - das ist gewollt.
--
-- Beide Richtungen werden geprueft:
--   1. Mit `role=authenticated` muss der Versuch scheitern.
--   2. Mit `role=service_role` muss er gelingen - sonst koennten die
--      Edge Functions (verify-account) das Badge nicht mehr setzen.
--
-- Der Test aendert keine Daten: der urspruengliche Wert wird im selben
-- Lauf zurueckgeschrieben, und bei einem Abbruch rollt die Migration
-- komplett zurueck.
-- =============================================================================

BEGIN;

DO $selftest$
DECLARE
  v_uid      uuid;
  v_orig     boolean;
  v_wert     boolean;
  v_err      text;
  v_ursache  text;
BEGIN
  -- Ein vorhandenes Profil als Testobjekt. Ohne Profil (frische
  -- Datenbank) gibt es nichts zu pruefen - das ist kein Fehler.
  SELECT user_id, coalesce(is_verified, false)
    INTO v_uid, v_orig
    FROM public.profiles
   LIMIT 1;

  IF v_uid IS NULL THEN
    RAISE NOTICE
      'Selbsttest uebersprungen: es gibt noch kein Profil in der Datenbank.';
    RETURN;
  END IF;

  v_wert := NOT v_orig;

  -- ------------------------------------------------------------------
  -- 1) Der Angreifer-Fall: Rolle "authenticated" (jeder angemeldete
  --    Nutzer) versucht, is_verified selbst zu setzen.
  --
  --    Die Rolle wird NICHT per SET ROLE gesetzt - die Trigger-Funktion
  --    ist SECURITY DEFINER und laeuft ohnehin als Owner. Entscheidend
  --    ist allein der Role-Claim aus dem JWT, und genau den setzen wir
  --    hier. Das entspricht dem, was die Datenbank bei einem echten
  --    Request sieht.
  -- ------------------------------------------------------------------
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('role', 'authenticated', 'sub', v_uid::text)::text,
    true);

  BEGIN
    UPDATE public.profiles
       SET is_verified = v_wert
     WHERE user_id = v_uid;
  EXCEPTION WHEN others THEN
    v_err := SQLERRM;
    v_ursache := SQLSTATE;
  END;

  IF v_err IS NULL THEN
    -- Der Schreibschutz hat NICHT ausgeloest. Die Migration bricht ab,
    -- und weil die gesamte Migration eine Transaktion ist, wird der
    -- eben ausgefuehrte UPDATE mit zurueckgerollt.
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: ein angemeldeter Nutzer konnte '
      'is_verified selbst setzen (SQLSTATE %) - der Schreibschutz der '
      'Verifikationsfelder greift nicht. Migration 156 zurueckrollen und '
      'die Trigger-Funktion pruefen.', coalesce(v_ursache, '-');
  END IF;

  IF v_err NOT LIKE '%clientseitig nicht aenderbar%' THEN
    -- Ein Fehler, aber nicht der erwartete: z. B. ein fehlendes Grant.
    -- Dann waere die Sperre auch fuer echte Nutzer zu streng - oder
    -- gar nicht die, die gemeint ist.
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: der Schreibschutz hat mit "%" '
      'abgewiesen, erwartet wurde die Meldung "clientseitig nicht '
      'aenderbar".', v_err;
  END IF;

  -- ------------------------------------------------------------------
  -- 2) Der Gegenfall: Rolle "service_role" (Edge Functions) MUSS
  --    schreiben duerfen. Sonst koennte verify-account kein Badge
  --    setzen - die App waere fuer niemanden mehr freigebbar.
  -- ------------------------------------------------------------------
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('role', 'service_role', 'sub', v_uid::text)::text,
    true);

  BEGIN
    UPDATE public.profiles
       SET is_verified = v_wert
     WHERE user_id = v_uid;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: die Edge Function-Rolle '
      'service_role kann is_verified nicht mehr setzen ("%"). Die '
      'Verifikations-Freigabe waere damit kaputt.', SQLERRM;
  END;

  -- Urspruenglichen Wert zurueckschreiben.
  UPDATE public.profiles
     SET is_verified = v_orig
   WHERE user_id = v_uid;

  -- ------------------------------------------------------------------
  -- 3) Und derselbe Test fuer das zweite geschuetzte Feld: das
  --    verifizierte Alter. Wer es selbst setzen koennte, koennte die
  --    Altersgrenze des Jugendschutzes aushebeln.
  -- ------------------------------------------------------------------
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('role', 'authenticated', 'sub', v_uid::text)::text,
    true);

  v_err := NULL;
  BEGIN
    UPDATE public.profiles
       SET verified_age = 99
     WHERE user_id = v_uid;
  EXCEPTION WHEN others THEN
    v_err := SQLERRM;
  END;

  IF v_err IS NULL THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: ein angemeldeter Nutzer konnte '
      'verified_age selbst setzen - der Jugendschutz waere damit '
      'client-kontrolliert.';
  END IF;

  RAISE NOTICE
    'Selbsttest bestanden: geschuetzte Felder werden abgewiesen, '
    'service_role darf schreiben.';
END;
$selftest$;

-- Der JWT-Claim wird fuer die restliche Migration wieder zurueckgesetzt,
-- damit nachfolgende Anweisungen nicht mit einem erfundenen Rollen-Claim
-- laufen.
RESET request.jwt.claims;

COMMIT;
