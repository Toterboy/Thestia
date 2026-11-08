-- Raeumt die Testdaten des Live-Nachweises weg.
--
-- WOFUER: Der Live-Nachweis (test/live_message_flow_test.dart) legt
-- ueber die echten RPCs echte Zeilen an: beidseitige Likes, einen Match
-- und eine Relay-Nachricht. Die Relay-Zeile raeumt der Test selbst ab
-- (relay_ack) - die Likes und der Match bleiben, weil die App keine
-- Funktion hat, sie zu loeschen.
--
-- Das Skript wird nach dem Testlauf aufgerufen:
--
--     psql "$SUPABASE_DB_URL" -f tool/cleanup_transit_testdata.sql
--
-- oder ueber den Supabase-CLI:
--
--     supabase db query --linked --file tool/cleanup_transit_testdata.sql

BEGIN;

-- Die beidseitigen Likes der Testkonten.
DELETE FROM public.likes
 WHERE (user_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5'
        AND liked_user_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
    OR (user_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056'
        AND liked_user_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5');

-- Der daraus entstandene Match.
DELETE FROM public.matches
 WHERE ((user_one_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5'
        AND user_two_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
     OR (user_one_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056'
         AND user_two_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5'))
   AND created_at > now() - interval '2 hours';

-- Und was vom Relay noch liegen blieb.
DELETE FROM public.direct_message_relay
 WHERE (sender_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5'
        AND receiver_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
    OR (sender_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056'
        AND receiver_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5');

-- Die Kontrolle: es darf nichts mehr da sein.
DO $$
DECLARE
  v_rest int;
BEGIN
  SELECT (SELECT count(*) FROM public.likes
           WHERE (user_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5'
                  AND liked_user_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
              OR (user_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056'
                  AND liked_user_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5'))
       + (SELECT count(*) FROM public.matches
           WHERE ((user_one_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5'
                   AND user_two_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
               OR (user_one_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056'
                   AND user_two_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5'))
             AND created_at > now() - interval '2 hours')
       + (SELECT count(*) FROM public.direct_message_relay
           WHERE (sender_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5'
                  AND receiver_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
              OR (sender_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056'
                  AND receiver_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5'))
    INTO v_rest;

  IF v_rest > 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: % Testzeile(n) sind noch da', v_rest;
  END IF;
END;
$$;

COMMIT;
