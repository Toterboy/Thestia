-- 098_relay_store_relationship_check.sql
--
-- Audit S2 (Security-Fix): relay_store erlaubte BISHER jedem
-- authentifizierten Nutzer, an BELIEBIGE Empfänger-UUIDs bis zu 100
-- Ciphertexte (à 8 KB) zu hinterlegen - unabhängig von einer bestehenden
-- Chat-Beziehung. Konsequenzen:
--   1. Spam-/Storage-DoS: ein Skript konnte tausende Nutzer mit je
--      ~800 KB Relay-Zeilen befüllen.
--   2. UUID-Enumeration: FK-Verletzung (unbekannte UUID) vs. Erfolg
--      (bekannte UUID) verrät, welche User-IDs existieren.
--
-- Fix: relay_store akzeptiert Empfänger nur noch mit echter Beziehung:
--   - aktive random_chat_sessions-Partnerschaft (Zufallschat), ODER
--   - bestehendes Match (likes/matches-Pipeline).
-- Die Signatur bleibt identisch (kein Client-Break); kein Direktzugriff
-- auf die Tabellen (RLS default-deny bleibt bestehen).

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
     OR length(p_ciphertext) > 8192 THEN
    RAISE EXCEPTION 'Ungueltige Nachricht';
  END IF;
  IF p_kind NOT IN ('text', 'icebreaker') THEN
    RAISE EXCEPTION 'Ungueltige Art';
  END IF;

  -- Audit S2: Nur mit echter Chat-Beziehung relayen (aktiver Zufallschat
  -- ODER bestehendes Match). Ohne Beziehung: generischer Fehler, keine
  -- Unterscheidung existiert/nicht existiert (Anti-Enumeration).
  IF NOT EXISTS (
    SELECT 1 FROM public.random_chat_sessions s
     WHERE s.status = 'active'
       AND ((s.user_a = v_uid AND s.user_b = p_receiver)
         OR (s.user_b = v_uid AND s.user_a = p_receiver))
  ) AND NOT EXISTS (
    SELECT 1 FROM public.matches m
     WHERE (m.user_one_id = v_uid AND m.user_two_id = p_receiver)
        OR (m.user_two_id = v_uid AND m.user_one_id = p_receiver)
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

-- Grants unverändert idempotent neu setzen (Revoke-First wie in 093).
REVOKE EXECUTE ON FUNCTION public.relay_store(uuid, text, int, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relay_store(uuid, text, int, text)
  TO authenticated;

COMMENT ON FUNCTION public.relay_store(uuid, text, int, text) IS
  '093 + 098: E2E-Ciphertext-Relay (P2P-Fallback). 098: Empfänger nur '
  'noch mit aktiver random_chat_session oder bestehendem Match '
  '(Anti-Spam/DoS, Anti-Enumeration).';
