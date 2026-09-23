-- Migration 118: set_match_kind (Funken-Typ umschalten, Idee 3)
--
-- Beide Partner duerfen den Typ setzen (least privilege: eigener RLS-
-- Kontext via SECURITY DEFINER-Pruefung der Mitgliedschaft). Der Typ
-- gilt fuer BEIDE (Match-Eigenschaft); 'last writer wins'.

CREATE OR REPLACE FUNCTION public.set_match_kind(
  p_match_id bigint, p_kind text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;
  IF p_kind NOT IN ('spark', 'friends') THEN
    RAISE EXCEPTION 'Ungueltiger Typ';
  END IF;
  UPDATE public.matches m
     SET kind = p_kind
   WHERE m.id = p_match_id
     AND (m.user_one_id = v_uid OR m.user_two_id = v_uid)
     AND m.status <> 'ended';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kein Match';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_match_kind(bigint, text) TO authenticated;
