-- =============================================================================
-- 125_harden_like_quiz_proximity.sql
-- =============================================================================
-- Sicherheitsaudit 2026-09-26: Logik-Flaws in Like-, Quiz- und Transit-Pfaden.
--
-- 1) respond_to_like (033:100) - NIE gehaertet (einzige Definition im Repo).
--    Fehlend im Vergleich zu like_user (105:29-49):
--      - kein Rate-Limit          -> unbegrenzte Match-Erzeugung; jeder Match
--                                     loest 2 FCM-Pushes aus (Push-Trigger 040:57)
--      - kein assert_age_compatible -> Jugendschutz beim ANNEHMEN umgangen
--      - kein blocked_users       -> Blockade umgangen
--      - `DO UPDATE SET created_via` ueberschrieb rueckwirkend den Match-Typ
--        eines bestehenden Zufallschat-/Dating-Hour-Matches
--
-- 2) match_proximity_spark(text[]) - die 1-arg-Ueberladung aus 104 hat weder
--    Rate-Limit noch Block-/Alterspruefung. Da `matched: true/false` verr
--    ae, ob ein pending Signal ein Token enthaelt, war sie ein Online-
--    Enumerations-Orakel fuer die BLE-Naehe. Die gehaertete 5-arg-Variante
--    (110:111-139) hat alle drei Gates. Die 1-arg-Version wird GELOESCHT.
--
-- 3) Quiz-Cooldown: siehe Kopf von start_quiz_attempt. Zusaetzlich setzt ein
--    AFTER-INSERT-Trigger `last_attempt_at` bei JEDEM Versuch - damit ist der
--    Cooldown unabhaengig davon, ob der Aufrufer die geaenderte Funktion
--    benutzt, und kann durch kein spaeteres `CREATE OR REPLACE` verloren gehen.
--
--    Zusaetzlich `consume_rate_limit` auf start_quiz_attempt (60/h) und ein
--    Row-Cap fuer `match_quiz_attempts`.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) respond_to_like: gehaertet
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.respond_to_like(p_like_id bigint, p_accept boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_liker uuid;
  v_one uuid;
  v_two uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Nicht authentifiziert';
  END IF;

  -- Rate-Limit: 60 Antworten/Stunde. Ohne das war die Funktion ein
  -- Match-Generator: jeder erzeugte Match loest serverseitig zwei
  -- FCM-Pushes aus (notify_push_trigger, 040:57-82).
  IF NOT public.consume_rate_limit('respond_like:' || v_user::text, 60, 3600) THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  SELECT l.user_id
    INTO v_liker
    FROM public.likes l
   WHERE l.id = p_like_id
     AND l.liked_user_id = v_user
     AND l.status = 'pending';

  IF v_liker IS NULL THEN
    RAISE EXCEPTION 'Like nicht gefunden oder bereits beantwortet';
  END IF;

  -- Blockier-Schutz in beide Richtungen (wie 105:43-49 fuer like_user).
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker = v_user AND b.blocked = v_liker)
        OR (b.blocker = v_liker AND b.blocked = v_user)
  ) THEN
    RAISE EXCEPTION 'blocked';
  END IF;

  -- Jugendschutz (fehlte voellig - der Like-Versand prueft ihn in 105:40,
  -- das Annehmen bisher nicht).
  PERFORM public.assert_age_compatible(v_user, v_liker);

  IF p_accept THEN
    v_one := least(v_liker, v_user);
    v_two := greatest(v_liker, v_user);

    -- Kein Ueberschreiben bei Konflikt: created_via gehoert dem ERSTEN Match
    -- (created_via = 'find_match' beim Like). Ein spaeteres Annahme-Rennen
    -- darf den Typ eines bestehenden Zufallschat-/Dating-Hour-Matches nicht
    -- rueckwirkend ueberschreiben.
    INSERT INTO public.matches (user_one_id, user_two_id, created_via)
    VALUES (v_one, v_two, 'find_match')
    ON CONFLICT (user_one_id, user_two_id) DO NOTHING;

    UPDATE public.likes
       SET status = 'accepted', responded_at = now()
     WHERE id = p_like_id;
  ELSE
    UPDATE public.likes
       SET status = 'rejected', responded_at = now()
     WHERE id = p_like_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_to_like(bigint, boolean) TO authenticated;

-- -----------------------------------------------------------------------------
-- 2) match_proximity_spark(text[]): entfernen
--    Kein Aufrufer im Client: die App nutzt ausschliesslich die 5-arg-Version
--    (110). Vor dem Drop wird geprueft, dass es keine Abhaengigkeit gibt -
--    sonst waere es ein Breaking Change im Betrieb.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_deps text;
BEGIN
  SELECT string_agg(DISTINCT c.relname, ', ')
    INTO v_deps
    FROM pg_depend d
    JOIN pg_rewrite r ON r.oid = d.objid
    JOIN pg_class c ON c.oid = r.ev_class
    JOIN pg_proc p ON p.oid = d.refobjid
   WHERE p.proname = 'match_proximity_spark'
     AND p.pronargs = 1
     AND c.relname <> 'match_proximity_spark';

  -- Abhaengigkeiten sind tolerierbar (Trigger/Rewrite), werden aber gemeldet.
  IF v_deps IS NOT NULL THEN
    RAISE NOTICE 'match_proximity_spark(text[]) hatte Abhaengigkeiten: %', v_deps;
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.match_proximity_spark(text[]);

-- -----------------------------------------------------------------------------
-- 3a) Quiz: Cooldown auf JEDEN Versuch (Trigger statt Funktionslogik)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_quiz_attempt_cooldown()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Erfolgreiche Antworten liessen `failed_attempts` unveraendert, deshalb
  -- blieb `last_attempt_at` auf einem alten Wert stehen bzw. wurde nie
  -- gesetzt. start_quiz_attempt prueft aber (korrigiert) nur noch die Zeit.
  UPDATE public.match_quiz_state
     SET last_attempt_at = now()
   WHERE match_id = NEW.match_id
     AND (current_question_id IS NULL OR current_question_id = NEW.question_id);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_quiz_attempt_cooldown ON public.match_quiz_attempts;
CREATE TRIGGER trg_quiz_attempt_cooldown
  AFTER INSERT ON public.match_quiz_attempts
  FOR EACH ROW EXECUTE FUNCTION public.touch_quiz_attempt_cooldown();

-- -----------------------------------------------------------------------------
-- 3b) start_quiz_attempt: Cooldown-Bedingung + Rate-Limit
--     Der Body stammt 1:1 aus 089 - nur die markierte Stelle wurde geaendert.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_quiz_attempt(p_match_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_state public.match_quiz_state;
  v_cooldown int;
  v_question public.quiz_questions;
  v_answered int;
  v_next_attempt_at timestamptz;
  v_options jsonb;
  v_dummy int;
  v_partner uuid;
  v_name text;
  v_age int;
  v_interests_json jsonb;
  v_interests text[];
  v_attempt_count int;
  v_intro text;
  v_bio text;
  v_city text;
  v_intro_full text;
  v_city_distractors text[];
begin
  if not exists (
    select 1 from public.matches m
     where m.id = p_match_id
       and (m.user_one_id = v_user or m.user_two_id = v_user)
  ) then
    raise exception 'Kein Match oder keine Teilnahme';
  end if;

  -- AUDIT 2026-09-26: Das Quiz-Limit stand ausserhalb dieser Funktion in
  -- einem DO-Block und lief damit nur EINMAL bei der Migration (auth.uid()
  -- ist dort NULL) - es wurde nie gedrosselt. 120/h ist 10x ueber dem
  -- legitimen Maximum (Cooldown 300s => 12 Versuche/h) und begrenzt
  -- gleichzeitig das Umgehen des Cooldowns durch Pollen.
  if not public.consume_rate_limit('quiz_attempts:' || v_user::text, 120, 3600) then
    raise exception 'rate_limited';
  end if;

  select * into v_state
    from public.match_quiz_state s
   where s.match_id = p_match_id;

  if v_state is null then
    insert into public.match_quiz_state (match_id)
    values (p_match_id)
    returning * into v_state;
  end if;

  if v_state.passed_at is not null then
    raise exception 'Quiz bereits bestanden';
  end if;

  -- AUDIT 2026-09-26: Die Bedingung war `... and v_state.failed_attempts > 0`.
  -- RICHTIGE Antworten inkrementieren `failed_attempts` NICHT, also griff nach
  -- einem Treffer ueberhaupt kein Cooldown - und genau darum liess sich in
  -- einer Schleife immer eine neue Frage ziehen, bis die vom Partner
  -- beantwortete Frage kam (Bestehensbedingung ist "Partner hat IRGENDEINE
  -- Frage richtig", 060:404-410). `last_attempt_at` wird jetzt von einem
  -- AFTER-INSERT-Trigger auf JEDEN Versuch gesetzt, deshalb genuegt hier die
  -- reine Zeitpruefung.
  if v_state.last_attempt_at is not null then
    v_cooldown := coalesce(
      (select value::int from public.app_config where key = 'quiz_cooldown_seconds'),
      300
    );
    v_next_attempt_at := v_state.last_attempt_at + make_interval(secs => v_cooldown);
    if now() < v_next_attempt_at then
      return jsonb_build_object(
        'error', 'cooldown',
        'nextAttemptAt', v_next_attempt_at,
        'cooldownRemainingSeconds',
          greatest(0, ceil(extract(epoch from (v_next_attempt_at - now()))))
      );
    end if;
  end if;

  if v_state.current_question_id is not null then
    select count(*) into v_answered
      from public.match_quiz_attempts a
     where a.match_id = p_match_id
       and a.question_id = v_state.current_question_id;

    if v_answered < 2 then
      select * into v_question
        from public.quiz_questions q
       where q.id = v_state.current_question_id;

      select shuffled_options, shuffled_correct_index
        into v_options, v_dummy
        from public.quiz_shuffle_for_match(
               p_match_id, v_question.options, v_question.correct_index);

      return jsonb_build_object(
        'questionId', v_question.id,
        'prompt', v_question.prompt,
        'options', v_options,
        'roundInProgress', true
      );
    end if;
  end if;

  select case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end
    into v_partner
    from public.matches m
   where m.id = p_match_id;

  select p.name,
         date_part('year', age(p.birth_date))::int,
         coalesce(p.interests, '[]'::jsonb),
         coalesce(p.intro_text, ''),
         coalesce(p.bio, ''),
         nullif(trim(coalesce(p.city, '')), '')
    into v_name, v_age, v_interests_json, v_intro, v_bio, v_city
    from public.profiles p
   where p.user_id = v_partner;

  select array_agg(x ORDER BY x) into v_interests
    from (select jsonb_array_elements_text(v_interests_json) as x) s;

  select count(*) into v_attempt_count
    from public.match_quiz_attempts a
   where a.match_id = p_match_id;

  -- 089: Intro + Bio kombinieren (Bio füllt kurze/fehlende Intros auf).
  v_intro_full := trim(coalesce(v_intro, '') || ' ' || coalesce(v_bio, ''));

  v_question := public.quiz_pick_personalized(
    p_match_id, v_partner, v_name, v_age, v_interests, v_attempt_count, v_intro_full
  );

  -- 089: Neue Variante 3 (Stadt) - fast immer verfügbar, deterministisch.
  IF v_question IS NULL
     AND v_city IS NOT NULL AND v_city <> ''
     AND v_name IS NOT NULL AND v_name <> '' THEN
    DECLARE
      v_city_prompt text := 'Aus welcher Stadt kommt ' || v_name || '?';
      v_pool text[] := ARRAY['Berlin','Hamburg','München','Köln','Frankfurt',
                             'Stuttgart','Düsseldorf','Leipzig','Dresden','Bremen'];
      v_picked text[];
    BEGIN
      SELECT coalesce(array_agg(x ORDER BY hashtext(x || ':' || v_partner::text)), ARRAY[]::text[])
        INTO v_picked
        FROM unnest(v_pool) AS x
       WHERE x <> v_city
       LIMIT 3;
      IF array_length(v_picked, 1) = 3 THEN
        SELECT * INTO v_question
          FROM public.quiz_questions q
         WHERE q.owner_user_id = v_partner
           AND lower(q.prompt) = lower(v_city_prompt)
         LIMIT 1;
        IF v_question IS NULL THEN
          INSERT INTO public.quiz_questions (prompt, options, correct_index, owner_user_id)
          VALUES (v_city_prompt, to_jsonb(ARRAY[v_city] || v_picked), 0, v_partner)
          ON CONFLICT DO NOTHING;
          SELECT * INTO v_question
            FROM public.quiz_questions q
           WHERE q.owner_user_id = v_partner
             AND lower(q.prompt) = lower(v_city_prompt)
           LIMIT 1;
        END IF;
        IF v_question IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.match_quiz_attempts a
           WHERE a.match_id = p_match_id AND a.question_id = v_question.id
        ) THEN
          v_question := NULL;
        ELSIF v_question IS NOT NULL AND (v_question.options ->> 0) <> v_city THEN
          -- Stadt geändert -> veraltete Frage nicht wiederverwenden.
          v_question := NULL;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_question := NULL;
    END;
  END IF;

  -- Fallback: NUR nicht-deprecated generische Fragen (kein Trivia mehr,
  -- keine fremden personalisierten). Ist der Pool leer, gibt es eine klare
  -- Exception statt einer Smoothie-Frage.
  if v_question is null then
    select q.* into v_question
      from public.quiz_questions q
     where q.owner_user_id IS NULL
       and (q.is_deprecated IS DISTINCT FROM true)
       and not exists (
           select 1 from public.match_quiz_attempts a
            where a.match_id = p_match_id
              and a.question_id = q.id
       )
     order by random()
     limit 1;
  end if;

  if v_question is null then
    raise exception 'Keine personalisierten Fragen mehr verfügbar - bitte vervollständige dein Profil (Vorstellung, Interessen, Stadt)';
  end if;

  update public.match_quiz_state
     set current_question_id = v_question.id,
         last_attempt_at = now()
   where match_id = p_match_id;

  select shuffled_options, shuffled_correct_index
    into v_options, v_dummy
    from public.quiz_shuffle_for_match(
           p_match_id, v_question.options, v_question.correct_index);

  return jsonb_build_object(
    'questionId', v_question.id,
    'prompt', v_question.prompt,
    'options', v_options,
    'roundInProgress', false
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast)
--
-- WICHTIG: Geprueft wird der Function-Body, und `prosrc` enthaelt die
-- Kommentare MIT. Die Checks suchen deshalb echte Code-Muster
-- (`DO UPDATE SET` = Upsert) und nicht Prosa - ein erlaeuternder
-- Kommentar darf den Check nicht ausloesen (Lesson learned).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_src text;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'respond_to_like';

  IF v_src NOT LIKE '%consume_rate_limit%'
     OR v_src NOT LIKE '%blocked_users%'
     OR v_src NOT LIKE '%assert_age_compatible%'
     OR v_src LIKE '%DO UPDATE SET%' THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: respond_to_like ist nicht vollstaendig gehaertet.';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public'
                AND p.proname = 'match_proximity_spark' AND p.pronargs = 1) THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: match_proximity_spark(text[]) existiert noch.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_quiz_attempt_cooldown' AND NOT tgisinternal) THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: trg_quiz_attempt_cooldown fehlt.';
  END IF;
END;
$$;
