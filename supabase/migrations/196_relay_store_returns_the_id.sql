-- 196: public.relay_store gibt die ID zurueck - das Relay hat nie
--     funktioniert
--
-- BEFUND (07.11.2026, Betreiber): "Nachrichten kommen noch immer nicht an."
--
-- DIE URSACHE (live gemessen, nicht vermutet): Der Aufruf von
-- public.relay_store antwortet mit
--
--     HTTP 400  query has no destination for result data
--
-- und die Nachricht wird NICHT abgelegt.
--
-- Die Funktion endete mit:
--
--     INSERT INTO public.direct_message_relay ...
--     RETURNING id;
--   END;
--
-- In PL/pgSQL ist ein blosses "RETURNING id;" aber KEIN RETURN - es ist
-- nur ein SQL-Befehl, dessen Ergebnis verworfen wird. Die Funktion lief
-- danach ins Ende, ohne einen Wert zu liefern. Da sie RETURNS bigint
-- deklariert ist, meldet PostgreSQL genau diesen Fehler.
--
-- DAS HEISST: Das Relay hat NIE funktioniert. Jede Nachricht, die ueber
-- den Relay-Weg ging (also genau dann, wenn der Direktkanal nicht steht -
-- im Mobilfunk, hinter einem Router oder ohne TURN), wurde mit einem
-- 400 verworfen. Der Empfaenger sah nichts.
--
-- DIE LOESUNG: Die ID in eine Variable nehmen und zurueckgeben.
--
-- Die Funktion ist die LIVE-Definition; geaendert wurden genau drei
-- Zeilen (eine Variable, ein "INTO v_id", ein "RETURN v_id").

BEGIN;

CREATE OR REPLACE FUNCTION public.relay_store(p_receiver uuid, p_ciphertext text, p_msg_type integer DEFAULT 3, p_kind text DEFAULT 'text'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_msg_type int;
  v_kind text;
  v_seen record;
  v_id bigint;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  -- NEU (128): E-Mail-Bestaetigung + ggf. AAL2 serverseitig.
  IF NOT public.session_meets_auth_requirements() THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'auth_strength_insufficient';
  END IF;

  IF length(p_ciphertext) > 32768 THEN
    RAISE EXCEPTION 'ciphertext_too_large';
  END IF;

  IF length(p_ciphertext) < 8 THEN
    RAISE EXCEPTION 'ciphertext_too_short';
  END IF;

  IF p_receiver = v_user THEN
    RAISE EXCEPTION 'self_send';
  END IF;

  -- Beziehung in beide Richtungen: Match ODER aktive Zufallschat-Session
  -- ODER aktive Dating-Hour-Session (106).
  SELECT true INTO v_seen
    FROM public.matches m
   WHERE (m.user_one_id = v_user AND m.user_two_id = p_receiver)
      OR (m.user_two_id = v_user AND m.user_one_id = p_receiver);

  IF v_seen IS NULL THEN
    SELECT true INTO v_seen
      FROM public.random_chat_sessions s
     WHERE s.status = 'active'
       AND ((s.user_a = v_user AND s.user_b = p_receiver)
         OR (s.user_a = p_receiver AND s.user_b = v_user));

    IF v_seen IS NULL THEN
      SELECT true INTO v_seen
        FROM public.dating_hour_session s
       WHERE s.ended_at IS NULL
         AND ((s.user_a = v_user AND s.user_b = p_receiver)
           OR (s.user_b = v_user AND s.user_a = p_receiver));
    END IF;
  END IF;

  IF v_seen IS NULL THEN
    RAISE EXCEPTION 'no_relationship';
  END IF;

  v_msg_type := CASE
    WHEN p_msg_type IS NULL OR p_msg_type < 0 THEN 0
    WHEN p_msg_type > 7 THEN 7
    ELSE p_msg_type
  END;

  v_kind := CASE
    WHEN p_kind IS NULL OR p_kind = '' THEN 'text'
    WHEN p_kind IN ('text', 'icebreaker', 'image', 'voice', 'file') THEN p_kind
    ELSE 'text'
  END;

  INSERT INTO public.direct_message_relay
    (sender_id, receiver_id, ciphertext, msg_type, kind)
  VALUES
    (v_user, p_receiver, p_ciphertext, v_msg_type, v_kind)
  RETURNING id INTO v_id;

  -- DIE ID zurueckgeben (v0.10.0, Migration 196): Ein blosses
  -- "RETURNING id;" ist in PL/pgSQL KEIN RETURN - die Funktion
  -- lieferte keinen Wert und der Aufruf scheiterte mit
  -- "query has no destination for result data". Damit wurde jede
  -- ueber das Relay gesendete Nachricht verworfen.
  RETURN v_id;
END;
$$;
-- Die Kontrolle: die Funktion muss die ID zurueckgeben. Ohne das
-- scheitert jeder Aufruf mit 400 - und die Nachricht wird nie
-- abgelegt.
DO $$
DECLARE
  v_ok int;
BEGIN
  SELECT count(*) INTO v_ok
    FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'relay_store'
     AND p.prosrc ILIKE '%return v_id;%'
     AND p.prosrc ILIKE '%returning id into v_id;%';

  IF v_ok = 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: relay_store gibt die ID nicht zurueck - das Relay nimmt keine Nachrichten an';
  END IF;
END;
$$;

COMMIT;
