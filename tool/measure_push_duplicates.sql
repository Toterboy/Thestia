-- MESSUNG: Wie viele Push-Aufrufe erzeugt ein Ereignis?
--
-- DER ZAEHLWEG: Die Trigger rufen net.http_post() auf. Jeder Aufruf landet
-- in net.http_request_queue. Innerhalb einer Transaktion sieht der
-- pg_net-Worker die Zeilen NICHT (er kann uncommittete Zeilen einer
-- anderen Sitzung nicht sehen) - darum kann man hier zaehlen, ohne dass
-- eine einzige Push-Nachricht rausgeht. ROLLBACK macht alles rueckgaengig.
--
-- A = 46f3f558-b134-4d25-946b-4e052a8ab3b5 (Testkonto)
-- B = d177d5f9-f2d0-420e-981b-4d6ef5b77056 (Testkonto)
--
-- DER SOLL-ZUSTAND (Migration 200): ein Ereignis, eine Meldung.
--   Szenario 1 (Transit-Funke):   2 Aufrufe - je einer pro Seite.
--   Szenario 2 (Profil-Like):     1 Aufruf  - der Geliebte wird informiert.
--   Szenario 3 (gegenseitig):    2 + 0 Aufrufe - der zweite Like erzeugt
--                                 den Funke (2 Meldungen, je eine pro Seite)
--                                 und danach KEINE Like-Meldung mehr.
--   Szenario 4 (Soft-Ping):       1 Aufruf  - der Gegruesste wird informiert.
--
-- VORHER (gemessen am 08.11.2026, vor Migration 200):
--   Szenario 1: 4 Aufrufe (2x Like, 2x Funke) - beide Seiten bekamen je
--                ZWEI Meldungen fuer EIN Ereignis.

BEGIN;

CREATE TEMP TABLE messung (
  szenario text,
  empfaenger text,
  art text,
  titel text
);

-- Kuerzlich: die letzten N Zeilen der Queue markieren, um die Szenarien
-- voneinander zu trennen.
CREATE TEMP TABLE marke AS SELECT coalesce(max(id), 0) AS id FROM net.http_request_queue;

-- =========================================================================
-- Szenario 1: ein Transit-Funke (beide funken sich im Radar).
-- Das ist der Pfad aus match_proximity_spark (Migration 194/200):
-- zwei technische Likes, ein Match, ein Soft-Ping.
-- =========================================================================
DELETE FROM public.transit_soft_pings
 WHERE (sender = '46f3f558-b134-4d25-946b-4e052a8ab3b5' AND recipient = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
    OR (sender = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056' AND recipient = '46f3f558-b134-4d25-946b-4e052a8ab3b5');
DELETE FROM public.matches
 WHERE (user_one_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5' AND user_two_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
    OR (user_one_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056' AND user_two_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5');
DELETE FROM public.likes
 WHERE (user_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5' AND liked_user_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
    OR (user_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056' AND liked_user_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5');

INSERT INTO public.likes (user_id, liked_user_id, source)
VALUES ('46f3f558-b134-4d25-946b-4e052a8ab3b5', 'd177d5f9-f2d0-420e-981b-4d6ef5b77056', 'transit'),
       ('d177d5f9-f2d0-420e-981b-4d6ef5b77056', '46f3f558-b134-4d25-946b-4e052a8ab3b5', 'transit');

INSERT INTO public.matches (user_one_id, user_two_id, created_via, status, kind)
VALUES (least('46f3f558-b134-4d25-946b-4e052a8ab3b5'::uuid, 'd177d5f9-f2d0-420e-981b-4d6ef5b77056'::uuid),
        greatest('46f3f558-b134-4d25-946b-4e052a8ab3b5'::uuid, 'd177d5f9-f2d0-420e-981b-4d6ef5b77056'::uuid),
        'swipe', 'active', 'spark');

INSERT INTO public.transit_soft_pings
  (sender, recipient, encounter_token, message_key, custom_line, status, expires_at)
VALUES ('46f3f558-b134-4d25-946b-4e052a8ab3b5', 'd177d5f9-f2d0-420e-981b-4d6ef5b77056',
        'messung-duplikat-test', 'wave', 'Testzeile', 'pending', now() + interval '1 hour');

INSERT INTO messung
SELECT '1 Transit-Funke',
       CASE WHEN convert_from(body, 'UTF8')::jsonb ->> 'target_user_id'
               = '46f3f558-b134-4d25-946b-4e052a8ab3b5' THEN 'A' ELSE 'B' END,
       convert_from(body, 'UTF8')::jsonb ->> 'kind',
       convert_from(body, 'UTF8')::jsonb ->> 'title'
  FROM net.http_request_queue
 WHERE url LIKE '%notify-user%' AND id > (SELECT id FROM marke);

UPDATE marke SET id = (SELECT coalesce(max(id), 0) FROM net.http_request_queue);

-- =========================================================================
-- Szenario 2: ein einseitiger Profil-Like (A liked B).
-- =========================================================================
DELETE FROM public.transit_soft_pings
 WHERE (sender = '46f3f558-b134-4d25-946b-4e052a8ab3b5' AND recipient = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
    OR (sender = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056' AND recipient = '46f3f558-b134-4d25-946b-4e052a8ab3b5');
DELETE FROM public.matches
 WHERE (user_one_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5' AND user_two_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
    OR (user_one_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056' AND user_two_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5');
DELETE FROM public.likes
 WHERE (user_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5' AND liked_user_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
    OR (user_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056' AND liked_user_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5');

INSERT INTO public.likes (user_id, liked_user_id, source)
VALUES ('46f3f558-b134-4d25-946b-4e052a8ab3b5', 'd177d5f9-f2d0-420e-981b-4d6ef5b77056', 'profile');

INSERT INTO messung
SELECT '2 Profil-Like (einseitig)',
       CASE WHEN convert_from(body, 'UTF8')::jsonb ->> 'target_user_id'
               = '46f3f558-b134-4d25-946b-4e052a8ab3b5' THEN 'A' ELSE 'B' END,
       convert_from(body, 'UTF8')::jsonb ->> 'kind',
       convert_from(body, 'UTF8')::jsonb ->> 'title'
  FROM net.http_request_queue
 WHERE url LIKE '%notify-user%' AND id > (SELECT id FROM marke);

UPDATE marke SET id = (SELECT coalesce(max(id), 0) FROM net.http_request_queue);

-- =========================================================================
-- Szenario 3: der gegenseitige Like - genau die Reihenfolge der
-- reparierten like_user: ERST der Match, DANN der eigene Like.
--   3a: der Match entsteht -> 2 Meldungen (je eine pro Seite).
--   3b: der eigene Like folgt -> KEINE Meldung (der Match-Push hat
--       beide Seiten schon informiert).
-- =========================================================================
INSERT INTO public.matches (user_one_id, user_two_id, created_via, status, kind)
VALUES (least('46f3f558-b134-4d25-946b-4e052a8ab3b5'::uuid, 'd177d5f9-f2d0-420e-981b-4d6ef5b77056'::uuid),
        greatest('46f3f558-b134-4d25-946b-4e052a8ab3b5'::uuid, 'd177d5f9-f2d0-420e-981b-4d6ef5b77056'::uuid),
        'swipe', 'active', 'spark');

INSERT INTO messung
SELECT '3a Match entsteht',
       CASE WHEN convert_from(body, 'UTF8')::jsonb ->> 'target_user_id'
               = '46f3f558-b134-4d25-946b-4e052a8ab3b5' THEN 'A' ELSE 'B' END,
       convert_from(body, 'UTF8')::jsonb ->> 'kind',
       convert_from(body, 'UTF8')::jsonb ->> 'title'
  FROM net.http_request_queue
 WHERE url LIKE '%notify-user%' AND id > (SELECT id FROM marke);

UPDATE marke SET id = (SELECT coalesce(max(id), 0) FROM net.http_request_queue);

INSERT INTO public.likes (user_id, liked_user_id, source)
VALUES ('d177d5f9-f2d0-420e-981b-4d6ef5b77056', '46f3f558-b134-4d25-946b-4e052a8ab3b5', 'profile');

INSERT INTO messung
SELECT '3b zweiter Like (Match besteht)',
       CASE WHEN convert_from(body, 'UTF8')::jsonb ->> 'target_user_id'
               = '46f3f558-b134-4d25-946b-4e052a8ab3b5' THEN 'A' ELSE 'B' END,
       convert_from(body, 'UTF8')::jsonb ->> 'kind',
       convert_from(body, 'UTF8')::jsonb ->> 'title'
  FROM net.http_request_queue
 WHERE url LIKE '%notify-user%' AND id > (SELECT id FROM marke);

UPDATE marke SET id = (SELECT coalesce(max(id), 0) FROM net.http_request_queue);

-- =========================================================================
-- Szenario 4: der manuelle "Zuzwinken" (Soft-Ping ohne Funke).
-- =========================================================================
DELETE FROM public.transit_soft_pings
 WHERE (sender = '46f3f558-b134-4d25-946b-4e052a8ab3b5' AND recipient = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
    OR (sender = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056' AND recipient = '46f3f558-b134-4d25-946b-4e052a8ab3b5');
DELETE FROM public.matches
 WHERE (user_one_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5' AND user_two_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
    OR (user_one_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056' AND user_two_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5');
DELETE FROM public.likes
 WHERE (user_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5' AND liked_user_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056')
    OR (user_id = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056' AND liked_user_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5');

INSERT INTO public.transit_soft_pings
  (sender, recipient, encounter_token, message_key, custom_line, status, expires_at)
VALUES ('46f3f558-b134-4d25-946b-4e052a8ab3b5', 'd177d5f9-f2d0-420e-981b-4d6ef5b77056',
        'messung-zuzwinken', 'wave', 'Testzeile', 'pending', now() + interval '1 hour');

INSERT INTO messung
SELECT '4 Soft-Ping (ohne Funke)',
       CASE WHEN convert_from(body, 'UTF8')::jsonb ->> 'target_user_id'
               = '46f3f558-b134-4d25-946b-4e052a8ab3b5' THEN 'A' ELSE 'B' END,
       convert_from(body, 'UTF8')::jsonb ->> 'kind',
       convert_from(body, 'UTF8')::jsonb ->> 'title'
  FROM net.http_request_queue
 WHERE url LIKE '%notify-user%' AND id > (SELECT id FROM marke);

-- =========================================================================
-- DAS ERGEBNIS
-- =========================================================================
SELECT szenario, count(*) AS aufrufe
  FROM messung GROUP BY szenario ORDER BY szenario;

SELECT szenario, empfaenger, art, titel FROM messung ORDER BY szenario, empfaenger;

ROLLBACK;
