-- Migration 113: Push-Texte "Match" -> "Funke" (Nutzerwunsch)
--
-- Der DB-Trigger notify_push_trigger (Migration 040) schickte bei neuen
-- Matches title 'Neues Match!' / body 'Du hast ein neues Match ...'.
-- In der App heißt das Konzept FUNKE - die Push passt sich an:
--   title 'Neuer Funke!', body 'Du hast einen neuen Funken!'.

CREATE OR REPLACE FUNCTION public.notify_push_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_url text;
  v_secret text := NULL;
BEGIN
  -- Secret aus Vault lesen. Falls Vault/das Secret fehlt, wird KEIN Push
  -- versendet (fail-closed für das Feature, sicher gegen Missbrauch).
  BEGIN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'wisp_internal_secret'
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'notify_push_trigger: Secret wisp_internal_secret fehlt in Vault - kein Push-Versand.';
    RETURN NEW;
  END IF;

  v_url := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/notify-user';

  IF TG_TABLE_NAME = 'matches' THEN
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-wisp-internal', v_secret
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
        'x-wisp-internal', v_secret
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
        'x-wisp-internal', v_secret
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
