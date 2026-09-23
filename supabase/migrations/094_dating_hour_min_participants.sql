-- 094_dating_hour_min_participants.sql
--
-- v0.9.1: Die Dating-Hour-Mindestteilnehmerzahl (bisher hart 20 in
-- match_dating_hour_round, 070) wird konfigurierbar - der Admin kann sie
-- zum Testen bis auf 2 senken. Standard bleibt 20.
--
--   app_config 'dating_hour_min_participants' (Default '20')
--   get_dating_hour_min_participants() -> int (Floor 2, Fallback 20)
--   match_dating_hour_round() nutzt den Helper (Rest identisch zu 070)
--   admin_get/set_dating_hour_min_participants() (nur Admins, 2..100)

INSERT INTO public.app_config (key, value)
VALUES ('dating_hour_min_participants', '20')
ON CONFLICT (key) DO NOTHING;

-- Konfigurierbares Minimum (mindestens 2, Fallback 20).
CREATE OR REPLACE FUNCTION public.get_dating_hour_min_participants()
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_raw text;
  v_val int;
BEGIN
  SELECT value INTO v_raw FROM public.app_config
   WHERE key = 'dating_hour_min_participants';
  BEGIN
    v_val := v_raw::int;
  EXCEPTION WHEN OTHERS THEN
    v_val := 20;
  END;
  IF v_val IS NULL OR v_val < 2 THEN
    RETURN 2;
  END IF;
  RETURN v_val;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_dating_hour_min_participants()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_dating_hour_min_participants()
  TO authenticated;

-- match_dating_hour_round: identisch zu 070, nur das Minimum kommt aus
-- der Konfiguration statt der Konstanten 20.
CREATE OR REPLACE FUNCTION public.match_dating_hour_round(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_event public.dating_hour_event%rowtype;
  v_user record;
  v_pair record;
  v_active_participants int;
  v_min_participants int := public.get_dating_hour_min_participants();
BEGIN
  SELECT * INTO v_event FROM public.dating_hour_event WHERE id = p_event_id;
  IF NOT FOUND OR v_event.status != 'active' THEN
    RETURN;
  END IF;

  -- Mindestanzahl aktiver Teilnehmer (nur Accounts >= 24 h, konsistent
  -- zur Anzeige in get_dating_hour_participant_count, Migration 068):
  -- Unter dem Limit fällt das Event aus.
  SELECT count(*) INTO v_active_participants
  FROM public.dating_hour_participant p
  JOIN public.profiles pr ON pr.user_id = p.user_id
  WHERE p.event_id = p_event_id
    AND p.left_at IS NULL
    AND pr.created_at < now() - interval '24 hours';

  IF v_active_participants < v_min_participants THEN
    UPDATE public.dating_hour_event
    SET status = 'cancelled'
    WHERE id = p_event_id;
    RETURN;
  END IF;

  FOR v_user IN
    SELECT p.user_id, p.preferences
    FROM public.dating_hour_participant p
    WHERE p.event_id = p_event_id
      AND p.left_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = p.user_id OR s.user_b = p.user_id)
      )
    ORDER BY random()
  LOOP
    -- 1. Versuch: Partner, mit dem es noch NIE eine Dating-Hour-Session
    --    gab (keine Dopplungen, solange Alternativen existieren).
    SELECT q.user_id INTO v_pair
    FROM public.dating_hour_participant q
    WHERE q.event_id = p_event_id
      AND q.left_at IS NULL
      AND q.user_id <> v_user.user_id
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = q.user_id OR s.user_b = q.user_id)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.ended_at IS NOT NULL
          AND ((s.user_a = v_user.user_id AND s.user_b = q.user_id)
            OR (s.user_a = q.user_id AND s.user_b = v_user.user_id))
      )
      AND (
        COALESCE(v_user.preferences->>'genderPreference','all') = 'all'
        OR EXISTS (
          SELECT 1 FROM public.profiles pr
          WHERE pr.user_id = q.user_id
            AND pr.gender = v_user.preferences->>'genderPreference'
        )
      )
    ORDER BY random()
    LIMIT 1;

    -- 2. Versuch (Fallback): Wenn keine unbesuchte Kombination mehr übrig
    --    ist, darf auch wiederholt werden - niemand bleibt leer aus.
    IF v_pair.user_id IS NULL THEN
      SELECT q.user_id INTO v_pair
      FROM public.dating_hour_participant q
      WHERE q.event_id = p_event_id
        AND q.left_at IS NULL
        AND q.user_id <> v_user.user_id
        AND NOT EXISTS (
          SELECT 1 FROM public.dating_hour_session s
          WHERE s.event_id = p_event_id
            AND s.ended_at IS NULL
            AND (s.user_a = q.user_id OR s.user_b = q.user_id)
        )
        AND (
          COALESCE(v_user.preferences->>'genderPreference','all') = 'all'
          OR EXISTS (
            SELECT 1 FROM public.profiles pr
            WHERE pr.user_id = q.user_id
              AND pr.gender = v_user.preferences->>'genderPreference'
          )
        )
      ORDER BY random()
      LIMIT 1;
    END IF;

    IF v_pair.user_id IS NOT NULL THEN
      INSERT INTO public.dating_hour_session(
        event_id, user_a, user_b, expires_at
      ) VALUES (
        p_event_id,
        least(v_user.user_id, v_pair.user_id),
        greatest(v_user.user_id, v_pair.user_id),
        now() + interval '5 minutes'
      );
    END IF;
  END LOOP;
END;
$$;

-- Admin: Minimum lesen/setzen (2..100, nur Admins).
CREATE OR REPLACE FUNCTION public.admin_get_dating_hour_min_participants()
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_current_user_admin() THEN
    RAISE EXCEPTION 'Kein Admin-Zugriff' USING ERRCODE = '42501';
  END IF;
  RETURN public.get_dating_hour_min_participants();
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_dating_hour_min_participants(
  p_value int
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_current_user_admin() THEN
    RAISE EXCEPTION 'Kein Admin-Zugriff' USING ERRCODE = '42501';
  END IF;
  IF p_value IS NULL OR p_value < 2 OR p_value > 100 THEN
    RAISE EXCEPTION 'Wert muss zwischen 2 und 100 liegen';
  END IF;
  INSERT INTO public.app_config (key, value)
  VALUES ('dating_hour_min_participants', p_value::text)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  RETURN p_value;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_get_dating_hour_min_participants()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_dating_hour_min_participants()
  TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_set_dating_hour_min_participants(int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_dating_hour_min_participants(int)
  TO authenticated;
