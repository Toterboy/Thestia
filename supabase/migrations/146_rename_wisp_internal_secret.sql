-- 146: WISP_INTERNAL_SECRET -> THESTIA_INTERNAL_SECRET
--
-- "wisp" ist ein Fremdname aus einem anderen Projekt. Der interne
-- Push-Kanal heisst in der App "Thestia" - der Name im Secret war
-- Altlast. Umbenannt wird er, BEVOR rotiert wird: sonst muesste man
-- nach der Rotation noch einmal umbenennen, und die Function laeuft
-- in der Zwischenzeit ohne Secret (fail-closed, kein Push).
--
-- DREI Stellen muessen zusammenpassen:
--
--   1) Das VAULT-Secret 'wisp_internal_secret'. Aus ihm liest der
--      Datenbank-Trigger notify_push_trigger den Wert, mit dem er
--      die Edge Function aufruft. Vault kann nicht umbenennen, also:
--      neues Secret mit demselben Wert anlegen, altes loeschen.
--
--   2) Die ENV-VARIABLE der Edge Function. notify-user vergleicht
--      den empfangenen Header gegen Deno.env.get(...). Beide Namen
--      muessen gleich sein.
--
--   3) Der HTTP-HEADER zwischen Trigger und Function: 'x-wisp-internal'
--      -> 'x-thestia-internal'. Beide Seiten werden hier geaendert.
--
-- Die Funktion notify_push_trigger wird komplett neu definiert, weil
-- sie den Secret-Namen hart verdrahtet hatte. Der Body ist der der
-- LIVE-Definition entnommen (nicht rekonstruiert) und unterscheidet
-- sich nur in den beiden Namen.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Vault-Secret umbenennen
-- ---------------------------------------------------------------------------
-- Vault kennt kein RENAME, also: neuen Eintrag mit demselben Wert
-- anlegen, alten loeschen. Der Wert bleibt dabei unveraendert - die
-- ROTATION ist ein separater, manueller Schritt (der Nutzer setzt
-- danach einen neuen zufaelligen Wert in Vault UND als Function-
-- Secret).
DO $vault$
DECLARE
  v_wert text;
BEGIN
  IF EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'wisp_internal_secret')
     AND NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'thestia_internal_secret')
  THEN
    SELECT decrypted_secret INTO v_wert
      FROM vault.decrypted_secrets
     WHERE name = 'wisp_internal_secret'
     LIMIT 1;

    PERFORM vault.create_secret(v_wert, 'thestia_internal_secret');
    DELETE FROM vault.secrets WHERE name = 'wisp_internal_secret';

    RAISE NOTICE 'Vault-Secret wisp_internal_secret -> thestia_internal_secret umbenannt.';
  ELSIF EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'wisp_internal_secret')
        AND EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'thestia_internal_secret')
  THEN
    RAISE NOTICE 'Beide Vault-Secrets existieren - das alte wird entfernt.';
    DELETE FROM vault.secrets WHERE name = 'wisp_internal_secret';
  ELSIF NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'thestia_internal_secret')
  THEN
    RAISE WARNING 'Weder wisp_internal_secret noch thestia_internal_secret '
      'im Vault. Der Push-Versand bleibt aus (fail-closed) - das Secret '
      'muss neu angelegt werden.';
  END IF;
END;
$vault$;

-- ---------------------------------------------------------------------------
-- 2) Trigger-Funktion auf den neuen Secret-Namen und Header umstellen
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_push_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$

DECLARE
  v_url text;
  v_secret text := NULL;
BEGIN
  -- Secret aus Vault lesen. Falls Vault/das Secret fehlt, wird KEIN Push
  -- versendet (fail-closed f├╝r das Feature, sicher gegen Missbrauch).
  BEGIN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'thestia_internal_secret'
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'notify_push_trigger: Secret thestia_internal_secret fehlt in Vault - kein Push-Versand.';
    RETURN NEW;
  END IF;

  v_url := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/notify-user';

  IF TG_TABLE_NAME = 'matches' THEN
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-thestia-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'matches',
        'target_user_id', NEW.user_one_id,
        'title', 'Neuer Funke!',
        'body', 'Du hast einen neuen Funken - schau in deine Funken!'
      )
    );
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-thestia-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'matches',
        'target_user_id', NEW.user_two_id,
        'title', 'Neuer Funke!',
        'body', 'Du hast einen neuen Funken - schau in deine Funken!'
      )
    );
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'likes' THEN
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-thestia-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'likes',
        'target_user_id', NEW.liked_user_id,
        'title', 'Du hast ein neues Like!',
        'body', 'Jemand hat dein Profil geliked.'
      )
    );
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_push_trigger() IS
  'Push-Trigger fuer Matches, Likes und Direktnachrichten. Liest das '
  'Vault-Secret ''thestia_internal_secret'' (v0.10.0, Migration 146 - '
  'vorher ''wisp_internal_secret'') und ruft die Edge Function '
  'notify-user mit dem Header ''x-thestia-internal''. Faellt das Secret '
  'aus, wird kein Push versendet (fail-closed).';

COMMIT;
