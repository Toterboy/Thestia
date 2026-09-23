-- 120_auto_verification_audit.sql
--
-- v0.9.0 (Manipulationsschutz): Auto-Freigaben ("auto") waren nach der
-- Erteilung nirgends mehr sichtbar - die versprochenen "Stichproben"
-- fanden faktisch nicht statt. Ein modifizierter Client konnte damit
-- (falsches Geburtsdatum + erfundene KI-Schätzung + echtes Video) das
-- Badge erschleichen, ohne je einem Menschen zu begegnen.
--
-- Diese Migration ergänzt die Audit-Liste: Alle Auto-Freigaben mit
-- vorhandenem Video, neueste zuerst. Der Support sieht sie im
-- Admin-Tab ("Stichproben"), schaut das Video an und bestätigt
-- (review/approve -> 'approved') oder entzieht (review/reject ->
-- Badge weg + Video gelöscht). Der Angriff hinterlässt damit immer
-- ein echtes Video als Beweis.
--
-- Reine Ergänzung: Bestehende Funktionen/Flows bleiben unverändert.

CREATE OR REPLACE FUNCTION public.admin_list_auto_verifications()
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
           ) ORDER BY COALESCE(p.updated_at, p.created_at) DESC), '[]'::jsonb)
  FROM public.profiles p
  WHERE public.is_current_user_admin()
    AND p.verification_status = 'auto'
    AND p.verification_video_path IS NOT NULL;
$$;

COMMENT ON FUNCTION public.admin_list_auto_verifications() IS
  '120: Audit-Liste der Auto-Freigaben (KI-Triage) für nachträgliche Stichproben - neueste zuerst.';

REVOKE ALL ON FUNCTION public.admin_list_auto_verifications() FROM public;
GRANT EXECUTE ON FUNCTION public.admin_list_auto_verifications() TO authenticated;
