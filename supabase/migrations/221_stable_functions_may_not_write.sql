-- 221_stable_functions_may_not_write.sql
--
-- BEFUND (20.11.2026, Betreiber): "Die Funken beim Interessen-Screen
-- koennen nicht geladen werden."
--
-- DIE URSACHE (live gemessen, nicht vermutet): Der Aufruf von
-- public.list_my_matches_with_state() ueber die Data-API antwortete
-- mit
--
--   HTTP 405  {"code":"25006","message":"cannot execute INSERT in a
--   read-only transaction"}
--
-- Die Kette dahinter:
--
--   1) Die Funktion ist STABLE. PostgREST fuehrt den Aufruf deshalb in
--      einer READ-ONLY-Transaktion aus (das ist die Optimierung fuer
--      lesende Funktionen).
--   2) Die Funktion berechnet fuer jede Zeile die Entfernung ueber
--      public.profile_distance_km(...).
--   3) profile_distance_km() ruft public.consume_rate_limit() auf -
--      der Trilaterationsschutz (Migration 059). Diese Funktion
--      SCHREIBT in public.rate_limit_hits.
--   4) Ein INSERT in einer READ-ONLY-Transaktion ist verboten - der
--      Aufruf bricht ab, und die App sieht die Fehlermeldung statt
--      der Liste.
--
-- Es waren DREI Funktionen betroffen, alle ueber denselben Weg:
--
--   * public.list_my_matches_with_state()  - die Funken-Liste (dieser
--     Befund) und der Bad "Neue Funken".
--   * public.profile_distance_km(uuid)      - die Distanzanzeige.
--     Die App faengt den Fehler stillschweigend ab, die Entfernung
--     war deshalb IMMER leer.
--   * public.get_public_profiles(uuid[])   - der Stapel-Abruf von
--     Profilen (Profilseite, Chat, Listen).
--
-- DIE REGEL VON POSTGRESQL: Eine STABLE-Funktion darf die Datenbank
-- nicht veraendern. Hier wurde gegen diese Regel verstossen - der
-- Rate-Limit-Zaehler wurde in eine STABLE-Funktion eingebaut.
--
-- DIE LOESUNG: Funktionen, die (auch nur indirect) schreiben, werden
-- VOLATILE. Dann laeuft der Aufruf in einer Transaktion mit Schreibrecht
-- und der Zaehler laesst sich zaehlen. Die Sicherheitswirkung des
-- Trilaterationsschutzes bleibt unveraendert - nur die Deklaration
-- stimmt jetzt.
--
-- Der Fix ist bewusst GENERISCH: der DO-Block unten sucht JEDE
-- STABLE-Funktion, die den Rate-Limit benutzt, und macht sie VOLATILE.
-- Eine neue Liste, die denselben Fehler macht, ist damit nicht mehr
-- moeglich.
--
-- Rollback: dieselben Funktionen mit ALTER FUNCTION ... STABLE
-- zuruecksetzen. Dann ist der Fehler aber wieder da.

-- ---------------------------------------------------------------------------
-- 1) Der generische Fix
-- ---------------------------------------------------------------------------
-- WARUM EIN DO-BLOCK UND KEINE LISTE: Die Liste der betroffenen
-- Funktionen wuerde bei der naechsten Aenderung wieder veralten. Der
-- Block findet die Funktionen selbst - er faengt auch eine Funktion ab,
-- die spaeter hinzukommt.
DO $$
DECLARE
  v_funktion record;
BEGIN
  FOR v_funktion IN
    SELECT p.oid::regprocedure::text AS signatur
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.provolatile = 's'
       AND (p.prosrc ILIKE '%consume_rate_limit%'
            OR p.prosrc ILIKE '%profile_distance_km%')
     ORDER BY p.proname
  LOOP
    EXECUTE format('ALTER FUNCTION %s VOLATILE', v_funktion.signatur);
    RAISE NOTICE 'VOLATILE gesetzt: %', v_funktion.signatur;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2) Die drei bekannten Funktionen ausdruecklich
-- ---------------------------------------------------------------------------
-- DER GRUND FUER DIE DOPPELTE NENNUNG: Der DO-Block sucht im
-- Quelltext der Funktion. Die drei hier sind die, die der Betreiber
-- gesehen hat - sie sollen im Protokoll namentlich auftauchen, auch
-- wenn sich der Quelltext eines Tages aendert.
ALTER FUNCTION public.profile_distance_km(uuid) VOLATILE;
ALTER FUNCTION public.get_public_profiles(uuid[]) VOLATILE;
ALTER FUNCTION public.list_my_matches_with_state() VOLATILE;

COMMENT ON FUNCTION public.profile_distance_km(uuid) IS
  'Entfernung in 5-km-Schritten. Schreibt den Rate-Limit-Zaehler '
  '(Trilaterationsschutz) - deshalb VOLATILE und nicht STABLE: eine '
  'STABLE-Funktion darf die Datenbank nicht veraendern, und PostgREST '
  'fuehrt STABLE-Aufrufe in einer READ-ONLY-Transaktion aus '
  '(Migration 221).';

COMMENT ON FUNCTION public.get_public_profiles(uuid[]) IS
  'Holt mehrere oeffentliche Profile in einem Aufruf. Schreibt den '
  'Rate-Limit-Zaehler - deshalb VOLATILE (Migration 221).';

COMMENT ON FUNCTION public.list_my_matches_with_state() IS
  'Die Funken-Liste (Interessen-Screen) mit Zustand. Schreibt ueber '
  'profile_distance_km() den Rate-Limit-Zaehler - deshalb VOLATILE '
  '(Migration 221). Ohne diese Aenderung antwortete der Aufruf mit '
  'HTTP 405 ("cannot execute INSERT in a read-only transaction") und '
  'die Liste war leer.';

-- ---------------------------------------------------------------------------
-- 3) Fail-Fast: keine STABLE-Funktion darf mehr schreiben
-- ---------------------------------------------------------------------------
-- BEFUND (20.11.2026): Der Fehler war still. Die App zeigte "Fehler
-- beim Laden", der Server loggte nichts, und die Migrationen waren
-- gruen. Deshalb prueft diese Migration am Ende selbst nach - wenn
-- jemand die Funktionen zuruecksetzt, bricht die Migration ab.
DO $$
DECLARE
  v_anzahl integer;
  v_namen text;
BEGIN
  SELECT count(*), string_agg(p.proname, ', ')
    INTO v_anzahl, v_namen
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.provolatile = 's'
     AND (p.prosrc ILIKE '%consume_rate_limit%'
          OR p.prosrc ILIKE '%profile_distance_km%');

  IF v_anzahl > 0 THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: % STABLE-Funktion(en) schreiben noch in die Datenbank: %',
      v_anzahl, v_namen;
  END IF;
END;
$$;
