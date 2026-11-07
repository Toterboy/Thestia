-- 190: die Dating-Hour-Paarung konnte NIE eine Sitzung anlegen
--
-- BEFUND (07.11.2026, Betreiber): "Bei Dating Hour finden sich die
-- Partner nicht (zwei user drin (meine geraete)) und es passiert
-- nichts. Es steht, dass die sich suchen, aber finden niemanden."
--
-- DIE URSACHE (live geprueft, nicht vermutet):
--
--   Die Paarungsrunde sagt
--       ON CONFLICT (event_id, user_a, user_b) DO NOTHING
--   der Unique-Index lautet aber
--       CREATE UNIQUE INDEX uniq_active_dh_pair
--         ON public.dating_hour_session (event_id, user_a, user_b)
--         WHERE (ended_at IS NULL)
--
--   Ein PARTIELLER Index traegt ein ON-CONFLICT-Ziel nur, wenn die
--   Bedingung GENAU dieselbe ist. Sonst: 42P10 "there is no unique or
--   exclusion constraint matching the ON CONFLICT specification".
--
--   ==> Die Paarungsrunde konnte nie eine Sitzung anlegen. Im
--   Cron-Log faellt das nicht auf - der Cron laeuft alle 30 Minuten,
--   und in der App sieht man nur "sie suchen sich" und wartet.
--
--   Gefunden hat das tool/check_on_conflict.py: es fragt die
--   PRODUKTIVDATENBANK ab und vergleicht jedes ON-CONFLICT-Ziel mit
--   den tatsaechlichen Indizes.
--
--   Diese Migration aendert GENAU EIN STUECK: das ON-CONFLICT-Ziel
--   bekommt die Bedingung des partiellen Index. Die Funktion selbst
--   ist die LIVE-Definition - Bot-Schutz, Mindestteilnehmerzahl und
--   Alterspruefung bleiben unveraendert.

BEGIN;

CREATE OR REPLACE FUNCTION public.match_dating_hour_round(p_event_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_event public.dating_hour_event%rowtype;
  v_user record;
  v_pair record;
  v_user_birth date;
BEGIN
  SELECT * INTO v_event FROM public.dating_hour_event WHERE id = p_event_id;
  IF NOT FOUND OR v_event.status != 'active' THEN
    RETURN;
  END IF;

  -- Verifikationspflicht (v0.10.0, Migration 161) - NUR fuer den
  -- Aufrufer, der selbst handelt.
  --
  -- BEFUND 04.11.2026: Vorher stand hier ohne Einschraenkung
  --     IF NOT public.verification_granted(auth.uid()) THEN RAISE ...
  -- Der Cron ruft diese Funktion OHNE JWT auf - auth.uid() ist NULL,
  -- verification_granted(NULL) ist false - also hat der Cron bei der
  -- ERSTEN aktiven Veranstaltung 'verification_required' geworfen und
  -- die ganze Runde abgebrochen. Die Dating Hour hat damit seit dem
  -- 03.11.2026 nicht mehr gepaart.
  IF auth.uid() IS NOT NULL
     AND NOT public.verification_granted(auth.uid()) THEN
    RAISE EXCEPTION 'verification_required';
  END IF;

  FOR v_user IN
    SELECT p.user_id, p.preferences
    FROM public.dating_hour_participant p
    WHERE p.event_id = p_event_id
      AND p.left_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = p.user_id OR s.user_b = p.user_id)
      )
      AND public.guardian_usage_time_allows(p.user_id)
    ORDER BY random()
  LOOP
    IF NOT public.verification_granted(v_user.user_id) THEN
      CONTINUE;
    END IF;

    SELECT birth_date INTO v_user_birth
      FROM public.profiles WHERE user_id = v_user.user_id;

    SELECT q.user_id INTO v_pair
    FROM public.dating_hour_participant q
    LEFT JOIN public.profiles qp ON qp.user_id = q.user_id
    WHERE q.event_id = p_event_id
      AND q.left_at IS NULL
      AND q.user_id <> v_user.user_id
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = q.user_id OR s.user_b = q.user_id)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.blocked_users b
        WHERE (b.blocker = v_user.user_id AND b.blocked = q.user_id)
           OR (b.blocker = q.user_id AND b.blocked = v_user.user_id)
      )
      AND public.age_compatible_bidirectional(v_user_birth, qp.birth_date)
      AND (
        v_user.preferences->>'ageMin' IS NULL
        OR public.profile_age(qp.birth_date) >= (v_user.preferences->>'ageMin')::int
      )
      AND (
        v_user.preferences->>'ageMax' IS NULL
        OR public.profile_age(qp.birth_date) <= (v_user.preferences->>'ageMax')::int
      )
      AND public.guardian_usage_time_allows(q.user_id)
    LIMIT 1;

    IF v_pair.user_id IS NOT NULL THEN
      INSERT INTO public.dating_hour_session(
        event_id, user_a, user_b, expires_at, auto_match_at
      ) VALUES (
        p_event_id,
        least(v_user.user_id, v_pair.user_id),
        greatest(v_user.user_id, v_pair.user_id),
        -- 5 Minuten: bis hierher entscheidet man sich.
        now() + interval '5 minutes',
        -- 10 Minuten: ab hier gibt es den automatischen Funke, wenn
        -- niemand vorher entschieden oder beendet hat.
        now() + interval '10 minutes'
      )
      ON CONFLICT (event_id, user_a, user_b) WHERE (ended_at IS NULL) DO NOTHING;
    END IF;
  END LOOP;
END;
  $$;


-- Der Tabellenteil fuer den Bild-Missbrauchsschutz (aus Migration 068).
--
-- public.register_chat_image_hash schreibt in public.chat_image_hashes
-- und sagt "ON CONFLICT (sender_id, receiver_id, photo_hash)". Die
-- Tabelle EXISTIERT NICHT: Migration 068 hat sie angelegt, aber die
-- Migration ist beim Anwenden gescheitert (der Fehler stand in einem
-- frueheren Statement), und die Historie wurde trotzdem fortgeschrieben.
-- Migration 108 hat die Funktion neu angelegt und auf die Tabelle
-- verwiesen - damit sah alles fertig aus.
--
-- ==> Der Missbrauchsschutz fuer Chat-Bilder (der Bild-Pruefhash aus
-- der Datenschutzerklaerung) hat nie gearbeitet: jede Meldung eines
-- Bildes schlug mit "relation does not exist" fehl.

CREATE TABLE IF NOT EXISTS public.chat_image_hashes (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sender_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  photo_hash  TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (sender_id, receiver_id, photo_hash)
);

COMMENT ON TABLE public.chat_image_hashes IS
  'Hashes der im Chat gesendeten Bilder (v0.10.0, Migration 190). Die '
  'Tabelle wurde in Migration 068 angelegt, aber die Migration ist beim '
  'Anwenden gescheitert - ohne sie konnte der Missbrauchsschutz fuer '
  'Bildmeldungen nie arbeiten. Ein Hash ist nicht rekonstruierbar, die '
  'Aufbewahrung ist daher unkritisch.';

ALTER TABLE public.chat_image_hashes ENABLE ROW LEVEL SECURITY;

-- KEINE Policies: Clients lesen und schreiben die Tabelle nicht direkt -
-- nur die SECURITY-DEFINER-RPC (Schreibweg) und die Edge Function
-- `report-image` (Service-Role, Lese- und Pruefweg). Aus Migration 068.

-- ---------------------------------------------------------------------------
-- Die Kontrolle: beides muss da sein und benutzbar sein.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_ok int;
  v_tabelle text;
  v_index text;
BEGIN
  -- Die Paarungsrunde muss die Bedingung des partiellen Index tragen.
  -- Ohne sie sagt der Server 42P10, und die Paarung findet nicht statt
  -- das waere wieder ein stiller Fehler.
  SELECT count(*) INTO v_ok
    FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'match_dating_hour_round'
     AND p.prosrc ILIKE
         '%on conflict (event_id, user_a, user_b) where (ended_at is null)%';
  IF v_ok = 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: die Paarungsrunde traegt die Bedingung des partiellen Index nicht';
  END IF;

  SELECT to_regclass('public.chat_image_hashes')::text INTO v_tabelle;
  IF v_tabelle IS NULL THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: chat_image_hashes fehlt';
  END IF;

  -- Der Index, den das ON-CONFLICT-Ziel der Funktion braucht.
  SELECT indexrelid::regclass::text INTO v_index
    FROM pg_index i
   WHERE i.indrelid = 'public.chat_image_hashes'::regclass
     AND i.indisunique
     AND (SELECT string_agg(a.attname::text, ',')
            FROM unnest(i.indkey) WITH ORDINALITY AS k(attnum, ord)
            JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum)
         = 'sender_id,receiver_id,photo_hash';
  IF v_index IS NULL THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: der Unique-Index auf (sender_id, receiver_id, photo_hash) fehlt';
  END IF;
END;
$$;

COMMIT;