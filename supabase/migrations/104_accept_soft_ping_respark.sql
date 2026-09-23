-- 104_accept_soft_ping_respark.sql
--
-- Fix "Funke verschwindet bei Transit-Spark-Annahme": Wenn der Nutzer
-- einen Soft-Ping von jemandem annimmt, mit dem er bereits einen Funken
-- hat (ggf. durch die 72-h-Auto-Kühlung 'cooled'), blieb der Funke
-- gekühlt und "verschwand" sichtbar aus der aktiven Liste.
--
-- Fix: accept_soft_ping reaktiviert einen gekühlten Funken automatisch
-- (cooled -> active + resparked_at-Zeitstempel) statt nur Likes
-- anzulegen, die wegen ON CONFLICT DO NOTHING bei bestehender
-- Beziehung ins Leere laufen.
--
-- Zusätzlich: match_proximity_spark (BLE-Gegentreffer) bekommt dasselbe
-- Verhalten - dort gilt das identische Szenario.

CREATE OR REPLACE FUNCTION public.accept_soft_ping(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sender uuid;
  v_match_id bigint;
BEGIN
  SELECT sender INTO v_sender
    FROM public.transit_soft_pings
   WHERE id = p_id
     AND recipient = v_uid
     AND status = 'pending'
     AND expires_at > now();

  IF v_sender IS NULL THEN
    RAISE EXCEPTION 'Ping nicht mehr gueltig';
  END IF;

  -- Blockier-Schutz.
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker = v_uid AND b.blocked = v_sender)
        OR (b.blocker = v_sender AND b.blocked = v_uid)
  ) THEN
    RAISE EXCEPTION 'Nicht moeglich.';
  END IF;

  UPDATE public.transit_soft_pings
     SET status = 'accepted'
   WHERE id = p_id;

  -- Gegenseitige Likes anlegen (neue Beziehung).
  INSERT INTO public.likes (user_id, liked_user_id)
  VALUES (v_uid, v_sender), (v_sender, v_uid)
  ON CONFLICT (user_id, liked_user_id) DO NOTHING;

  -- BESTEHENDEN gekühlten Funken reaktivieren (Fix: "Funke verschwindet
  -- bei Annahme"). Der Funke kommt sofort wieder in die aktive Liste,
  -- ohne dass eine neue Session nötig ist.
  UPDATE public.matches
     SET status = 'active',
         resparked_at = now()
   WHERE status = 'cooled'
     AND ((user_one_id = v_uid AND user_two_id = v_sender)
       OR (user_one_id = v_sender AND user_two_id = v_uid));

  RETURN jsonb_build_object('matched', true, 'partner', v_sender);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.accept_soft_ping(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_soft_ping(uuid) TO authenticated;

-- Dasselbe für match_proximity_spark (BLE-Gegentreffer mit bestehendem
-- gekühltem Funken).
CREATE OR REPLACE FUNCTION public.match_proximity_spark(p_tokens text[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_clean text[];
  v_other record;
  v_shared text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht authentifiziert';
  END IF;

  -- Token bereinigen (nur gültige, max. 12).
  SELECT array_agg(t) INTO v_clean
    FROM (
      SELECT DISTINCT t FROM unnest(p_tokens) AS t
       WHERE t ~ '^[A-Za-z0-9_-]{8,64}$'
       ORDER BY t
       LIMIT 12
    ) clean;
  IF v_clean IS NULL OR array_length(v_clean, 1) = 0 THEN
    RETURN jsonb_build_object('matched', false);
  END IF;

  -- Anderen aktiven (pending) Gegenüber mit überlappenden Tokens suchen.
  FOR v_other IN
    SELECT s.id, s.user_id, s.tokens
      FROM public.transit_signals s
     WHERE s.user_id <> v_uid
       AND s.status = 'pending'
       AND s.created_at > now() - interval '45 minutes'
       AND (SELECT count(*) FROM unnest(s.tokens) x
             JOIN unnest(v_clean) y ON x = y) > 0
     ORDER BY s.created_at DESC
     LIMIT 1
  LOOP
    v_shared := (SELECT array_to_string(
      ARRAY(SELECT unnest(v_other.tokens) INTERSECT SELECT unnest(v_clean)), ','));

    -- 1) Beide Signale auf matched setzen.
    UPDATE public.transit_signals
       SET status = 'matched', matched_with = v_other.user_id
     WHERE id = v_other.id;
    INSERT INTO public.transit_signals
      (user_id, tokens, status, matched_with, created_at)
    VALUES (v_uid, v_clean, 'matched', v_other.user_id, now());

    -- 2) Gegenseitige Likes anlegen.
    INSERT INTO public.likes (user_id, liked_user_id)
    VALUES (v_uid, v_other.user_id), (v_other.user_id, v_uid)
    ON CONFLICT (user_id, liked_user_id) DO NOTHING;

    -- 3) Gekühlten Funken reaktivieren (Fix: Funke verschwand sichtbar).
    UPDATE public.matches
       SET status = 'active',
           resparked_at = now()
     WHERE status = 'cooled'
       AND ((user_one_id = v_uid AND user_two_id = v_other.user_id)
         OR (user_one_id = v_other.user_id AND user_two_id = v_uid));

    RETURN jsonb_build_object(
      'matched', true,
      'partner', v_other.user_id,
      'sharedTokens', coalesce(v_shared, 0)
    );
  END LOOP;

  -- Kein Gegensignal: eigenes Signal pending ablegen (45-min-Fenster).
  DELETE FROM public.transit_signals
   WHERE user_id = v_uid AND status = 'pending';
  INSERT INTO public.transit_signals (user_id, tokens, status)
  VALUES (v_uid, v_clean, 'pending');

  RETURN jsonb_build_object('matched', false);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.match_proximity_spark(text[])
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.match_proximity_spark(text[])
  TO authenticated;
