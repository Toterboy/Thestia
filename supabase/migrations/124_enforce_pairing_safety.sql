-- =============================================================================
-- 124_enforce_pairing_safety.sql
-- =============================================================================
-- Sicherheitsaudit 2026-09-26: Blockier- und Jugendschutz in beiden
-- Paarungsfunktionen verloren (REGRESSION).
--
-- BEFUND (verifiziert):
--   join_random_chat()        Endstand 102:79-89  -> kein blocked_users, kein age_check
--   match_dating_hour_round() Endstand 096:47-98  -> kein blocked_users, kein age_check
--   Beide hatten die Pruefungen frueher: 056:540-548 bzw. 058:71-76.
--   Der Kommentar in 058:4 ("Migration 055 hatte den blocked_users-Check
--   entfernt") zeigt: zum zweiten Mal passiert.
--
-- AUSWIRKUNG:
--   (a) Blockierte Paare wurden gepaart - der Blocker bekam nichts mitgeteilt,
--       `leave_random_chat` lief nicht.
--   (b) `age_compatible(18,16)=true`, aber `age_compatible(16,18)=false`.
--       Die Einseitigkeit, die `age_compatible_bidirectional` verhindern soll,
--       war wieder aktiv: Minderjaehrige (16/17) konnten mit Erwachsenen in
--       eine Session gesetzt werden. Die Session ist danach ein gueltiger
--       Chat-Kontext - `relay_store` akzeptiert sie (106:60-64), E2E-Nachrichten
--       sind moeglich. `record_dating_hour_decision` prueft zwar beidseitig, aber
--       erst BEIM MATCH - der Chat gab es vorher schon.
--
-- LÖSUNG - ZWEI STUFEN:
--
--   (1) Pruefungen wieder in die Funktionskoerper einsetzen (korrektes
--       Verhalten, nutzt die Indizes).
--
--   (2) Zusaetzlich eine VALIDIERUNG AUF TABELLENEBENE. Das ist der
--       entscheidende Teil: eine Tabelle-Tabelle-Regel kann nicht durch ein
--       spaeteres `CREATE OR REPLACE` der Paarungsfunktion verloren gehen.
--       Genau daran ist der Check zweimal gescheitert - die Funktion wurde
--       neu geschrieben und die Bedingungen nicht mitkopiert. Ein BEFORE-
--       INSERT/UPDATE-Trigger auf der Session-Tabelle greift dagegen IMMER,
--       unabhaengig davon, wer die Zeile erzeugt.
--
-- (3) Race-Condition (Audit A13a): `match_dating_hour_round` hatte weder
--       `FOR UPDATE` noch einen Unique-Constraint auf dem Paar. Zwei
--       parallele Cron-Laeufe erzeugten zwei Sessions fuer dieselbe Paarung
--       (doppelte Pushes, zwei Chat-Kontexte). `uniq_active_dh_pair` schliesst
--       das jetzt auf DB-Ebene aus.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (2) TABLE-LEVEL-ENFORCEMENT: Zufallschat
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_pairing_safety()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_birth date;
BEGIN
  -- Zufallschat: pruefen, sobald eine echte Paarung entsteht (user_b gesetzt).
  IF TG_TABLE_NAME = 'random_chat_sessions' THEN
    IF NEW.user_b IS NULL THEN
      RETURN NEW;  -- Warteschlange: noch keine Paarung, nichts zu pruefen
    END IF;
  ELSE
    RETURN NEW;  -- dating_hour_session: wird in beiden Triggern behandelt
  END IF;

  -- 1) Keine Selbstpaarung (zusaetzlich zur-table, fuer Random-Chat fehlend).
  IF NEW.user_b = NEW.user_a THEN
    RAISE EXCEPTION 'pairing_self_session: Zufallschat mit sich selbst';
  END IF;

  -- 2) Blockier-Schutz in BEIDEN Richtungen.
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker = NEW.user_a AND b.blocked = NEW.user_b)
        OR (b.blocker = NEW.user_b AND b.blocked = NEW.user_a)
  ) THEN
    RAISE EXCEPTION 'pairing_blocked: Blockierte Paarung abgelehnt';
  END IF;

  -- 3) Jugendschutz beidseitig.
  SELECT p.birth_date INTO v_birth
    FROM public.profiles p WHERE p.user_id = NEW.user_b;

  IF v_birth IS NOT NULL AND NOT public.age_compatible_bidirectional(
       (SELECT p2.birth_date FROM public.profiles p2 WHERE p2.user_id = NEW.user_a),
       v_birth
     ) THEN
    RAISE EXCEPTION 'pairing_age_restricted';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_random_chat_safety ON public.random_chat_sessions;
CREATE TRIGGER trg_enforce_random_chat_safety
  BEFORE INSERT OR UPDATE OF user_b, status ON public.random_chat_sessions
  FOR EACH ROW EXECUTE FUNCTION public.enforce_pairing_safety();

-- -----------------------------------------------------------------------------
-- (2) TABLE-LEVEL-ENFORCEMENT: Dating Hour
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_dating_hour_safety()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_birth_a date;
  v_birth_b date;
BEGIN
  IF NEW.user_a = NEW.user_b THEN
    RAISE EXCEPTION 'pairing_self_session: Dating Hour mit sich selbst';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker = NEW.user_a AND b.blocked = NEW.user_b)
        OR (b.blocker = NEW.user_b AND b.blocked = NEW.user_a)
  ) THEN
    RAISE EXCEPTION 'pairing_blocked: Blockierte Paarung abgelehnt';
  END IF;

  SELECT p.birth_date INTO v_birth_a
    FROM public.profiles p WHERE p.user_id = NEW.user_a;
  SELECT p.birth_date INTO v_birth_b
    FROM public.profiles p WHERE p.user_id = NEW.user_b;

  IF v_birth_a IS NOT NULL AND v_birth_b IS NOT NULL
     AND NOT public.age_compatible_bidirectional(v_birth_a, v_birth_b) THEN
    RAISE EXCEPTION 'pairing_age_restricted';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_dating_hour_safety ON public.dating_hour_session;
CREATE TRIGGER trg_enforce_dating_hour_safety
  BEFORE INSERT OR UPDATE OF user_a, user_b ON public.dating_hour_session
  FOR EACH ROW EXECUTE FUNCTION public.enforce_dating_hour_safety();

-- -----------------------------------------------------------------------------
-- (3) Race-Condition: hoechstens EINE aktive Session pro (Event, Paar).
--     Bestehende Indizes (020) sichern nur je User einzeln - nicht das Paar.
-- -----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uniq_active_dh_pair
  ON public.dating_hour_session(event_id, user_a, user_b)
  WHERE ended_at IS NULL;

-- -----------------------------------------------------------------------------
-- (1) join_random_chat(): Pruefungen wieder im Funktionskoerper.
--     (2) bleibt als Defense-in-Deckung bestehen - der Trigger greift auch,
--     wenn diese Query zukuenft wieder verlusten geht.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_random_chat()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_id uuid;
  v_partner uuid;
  v_status text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Nicht authentifiziert';
  END IF;

  -- Verwaiste Wartesessions aufraeumen (aelter als das Matching-Fenster,
  -- nie gematcht): geben den Unique-Index fuer den frischen Join frei.
  UPDATE public.random_chat_sessions
     SET status = 'ended',
         ended_at = now()
   WHERE user_a = v_user
     AND status = 'waiting'
     AND user_b IS NULL
     AND created_at <= now() - interval '30 minutes';

  -- Reconnect: bestehende Session bevorzugen (30-Minuten-Fenster).
  SELECT s.id,
         CASE WHEN s.user_a = v_user THEN s.user_b ELSE s.user_a END,
         s.status
    INTO v_id, v_partner, v_status
    FROM public.random_chat_sessions s
   WHERE s.status IN ('waiting', 'active')
     AND (s.user_a = v_user OR s.user_b = v_user)
     AND s.created_at > now() - interval '30 minutes'
   ORDER BY s.created_at DESC
   LIMIT 1;

  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'sessionId', v_id,
      'partnerId', v_partner,
      'status', v_status
    );
  END IF;

  -- Aeltesten Wartenden atomar uebernehmen (30-Minuten-Fenster, 099).
  -- WIEDERHERGESTELLT (056:540-548, in 102 verloren):
  --   - nie blockiert (in beide Richtungen)
  --   - alterskompatibel BEIDSEITIG (nicht nur viewer -> target: sonst
  --     duerfte 18 mit 16, aber 16 nicht mit 18)
  SELECT s.id, s.user_a
    INTO v_id, v_partner
    FROM public.random_chat_sessions s
    JOIN public.profiles me_p ON me_p.user_id = v_user
   WHERE s.status = 'waiting'
     AND s.user_b IS NULL
     AND s.user_a <> v_user
     AND s.created_at > now() - interval '30 minutes'
     AND NOT EXISTS (
       SELECT 1 FROM public.blocked_users b
        WHERE (b.blocker = v_user AND b.blocked = s.user_a)
           OR (b.blocker = s.user_a AND b.blocked = v_user)
     )
     AND public.age_compatible_bidirectional(
           me_p.birth_date,
           (SELECT p.birth_date FROM public.profiles p WHERE p.user_id = s.user_a)
         )
   ORDER BY s.created_at ASC
   LIMIT 1
   FOR UPDATE OF s SKIP LOCKED;

  IF v_id IS NOT NULL THEN
    UPDATE public.random_chat_sessions
       SET user_b = v_user,
           status = 'active',
           matched_at = now()
     WHERE id = v_id;

    RETURN jsonb_build_object(
      'sessionId', v_id,
      'partnerId', v_partner,
      'status', 'active'
    );
  END IF;

  -- Neue wartende Session (Unique-Index ist jetzt frei).
  INSERT INTO public.random_chat_sessions (user_a, status)
  VALUES (v_user, 'waiting')
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'sessionId', v_id,
    'partnerId', NULL,
    'status', 'waiting'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_random_chat() TO authenticated;

-- -----------------------------------------------------------------------------
-- (1) match_dating_hour_round(): Pruefungen wieder in BEIDEN Paarungsqueries
--     (1. Versuch und Fallback), plus `FOR UPDATE SKIP LOCKED`.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.match_dating_hour_round(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_event public.dating_hour_event%rowtype;
  v_user record;
  v_pair uuid;
BEGIN
  SELECT * INTO v_event FROM public.dating_hour_event WHERE id = p_event_id;
  IF NOT FOUND OR v_event.status <> 'active' THEN
    RETURN;
  END IF;

  -- Der 096-Verzicht auf eine Mindestteilnehmerzahl bleibt bewusst erhalten
  -- (mit wenigen Teilnehmern wird gepaart). Neu ist ausschliesslich, dass die
  -- Schutzabfragen wieder VOR der Paarungsentscheidung greifen.

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
    ORDER BY random()
  LOOP
    -- 1. Versuch: Partner, mit dem es noch NIE eine Dating-Hour-Session gab.
    --    WIEDERHERGESTELLT (058:71-76, in 096 verloren):
    --      - blocked_users in BEIDEN Richtungen
    --      - age_compatible_bidirectional (beidseitig, nicht viewer->target)
    --    (3) `FOR UPDATE OF q SKIP LOCKED`: verhindert, dass zwei parallele
    --    Cron-Laeufe dieselbe Teilnehmerzeile zweimal vergeben.
    SELECT q.user_id INTO v_pair
      FROM public.dating_hour_participant q
      JOIN public.profiles me_p ON me_p.user_id = v_user.user_id
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
         SELECT 1 FROM public.dating_hour_session s
          WHERE s.ended_at IS NOT NULL
            AND ((s.user_a = v_user.user_id AND s.user_b = q.user_id)
              OR (s.user_a = q.user_id AND s.user_b = v_user.user_id))
       )
       AND NOT EXISTS (
         SELECT 1 FROM public.blocked_users b
          WHERE (b.blocker = v_user.user_id AND b.blocked = q.user_id)
             OR (b.blocker = q.user_id AND b.blocked = v_user.user_id)
       )
       AND public.age_compatible_bidirectional(
             me_p.birth_date,
             (SELECT pr.birth_date FROM public.profiles pr WHERE pr.user_id = q.user_id)
           )
       AND (
         COALESCE(v_user.preferences->>'genderPreference', 'all') = 'all'
         OR EXISTS (
           SELECT 1 FROM public.profiles pr
            WHERE pr.user_id = q.user_id
              AND pr.gender = v_user.preferences->>'genderPreference'
         )
       )
     ORDER BY random()
     LIMIT 1
     FOR UPDATE OF q SKIP LOCKED;

    -- 2. Versuch (Fallback): Wiederholung ist erlaubt, niemand bleibt leer.
    --    Die Schutzabfragen gelten hier genauso - der Fallback darf sie nicht
    --    umgehen (in 096 war genau das der Fall).
    IF v_pair IS NULL THEN
      SELECT q.user_id INTO v_pair
        FROM public.dating_hour_participant q
        JOIN public.profiles me_p ON me_p.user_id = v_user.user_id
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
         AND public.age_compatible_bidirectional(
               me_p.birth_date,
               (SELECT pr.birth_date FROM public.profiles pr WHERE pr.user_id = q.user_id)
             )
         AND (
           COALESCE(v_user.preferences->>'genderPreference', 'all') = 'all'
           OR EXISTS (
             SELECT 1 FROM public.profiles pr
              WHERE pr.user_id = q.user_id
                AND pr.gender = v_user.preferences->>'genderPreference'
           )
         )
       ORDER BY random()
       LIMIT 1
       FOR UPDATE OF q SKIP LOCKED;
    END IF;

    IF v_pair IS NOT NULL THEN
      -- Der BEFORE-INSERT-Trigger (enforce_dating_hour_safety) prueft ein
      -- drittes Mal unabhaengig davon, wer diese Zeile schreibt.
      INSERT INTO public.dating_hour_session(
        event_id, user_a, user_b, expires_at
      ) VALUES (
        p_event_id,
        least(v_user.user_id, v_pair),
        greatest(v_user.user_id, v_pair),
        now() + interval '5 minutes'
      );
    END IF;
  END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast): die Paarungsfunktionen MUESSEN die Schutzabfragen
-- enthalten. Ohne diesen Check faellt eine spaetere Regression wieder still
-- durch - genau das ist zweimal passiert.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_fn text;
BEGIN
  FOR v_fn IN
    VALUES ('public.join_random_chat'), ('public.match_dating_hour_round')
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = split_part(v_fn, '.', 2)
         AND p.prosrc LIKE '%blocked_users%'
         AND p.prosrc LIKE '%age_compatible_bidirectional%'
    ) THEN
      RAISE EXCEPTION
        'Sicherheitscheck fehlgeschlagen: % enthaelt weder blocked_users- noch age_compatible_bidirectional-Pruefung. Paarungs-Regeln wiederherstellen.',
        v_fn;
    END IF;
  END LOOP;

  -- Defense-in-Deckung: beide Tabellentrigger muessen existieren.
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_enforce_random_chat_safety'
                    AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Sicherheitscheck fehlgeschlagen: trg_enforce_random_chat_safety fehlt.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_enforce_dating_hour_safety'
                    AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Sicherheitscheck fehlgeschlagen: trg_enforce_dating_hour_safety fehlt.';
  END IF;
END;
$$;
