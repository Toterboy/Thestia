-- 102_signaling_insert_policy_and_stale_queue.sql
--
-- Fix 1 "Signaling-Kanal nicht verfügbar": Realtime-Authorization für
-- Private Channels läuft als INSERT + SELECT + ROLLBACK mit den Claims
-- des Joining-Users. Migration 062 hatte nur eine SELECT-Policy - der
-- INSERT als authenticated scheiterte mit 42501 (live per SQL-Simulation
-- nachgewiesen), der Join wurde deshalb grundsätzlich verweigert.
-- Fix: INSERT-Policy mit identischem Topic-/Mitgliedschafts-Muster.
create policy "signaling_channel_insert"
  on realtime.messages
  for insert
  to authenticated
  with check (
    topic ~* '^realtime:signaling:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and (
      auth.uid()::text = split_part(topic, ':', 3)
      or auth.uid()::text = split_part(topic, ':', 4)
    )
  );

comment on policy "signaling_channel_insert" on realtime.messages is
  'Signaling-Private-Channel (Fix zu 062): Realtime-Authorization prueft '
  'INSERT und SELECT - beide Policies noetig. Identisches Topic-/'
  'Mitgliedschafts-Muster wie signaling_channel_membership.';

-- Fix 2 "Zufallschat konnte nicht gestartet werden (sofort)": Der
-- N-12-Unique-Index (061) erlaubt nur EINE wartende Session pro Nutzer -
-- OHNE Altersgrenze. Eine verwaiste Wartesession (App-Kill/System-Back
-- ohne leave_random_chat) blockierte damit jeden neuen Join für immer:
-- Reconnect überspringt sie (>30 min), der INSERT scheitert am Index.
-- Fix: Verwaiste eigene Wartesessions (älter als das Matching-Fenster,
-- nie gematcht) werden vor dem frischen Join sauber beendet.
CREATE OR REPLACE FUNCTION public.join_random_chat()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_id uuid;
  v_partner uuid;
  v_status text;
begin
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Nicht authentifiziert';
  END IF;

  -- Verwaiste Wartesessions aufräumen (älter als das Matching-Fenster,
  -- nie gematcht): geben den Unique-Index für den frischen Join frei.
  update public.random_chat_sessions
     set status = 'ended',
         ended_at = now()
   where user_a = v_user
     and status = 'waiting'
     and user_b is null
     and created_at <= now() - interval '30 minutes';

  -- Reconnect: bestehende Session bevorzugen (30-Minuten-Fenster).
  SELECT s.id,
         CASE WHEN s.user_a = v_user THEN s.user_b ELSE s.user_a END,
         s.status
    INTO v_id, v_partner, v_status
    FROM public.random_chat_sessions s
   WHERE s.status IN ('waiting', 'active')
     AND (s.user_a = v_user OR s.user_b = v_user)
     AND s.created_at > now() - interval '30 minutes'
   ORDER BY s.created_at DESC
   LIMIT 1;

  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'sessionId', v_id,
      'partnerId', v_partner,
      'status', v_status
    );
  END IF;

  -- Ältesten Wartenden atomar übernehmen (30-Minuten-Fenster, 099).
  SELECT s.id, s.user_a
    INTO v_id, v_partner
    FROM public.random_chat_sessions s
   WHERE s.status = 'waiting'
     AND s.user_b IS NULL
     AND s.user_a <> v_user
     AND s.created_at > now() - interval '30 minutes'
   ORDER BY s.created_at ASC
   LIMIT 1
   FOR UPDATE SKIP LOCKED;

  IF v_id IS NOT NULL THEN
    UPDATE public.random_chat_sessions
       SET user_b = v_user,
           status = 'active',
           matched_at = now()
     WHERE id = v_id;

    RETURN jsonb_build_object(
      'sessionId', v_id,
      'partnerId', v_partner,
      'status', 'active'
    );
  END IF;

  -- Neue wartende Session (Unique-Index ist jetzt frei).
  INSERT INTO public.random_chat_sessions (user_a, status)
  VALUES (v_user, 'waiting')
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'sessionId', v_id,
    'partnerId', NULL,
    'status', 'waiting'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_random_chat() TO authenticated;
