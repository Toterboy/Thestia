-- 108_hardening_followups.sql
--
-- Nachhärtung aus Code-/DB-Audit:
--
-- 1) register_chat_image_hash (068): kein Rate-Limit - beliebige
--    (receiver,hash)-Zeilen in unbegrenzter Menge anlegbar
--    (Table-Bloat/Storage-DoS). Jetzt: 50/h pro Nutzer (Bilder-Chats
--    brauchen nur wenige Hashes; fail-open bei RPC-Fehlern gibt es
--    hier bewusst NICHT - die RPC ist kein kritischer Pfad, ein
--    fehlgeschlagener Hash-Report blockiert nichts).
CREATE OR REPLACE FUNCTION public.register_chat_image_hash(
  p_receiver_id uuid,
  p_photo_hash text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_receiver_id = auth.uid() THEN
    RAISE EXCEPTION 'self_register';
  END IF;

  IF NOT public.consume_rate_limit(
    'imghash:' || auth.uid()::text, 50, 3600
  ) THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  INSERT INTO public.chat_image_hashes (sender_id, receiver_id, photo_hash)
  VALUES (auth.uid(), p_receiver_id, lower(trim(p_photo_hash)))
  ON CONFLICT (sender_id, receiver_id, photo_hash) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.register_chat_image_hash(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_chat_image_hash(uuid, text)
  TO authenticated;

-- 2) transit_soft_pings: Absender sah per Direkt-SELECT Status +
--    sender-UUID (De-Anonymisierung + Annahme-vs-Ablehnung
--    unterscheidbar, entgegen "Absender sieht nichts"). Ab jetzt:
--    SELECT nur für den EMPFÄNGER; der Absender erfährt Annahme
--    ausschließlich über den entstehenden Funke/Match.
DROP POLICY IF EXISTS "soft_pings_select_own" ON public.transit_soft_pings;
CREATE POLICY "soft_pings_select_recipient"
  ON public.transit_soft_pings
  FOR SELECT
  TO authenticated
  USING (recipient = auth.uid());

-- list_my_soft_pings: sender-UUID nicht mehr preisgeben (Empfänger-Sicht
-- braucht sie nicht - accept_soft_ping löst den Partner serverseitig auf).
CREATE OR REPLACE FUNCTION public.list_my_soft_pings()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(jsonb_agg(
           jsonb_build_object(
             'id', s.id,
             'messageKey', s.message_key,
             'customLine', s.custom_line,
             'createdAt', s.created_at,
             'expiresAt', s.expires_at
           ) ORDER BY s.created_at DESC), '[]'::jsonb)
  FROM public.transit_soft_pings s
  WHERE s.recipient = auth.uid()
    AND s.status = 'pending'
    AND s.expires_at > now();
$$;

REVOKE EXECUTE ON FUNCTION public.list_my_soft_pings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_soft_pings() TO authenticated;

-- 3) Legacy-Tabelle public.messages (010) entfernen: ungenutztes
--    Klartext-Archiv (kein Writer im Client - verifiziert), dessen
--    Teilnehmer-Policies bei künftiger Nutzung den E2E-Anspruch brechen
--    würden. Chats laufen ausschließlich P2P + Relay-Ciphertext.
DROP TABLE IF EXISTS public.messages;

-- Zugehöriger 90-Tage-Cleanup-Job (038) wird obsolet: still entfernen,
-- damit er nicht täglich auf die fehlende Tabelle läuft (Muster wie 081:
-- erst Existenz prüfen, sonst wirft unschedule).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup_old_messages') THEN
    PERFORM cron.unschedule('cleanup_old_messages');
  END IF;
END $$;
