-- 100_service_role_grants.sql
--
-- Fix PreKey-500 (diagnostiziert per Edge-Function-Probe, Fehlercode
-- 42501): Der prekeys-Edge-Function-Select lief mit der service_role auf
-- public.prekeys auf "permission denied for table prekeys" -> HTTP 500
-- "Datenbankfehler beim Abruf" - unabhaengig von der deployten Function-
-- Version und davon, ob Bundles existieren. Grund: Die Tabellen dieses
-- Projekts haben die Supabase-Default-Privilegien fuer service_role nie
-- erhalten (Migration-061-Revokes + Historie); explizite Grants gab es
-- nur fuer authenticated (027).
--
-- GET  /prekeys/:id  braucht SELECT.
-- POST /prekeys      macht upsert -> INSERT + UPDATE.
GRANT SELECT, INSERT, UPDATE ON public.prekeys TO service_role;

-- Diagnose/Operations-Zugriff (Edge Functions lesen den Queue-Zustand;
-- RPCs der App laufen als SECURITY DEFINER und brauchen es nicht).
GRANT SELECT ON public.random_chat_sessions TO service_role;
