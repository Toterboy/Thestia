-- 177: Automatischer Funke nach 10 Minuten (mit Rueckfrage)
--
-- NUTZERWUNSCH (04.11.2026):
--
--   1. Der 5-Minuten-Countdown ist eine ENTSCHEIDUNGSphase, nicht das
--      Ende des Gespraechs. Nach 5 Minuten kommt im Chat eine sanfte
--      Nachricht: die Zeit ist um, entscheidet in Ruhe.
--
--   2. Nach 10 Minuten entsteht automatisch ein beidseitiger Funke.
--      Grund: Wenn auf einer Seite die Verbindung abbricht und das
--      Gespraech trotzdem weiterlaeuft, sollen die beiden trotzdem ihr
--      Match bekommen - nicht nur, weil niemand auf "Ablehnen"
--      geklickt hat.
--
--   3. Der automatische Funke wird als solcher gekennzeichnet. Auf dem
--      Interessen-Screen kann man ihn bei Bedarf wieder entfernen
--      ("war das so richtig?") oder den Hinweis wegklicken.
--
--   4. Wer das Gespraech vorher beendet, bekommt KEINEN automatischen
--      Funke. "Beenden" ist ein aktives "ich will das nicht".
--
-- UMSETZUNG:
--
--   * dating_hour_session bekommt:
--       auto_match_at   - wann der automatische Funke entsteht
--                        (Start + 10 Minuten)
--       auto_matched    - der Funke war automatisch
--       ended_by        - wer das Gespraech vorher beendet hat
--
--   * public.matches bekommt:
--       auto_match      - dieser Funke kam automatisch zustande
--
--   * Der Cron erzeugt den automatischen Funke. Das ist wichtig: er
--     passiert auch dann, wenn BEIDE Apps geschlossen sind. Ein rein
--     clientseitiger Funke waere genau die Sorte "gruener Status",
--     die nichts bedeutet.
--
--   * Die 5-Minuten-Marke (expires_at) beendet die Session NICHT
--     mehr. Bisher tat sie das auch nicht - die Session blieb bis zum
--     Ende des Events offen. Neu ist: nach 10 Minuten gibt es den
--     automatischen Funke, nach dem Ende des Events weiterhin nicht.

BEGIN;

-- =========================================================================
-- 1) Die Spalten
-- =========================================================================
ALTER TABLE public.dating_hour_session
  ADD COLUMN IF NOT EXISTS auto_match_at timestamptz,
  ADD COLUMN IF NOT EXISTS auto_matched boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ended_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.dating_hour_session.auto_match_at IS
  'Zeitpunkt des automatischen Funkes (Start + 10 Minuten). NULL = kein '
  'automatischer Funke (Migration 177).';
COMMENT ON COLUMN public.dating_hour_session.auto_matched IS
  'Der Funke wurde automatisch erzeugt, nicht von beiden Seiten bestaetigt '
  '(Migration 177).';
COMMENT ON COLUMN public.dating_hour_session.ended_by IS
  'Wer das Gespraech vorzeitig beendet hat. Ein solcher Chat erhaelt '
  'KEINEN automatischen Funke (Migration 177).';

ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS auto_match boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.matches.auto_match IS
  'Der Funke kam automatisch zustande (Dating Hour nach 10 Minuten) und '
  'wurde nicht von beiden Seiten bestaetigt. Der Interessen-Screen '
  'fragt deshalb einmal nach (Migration 177).';

-- Bestand nachziehen: Sessions, die noch laufen, bekommen ihre
-- 10-Minuten-Marke.
UPDATE public.dating_hour_session
   SET auto_match_at = started_at + interval '10 minutes'
 WHERE auto_match_at IS NULL
   AND ended_at IS NULL;

-- =========================================================================
-- 2) Die Paarungsrunde setzt die 10-Minuten-Marke
-- =========================================================================
CREATE OR REPLACE FUNCTION public.match_dating_hour_round(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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
      ON CONFLICT (event_id, user_a, user_b) DO NOTHING;
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.match_dating_hour_round(uuid) IS
  'Paart Teilnehmer eines Dating-Hour-Events. Verifikation beider '
  'Teilnehmer (serverseitig). Die Session traegt zwei Fristen: 5 '
  'Minuten bis zur Entscheidung, 10 Minuten bis zum automatischen '
  'Funke (Migration 177).';

-- =========================================================================
-- 3) Der Cron: der automatische Funke nach 10 Minuten
-- =========================================================================
CREATE OR REPLACE FUNCTION public.run_dating_hour_scheduler()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_event public.dating_hour_event%rowtype;
  v_session record;
BEGIN
  -- Aktives Event starten (innerhalb von 1 Minute vor Beginn).
  UPDATE public.dating_hour_event
  SET status = 'active'
  WHERE status = 'scheduled'
    AND now() >= starts_at - interval '1 minute'
    AND now() < ends_at;

  -- ---------------------------------------------------------------------
  -- DER AUTOMATISCHE FUNKE (Migration 177)
  --
  -- Nach 10 Minuten bekommt eine Session, die noch offen ist und in der
  -- sich niemand entschieden hat, automatisch einen Funke.
  --
  -- Warum ueber den Cron und nicht ueber den Client: der Cron laeuft
  -- auch dann, wenn beide Apps geschlossen sind. Ein clientseitiger
  -- Funke waere genau die Sorte gruener Status, die nichts bedeutet -
  -- und bei einem Verbindungsabbruch waare er eben gerade nicht
  -- entstanden.
  --
  -- Ausgenommen ist jede Session, die beendet wurde (ended_at gesetzt).
  -- Wer das Gespraech beendet hat, will es nicht - "beenden" ist ein
  -- aktives "ich will das nicht", kein passives "es ist nichts passiert".
  -- ---------------------------------------------------------------------
  FOR v_session IN
    SELECT * FROM public.dating_hour_session
    WHERE ended_at IS NULL
      AND auto_match_at IS NOT NULL
      AND auto_match_at <= now()
      AND user_a_decision IS NULL
      AND user_b_decision IS NULL
  LOOP
    BEGIN
      INSERT INTO public.matches(user_one_id, user_two_id, auto_match)
      VALUES (v_session.user_a, v_session.user_b, true)
      ON CONFLICT (user_one_id, user_two_id)
      DO UPDATE SET auto_match = true;

      UPDATE public.dating_hour_session
      SET ended_at = now(),
          is_match = true,
          auto_matched = true
      WHERE id = v_session.id;
    EXCEPTION WHEN OTHERS THEN
      -- Eine fehlgeschlagene automatische Paarung darf die ganze
      -- Scheduler-Runde nicht abbrechen - die uebrigen Sessions
      -- sollen trotzdem ihren automatischen Funke bekommen.
      RAISE WARNING 'Automatischer Funke fehlgeschlagen: %', SQLERRM;
    END;
  END LOOP;

  -- Beendete Events abschliessen und Teilnahmestatus zuruecksetzen.
  FOR v_event IN
    SELECT * FROM public.dating_hour_event
    WHERE status = 'active'
      AND now() >= ends_at
  LOOP
    UPDATE public.dating_hour_event
    SET status = 'ended'
    WHERE id = v_event.id;

    -- Offene Sessions als "kein Match" beenden.
    --
    -- ACHTUNG (Migration 177): Eine Session, die nach 10 Minuten
    -- automatisch gepaart wurde, ist hier schon beendet (ended_at
    -- gesetzt) und wird hier nicht mehr angefasst. Ihre
    -- auto_matched-Markierung bleibt erhalten.
    UPDATE public.dating_hour_session
    SET ended_at = now(), is_match = false
    WHERE event_id = v_event.id
      AND ended_at IS NULL;

    -- Reset der Teilnehmer fuer die naechste Datinghour passiert automatisch
    -- durch neue Zeilen; alte Eintraege bleiben als Historie. Neuen Nutzern
    -- wird kein Opt-in gegeben.
  END LOOP;

  -- Matching-Runden waehrend aktiver Events durchfuehren.
  FOR v_event IN
    SELECT * FROM public.dating_hour_event
    WHERE status = 'active'
  LOOP
    PERFORM public.match_dating_hour_round(v_event.id);
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.run_dating_hour_scheduler() IS
  'Dating-Hour-Scheduler. Erzeugt nach 10 Minuten die automatischen '
  'Funken (Migration 177) und beendet die Sessions am Eventende.';

-- =========================================================================
-- 4) Das Gespraech beenden - von einer Seite aus, jederzeit
-- =========================================================================
--
-- Wer nicht will, beendet das Gespraech. Damit gibt es keinen
-- automatischen Funke (der Cron nimmt nur Sessions ohne ended_at).
CREATE OR REPLACE FUNCTION public.end_dating_hour_conversation(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session record;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO v_session
    FROM public.dating_hour_session
   WHERE id = p_session_id
     AND (user_a = v_user OR user_b = v_user);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  -- Schon beendet: nichts zu tun (idempotent).
  IF v_session.ended_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'ended', true, 'is_match', v_session.is_match);
  END IF;

  -- Beenden heisst: kein Match. Ein laufendes "accept" wird
  -- verworfen - wer beendet, meint es.
  UPDATE public.dating_hour_session
    SET ended_at = now(),
        is_match = false,
        user_a_decision = CASE WHEN user_a = v_user THEN 'reject' ELSE user_a_decision END,
        user_b_decision = CASE WHEN user_b = v_user THEN 'reject' ELSE user_b_decision END,
        ended_by = v_user,
        updated_at = now()
   WHERE id = p_session_id;

  RETURN jsonb_build_object('ok', true, 'ended', true, 'is_match', false);
END;
$$;

COMMENT ON FUNCTION public.end_dating_hour_conversation(uuid) IS
  'Beendet das Gespraech einer Dating-Hour-Session. Von beiden Seiten '
  'moeglich, jederzeit. Ein beendetes Gespraech erhaelt KEINEN '
  'automatischen Funke (Migration 177).';

REVOKE ALL ON FUNCTION public.end_dating_hour_conversation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.end_dating_hour_conversation(uuid) TO authenticated;

-- =========================================================================
-- 5) Die Rueckfrage: behalten oder entfernen
-- =========================================================================
--
-- p_keep = true   -> der Hinweis verschwindet, der Funke bleibt
-- p_keep = false  -> der Funke (und damit die Person) wird entfernt
--
-- Die Abfrage wird EINMAL gestellt: danach ist auto_match false
-- (behalten) oder der Funke geloescht (entfernt) - in beiden Faellen
-- wird die Frage nicht mehr gestellt.
CREATE OR REPLACE FUNCTION public.resolve_dating_hour_auto_match(
  p_partner_id uuid,
  p_keep        boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_one uuid;
  v_two uuid;
  v_removed integer := 0;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_partner_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_partner');
  END IF;

  v_one := least(v_user, p_partner_id);
  v_two := greatest(v_user, p_partner_id);

  IF p_keep THEN
    -- Behalten: der Hinweis verschwindet. Die Frage wird danach nicht
    -- mehr gestellt.
    UPDATE public.matches
       SET auto_match = false
     WHERE user_one_id = v_one AND user_two_id = v_two;

    UPDATE public.dating_hour_session
       SET auto_matched = false
     WHERE (user_a = v_one AND user_b = v_two)
        OR (user_a = v_two AND user_b = v_one);

    RETURN jsonb_build_object('ok', true, 'kept', true, 'removed', false);
  END IF;

  -- Entfernen: der Funke wird geloescht. Damit verschwindet die Person
  -- auch aus der Match-Liste.
  DELETE FROM public.matches
   WHERE user_one_id = v_one AND user_two_id = v_two;
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  UPDATE public.dating_hour_session
     SET is_match = false,
         auto_matched = false,
         ended_at = COALESCE(ended_at, now()),
         updated_at = now()
   WHERE (user_a = v_one AND user_b = v_two)
      OR (user_a = v_two AND user_b = v_one);

  RETURN jsonb_build_object('ok', true, 'kept', false, 'removed', v_removed > 0);
END;
$$;

COMMENT ON FUNCTION public.resolve_dating_hour_auto_match(uuid, boolean) IS
  'Die einmalige Rueckfrage zum automatischen Funke: behalten (der '
  'Hinweis verschwindet) oder entfernen (der Funke und damit die Person '
  'werden geloescht). Migration 177.';

REVOKE ALL ON FUNCTION public.resolve_dating_hour_auto_match(uuid, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_dating_hour_auto_match(uuid, boolean)
  TO authenticated;

-- =========================================================================
-- 6) Die Session auch nach dem automatischen Funke noch finden
-- =========================================================================
--
-- BEFUND 04.11.2026: Die RPC lieferte nur Sessions MIT
-- ended_at IS NULL. Nach dem automatischen Funke ist die Session
-- beendet - der Client haette sie nicht mehr gesehen und wuerste den
-- Funke nicht erfahren.
--
-- Deshalb: offene Sessions zuerst, danach die zuletzt beendete (die
-- letzten 20 Minuten). Der Client sieht dadurch auch den automatischen
-- Funke.
CREATE OR REPLACE FUNCTION public.get_my_active_dating_hour_session(p_event_id uuid)
RETURNS SETOF public.dating_hour_session
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT *
    FROM public.dating_hour_session
    WHERE event_id = p_event_id
      AND (user_a = auth.uid() OR user_b = auth.uid())
      AND (
        ended_at IS NULL
        OR ended_at > now() - interval '20 minutes'
      )
    ORDER BY (ended_at IS NULL) DESC, started_at DESC
    LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_my_active_dating_hour_session(uuid) IS
  'Die Session des Aufrufers im Event. Offene Sessions zuerst, danach '
  'die zuletzt beendete (20 Minuten) - damit sieht der Client auch den '
  'automatischen Funke (Migration 177).';

COMMIT;
