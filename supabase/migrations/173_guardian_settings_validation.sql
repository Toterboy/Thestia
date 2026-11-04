-- 173: Eltern-Einstellungen - Werte pruefen und nichts ungewollt loeschen
--
-- BEFUND (04.11.2026, Audit der Edge Functions):
--
-- Die RPC public.set_guardian_portal_settings() (Migration 165) hatte
-- zwei Fehler:
--
-- 1) KEINE BEREICHSPRUEFUNG
--    Die Minutenwerte (Nutzungszeit) wurden ungeprueft gespeichert.
--    Die Edge Function reicht Number(body.usageStartMin) durch - ein
--    "abc" ergibt NaN, ein "-5" ergibt -5, ein 99999 ergibt 99999.
--    Gespeichert wurde alles. Die Anzeige im Elternportal zeigte dann
--    eine unsinnige Zeit ("-5 Minuten seit Mitternacht").
--
-- 2) DIE NUTZUNGSZEIT WIRD UNGEWOLLT GELOESCHT
--    Die UPDATE-Zeile schrieb:
--
--        usage_start_min = p_usage_start_min,
--        usage_end_min   = p_usage_end_min,
--
--    Die uebrigen Felder nutzen coalesce(p_x, x) - bleiben also
--    unveraendert, wenn der Wert nicht mitkommt. Bei der Nutzungszeit
--    war das anders: fehlte der Wert im Request, wurde die Spalte auf
--    NULL gesetzt. "usage_limit_enabled" blieb dabei true - die
--    Beschraenkung war also sichtbar aktiv, wirkte aber nicht mehr.
--
--    Das ist im Jugendschutz-relevant: Der Elternteil glaubt, die
--    Nutzungszeit sei gesetzt, und sie ist es nicht.
--
-- DIE LOESUNG:
--
--   * coalesce fuer beide Minutenwerte - ein unvollstaendiger Request
--     loescht nichts.
--   * Bereichspruefung 0..1439 (Minuten seit Mitternacht) und
--     "Ende > Beginn", wenn beide gesetzt sind.
--   * Wenn die Nutzungszeit aktiviert wird, MUSS sie auch gesetzt
--     sein. Sonst gibt es eine "aktive, aber wirkungslose"
--     Beschraenkung.
--
-- Die zweite RPC (set_guardian_settings_with_pin, Migration 167) nutzt
-- bereits coalesce - sie wird hier nur um dieselbe Bereichspruefung
-- ergaenzt, damit die beiden Wege (Elternportal und Kind mit PIN)
-- dieselben Grenzen haben.

BEGIN;

-- -------------------------------------------------------------------------
-- 1) Elternportal: coalesce + Bereichspruefung
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_guardian_portal_settings(
  p_token                text,
  p_notify_enabled       boolean,
  p_notify_frequency     text,
  p_usage_limit_enabled  boolean,
  p_usage_start_min      int,
  p_usage_end_min        int,
  p_pin                  text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row record;
BEGIN
  IF p_token IS NULL OR length(p_token) < 16 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END;

  SELECT * INTO v_row
    FROM public.guardian_consents
   WHERE token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
     AND status = 'active'
     AND token_expires_at > now()
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END;

  IF p_notify_frequency IS NOT NULL
     AND p_notify_frequency NOT IN ('daily','weekly','monthly','none') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_frequency');
  END;

  -- Die Nutzungszeit ist nur mit PIN erlaubt: sie ist die einzige
  -- Einstellung, die den Jugendlichen in seiner Freiheit beschraenkt.
  IF coalesce(p_usage_limit_enabled, false) AND p_pin IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pin_required');
  END;

  -- PIN: genau vier Ziffern.
  IF p_pin IS NOT NULL AND p_pin !~ '^[0-9]{4}$' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_pin');
  END;

  -- NEU (04.11.2026): Bereich der Nutzungszeit.
  --
  -- Die Minuten sind "Minuten seit Mitternacht" - 0..1439. Ausserhalb
  -- dieses Bereichs waere die Anzeige im Elternportal unsinnig ("-5
  -- Minuten seit Mitternacht") und die Zeitentscheidung unbrauchbar.
  IF p_usage_start_min IS NOT NULL
     AND (p_usage_start_min < 0 OR p_usage_start_min > 1439) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_usage_time');
  END IF;
  IF p_usage_end_min IS NOT NULL
     AND (p_usage_end_min < 0 OR p_usage_end_min > 1439) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_usage_time');
  END IF;

  -- Beide Werte gesetzt: das Ende muss nach dem Beginn liegen.
  IF p_usage_start_min IS NOT NULL AND p_usage_end_min IS NOT NULL
     AND p_usage_end_min <= p_usage_start_min THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_usage_time');
  END IF;

  -- NEU (04.11.2026): Eine aktive Nutzungszeit braucht eine Zeit.
  --
  -- Sonst gibt es den Zustand "aktiv, aber ohne Wirkung" - fuer den
  -- Elternteil ist das der schlimmere Fall, weil er sich auf eine
  -- Beschraenkung verlaesst, die es nicht gibt.
  IF coalesce(p_usage_limit_enabled, v_row.usage_limit_enabled)
     AND coalesce(p_usage_start_min, v_row.usage_start_min) IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'usage_time_required');
  END IF;

  UPDATE public.guardian_consents
     SET notify_enabled      = coalesce(p_notify_enabled, notify_enabled),
         notify_frequency    = coalesce(p_notify_frequency, notify_frequency),
         usage_limit_enabled = coalesce(p_usage_limit_enabled, usage_limit_enabled),
         -- NEU (04.11.2026): coalesce statt direktem Zuweisen. Ein
         -- Request, der die Nutzungszeit nicht mitschickt, darf sie
         -- nicht loeschen.
         usage_start_min     = coalesce(p_usage_start_min, usage_start_min),
         usage_end_min       = coalesce(p_usage_end_min, usage_end_min),
         pin_hash            = CASE WHEN p_pin IS NOT NULL
                                   THEN extensions.crypt(p_pin, extensions.gen_salt('bf'))
                                   ELSE pin_hash END,
         pin_set_at          = CASE WHEN p_pin IS NOT NULL THEN now() ELSE pin_set_at END,
         updated_at          = now()
   WHERE id = v_row.id;

  INSERT INTO public.guardian_consent_audit
    (consent_id, child_user_id, actor, action, detail)
  VALUES
    (v_row.id, v_row.child_user_id, 'guardian', 'settings_changed',
     jsonb_build_object(
       'notifyEnabled',   coalesce(p_notify_enabled, v_row.notify_enabled),
       'notifyFrequency', coalesce(p_notify_frequency, v_row.notify_frequency),
       'usageLimit',      coalesce(p_usage_limit_enabled, v_row.usage_limit_enabled),
       'usageStartMin',   coalesce(p_usage_start_min, v_row.usage_start_min),
       'usageEndMin',     coalesce(p_usage_end_min, v_row.usage_end_min),
       'pinSet',          p_pin IS NOT NULL
     ));

  RETURN jsonb_build_object('ok', true);
END;
$$;

COMMENT ON FUNCTION public.set_guardian_portal_settings(text, boolean, text, boolean, int, int, text) IS
  'Der Elternteil stellt im Portal ein: Benachrichtigungen (Haeufigkeit), Nutzungszeit und PIN. Die Nutzungszeit ist nur mit PIN erlaubt - sie beschraenkt den Jugendlichen. Die Minuten sind Minuten seit Mitternacht (0..1439). v0.10.0, Migration 173: coalesce fuer die Nutzungszeit (ein unvollstaendiger Request loescht nichts mehr) und Bereichspruefung.';

-- -------------------------------------------------------------------------
-- 2) Kind mit PIN: dieselbe Bereichspruefung
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_guardian_settings_with_pin(
  p_pin                text,
  p_notify_frequency  text DEFAULT NULL,
  p_usage_limit_enabled boolean DEFAULT NULL,
  p_usage_start_min   int DEFAULT NULL,
  p_usage_end_min     int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_row  record;
  v_hash text;
  v_ok   boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_pin IS NULL OR p_pin !~ '^[0-9]{4}$' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_pin');
  END;

  IF p_notify_frequency IS NOT NULL
     AND p_notify_frequency NOT IN ('daily','weekly','monthly','none') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_frequency');
  END;

  -- NEU (04.11.2026): Bereich der Nutzungszeit - identisch zum
  -- Elternportal (Migration 173), damit beide Wege dieselben Grenzen
  -- haben.
  IF p_usage_start_min IS NOT NULL
     AND (p_usage_start_min < 0 OR p_usage_start_min > 1439) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_usage_time');
  END IF;
  IF p_usage_end_min IS NOT NULL
     AND (p_usage_end_min < 0 OR p_usage_end_min > 1439) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_usage_time');
  END IF;
  IF p_usage_start_min IS NOT NULL AND p_usage_end_min IS NOT NULL
     AND p_usage_end_min <= p_usage_start_min THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_usage_time');
  END IF;

  -- Rate-Limit: 5 Versuche pro Stunde. Dieselbe Sperre wie bei
  -- verify_guardian_pin - zwei getrennte Zaehler wuerden die Sperre
  -- umgehen (5 hier, 5 dort).
  IF NOT public.consume_rate_limit(
       'guardian_pin:' || v_uid::text, 5, 3600) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'rate_limited');
  END;

  SELECT c.id, c.pin_hash INTO v_row
    FROM public.guardian_consents c
   WHERE c.child_user_id = v_uid
     AND c.status = 'active'
   ORDER BY c.requested_at DESC
   LIMIT 1;

  IF NOT FOUND OR v_row.pin_hash IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_pin');
  END;

  v_hash := v_row.pin_hash;
  v_ok := (extensions.crypt(p_pin, v_hash) = v_hash);

  IF NOT v_ok THEN
    RETURN jsonb_build_object('ok', false, 'error', 'wrong_pin');
  END;

  UPDATE public.guardian_consents
     SET notify_frequency    = coalesce(p_notify_frequency, notify_frequency),
         usage_limit_enabled = coalesce(p_usage_limit_enabled, usage_limit_enabled),
         usage_start_min     = coalesce(p_usage_start_min, usage_start_min),
         usage_end_min       = coalesce(p_usage_end_min, usage_end_min),
         updated_at          = now()
   WHERE id = v_row.id;

  INSERT INTO public.guardian_consent_audit
    (consent_id, child_user_id, actor, action, detail)
  VALUES
    (v_row.id, v_uid, 'youth', 'settings_changed_with_pin',
     jsonb_build_object(
       'notifyFrequency',   p_notify_frequency,
       'usageLimitEnabled', p_usage_limit_enabled,
       'usageStartMin',     p_usage_start_min,
       'usageEndMin',       p_usage_end_min
     ));

  RETURN jsonb_build_object('ok', true);
END;
$$;

COMMENT ON FUNCTION public.set_guardian_settings_with_pin(text, text, boolean, int, int) IS
  'Aendert die Einstellungen der Aufsicht - NUR mit der korrekten PIN des Elternteils. Die Pruefung laeuft serverseitig gegen den bcrypt-Hash (v0.10.0, Migration 167). Ohne PIN wird nichts geaendert. Migration 173: Bereichspruefung fuer die Nutzungszeit (0..1439).';

-- Die Rechte bleiben unveraendert - sie werden hier nur zur Sicherheit
-- erneut gesetzt, damit die Migration auch nach einem Handgriff in
-- der Datenbank sicher ist.
REVOKE ALL ON FUNCTION public.set_guardian_settings_with_pin(text, text, boolean, int, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_guardian_settings_with_pin(text, text, boolean, int, int)
  TO authenticated;

COMMIT;
