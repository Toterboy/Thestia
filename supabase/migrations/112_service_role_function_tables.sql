-- Migration 112: service_role-DML für Edge Functions (SYSTEM-FIX)
--
-- ROOT CAUSE (Build 27-Verifikation, Server-Log-Beweis): Das Projekt hat
-- die Supabase-Default-Privilegien für service_role nie erhalten
-- (siehe Migration 100) - und nahezu ALLE Tabellen geben service_role
-- nur REFERENCES/TRIGGER/TRUNCATE. Jede Edge Function, die Profile oder
-- Beziehungsdaten als service_role liest/schreibt, lief deshalb still
-- ins Leere:
--
--   - verify-account 'submit'/'auto'/'review' -> 500
--     ("Submit update error: 42501 permission denied for table profiles",
--     Function-Log 2026-09-19) => "Einreichen schlägt fehl"
--   - match-media (profiles.photos via Service-Role) -> kein Schlüssel
--     => fremde Profilbilder unsichtbar
--   - notify-user (profiles-Prefs/FCM-Token via Service-Role) ->
--     "no_profile" => KEIN Push je versendet
--   - send-bug-report / report-image (INSERTs) -> still verworfen
--
-- FIX nach Projekt-Konvention (explizite Grants wie 045/067/100):
-- kleinstmögliche Rechte NUR für das, was die Functions brauchen
-- (Service-Role umgeht RLS - least privilege bleibt bestehen).

GRANT SELECT, UPDATE ON public.profiles TO service_role;
GRANT SELECT ON public.matches TO service_role;
GRANT SELECT ON public.match_quiz_state TO service_role;
GRANT SELECT ON public.likes TO service_role;
GRANT SELECT ON public.dating_hour_session TO service_role;
GRANT INSERT ON public.bug_reports TO service_role;
GRANT INSERT ON public.photo_moderation TO service_role;

-- chat_image_hashes nur falls vorhanden (report-image Lookup).
DO $$
BEGIN
  IF to_regclass('public.chat_image_hashes') IS NOT NULL THEN
    EXECUTE 'GRANT SELECT ON public.chat_image_hashes TO service_role';
  END IF;
END
$$;
