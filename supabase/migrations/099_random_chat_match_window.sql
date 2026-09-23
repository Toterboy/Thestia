-- 099_random_chat_match_window.sql
--
-- Fix "Zufallschat findet keinen Partner / sucht nicht richtig":
-- join_random_chat matchete nur wartende Sessions, die juenger als
-- 5 MINUTEN waren (Migrations-Fenster aus 032). Wartete der erste
-- Nutzer laenger allein, wurde seine Session fuer spaetere Joiner
-- unsichtbar: Der Joiner fand nichts, legte eine EIGENE wartende
-- Session an - und BEIDE warteten ewig, obwohl beide online waren.
-- (Erklaert auch den Eindruck "auf Geraet X funktioniert die Suche
-- nicht": ausschlaggebend ist allein, ob die Wartezeit des ersten
-- Nutzers die 5 Minuten ueberschritten hatte.)
--
-- Fix: Das Matching-Fenster wird auf 30 Minuten angehoben - identisch
-- zum Reconnect-Fenster derselben Funktion. Wartende Sessions sind
-- damit durchgehend paabar, solange der Nutzer sie nicht verlaesst
-- (leave_random_chat setzt 'ended').
--
-- Nur das MATCHING-Fenster aendert sich; der Reconnect-Block (30 Min.)
-- bleibt unberuehrt.

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

  -- Aeltesten Wartenden atomar uebernehmen (jetzt 30-Minuten-Fenster
  -- statt 5 Minuten - Fix fuer "sucht nicht richtig").
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

  -- Neue wartende Session.
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
