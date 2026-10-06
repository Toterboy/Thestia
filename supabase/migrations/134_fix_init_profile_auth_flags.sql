-- =============================================================================
-- 134_fix_init_profile_auth_flags.sql
-- =============================================================================
-- URSACHE der gescheiterten Registrierung (2026-10-06, Log aus Supabase):
--
--   17:38:16  POST /auth/v1/signup -> 500
--   17:38:16  42703 record "new" has no field "id"
--   17:38:16  25P02 current transaction is aborted
--
-- Der Fehler kommt NICHT aus der App und nicht aus dem Netz. Er kommt aus
-- einem Trigger auf public.profiles:
--
--   trg_init_profile_auth_flags  AFTER INSERT ON public.profiles
--                                EXECUTE FUNCTION init_profile_auth_flags()
--
-- Der Triggerkoerper (aus Migration 128) war:
--
--   UPDATE public.profiles
--      SET email_verified_at = NEW.email_confirmed_at
--    WHERE user_id = NEW.id
--      AND email_verified_at IS DISTINCT FROM NEW.email_confirmed_at;
--
-- `NEW` ist auf public.profiles der Zeilen-Typ von PROFILES - und
-- profiles hat keine Spalte `id`. Der Primaerschluessel heisst dort
-- `user_id`. Postgres meldet das als 42703 "record new has no field id"
-- und bricht das Statement ab; die Transaktion danach ist mit 25P02
-- vergiftet. GoTrue gibt daraufhin 500 statt einer Anmeldung zurueck.
--
-- Warum es SO LANGE unbemerkt blieb:
--
--  1) `profiles` hat KEINE Spalte `id`, wohl aber `auth.users`. Ein Blick
--     in Migration 128 zeigt zwei fast identische Funktionen:
--     `sync_email_verified_at` (Trigger auf auth.users, NEW.id korrekt)
--     und `init_profile_auth_flags` (Trigger auf profiles, NEW.id falsch).
--     Die zweite ist eine Kopie der ersten - mit demselben Feld, aber
--     an einer anderen Tabelle. Beim Lesen sieht es stimmig aus.
--  2) Der Pfad ist AFTER INSERT auf profiles. Er feuert also bei JEDER
--     Profil-Erzeugung - aber nur, solange jemand einen neuen Nutzer
--     anlegt. Ein bestehender Konto-Login beruehrt ihn nicht.
--  3) Der einzige Testpfad dafuer ist eine Registrierung. Genau die
--     schlug seit v0.9.2 fehl, ohne dass ein Log den Grund nannte: die
--     App bekam eine 500, meldete "Server fehlgeschlagen", und das Log
--     des Clients endete bei "Registriere Nutzer...". Die Ursache stand
--     ausschliesslich im Server-Log.
--
-- DIE KORREKTUR:
--
-- profiles fuehrt BOTH `email_confirmed_at` (aus auth.users gespiegelt)
-- und `email_verified_at` (das, was die App auswertet). Der Trigger
-- soll bei INSERT den Wert aus NEW.email_confirmed_at uebernehmen - auf
-- profiles ist das eine echte Spalte, also NEW.email_confirmed_at war
-- richtig. Nur `NEW.id` war falsch, es muss `NEW.user_id` heissen, und
-- `email_confirmed_at` kommt bei profiles aus `NEW.email_confirmed_at`.
--
-- Warum ueberhaupt ein zweiter Trigger, wenn sync_email_verified_at auf
-- auth.users laeuft? Reihenfolge: `handle_new_user` (AFTER INSERT auf
-- auth.users) legt die Profilzeile an - und feuert dabei AFTER INSERT auf
-- profiles. Dieser zweite Trigger setzt email_verified_at auf denselben
-- Wert, den auth.users gerade in raw_user_meta_data spiegelt. Er ist
-- damit entbehrlich: sync_email_verified_at laeuft ebenfalls AFTER INSERT
-- auf auth.users, aber AFTER handle_new_user (Trigger auf auth.users
-- feuern in Namenreihenfolge, und on_auth_user_created steht davor).
--
-- Wir loeschen den Trigger deshalb und ersetzen die Funktion durch eine
-- selbst-pruefende Variante, die beim naechsten INSERT gegen die echten
-- Spalten testet statt einen Feldnamen zu raten. So kann derselbe Fehler
-- nicht wiederkommen, ohne dass es auffaellt.
--
-- Warum keine Spalte in profiles ergaenzt wird: `id` auf profiles waere
-- eine zweite Primaerschluessel-Spalte mit demselben Inhalt wie
-- user_id. Das ist Datenmodell-Unmut, die man nicht fuehrt, um einen
-- Trigger zu retten, der ohnehin nicht gebraucht wird.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Bestehende Definitionen zurueckbauen.
--
-- DROP statt CREATE OR REPLACE: die Trigger-Definition wird unveraendert
-- mitgenommen (gleicher Name, gleiche Tabelle), damit ein spaeterer
-- CREATE nicht an einem Rest-Objekt scheitert.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_init_profile_auth_flags ON public.profiles;
DROP FUNCTION IF EXISTS public.init_profile_auth_flags();

-- -----------------------------------------------------------------------------
-- 2) Der Profil-Trigger, jetzt mit der richtigen Spalte.
--
--    profiles hat user_id, nicht id - sein Primaerschluessel heisst
--    user_id. Und profiles.email_confirmed_at ist eine echte Spalte,
--    weil handle_new_user sie beim Anlegen aus auth.users fuellt.
--    Deshalb ist NEW.email_confirmed_at richtig und nur NEW.id war falsch.
--
--    BEFORE INSERT statt AFTER INSERT: die Funktion fuellt ein Feld der
--    Zeile, die gerade entsteht. Das geht nur, solange die Zeile noch
--    geschrieben werden kann - ein AFTER-Trigger kann per UPDATE nur
--    einen zweiten Durchlauf erzwingen. BEFORE ist hier richtig UND
--    billiger, weil genau einmal geschrieben wird.
--
--    Suchpfad bleibt '' (leer, am strengsten, wie in Migration 128).
--    Es braucht trotzdem keine Aufloesung: es werden nur Felder von NEW
--    zugewiesen, keine Tabellen oder Funktionen nachgeschlagen.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.init_profile_auth_flags()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Der eigentliche Zweck: email_verified_at fuellen, damit die App
  -- einen frisch registrierten Nutzer sofort als "unbestaetigt" sieht,
  -- ohne auf den naechsten auth.users-Update zu warten.
  IF NEW.email_confirmed_at IS NOT NULL THEN
    NEW.email_verified_at := NEW.email_confirmed_at;
  ELSE
    NEW.email_verified_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.init_profile_auth_flags() IS
  'Fuellt profiles.email_verified_at aus profiles.email_confirmed_at bei '
  'INSERT. Nutzt NEW.email_confirmed_at (eine echte Spalte von profiles), '
  'NICHT NEW.id - profiles hat keine Spalte id, sein Schluessel heisst '
  'user_id. Genau dieser Unterschied hat jede Registrierung mit 500 '
  'abgebrochen (Migration 128, Befund 2026-10-06).';

CREATE TRIGGER trg_init_profile_auth_flags
  BEFORE INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.init_profile_auth_flags();

-- -----------------------------------------------------------------------------
-- 3) BEWEIS (Fail-Fast), nicht Annahme.
--
-- Zwei Pruefungen, beide brechen den Push ab, statt still weiterzulaufen:
--
-- a) DER FEHLER, DEN DIESE MIGRATION BEHEBT: keine Triggerfunktion liest
--    ein NEW/OLD-Feld, das ihre Tabelle nicht hat. Genau diese Abfrage
--    hat den Befund gefunden; sie gehoert in die Datei, damit er nicht
--    noch einmal per Hand gesucht werden muss.
--
-- b) sync_email_verified_at muss weiter existieren: haengt am
--    auth.users-Trigger trg_sync_email_verified_at. Faellt sie weg, laeuft
--    der auth-Pfad still ins Leere, ohne dass ein INSERT bricht.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
  v_uebrig int := 0;
BEGIN
  -- DER FEHLER, DEN DIESE MIGRATION BEHEBT, als Muster.
  --
  -- Ein Triggerfunktionen-Body, der NEW.<spalte> liest, dessen Tabelle
  -- <spalte> aber nicht hat, bricht beim INSERT mit 42703 ab. Genau das
  -- war hier der Fall (profiles.id).
  --
  -- Drei Dinge mussten fuer diese Abfrage stimmen, sonst haette sie
  -- entweder nichts gefunden oder alles gemeldet - beides beim Schreiben
  -- per Test gegen die echte Datenbank festgestellt:
  --
  --  1) Kommentare aus dem Body entfernen (`-- ...`). Sonst meldet der
  --     Guard die eigene Dokumentation "NICHT NEW.id" als Fehler.
  --  2) Gruppen richtig indizieren: `(?:NEW|OLD)\.(...)` ist eine nicht
  --     fangende Gruppe plus eine fangende, also ist der Spaltenname m[1].
  --     Mit `(NEW|OLD)\.(...)` waere es m[2]; der Guard lieferte dann
  --     die ersten zwei Zeichen des Treffers ("EW" aus "NEW.id").
  --  3) Dispatcher ausnehmen. notify_push_trigger haengt an zwei
  --     Tabellen und verzweigt ueber TG_TABLE_NAME - dort ist
  --     NEW.liked_user_id auf `matches` nicht vorhanden und umgekehrt,
  --     ohne dass etwas falsch waere. Eine Abfrage ohne diese Ausnahme
  --     flaggt die Push-Zustellung und wuerde beim naechsten Push einen
  --     intakten Pfad zerlegen.
  -- Der Alias der CTE heisst bewusst r2, nicht r: r ist die
  -- Schleifenvariable, und ein SELECT ... FROM refs r wuerde in
  -- PL/pgSQL den Record zerstoeren, der gerade gefuellt wird. Das war
  -- die Ursache von "record r is not assigned yet" beim ersten
  -- Pushversuch dieser Migration.
  FOR r IN
    WITH refs AS (
      SELECT c.oid AS tab_oid,
             c.relname AS tabelle,
             p.proname AS funktion,
             m[1] AS spalte,
             (pg_get_functiondef(p.oid) LIKE '%TG_TABLE_NAME%'
              OR pg_get_functiondef(p.oid) LIKE '%TG_OP%') AS dispatchiert
        FROM pg_trigger tg
        JOIN pg_class c     ON c.oid = tg.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_proc p      ON p.oid = tg.tgfoid
        CROSS JOIN LATERAL regexp_matches(
             regexp_replace(pg_get_functiondef(p.oid),
                            '--[^\n\r]*', '', 'g'),
             '(?:NEW|OLD)\.([a-z_][a-z0-9_]*)', 'g') AS m
       WHERE NOT tg.tgisinternal
         AND c.relkind = 'r'
         AND n.nspname NOT IN (
               'pg_catalog', 'information_schema', 'auth', 'cron',
               'storage', 'graphql', 'realtime', 'supabase_functions',
               'vault', 'pgsodium', 'pgsodium_masks')
    )
    SELECT r2.tabelle AS tabelle,
           r2.funktion AS funktion,
           r2.spalte AS fehlende_spalte
      FROM refs r2
     WHERE NOT r2.dispatchiert
       AND NOT EXISTS (
             SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = r2.tab_oid
                AND a.attname = r2.spalte
                AND a.attnum > 0
                AND NOT a.attisdropped)
  LOOP
    v_uebrig := v_uebrig + 1;
    RAISE WARNING 'Trigger auf %.% liest NEW/OLD.%, das es dort nicht gibt.',
      r.tabelle, r.funktion, r.fehlende_spalte;
  END LOOP;

  IF v_uebrig > 0 THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: % Triggerfunktion(en) benutzen eine '
      'Spalte, die ihre Tabelle nicht hat (Muster aus Migration 128). '
      'Jede davon bricht beim INSERT mit 42703 ab.', v_uebrig;
  END IF;

  RAISE NOTICE 'Sicherheitscheck bestanden: kein NEW/OLD auf fehlender Spalte.';
END
$$;

DO $$
DECLARE
  v_alt int := 0;
BEGIN
  SELECT count(*) INTO v_alt
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'sync_email_verified_at';

  -- Die alte Funktion wird NICHT geloescht: sync_email_verified_at
  -- haengt am auth.users-Trigger trg_sync_email_verified_at und wird
  -- dort weiter gebraucht. Sie ist an auth.users korrekt. Geprueft wird
  -- nur, dass sie existiert - fehlen wuerde, bedeutet der Trigger auf
  -- auth.users waere jetzt ins Leere.
  IF v_alt = 0 THEN
    RAISE EXCEPTION
      'public.sync_email_verified_at fehlt, trg_sync_email_verified_at '
      'auf auth.users waere wirkungslos. Bitte Migration 128 pruefen.';
  END IF;

  RAISE NOTICE 'sync_email_verified_at vorhanden (% Treffer) - auth.users-Pfad intakt.', v_alt;
END
$$;

-- -----------------------------------------------------------------------------
-- 4) Bestehende Zeilen nachziehen.
--
-- Fuer Profile, die zwischen dem Fehler und dieser Migration entstanden
-- sind, bleibt email_verified_at sonst NULL. Das ist derselbe Zustand,
-- den ein neu registrierter, unbestaetigter Nutzer haben soll - aber
-- bei einem ALTEN, bereits bestaetigten Konto waere es falsch.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_angepasst int := 0;
BEGIN
  UPDATE public.profiles p
     SET email_verified_at = p.email_confirmed_at
   WHERE p.email_verified_at IS DISTINCT FROM p.email_confirmed_at
     AND p.email_confirmed_at IS NOT NULL;

  GET DIAGNOSTICS v_angepasst = ROW_COUNT;
  RAISE NOTICE '% Profilzeile(n) nachgezogen (email_verified_at).', v_angepasst;
END
$$;

-- =============================================================================
-- NACH DEM PUSH ZU PRÜFEN:
--
-- 1) Registrierung auf dem Geraet. Sie muss jetzt durchlaufen. Erscheint
--    weiterhin 500, ist es ein zweiter Trigger - die Pruefung oben deckt
--    das Muster fuer alle Tabellen ab, aber sie kann keine Funktion
--    mit einem anderen Fehlerbild ausschliessen.
--
-- 2) Neues Konto anlegen, Logcat nach `500` und `42703` filtern.
--
-- 3) Bestehendes Konto einloggen: darf nicht betroffen sein, der
--    auth.users-Pfad (sync_email_verified_at) bleibt unberuehrt.
--
-- DIESE Migration war die Zweite ohne echten Geraetetest (die erste war
-- 133, ebenfalls ohne Wirkung). 134 ist aber anders: sie behebt einen
-- Fehler, der auf einem echten Geraet reproduziert und dort belegt ist -
-- die 500 und die 42703 stehen im Server-Log vom 06.10.2026.
-- =============================================================================