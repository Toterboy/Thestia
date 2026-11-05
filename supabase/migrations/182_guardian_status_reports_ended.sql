-- 182: Die App muss erfahren, dass die Freigabe beendet ist.
--
-- BEFUND (04.11.2026, gefunden beim Test auf dem Android-Emulator):
--
-- public.get_my_guardian_status() suchte die Freigabe mit
--
--     status IN ('pending','active','expired')
--
-- 'revoked' fehlte in der Liste. Bei einer widerrufenen Freigabe fand
-- die Funktion also KEINE Zeile und meldete im Ersatzweg
--
--     'status': 'none'
--
-- zurueck. Fuer die App war eine widerrufene Freigabe damit nicht von
-- "es gab nie eine Freigabe" zu unterscheiden - sie zeigte in beiden
-- Faellen "Elternfreigabe anfordern".
--
-- Warum das mehr als Kosmetik ist: Mit dem Ende der Freigabe wird die
-- E-Mail-Adresse des Elternteils geloescht (Migration 179). Der
-- Jugendliche soll das WISSEN - der Screen sagt es jetzt ("Die Freigabe
-- ist beendet", Migration 180 in der App). Aber genau dieser Bild-
-- schirm bekam den Zustand nie.
--
-- DER TEST HAT ES GEFUNDEN: Der Widget-Test fuettert das Modell direkt
-- mit dem Status - der Serverpfad wurde dabei nicht geprueft. Der
-- Emulator-Test ging den echten Weg (App -> Server -> App) und hat den
-- Fehler sofort gezeigt.
--
-- 'revoked' kommt jetzt dazu. Fuer den Nutzer aendert sich nichts
-- beim Anfordern: der Jugendliche kann weiterhin eine neue Freigabe
-- anfordern (der Knopf bleibt). Er sieht nur jetzt, dass es eine
-- gab und dass sie beendet ist.
--
-- Migration 180 wird NICHT veraendert - sie ist bereits angewandt.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_guardian_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_row    record;
  v_profile record;
  v_age    int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO v_profile
    FROM public.profiles
   WHERE user_id = v_uid;

  v_age := public.guardian_eligible_age(v_uid);

  SELECT * INTO v_row
    FROM public.guardian_consents
   WHERE child_user_id = v_uid
     AND status IN ('pending','active','expired','revoked')
   ORDER BY requested_at DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'consentState',       coalesce(v_profile.consent_state, 'none'),
      'supervised',         coalesce(v_profile.supervised, false),
      'status',             'none',
      'age',                v_age,
      'guardianEmail',      null,
      'guardianEmailMasked', null,
      'notifyEnabled',      false,
      'notifyFrequency',    'none',
      'usageLimitEnabled',  false,
      'usageStartMin',      null,
      'usageEndMin',        null,
      'hasPin',             false,
      'accessPolicy',       'ended',
      'accessUntil',        null,
      'transitionPending',  false,
      'confirmedAt',        null,
      'revokedAt',          v_profile.consent_revoked_at
    );
  END IF;

  RETURN jsonb_build_object(
    'consentState',        coalesce(v_profile.consent_state, 'none'),
    'supervised',          coalesce(v_profile.supervised, false),
    'status',              v_row.status,
    'age',                 v_age,
    'guardianEmail',       v_row.guardian_email,
    'guardianEmailMasked', public.guardian_mask_email(v_row.guardian_email),
    'notifyEnabled',       v_row.notify_enabled,
    'notifyFrequency',     v_row.notify_frequency,
    'usageLimitEnabled',   v_row.usage_limit_enabled,
    'usageStartMin',       v_row.usage_start_min,
    'usageEndMin',         v_row.usage_end_min,
    'hasPin',              v_row.pin_hash IS NOT NULL,
    'accessPolicy',        v_row.access_policy,
    'accessUntil',         v_row.access_until,
    'graceMonths',         v_row.grace_months,
    -- Migration 180: Wann wurde die E-Mail-Adresse des Elternteils
    -- geloescht? Die App sagt das dem Nutzer - und kann es nur sagen,
    -- wenn der Server es weiss.
    'emailDeletedAt',      v_row.email_deleted_at,
    'confirmedAt',         v_row.confirmed_at,
    'revokedAt',           v_row.revoked_at,
    -- Der Screen zum 18. Geburtstag steht an, wenn das Konto volljährig
    -- geworden ist, eine aktive Freigabe besteht und noch nichts
    -- entschieden wurde.
    'transitionPending',   (v_age IS NOT NULL AND v_age >= 18
                             AND v_row.status = 'active'
                             AND coalesce(v_profile.guardian_transition_done, false) = false)
  );
END;
$$;;

COMMENT ON FUNCTION public.get_my_guardian_status() IS
  'Der Stand der elterlichen Aufsicht fuer die App: Freigabe, '
  'Benachrichtigungs-Frequenz, Nutzungszeit, PIN vorhanden, ob der '
  'Screen zum 18. Geburtstag ansteht (Migration 165), ob die '
  'E-Mail-Adresse des Elternteils geloescht wurde (Migration 180) und '
  'ob die Freigabe beendet ist (Migration 182).';

-- Selbsttest: die Liste muss 'revoked' enthalten.
DO $check$
DECLARE
  v_typ text;
BEGIN
  SELECT pg_get_functiondef('public.get_my_guardian_status()'::regprocedure)
    INTO v_typ;

  IF v_typ NOT LIKE '%status IN (''pending'',''active'',''expired'',''revoked'')%' THEN
    RAISE EXCEPTION
      'get_my_guardian_status meldet die beendete Freigabe nicht - die '
      'App wuerde "keine Freigabe" anzeigen, obwohl es eine gab.';
  END IF;

  IF v_typ NOT LIKE '%emailDeletedAt%' THEN
    RAISE EXCEPTION
      'get_my_guardian_status meldet den Loeschzeitpunkt der '
      'Eltern-Adresse nicht mehr.';
  END IF;

  RAISE NOTICE
    'Die Status-RPC meldet jetzt auch die beendete Freigabe (Selbsttest ok)';
END;
$check$;

COMMIT;
