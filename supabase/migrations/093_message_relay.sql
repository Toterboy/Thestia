-- 093_message_relay.sql
--
-- v0.9.1: Relay-Fallback für den P2P-Chat ("wenn P2P mal nicht so gut geht").
--
-- Prinzip: Textnachrichten (inkl. geteilter Eisbrecher-Fragen) werden bei
-- fehlendem DataChannel E2E-verschlüsselt (Signal Protocol, Client-seitig
-- mit der bestehenden Session) zwischengespeichert. Der Empfänger holt sie
-- beim Öffnen des Chats (plus Polling) ab und entschlüsselt lokal. Der
-- Server sieht NUR Ciphertext - niemals Inhalte (E2E bleibt gewahrt).
--
--   relay_store(p_receiver, p_ciphertext, p_msg_type, p_kind)
--     Legt eine Nachricht für den Empfänger ab. Nur Text (keine Bilder/Audio:
--     zu groß für Zeilen-Relay, bleiben P2P-only). Liefert die Zeilen-ID.
--   relay_fetch()
--     Liefert eigene unzugestellte Nachrichten (aufsteigend, max. 100).
--   relay_ack(p_ids)
--     Löscht zugestellte eigene Nachrichten (Privacy: kein Server-Archiv).
--
-- Direktzugriff auf die Tabelle ist gesperrt (RLS ohne Policies) - alles
-- läuft über SECURITY-DEFINER-RPCs mit auth.uid()-Checks.

CREATE TABLE IF NOT EXISTS public.direct_message_relay (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ciphertext text NOT NULL,
  msg_type int NOT NULL DEFAULT 3,
  kind text NOT NULL DEFAULT 'text' CHECK (kind IN ('text', 'icebreaker')),
  created_at timestamptz NOT NULL DEFAULT now(),
  delivered boolean NOT NULL DEFAULT false
);

COMMENT ON TABLE public.direct_message_relay IS
  '093: E2E-Ciphertext-Relay (P2P-Fallback). Server sieht nur Ciphertext, keine Inhalte.';

CREATE INDEX IF NOT EXISTS direct_message_relay_receiver_idx
  ON public.direct_message_relay (receiver_id, delivered, created_at);

ALTER TABLE public.direct_message_relay ENABLE ROW LEVEL SECURITY;

-- Kein Direktzugriff (weder lesen noch schreiben) - nur via RPCs unten.
-- (Keine Policies = default deny bei aktiviertem RLS.)

-- Nachricht für den Empfänger ablegen (nur Text, max. 8 KB Ciphertext).
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

-- Eigene unzugestellte Nachrichten abholen (max. 100, älteste zuerst).
CREATE OR REPLACE FUNCTION public.relay_fetch()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;
  SELECT coalesce(jsonb_agg(x.obj ORDER BY x.created), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT jsonb_build_object(
               'id', r.id,
               'sender', r.sender_id,
               'ciphertext', r.ciphertext,
               'msgType', r.msg_type,
               'kind', r.kind,
               'createdAt', r.created_at
             ) AS obj,
             r.created_at AS created
        FROM public.direct_message_relay r
       WHERE r.receiver_id = v_uid
         AND r.delivered = false
       ORDER BY r.created_at
       LIMIT 100
    ) x;
  RETURN v_result;
END;
$$;

-- Zugestellte eigene Nachrichten löschen (Privacy, kein Server-Archiv).
CREATE OR REPLACE FUNCTION public.relay_ack(p_ids bigint[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;
  IF p_ids IS NULL THEN
    RETURN;
  END IF;
  DELETE FROM public.direct_message_relay
   WHERE receiver_id = v_uid
     AND id = ANY (p_ids);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.relay_store(uuid, text, int, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relay_store(uuid, text, int, text)
  TO authenticated;
REVOKE EXECUTE ON FUNCTION public.relay_fetch() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relay_fetch() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.relay_ack(bigint[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relay_ack(bigint[]) TO authenticated;
