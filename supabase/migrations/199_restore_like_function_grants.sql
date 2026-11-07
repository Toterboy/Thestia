-- 199: die Rechte der Like-Funktionen wiederherstellen
--
-- BEFUND (07.11.2026, Betreiber, ueber den Push-Vorpruefer):
-- Zwei Funktionen waren fuer JEDEN aufrufbar - auch fuer die Rolle
-- "anon", also ohne Anmeldung:
--
--   like_user(uuid)          - ein Fremder haette Likes setzen und
--                               (seit Migration 197) sogar Funken
--                               erzeugen koennen.
--   ignore_like(bigint)      - eine neue Funktion ist fuer die
--                               Pseudo-Rolle PUBLIC automatisch
--                               aufrufbar, bis man sie entzieht.
--
-- DIE URSACHEN:
--
--   * Migration 197 hat like_user GELOESCHT und neu angelegt (der
--     Rueckgabetyp liess sich mit CREATE OR REPLACE nicht aendern).
--     Beim DROP gehen die Rechte verloren - der Entzug aus Migration
--     123 galt nur fuer die alte Funktion.
--   * Migration 198 hat ignore_like neu angelegt - und nicht
--     ausdruecklich entzogen.
--
-- DIE LOESUNG: Beide Funktionen bekommen ihre Rechte wieder
-- ausdruecklich: fuer "authenticated" ja, fuer "anon" und PUBLIC nein.
--
-- WICHTIG: Das wird in JEDER Migration, die eine Client-Funktion
-- anlegt oder neu erstellt, ausdruecklich mitgeschrieben - nicht
-- nur hier. Eine Migration, die eine Funktion per DROP/CREATE
-- ersetzt, holt sich die Rechte sonst nicht automatisch zurueck.

BEGIN;

-- like_user: nur angemeldete Nutzer duerfen liken.
REVOKE ALL ON FUNCTION public.like_user(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.like_user(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.like_user(uuid) TO authenticated;

-- ignore_like: dasselbe.
REVOKE ALL ON FUNCTION public.ignore_like(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ignore_like(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.ignore_like(bigint) TO authenticated;

-- Und die Kontrolle: "anon" darf keine der beiden aufrufen. Sonst
-- koennte sich jeder ohne Konto Likes setzen.
DO $$
DECLARE
  v_offen int;
BEGIN
  SELECT count(*) INTO v_offen
    FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('like_user', 'ignore_like')
     AND has_function_privilege('anon', p.oid, 'EXECUTE');

  IF v_offen > 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: % Like-Funktion(en) sind fuer die Rolle anon aufrufbar - ohne Anmeldung koennte jeder Likes setzen', v_offen;
  END IF;
END;
$$;

COMMIT;
