-- 096_no_min_participants.sql
--
-- v0.9.1 (Betreiber-Entscheidung): Die Dating Hour fällt NICHT mehr aus,
-- wenn zu wenige Leute da sind. Es gibt keine Mindestanzahl mehr -
-- `match_dating_hour_round` paart einfach alle Anwesenden (wer keinen
-- Partner abbekommt, bekommt keine Session, das Event läuft trotzdem).
--
-- Die Konfiguration aus 094 (app_config + Admin-RPCs) bleibt aus
-- Kompatibilität bestehen (alte Clients fragen sie weiter ab), wird
-- aber nicht mehr für Absagen verwendet.

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
BEGIN
  SELECT * INTO v_event FROM public.dating_hour_event WHERE id = p_event_id;
  IF NOT FOUND OR v_event.status != 'active' THEN
    RETURN;
  END IF;

  -- KEINE Mindestanzahl mehr (096): Auch mit wenigen Teilnehmern wird
  -- gepaart. Reicht es für niemanden zu einem Paar, entstehen schlicht
  -- keine Sessions - abgesagt ('cancelled') wird nicht mehr.

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
