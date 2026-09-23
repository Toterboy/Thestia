-- 106_relay_dating_hour_and_limits.sql
--
-- 1) Dating-Hour-Relays erlauben: relay_store (098) akzeptierte nur
--    Zufallschat-Partner und Matches - Dating-Hour-Partner (weder Match
--    noch Random-Session) wurden mit 'Kein Chat-Kontext' abgewiesen, der
--    Dating-Hour-Chat hatte damit gar keinen Fallback-Pfad. Jetzt gilt
--    zusätzlich: aktive Dating-Hour-Session (ended_at IS NULL) zwischen
--    den beiden Nutzern.
-- 2) Ciphertext-Limit 8 KB -> 32 KB: Lange Nachrichten (>~6 KB Klartext)
--    wurden abgewiesen und landeten in der Outbox-für-nie (ohne P2P kein
--    Hinweis im UI). 32 KB halten Spam begrenzt und lassen lange Texte zu.
-- 3) Cleanup-Cron: direct_message_relay hatte keinen Retention-Job -
--    nie abgeholte Zeilen (tote Chats) wuchsen unbegrenzt und konnten
--    den relay_fetch-LIMIT-100-Pfad verhungern lassen. Analog 060
--    (user_reports, 180 Tage): Relay-Zeilen älter als 30 Tage fliegen
--    täglich raus.

CREATE OR REPLACE FUNCTION public.relay_store(
  p_receiver uuid,
  p_ciphertext text,
  p_msg_type int DEFAULT 3,
  p_kind text DEFAULT 'text'
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id bigint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;
  IF p_receiver IS NULL OR p_receiver = v_uid THEN
    RAISE EXCEPTION 'Ungueltiges Ziel';
  END IF;
  IF p_ciphertext IS NULL OR length(p_ciphertext) = 0
     OR length(p_ciphertext) > 32768 THEN
    RAISE EXCEPTION 'Ungueltige Nachricht';
  END IF;
  IF p_kind NOT IN ('text', 'icebreaker') THEN
    RAISE EXCEPTION 'Ungueltige Art';
  END IF;

  -- Echte Chat-Beziehung: aktiver Zufallschat ODER bestehendes Match
  -- ODER aktive Dating-Hour-Session. Ohne Beziehung: generischer
  -- Fehler, keine Unterscheidung existiert/nicht existiert
  -- (Anti-Enumeration, Audit S2).
  IF NOT EXISTS (
    SELECT 1 FROM public.random_chat_sessions s
     WHERE s.status = 'active'
       AND ((s.user_a = v_uid AND s.user_b = p_receiver)
         OR (s.user_b = v_uid AND s.user_a = p_receiver))
  ) AND NOT EXISTS (
    SELECT 1 FROM public.matches m
     WHERE (m.user_one_id = v_uid AND m.user_two_id = p_receiver)
        OR (m.user_two_id = v_uid AND m.user_one_id = p_receiver)
  ) AND NOT EXISTS (
    SELECT 1 FROM public.dating_hour_session s
     WHERE s.ended_at IS NULL
       AND ((s.user_a = v_uid AND s.user_b = p_receiver)
         OR (s.user_b = v_uid AND s.user_a = p_receiver))
  ) THEN
    RAISE EXCEPTION 'Kein Chat-Kontext mit diesem Nutzer';
  END IF;

  -- Spam-Schutz: max. 100 unzugestellte Nachrichten pro Empfänger.
  IF (SELECT count(*) FROM public.direct_message_relay
       WHERE sender_id = v_uid AND receiver_id = p_receiver
         AND delivered = false) >= 100 THEN
    RAISE EXCEPTION 'Relay voll - Partner muss den Chat oeffnen';
  END IF;

  INSERT INTO public.direct_message_relay
    (sender_id, receiver_id, ciphertext, msg_type, kind)
  VALUES (v_uid, p_receiver, p_ciphertext, coalesce(p_msg_type, 3), p_kind)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.relay_store(uuid, text, int, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relay_store(uuid, text, int, text)
  TO authenticated;

COMMENT ON FUNCTION public.relay_store(uuid, text, int, text) IS
  '093 + 098 + 106: E2E-Ciphertext-Relay (P2P-Fallback). 106: zusaetzlich '
  'aktive Dating-Hour-Sessions als Beziehung; Limit 8 KB -> 32 KB.';

-- Retention: nie abgeholte Relay-Zeilen aelter als 30 Tage loeschen
-- (Muster wie 060 cleanup_old_user_reports).
SELECT cron.schedule(
  'cleanup_old_relay_rows',
  '45 5 * * *',
  $$ DELETE FROM public.direct_message_relay
     WHERE created_at < now() - interval '30 days' $$
);
