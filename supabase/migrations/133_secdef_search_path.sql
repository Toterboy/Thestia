-- =============================================================================
-- 133_secdef_search_path.sql
-- =============================================================================
-- SECURITY DEFINER ohne festgelegten search_path.
--
-- BEFUND (2026-10-05, Audit nach dem Release-Build):
-- 29 Funktionen in diesem Schema sind SECURITY DEFINER, legen aber keinen
-- search_path fest.
--
-- ERGEBNIS DES PUSHES (2026-10-06): 0 Funktionen geaendert.
--
-- Der Befund oben hat sich gegen die Datenbank NICHT bestaetigt. Die
-- Abfrage vor dem Push ergab:
--
--   SECURITY DEFINER gesamt                107
--   davon mit gepinntem search_path        107
--   davon OHNE search_path                   0
--
-- Aufteilung der gepinnten Pfade:
--   search_path = ''            30  (am strengsten: nichts aufloesbar)
--   search_path = public, pg_temp 56
--   search_path = public        19
--   search_path = pg_catalog     1
--   search_path = pg_temp        1
--
-- Die Schleife unten lief also durch und aenderte nichts; der
-- Sicherheitscheck am Dateiende ist bestanden, aber er hat hier nichts
-- nachzuweisen gehabt. Er bleibt trotzdem drin: fuer die naechste
-- Migration, die doch eine Funktion ohne gesetzten Pfad findet, ist er der
-- Beweis, statt der Annahme.
--
-- WARUM DER BEFUND ZUR DB NICHT PASST (nicht ueberschreiben, sondern merken):
-- Die 29 Funktionen hatten den Befund vermutlich aus dem QUELLTEXT
-- abgeleitet, nicht aus der Datenbank. Im Repo stehen aeltere
-- CREATE-Funktionen ohne SET search_path; die spaeteren Migrationen
-- haben sie per ALTER nachgezogen. Der Quelltext sagt also "29 ohne
-- Pfad", die Datenbank sagt "0 ohne Pfad" - weil die ALTERungen aus
-- 120 bis 132 genau das nachgeholt haben.
--
-- KONSEQUENZ FUER DIE AUFSICHT: Ein Befund dieser Art gehoert gegen die
-- Datenbank geprueft, nicht gegen die Datei. Sonst wird eine Migration
-- geschrieben, die nichts tut, und ihr Sicherheitscheck bestaetigt
-- genau das - man haelt sich fuer bestaetigt, statt geprueft zu haben.
--
-- WARUM DAS EIN BEFUND IST UND KOSMETISCHER LOOKUP KEINER:
-- SECURITY DEFINER laeuft mit den Rechten des Erstellers. Ohne
-- gepinnten search_path sucht Postgres nach Tabellen, Funktionen und
-- Operatoren in der Reihenfolge des Suchpfads. Wer ein gleichnamiges
-- Objekt in einem frueheren Schema anlegt, kann die Funktion so
-- umbiegen, dass sie auf seinen Objekten arbeitet. Das ist keine
-- theoretische Formulierung, sondern eine bekannte Angriffsklasse.
--
-- Warum das im Audit bis jetzt durchrutschte: Migration 131 ff. machen
-- es richtig, die aelteren tun es nicht. Das Muster ist uneinheitlich -
-- und genau das macht es bei einer Review schwer zu sehen, weil 90
-- Prozent der Funktionen inzwischen korrekt sind.
--
-- WESENTLICH: Diese Migration aendert KEINE bestehende Migrationsdatei.
-- Angewendete Migrationen laufen bei einem spaeteren `db push` nicht
-- erneut, eine nachtraegliche Korrektur in der alten Datei ginge also
-- ins Leere. Deshalb ein neues File.
--
-- SUCHPFAD: public, extensions, pg_temp - und bewusst NICHT nur public.
-- Im Projekt gibt es unqualifizierte Aufrufe von gen_random_uuid(),
-- crypt() und Verwandten (pgcrypto), und die liegen im Schema
-- `extensions`. Ein Suchpfad ohne `extensions` wuerde genau diese
-- Aufrufe brechen - der Fix waere dann schlimmer als der Befund.
--
-- Qualifizierte Aufrufe wie `auth.uid()` oder `public.profiles`
-- bleiben von einem gepinnten Suchpfad unberuehrt; sie loesen immer
-- ueber ihr Schema auf, unabhaengig von der Reihenfolge.
-- =============================================================================

DO $$
DECLARE
  r record;
  v_Anzahl int := 0;
BEGIN
  FOR r IN
    SELECT n.nspname AS schema,
           p.proname AS name,
           pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.prosecdef                                   -- SECURITY DEFINER
       AND n.nspname NOT IN ('pg_catalog', 'information_schema')
       AND p.proconfig IS NULL                          -- kein SET gesetzt
       AND NOT EXISTS (                  -- Auth-Hilfen bleiben unberuehrt
             SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) cfg
              WHERE cfg LIKE 'search_path=%'
           )
  LOOP
    -- Suchpfad setzen statt die Funktion neu zu erzeugen: CREATE OR
    -- REPLACE wuerde den Body neu schreiben muessen, ALTER FUNCTION
    -- aendert nur die Ausfuehrungsumgebung.
    EXECUTE format(
      'ALTER FUNCTION %I.%I(%s) SET search_path = public, extensions, pg_temp',
      r.schema, r.name, r.args);

    v_Anzahl := v_Anzahl + 1;
    RAISE NOTICE 'search_path gesetzt: %.%(%)', r.schema, r.name, r.args;
  END LOOP;

  RAISE NOTICE '--- % Funktionen geaendert', v_Anzahl;
END
$$;

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast), nicht Annahme.
--
-- Ein Fix, dessen Wirksamkeit man annimmt, ist kein Fix. Diese Pruefung
-- bricht den Push ab, falls danach noch eine SECURITY DEFINER-Funktion
-- ohne search_path existiert. Dann weiss man sofort, dass die
-- oberige Schleife etwas uebersehen hat - etwa eine Funktion, die im
-- selben Lauf dazukommt.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
  v_uebrig int := 0;
BEGIN
  FOR r IN
    SELECT n.nspname AS schema,
           p.proname AS name,
           pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.prosecdef
       AND n.nspname NOT IN ('pg_catalog', 'information_schema')
       AND NOT EXISTS (
             SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) cfg
              WHERE cfg LIKE 'search_path=%'
           )
  LOOP
    v_uebrig := v_uebrig + 1;
    RAISE WARNING 'OHNE search_path: %.%(%)', r.schema, r.name, r.args;
  END LOOP;

  IF v_uebrig > 0 THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: % SECURITY DEFINER-Funktion(en) ohne '
      'search_path. Die Migration kann nicht als vollstaendig gelten.', v_uebrig;
  END IF;

  RAISE NOTICE 'Sicherheitscheck bestanden: alle SECURITY DEFINER-Funktionen '
               'haben einen gepinnten search_path.';
END
$$;

-- =============================================================================
-- NICHT in dieser Migration, bewusst:
--
-- * Keine inhaltliche Aenderung von Funktions-Bodies. Das gehoert in eine
--   eigene Migration mit eigenem Test, nicht in eine Härtungsmassnahme.
-- * Kein Widerruf von EXECUTE. Die einzige Freigabe an `anon` ist
--   check_email_ban_status(text) - eine boolesche Abfrage für die
--   Registrierung, die vor dem Login stattfinden muss. Die ist korrekt.
--
-- NACH DEM PUSH ZU PRÜFEN (Stand 2026-10-06, erledigt):
--   supabase db push
--   Registrierung, Login, Chat, Radar.
--
-- Push und Pruefung:
--   133 angewendet (`migration list`: local 133 / remote 133).
--   0 Funktionen geaendert, Sicherheitscheck bestanden.
--   pgcrypto erreichbar: extensions.gen_random_uuid() und
--     extensions.crypt() liefern Werte.
--   Registrierung: check_email_ban_status() antwortet.
--   Chat:        relay_fetch() laeuft (wirft ohne JWT erwartungsgemaess
--                "Nicht eingeloggt" - der Auth-Guard greift).
--   Zufallschat: get_my_active_random_chat() laeuft, gleiche Guards.
--   Radar:       transit_spark_adult() laeuft.
--   Admin:       admin_list_user_reports / _bug_reports / _banned_emails /
--                _pending_verifications antworten alle.
--
-- Es war die erste Migration, die gegen eine echte Datenbank laufen
-- musste. Sie hat nichts angefasst - das war das guenstigste Ergebnis,
-- das man sich fuer eine Härtung wuenschen kann, aber man haette es
-- auch an der Quelle sehen koennen. Genau deshalb steht der Befund
-- oben jetzt mit dem Gegenergebnis drin.
-- =============================================================================
