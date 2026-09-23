-- 121_delete_account_grants.sql
--
-- Fix "Löschung abgelehnt (bug_reports)": Das Projekt hat keine
-- Supabase-Default-Privilegien für service_role (s. Migration 100/112),
-- sondern nur explizite Minimal-Grants. delete-account (DSGVO Art. 17)
-- braucht zum Komplettlöschen DELETE auf:
--   - bug_reports (eigene Meldungen; bisher nur INSERT aus 112),
--   - user_reports (Meldungen GEGEN den Nutzer),
--   - rate_limit_hits (operative Zähler; consume_rate_limit selbst
--     läuft als SECURITY-DEFINER-RPC und ist unbetroffen).
-- Ohne diese Grants schlug JEDER Löschversuch mit 500 fehl
-- ("Daten-Purge fehlgeschlagen (bug_reports)").
-- RLS bleibt unberührt (service_role umgeht RLS; Clients sind weiter
-- durch fehlende Policies blockiert).

GRANT DELETE ON public.bug_reports TO service_role;
GRANT DELETE ON public.user_reports TO service_role;
GRANT DELETE ON public.rate_limit_hits TO service_role;
