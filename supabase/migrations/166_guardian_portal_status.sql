-- =============================================================================
-- 166_guardian_portal_status.sql
-- =============================================================================
-- Das Eltern-Portal braucht den aktuellen Stand, wenn es neu geoeffnet
-- wird: sonst wuesste der Elternteil beim zweiten Besuch nicht, welche
-- Frequenz eingestellt ist und ob die Nutzungszeit begrenzt wurde.
--
-- WICHTIG: Die Funktion gibt die Einstellungen des ELTERNTEILS zurueck -
-- nicht die Daten des Kindes. Name und Alter des Kindes werden NICHT
-- ausgegeben: das Portal gehoert den Sorgeberechtigten, aber es soll kein
-- Vollprofil des Kindes sein (ROADMAP.md:764 - "Kein Volltext-Profil").
--
-- Nur service_role: der Token ist die Berechtigung, und der Aufrufer ist
-- die Edge Function.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.guardian_portal_status(
  p_token text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row record;
BEGIN
  IF p_token IS NULL OR length(p_token) < 16 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  SELECT c.* INTO v_row
    FROM public.guardian_consents c
   WHERE c.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
     AND c.status IN ('pending','active','expired')
     AND c.token_expires_at > now()
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  RETURN jsonb_build_object(
    'ok',                true,
    'status',            v_row.status,
    'notifyEnabled',     v_row.notify_enabled,
    'notifyFrequency',   v_row.notify_frequency,
    'usageLimitEnabled', v_row.usage_limit_enabled,
    'usageStartMin',     v_row.usage_start_min,
    'usageEndMin',       v_row.usage_end_min,
    'hasPin',            v_row.pin_hash IS NOT NULL,
    'requestedAt',       v_row.requested_at,
    'confirmedAt',       v_row.confirmed_at,
    'accessUntil',       v_row.access_until,
    'accessPolicy',      v_row.access_policy
  );
END;
$$;

COMMENT ON FUNCTION public.guardian_portal_status(text) IS
  'Der Stand der elterlichen Einstellungen fuer das Portal. Enthaelt '
  'KEINE Daten des Kindes ausser dem Freigabestatus (v0.10.0, '
  'Migration 166). Nur service_role.';

REVOKE ALL ON FUNCTION public.guardian_portal_status(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guardian_portal_status(text) TO service_role;

-- Selbsttest
DO $check$
DECLARE
  v_typ text;
BEGIN
  SELECT pg_get_functiondef('public.guardian_portal_status(text)'::regprocedure)
    INTO v_typ;
  IF v_typ IS NULL THEN
    RAISE EXCEPTION 'guardian_portal_status fehlt.';
  END IF;
  -- Der Name des Kindes darf NICHT ausgegeben werden.
  IF v_typ LIKE '%birth_date%' OR v_typ LIKE '%name%' THEN
    RAISE EXCEPTION
      'guardian_portal_status gibt Daten des Kindes preis - das Portal '
      'soll nur den Freigabestand zeigen.';
  END IF;
  RAISE NOTICE 'guardian_portal_status: gibt nur den Freigabestand aus (Selbsttest ok)';
END;
$check$;

COMMIT;
