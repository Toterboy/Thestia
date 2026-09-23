-- 105_like_robustness.sql
--
-- Like/Funke-Robustheit (Betreiber-Feedback: "Like und Funke verbuggt"):
--
-- 1) like_user: Wenn bereits ein GEKÜHLTER Funke existiert, wird statt
--    einem neuen Like der Funke reaktiviert (Re-Funke über like_user-
--    Shortcut). Vorher wurde der Like auf 'pending' zurückgesetzt und der
--    gekühlte Funke blieb trotzdem versteckt.
--
-- 2) like_user: Bei bestehendem AKTIVEM Funken bleibt der Early-Return
--    (keine Status-Reset-Potenzial).

CREATE OR REPLACE FUNCTION public.like_user(p_target uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Nicht authentifiziert';
  END IF;
  IF p_target IS NULL OR p_target = v_user THEN
    RAISE EXCEPTION 'Ungueltiges Ziel';
  END IF;

  -- Rate-Limit (Audit M-8).
  IF NOT public.consume_rate_limit(
       'likes_hourly:' || v_user::text, 30, 3600) THEN
    RAISE EXCEPTION 'like_rate_limited_hourly';
  END IF;
  IF NOT public.consume_rate_limit(
       'likes_daily:' || v_user::text, 100, 86400) THEN
    RAISE EXCEPTION 'like_rate_limited_daily';
  END IF;

  -- Alters-Schutz (Audit K-1).
  PERFORM public.assert_age_compatible(v_user, p_target);

  -- Blockier-Schutz.
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker = v_user AND b.blocked = p_target)
        OR (b.blocker = p_target AND b.blocked = v_user)
  ) THEN
    RAISE EXCEPTION 'blocked';
  END IF;

  -- Bestehender Funke?
  IF EXISTS (
    SELECT 1 FROM public.matches m
     WHERE (m.user_one_id = v_user AND m.user_two_id = p_target)
        OR (m.user_one_id = p_target AND m.user_two_id = v_user)
  ) THEN
    -- Gekühlten Funken reaktivieren statt still nichts tun
    -- (Fix: Nutzer tippt Like, Funke bleibt aber unsichtbar).
    UPDATE public.matches
       SET status = 'active',
           resparked_at = now()
     WHERE status = 'cooled'
       AND ((user_one_id = v_user AND user_two_id = p_target)
         OR (user_one_id = p_target AND user_two_id = v_user));
    RETURN;
  END IF;

  INSERT INTO public.likes (user_id, liked_user_id, status)
  VALUES (v_user, p_target, 'pending')
  ON CONFLICT (user_id, liked_user_id) DO UPDATE
    SET status = 'pending', responded_at = NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.like_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.like_user(uuid) TO authenticated;
