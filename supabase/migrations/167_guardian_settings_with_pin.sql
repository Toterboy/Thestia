-- =============================================================================
-- 167_guardian_settings_with_pin.sql
-- =============================================================================
-- Der Jugendliche darf die Einstellungen der Aufsicht NICHT einfach
-- aendern - die Nutzungszeit ist die einzige Einstellung, die ihn in
-- seiner Freiheit beschraenkt, und sie ist mit der vierstelligen PIN
-- des Elternteils gesichert (Migration 165).
--
-- Damit die PIN etwas schuetzt, muss die PRUEFUNG auf dem Server
-- passieren: ein lokaler Vergleich im Geraet wuerde durch einen
-- gepatchten Client umgangen, und die PIN waere fuer die Jugendlichen
-- sichtbar (im Klartext im Speicher oder im Code).
--
-- Diese Funktion:
--
--   1. prueft die PIN gegen den bcrypt-Hash (serverseitig),
--   2. begrenzt die Versuche (5 pro Stunde, wie verify_guardian_pin),
--   3. schreibt die Einstellungen NUR bei korrekter PIN,
--   4. protokolliert die Aenderung im Audit-Trail.
--
-- Ohne PIN (p_pin ist NULL) wird NICHTS geaendert. Es gibt keinen Weg,
-- die Nutzungszeit ohne die PIN des Elternteils zu verschieben.
-- =============================================================================

BEGIN;

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
  END IF;

  IF p_notify_frequency IS NOT NULL
     AND p_notify_frequency NOT IN ('daily','weekly','monthly','none') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_frequency');
  END IF;

  -- Rate-Limit: 5 Versuche pro Stunde. Dieselbe Sperre wie bei
  -- verify_guardian_pin - zwei getrennte Zaehler wuerden die Sperre
  -- umgehen (5 hier, 5 dort).
  IF NOT public.consume_rate_limit(
       'guardian_pin:' || v_uid::text, 5, 3600) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'rate_limited');
  END IF;

  SELECT c.id, c.pin_hash INTO v_row
    FROM public.guardian_consents c
   WHERE c.child_user_id = v_uid
     AND c.status = 'active'
   ORDER BY c.requested_at DESC
   LIMIT 1;

  IF NOT FOUND OR v_row.pin_hash IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_pin');
  END IF;

  v_hash := v_row.pin_hash;
  v_ok := (extensions.crypt(p_pin, v_hash) = v_hash);

  IF NOT v_ok THEN
    RETURN jsonb_build_object('ok', false, 'error', 'wrong_pin');
  END IF;

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
  'Aendert die Einstellungen der Aufsicht - NUR mit der korrekten PIN des '
  'Elternteils. Die Pruefung laeuft serverseitig gegen den bcrypt-Hash '
  '(v0.10.0, Migration 167). Ohne PIN wird nichts geaendert.';
REVOKE ALL ON FUNCTION public.set_guardian_settings_with_pin(text, text, boolean, int, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_guardian_settings_with_pin(text, text, boolean, int, int)
  TO authenticated;

-- Selbsttest
DO $check$
DECLARE
  v_typ text;
BEGIN
  SELECT pg_get_functiondef(
    'public.set_guardian_settings_with_pin(text,text,boolean,int,int)'::regprocedure
  ) INTO v_typ;

  IF v_typ IS NULL THEN
    RAISE EXCEPTION 'set_guardian_settings_with_pin fehlt.';
  END IF;

  IF v_typ NOT LIKE '%crypt%' THEN
    RAISE EXCEPTION
      'set_guardian_settings_with_pin prueft die PIN nicht - die '
      'Nutzungszeit waere ohne die PIN des Elternteils aenderbar.';
  END IF;

  IF v_typ NOT LIKE '%consume_rate_limit%' THEN
    RAISE EXCEPTION
      'set_guardian_settings_with_pin hat keine Sperre - die PIN waere in '
      'Sekunden durchprobierbar.';
  END IF;

  RAISE NOTICE 'Eltern-Aufsicht: Aenderungen nur mit PIN, mit Sperre (Selbsttest ok)';
END;
$check$;

COMMIT;
