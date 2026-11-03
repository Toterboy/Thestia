-- =============================================================================
-- 169_new_login_alert.sql
-- =============================================================================
-- Meldet dem Kontoinhaber, wenn sich ein NEUES Geraet anmeldet.
--
-- BETREIBER-AUFTRAG (03.11.2026): "Ich habe keine Mail bekommen, als ich
-- die App daten geloescht und mich neu angemeldet habe. Check die
-- Punkte noch mal genau."
--
-- DER BEFUND: Die Warnung haengte am Aufruf der App.
--
-- Die App registriert ihr Geraet nach dem Login in auth_devices. Der
-- erste Wurf lief ueber die Edge Function `notify-new-login`, die der
-- App aufrief - und die Edge Function legte die Zeile selbst an.
--
-- Das hat zwei schwaechen:
--
--   1. FAELLT DIE EDGE FUNCTION AUS (nicht deployed, Timeout, kalter
--      Start), schreibt die App die Zeile selbst - und die Mail geht
--      nie raus. Genau das ist der gemeldete Fall: der Aufruf war der
--      Flaschenhals, nicht die Logik.
--
--   2. DIE BREMSE ZAEHLTE DIE FALSCHE GROESSE. Sie hat die
--      Geraete-Zeilen der letzten Stunde gezaehlt. Nach fuenf
--      Neuinstallationen (jedes davon eine neue Zeile) war die Bremse
--      dicht - auch fuer eine echte fremde Anmeldung.
--
-- DIE LOESUNG: Der Trigger auf der TABELLE.
--
-- Der Trigger feuert bei jedem INSERT einer Geraete-Zeile - unabhaengig
-- davon, wer sie geschrieben hat (App, Fallback-Pfad der App, Admin,
-- Migration). Die Entscheidung "neu" trifft damit die Datenbank, und
-- die Mail geht auch dann raus, wenn der App-Aufruf scheitert.
--
-- DIE BREMSE ZAEHLT JETZT DIE MAILS (consume_rate_limit), nicht die
-- Geraete-Zeilen. Damit kann eine App, die sich haeufig neu
-- registriert, die Warnung nicht mehr zum Schweigen bringen.
--
-- ZUSAMMEN MIT DER EDGE FUNCTION (notify-new-login):
--
--   * Der Trigger ruft die Funktion mit dem internen Secret auf (das
--     Muster aus Migration 146, wie beim Funke-Push).
--   * Die Funktion schickt die Mail. Sie prueft NICHTS mehr selbst -
--     der Trigger ist die einzige Quelle der Wahrheit.
-- =============================================================================

BEGIN;

-- ===========================================================================
-- 1) Die Hilfsfunktion: Mail aus dem Trigger heraus anstoßen
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.notify_new_login_device(
  p_user_id uuid,
  p_device_id text,
  p_device_name text,
  p_device_model text,
  p_app_version text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_secret text := NULL;
  v_created timestamptz;
BEGIN
  -- 1) Ist das Konto aelter als 30 Minuten? Direkt nach der
  --    Registrierung gibt es keine Mail: die erste Anmeldung IST die
  --    Registrierung.
  SELECT u.created_at INTO v_created
    FROM auth.users u
   WHERE u.id = p_user_id;

  IF v_created IS NULL THEN
    RETURN;
  END IF;

  IF v_created > now() - interval '30 minutes' THEN
    RETURN;
  END IF;

  -- 2) Bremse: hoechstens 5 Mails pro Konto und Stunde. Das zaehlt die
  --    MAILS (nicht die Geraete-Zeilen) - sonst wuerde eine App, die
  --    sich haeufig neu registriert, jeden Alarm zum Schweigen bringen.
  IF NOT public.consume_rate_limit(
       'new_login_mail:' || p_user_id::text, 5, 3600) THEN
    RETURN;
  END IF;

  -- 3) Internes Secret fuer den Aufruf der Edge Function.
  BEGIN
    SELECT decrypted_secret INTO v_secret
      FROM vault.decrypted_secrets
     WHERE name = 'thestia_internal_secret'
     LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING
      'notify_new_login_device: Secret thestia_internal_secret fehlt - '
      'keine Mail versendet.';
    RETURN;
  END IF;

  -- 4) Die Mail anstoßen. Der Aufruf ist asynchron (pg_net) - die
  --    Geraete-Registrierung darf nicht darauf warten.
  PERFORM net.http_post(
    url := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/notify-new-login',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-thestia-internal', v_secret
    ),
    body := jsonb_build_object(
      'userId', p_user_id,
      'deviceId', p_device_id,
      'deviceName', p_device_name,
      'deviceModel', p_device_model,
      'appVersion', p_app_version
    )
  );
END;
$$;

COMMENT ON FUNCTION public.notify_new_login_device(uuid, text, text, text, text) IS
  'Loest die Warn-Mail fuer eine Anmeldung von einem neuen Geraet aus '
  '(v0.10.0, Migration 169). Wird vom Trigger auf auth_devices '
  'aufgerufen.';

REVOKE ALL ON FUNCTION public.notify_new_login_device(uuid, text, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_new_login_device(uuid, text, text, text, text)
  TO service_role;

-- ===========================================================================
-- 2) Der Trigger auf auth_devices
-- ===========================================================================
-- AFTER INSERT, weil ein UPDATE (last_seen_at) kein neues Geraet ist.
CREATE OR REPLACE FUNCTION public.trg_auth_devices_new_login()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Fail-open: Eine fehlgeschlagene Mail darf die Geraete-Registrierung
  -- NIE verhindern - der Nutzer soll nicht mit einem Login-Problem
  -- aus der App geworfen werden.
  BEGIN
    PERFORM public.notify_new_login_device(
      NEW.user_id,
      NEW.device_id,
      coalesce(NEW.device_name, ''),
      coalesce(NEW.device_model, ''),
      coalesce(NEW.app_version, '')
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'trg_auth_devices_new_login: %', SQLERRM;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auth_devices_new_login ON public.auth_devices;
CREATE TRIGGER trg_auth_devices_new_login
  AFTER INSERT ON public.auth_devices
  FOR EACH ROW EXECUTE FUNCTION public.trg_auth_devices_new_login();

COMMENT ON TRIGGER trg_auth_devices_new_login ON public.auth_devices IS
  'Meldet dem Kontoinhaber jede Anmeldung von einem neuen Geraet '
  '(v0.10.0, Migration 169).';

-- ===========================================================================
-- 3) Selbsttest
-- ===========================================================================
DO $check$
DECLARE
  v_count integer;
  v_body text;
BEGIN
  -- Der Trigger muss existieren.
  SELECT count(*) INTO v_count
    FROM pg_trigger
   WHERE tgname = 'trg_auth_devices_new_login'
     AND NOT tgisinternal;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'Der Trigger fuer die Neugeraete-Meldung fehlt - eine fremde '
      'Anmeldung wuerde unbemerkt bleiben.';
  END IF;

  -- Er muss auf auth_devices haengen.
  SELECT count(*) INTO v_count
    FROM pg_trigger t
   WHERE t.tgname = 'trg_auth_devices_new_login'
     AND t.tgrelid = 'public.auth_devices'::regclass;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Der Trigger haengt nicht an auth_devices.';
  END IF;

  -- Die Funktion muss die Bremse benutzen (nicht die Geraete-Zeilen
  -- zaehlen - das war der Fehler in der ersten Fassung).
  SELECT pg_get_functiondef(
    'public.notify_new_login_device(uuid,text,text,text,text)'::regprocedure
  ) INTO v_body;

  IF v_body NOT LIKE '%consume_rate_limit%' THEN
    RAISE EXCEPTION
      'Die Bremse der Neugeraete-Meldung zaehlt nicht die Mails - eine '
      'haeufig neu registrierende App wuerde jeden Alarm unterdruecken.';
  END IF;

  IF v_body NOT LIKE '%new_login_mail:%' THEN
    RAISE EXCEPTION 'Die Bremse nutzt nicht den eigenen Schluessel.';
  END IF;

  IF v_body NOT LIKE '%net.http_post%' THEN
    RAISE EXCEPTION 'Die Mail wird nicht angestoßen.';
  END IF;

  RAISE NOTICE 'Neugeraete-Meldung: Trigger auf auth_devices, Bremse zaehlt die Mails (Selbsttest ok)';
END;
$check$;

COMMIT;
