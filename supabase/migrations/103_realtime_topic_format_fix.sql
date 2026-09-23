-- 103_realtime_topic_format_fix.sql
--
-- ENDGÜLTIGER Fix "Signaling-Kanal nicht verfügbar (channelError)":
--
-- Realtimes Authorization-Check bewertet das Topic in ENTREPRÄFIXIERTER
-- Form (vgl. realtime.topic()-Helper der Doku: channel('signaling:a:b')
-- -> geprüftes Topic ist 'signaling:a:b', nicht 'realtime:signaling:a:b').
-- Die Policies aus 062/102 matchten aber nur die PRÄFIXIERTE Form
-- (per SQL-Simulation bewiesen: präfixiert = erlaubt, unpräfixiert =
-- 42501). Der Private-Channel-Join scheiterte daher grundsätzlich.
--
-- Fix: Beide Policies (SELECT + INSERT) akzeptieren BEIDE Formen -
-- defensiv, damit künftige Realtime-Versionen mit einer der beiden
-- Varianten durchlaufen. Das Mitgliedschafts-Muster ist jeweils
-- positionsrichtig (unpräfixiert: UUIDs an Position 2+3; präfixiert:
-- Position 3+4).
--
-- Betroffene Topics bleiben strikt auf Signaling beschränkt (2 UUIDs).

DROP POLICY IF EXISTS "signaling_channel_membership" ON realtime.messages;
DROP POLICY IF EXISTS "signaling_channel_insert" ON realtime.messages;

CREATE POLICY "signaling_channel_membership"
  ON realtime.messages
  FOR SELECT
  TO authenticated
  USING (
    topic ~* '^(realtime:)?signaling:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND (
      auth.uid()::text = split_part(topic, ':', 3)
      OR auth.uid()::text = split_part(topic, ':', 4)
      OR auth.uid()::text = split_part(topic, ':', 2)
    )
  );

COMMENT ON POLICY "signaling_channel_membership" ON realtime.messages IS
  'Signaling-Private-Channel: akzeptiert entpraefixiertes (signaling:a:b, '
  'realtime.topic()-Form) und praefixiertes (realtime:signaling:a:b) '
  'Topic. UUIDs an Position 2/3 bzw. 3/4.';

CREATE POLICY "signaling_channel_insert"
  ON realtime.messages
  FOR INSERT
  TO authenticated
  WITH CHECK (
    topic ~* '^(realtime:)?signaling:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND (
      auth.uid()::text = split_part(topic, ':', 3)
      OR auth.uid()::text = split_part(topic, ':', 4)
      OR auth.uid()::text = split_part(topic, ':', 2)
    )
  );

COMMENT ON POLICY "signaling_channel_insert" ON realtime.messages IS
  'Signaling-Private-Channel (Broadcast-Senden): identisches Dual-Form-'
  'Muster wie signaling_channel_membership.';
