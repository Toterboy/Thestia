
CREATE OR REPLACE FUNCTION public._test_rueckgabe_ohne_return()
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_id bigint;
BEGIN
  INSERT INTO public.likes (user_id, liked_user_id, status)
  VALUES (auth.uid(), auth.uid(), 'pending')
  ON CONFLICT DO NOTHING
  RETURNING id;
END;
$$;
