-- 122_delete_account_select_grants.sql
--
-- ROOT CAUSE (live verifiziert 2026-09-23, Edge-Function-Probe probe-h1):
-- Migration 121 grantete nur DELETE auf bug_reports/user_reports/
-- rate_limit_hits. PostgREST braucht für einen DELETE mit WHERE-Filter
-- (z. B. ?user_id=eq.<uuid>) zusätzlich SELECT-Privilegien auf die
-- Tabelle: Es validiert Filter-Spalten über die Spalten-Privilegien der
-- Rolle; ohne SELECT schlägt JEDER Filter-DELETE mit 42501
-- "permission denied for table bug_reports" und dem Hinweis
-- "GRANT SELECT ... TO service_role" fehl - auch wenn
-- has_table_privilege(...,'DELETE') = true ist.
--
-- Beweis-Run vor diesem Fix (Edge-Runtime, Service-Key):
--   GoTrue listUsers      -> OK (Key gültig, Rolle service_role)
--   PostgREST DELETE-NOOP -> 403 42501, Hinweis GRANT SELECT
--   has_table_privilege SELECT/DELETE -> false / true
--
-- Fix nach Projekt-Konvention (kleinstmögliche Rechte, Migration 121
-- bleibt bestehen, SELECT kommt ADDITIV dazu). RLS bleibt unberührt
-- (service_role umgeht RLS).

GRANT SELECT ON public.bug_reports TO service_role;
GRANT SELECT ON public.user_reports TO service_role;
GRANT SELECT ON public.rate_limit_hits TO service_role;
