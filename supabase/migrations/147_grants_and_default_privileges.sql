-- 147: Grants fuer den Client + Opt-in auf die neue Supabase-Default-Regel
--
-- ZWEI THEMA IN EINER MIGRATION, weil sie dieselbe Ursache haben: ein
-- fehlendes GRANT bedeutet "permission denied for table ...", egal ob
-- die RLS-Policy richtig ist.
--
-- ===========================================================================
-- 1) OPT-IN: neue Tabellen werden nicht mehr automatisch freigegeben
-- ===========================================================================
--
-- Supabase kuendigt an (Changelog 45329): ab 30.10.2026 bekommen
-- NEUE Tabellen im Schema public nicht mehr automatisch
-- SELECT/INSERT/UPDATE/DELETE fuer anon, authenticated und service_role.
-- Bestehende Tabellen behalten ihre Grants - nur neue sind betroffen.
--
-- BEDEUTUNG FUER DIESES PROJEKT: Transit Spark hat bisher ohne
-- Aussehens-Tabelle ausgereicht. Jede neue Tabelle, die jetzt kommt,
-- waere nach dem Stichtag ueber die Data API NICHT erreichbar, bis
-- jemand ein GRANT schreibt. Der Fehler ist dann ein 42501, und die
-- Policy wird nie ausgewertet - die RLS sieht intakt aus, der Fehler
-- sieht nach Berechtigung aus.
--
-- Deshalb wird HIER bewusst VORZUGSGLICH umgeschaltet. Ab dem
-- Stichtag passiert das automatisch; es vorher zu tun heisst: es
-- passiert kontrolliert und im Repo, statt an einem Stichtag
-- ueberraschend.
--
-- Der Switch gilt nur fuer KÜNFTIGE Tabellen. Bestehende Grants
-- bleiben unberuehrt - das ist genau die Zusicherung, die Supabase
-- gibt ("Existing tables are not affected").
--
-- ===========================================================================
-- 2) FEHLENDE GRANTS: der Client kam auf zwei Tabellen nicht durch
-- ===========================================================================
--
-- BEFUND (Audit der Live-DB, 21.10.2026): 32 Tabellen in public, alle
-- mit RLS. `anon` hat nirgends Zugriff - richtig. ABER fuenf Tabellen
-- hatten fuer `authenticated` gar KEINEN Grant:
--
--   profile_locations    - der Client schreibt dort DIREKT (Upsert,
--                           supabase_database_service.dart:484).
--                           Die RLS-Policies aus Migration 135 (Lesen
--                           nur eigener Standort, Schreiben nur eigener)
--                           werden nie ausgewertet, weil Postgres die
--                           Berechtigung VOR der Policy prueft. Der
--                           Standort wurde also nie gespeichert.
--   transit_soft_pings   - der Client loescht dort direkt (Dismiss,
--                           transit_radar_screen.dart). Ohne Grant
--                           konnte eine Funke nicht weggeklickt werden.
--   banned_emails        - nur ueber RPCs erreichbar, KEIN Grant noetig.
--   direct_message_relay - nur ueber RPCs erreichbar, KEIN Grant noetig.
--   match_bucket_list    - nur ueber RPCs erreichbar, KEIN Grant noetig.
--
-- Die ersten beiden sind ZWINGEND noetig, die letzten drei BEWUSST
-- ohne Grant: sie sollen ausschliesslich ueber SECURITY-DEFINER-RPCs
-- erreichbar sein, die ihrerseits den Admin-Status bzw. die
-- Beziehung pruefen.
--
-- Merkmale (Transits) kommen in dieser Migration noch nicht vor - die
-- gehoeren in die Lookup-Tabelle der Merkmals-Migration.

BEGIN;

-- ===========================================================================
-- 1) Default-Privileges umschalten
-- ===========================================================================
--
-- Ab jetzt bekommt eine neue Tabelle in public KEINE automatischen
-- Grants mehr. Wer eine braucht, schreibt das GRANT mit in die
-- Migration - im selben Statement-Block, der die Tabelle anlegt.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES
  FROM anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE USAGE, SELECT ON SEQUENCES
  FROM anon, authenticated, service_role;

-- Funktionen sind seit Migration 123 bereits ohne Default-Grant. Hier
-- noch einmal ausdruecklich, damit der Zustand auch nach einem
-- Restore aus einem Dump klar ist.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated, service_role;

-- ===========================================================================
-- 2) Grants fuer die Tabellen, die der Client direkt anfasst
-- ===========================================================================

-- profile_locations: der Client schreibt den eigenen Standort direkt.
-- INSERT/UPDATE/DELETE (Upsert), SELECT fuer die eigenen Zeilen.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profile_locations
  TO authenticated;
GRANT ALL ON public.profile_locations TO service_role;

-- transit_soft_pings: der Client blendet eine empfangene Funke aus
-- (DELETE). Die RLS-Policy erlaubt das nur fuer den Empfaenger.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.transit_soft_pings
  TO authenticated;
GRANT ALL ON public.transit_soft_pings TO service_role;

-- Die uebrigen direkt genutzten Tabellen haben ihre Grants bereits
-- (siehe das Audit oben: app_config, auth_devices, blocked_users,
-- dating_hour_participant, dating_hour_session, likes, matches,
-- photo_moderation, profiles). Sie werden hier NICHT erneut gesetzt -
-- ein GRANT waere redundant, und die Audit-Ausgabe zeigt, dass sie
-- passen.

-- Gegenprobe: Die Grants muessen jetzt greifen. Ohne Grant kommt
-- trotz korrekter Policy ein 42501 - deshalb wird hier ausdruecklich
-- geprueft, statt es dem App-Start zu ueberlassen.
DO $check$
DECLARE
  v_ok boolean;
BEGIN
  IF NOT has_table_privilege('authenticated', 'public.profile_locations'::regclass, 'INSERT')
     OR NOT has_table_privilege('authenticated', 'public.transit_soft_pings'::regclass, 'DELETE') THEN
    RAISE EXCEPTION 'Grants fuer profile_locations/transit_soft_pings fehlen - '
      'der Client kommt sonst nicht durch (42501).';
  END IF;

  -- Und die Absicht: Diese drei bleiben NUR ueber RPCs erreichbar.
  IF has_table_privilege('authenticated', 'public.banned_emails'::regclass, 'SELECT')
     OR has_table_privilege('authenticated', 'public.direct_message_relay'::regclass, 'SELECT')
     OR has_table_privilege('authenticated', 'public.match_bucket_list'::regclass, 'SELECT') THEN
    RAISE EXCEPTION 'Eine Admin-/Relay-Tabelle ist direkt erreichbar - '
      'sie soll nur ueber SECURITY-DEFINER-RPCs laufen.';
  END IF;
END;
$check$;

COMMENT ON TABLE public.profile_locations IS
  'Privater Standort des Nutzers (Raster 5 km). Der Client schreibt hier '
  'direkt per Upsert - Migration 147 hat dafuer das fehlende GRANT '
  'nachgezogen. Ohne GRANT laeuft die RLS nie an, weil Postgres die '
  'Berechtigung VOR der Policy prueft.';

COMMIT;
