-- 095_age_verification.sql
--
-- v0.9.1: Altersprüfung per Video-Verifizierung mit lokaler KI-Triage.
--
-- Ablauf (Client):
--   1) Selbstvideo + Liveness-Challenge (bestehend, verify-account/submit).
--   2) Lokale KI (on-device) schätzt das Alter aus einem Kamerabild und
--      vergleicht mit dem angegebenen Alter (2-Jahre-Regel).
--   3) Abweichung <= 2 Jahre (1 Gesicht, Liveness ok) -> Edge Action
--      "auto": Video bleibt für Stichproben erhalten, Badge sofort.
--      Größere Abweichung/kein Gesicht -> Status "pending", manuelle
--      Prüfung durch den Support (Admin-Queue zeigt KI-Schätzung +
--      angegebenes Alter). Der Account ist jederzeit voll nutzbar, nur
--      das Badge wartet auf die Prüfung.
--
-- Ehrlichkeitshinweis: Die lokale Prüfung ist ein Triage-Filter, kein
-- Beweis (modifizierte Clients könnten lügen). Deshalb: Video bleibt
-- erhalten, Admin-Queue + Stichproben bleiben bestehen.

-- KI-Schätzung am Profil (nur via Service-Role/Edge setzbar, siehe
-- Trigger unten - Clients können sie nicht schreiben).
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_estimated_age int;

COMMENT ON COLUMN public.profiles.verification_estimated_age IS
  '095: Lokale KI-Altersschätzung bei der Video-Verifizierung (Jahre). Nur Orientierung für die manuelle Prüfung, kein Beweis.';

-- Status 'auto' zulassen (KI unauffällig, Video für Stichproben da).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'profiles_verification_status_check'
      AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
      DROP CONSTRAINT profiles_verification_status_check;
  END IF;
END $$;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('none', 'pending', 'approved', 'rejected', 'auto'));

-- Client-Schreibschutz auch für die neue Spalte (056-Muster erweitern).
CREATE OR REPLACE FUNCTION public.prevent_client_update_verification_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role text := coalesce(
    current_setting('request.jwt.claims', true)::json->>'role', '');
BEGIN
  IF (new.is_verified IS DISTINCT FROM old.is_verified
      OR new.is_location_suspicious IS DISTINCT FROM old.is_location_suspicious
      OR new.birth_date IS DISTINCT FROM old.birth_date
      OR new.verification_status IS DISTINCT FROM old.verification_status
      OR new.verification_estimated_age IS DISTINCT FROM old.verification_estimated_age) THEN
    IF v_role IN ('authenticated', 'anon') THEN
      RAISE EXCEPTION 'Gesicherte Profil-Felder (birth_date, verification) sind clientseitig nicht aenderbar.';
    END IF;
  END IF;
  RETURN new;
END;
$$;

-- Admin-Queue: KI-Schätzung + angegebenes Alter mitschicken (schlimmste
-- Abweichung zuerst, damit 80-als-22-Fälle oben stehen).
CREATE OR REPLACE FUNCTION public.admin_list_pending_verifications()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(jsonb_agg(
           jsonb_build_object(
             'userId', p.user_id,
             'name', p.name,
             'videoPath', p.verification_video_path,
             'submittedAt', COALESCE(p.updated_at, p.created_at),
             'estimatedAge', p.verification_estimated_age,
             'statedAge', date_part('year', age(COALESCE(p.birth_date, '2000-01-01'::date)))::int
           ) ORDER BY COALESCE(p.updated_at, p.created_at) ASC), '[]'::jsonb)
  FROM public.profiles p
  WHERE public.is_current_user_admin()
    AND p.verification_status = 'pending'
    AND p.verification_video_path IS NOT NULL;
$$;
