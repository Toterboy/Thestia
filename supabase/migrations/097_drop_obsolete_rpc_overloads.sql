-- ============================================================================
-- 097: Veraltete RPC-Überladungen entfernen (PGRST203-Fix)
-- ============================================================================
-- Problem ("Blicke getauscht" schlug mit
-- "Could not choose the best candidate function" fehl):
-- CREATE OR REPLACE FUNCTION ersetzt eine Funktion NUR bei identischer
-- Signatur. Jede Signatur-Änderung (081 -> 082 -> 084 -> 091 bei
-- match_proximity_spark, uuid -> bigint bei 090) hat still eine ZUSÄTZLICHE
-- Überladung angelegt. Da alle neueren Parameter DEFAULTs tragen, matcht
-- fast jeder Aufruf MEHRERE Überladungen -> PostgREST verweigert mit
-- PGRST203 ("best candidate").
--
-- Fix: Alle obsoleten Überladungen droppen. Übrig bleibt je genau eine
-- Signatur (die jeweils neueste). Der Client (Fallback-Kette in
-- matchProximitySpark) funktioniert auf jedem Migrationsstand, profitiert
-- aber ab hier von eindeutigen Aufrufen.
-- ============================================================================

-- match_proximity_spark: nur die 091er-Signatur (5 Params) überlebt.
DROP FUNCTION IF EXISTS public.match_proximity_spark(text[]);
DROP FUNCTION IF EXISTS public.match_proximity_spark(text[], text[], text);
DROP FUNCTION IF EXISTS
  public.match_proximity_spark(text[], text[], text, text[]);

-- 090er-BIGINT-Fix: die toten uuid-Varianten entfernen
-- (matches.id ist BIGINT; der Client sendet Integer).
DROP FUNCTION IF EXISTS public.cool_match(uuid);
DROP FUNCTION IF EXISTS public.respark_match(uuid);
DROP FUNCTION IF EXISTS public.end_match(uuid);
DROP FUNCTION IF EXISTS public.hide_match(uuid);

-- Rechte der überlebenden Signaturen sicherstellen (idempotent).
GRANT EXECUTE ON FUNCTION
  public.match_proximity_spark(text[], text[], text, text[], text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.cool_match(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respark_match(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_match(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hide_match(bigint) TO authenticated;
