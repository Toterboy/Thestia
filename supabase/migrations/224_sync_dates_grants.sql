-- 224_sync_dates_grants.sql
--
-- BEFUND (28.11.2026): Nach dem Anwenden der Migration 223 meldete die
-- App "permission denied for table sync_dates" - die Tabelle gab es,
-- aber die Rechte fehlten.
--
-- DER GRUND: Die Migration 223 wurde mit dem Supabase-CLI
-- ("supabase db push") angewandt. Die CLI legt die Objekte mit einem
-- eingeschränkten "login role" an - dieser erbt die Standardrechte des
-- Projekts NICHT. Deshalb bekommen die Tabellen, die per CLI
-- entstehen, die Rechte nicht automatisch (die aus dem Dashboard schon).
--
-- DIE LOESUNG: Hier werden sie ausdruecklich vergeben - wie bei den
-- anderen Tabellen (siehe Migration 026, 027 und 005).
--
-- Ohne diese Rechte kann die App die Sync-Dates weder lesen noch
-- schreiben - der Fehler faellt in der App als "permission denied for
-- table sync_dates" auf.

GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_dates TO authenticated;

COMMENT ON TABLE public.sync_dates IS
  'Das Sync-Date eines Matches: die Idee, der gemeinsame Startzeitpunkt '
  'und die Annahme. Pro Match gibt es hoechstens eines.';
