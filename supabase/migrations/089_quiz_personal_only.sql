-- 089_quiz_personal_only.sql
--
-- v0.9.1-Feedback: "Kennlernquiz enthält noch immer komische und
-- unpersönliche Fragen z.B. zu Smoothies."
--
-- Ursache: Die Fallback-Kette (087) fiel bei leerer/kurzer Vorstellung,
-- fehlenden Interessen oder fehlendem Alter auf den generischen Trivia-
-- Pool (075, 60 Allgemeinwissensfragen inkl. "Was ist ein Smoothie?")
-- zurück. Zusätzlich filterte der Fallback nicht auf owner IS NULL,
-- sodass auch fremde personalisierte Fragen gezogen werden konnten.
--
-- Fix (rein serverseitig, keine Client-Änderung nötig):
--   1) Generische Trivia als deprecated markieren (FK-sicher: kein DELETE,
--      Verlauf in match_quiz_attempts bleibt erhalten). Zukünftige
--      start_quiz_attempt-Aufrufe schließen deprecated Fragen aus.
--   2) Lückentext-Schwelle senken (40 -> 20 Zeichen, 4 -> 3 Wörter) und
--      Bio als Ergänzung zum Intro nutzen (viele Profile haben Bio, aber
--      kurzes/kein intro_text) - deutlich mehr Treffer für Variante 0.
--   3) Neue personalisierte Variante: Stadt ("Aus welcher Stadt kommt
--      <Name>?") - fast immer verfügbar, deterministisch.
--   4) Generischer Fallback nur noch owner IS NULL UND nicht deprecated.
--      Ist auch dann nichts verfügbar, kommt eine klare Exception statt
--      einer Smoothie-Frage (Client zeigt "Keine Fragen mehr verfügbar"
--      statt Trivia).

-- ==========================================================================
-- 1) Deprecated-Flag (FK-sicher statt DELETE) -------------------------------
-- ==========================================================================
ALTER TABLE public.quiz_questions
  ADD COLUMN IF NOT EXISTS is_deprecated boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.quiz_questions.is_deprecated IS
  '089: Generische Trivia-Fragen (075) sind deprecated und werden vom Fallback ausgeschlossen. Verlauf bleibt für FK erhalten.';

-- Alle generischen Trivia-Fragen (owner NULL, nicht personalisiert) als
-- deprecated markieren. Personalisierte (owner gesetzt) bleiben aktiv.
UPDATE public.quiz_questions
   SET is_deprecated = true
 WHERE owner_user_id IS NULL
   AND prompt NOT LIKE 'Welches dieser Interessen gehört zu %'
   AND prompt NOT LIKE 'Wie alt ist %'
   AND prompt NOT LIKE 'Vorstellung von %'
   AND prompt NOT LIKE 'Aus welcher Stadt kommt %';

-- ==========================================================================
-- 2) quiz_pick_personalized: Schwelle senken (20 Zeichen, 3 Wörter) ---------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.quiz_pick_personalized(
  p_match_id bigint,
  p_partner uuid,
  p_name text,
  p_age int,
  p_interests text[],
  p_attempt_count int,
  p_intro text
)
RETURNS public.quiz_questions
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.quiz_questions;
  v_prompt text;
  v_options text[];
  v_correct text;
  v_n int;
  v_idx int;
  v_off int;
  v_intro text;
  v_words text[];
  v_candidate text;
  v_sentence text;
  v_masked text;
  v_distractors text[];
BEGIN
  v_intro := coalesce(p_intro, '');

  -- ------------------------------------------------------------------
  -- Variante 0 (087/089): Lückentext aus Vorstellung (+ Bio, vom Caller
  -- kombiniert). Schwelle 089: >= 20 Zeichen (vorher 40), >= 3 Wörter
  -- (vorher 4), Satz 10-200 Zeichen (vorher 12-180).
  -- ------------------------------------------------------------------
  IF length(trim(v_intro)) >= 20 THEN
    BEGIN
      SELECT coalesce(array_agg(w ORDER BY
               hashtext(w || ':' || p_partner::text || ':' || p_match_id::text)),
               ARRAY[]::text[])
        INTO v_words
        FROM (
          SELECT DISTINCT word AS w
            FROM regexp_split_to_table(
                   lower(v_intro), '[^a-zäöüß0-9]+') AS word
           WHERE word ~ '^[a-zäöüß][a-zäöüß-]{4,}$'
             AND NOT (word = ANY (public.quiz_stopwords()))
        ) t;

      IF array_length(v_words, 1) >= 3 THEN
        FOR v_off IN 0 .. LEAST(array_length(v_words, 1) - 1, 11) LOOP
          v_candidate := v_words[1 + ((coalesce(p_attempt_count, 0) + v_off)
                              % array_length(v_words, 1))];

          SELECT regexp_replace(s, '\s+', ' ', 'g')
            INTO v_sentence
            FROM (
              SELECT s
                FROM unnest(regexp_split_to_array(v_intro, '[.!?]+')) AS s
               WHERE s ~* ('\y' || v_candidate || '\y')
               ORDER BY length(s), s
               LIMIT 1
            ) q;

          IF v_sentence IS NULL
             OR length(v_sentence) < 10
             OR length(v_sentence) > 200 THEN
            CONTINUE;
          END IF;

          SELECT coalesce(array_agg(w ORDER BY
                   hashtext(w || ':' || v_candidate || ':' ||
                            p_partner::text)), ARRAY[]::text[])
            INTO v_distractors
            FROM unnest(v_words) AS w
           WHERE w <> v_candidate
             AND left(w, 4) <> left(v_candidate, 4);

          IF array_length(v_distractors, 1) < 3 THEN
            CONTINUE;
          END IF;

          v_masked := regexp_replace(v_sentence, '\y' || v_candidate || '\y',
                                     '_____', 'gi');
          v_prompt := 'Vorstellung von ' || p_name || ': "' || v_masked
                      || '" Welches Wort gehört in die Lücke?';
          v_options := ARRAY[v_candidate, v_distractors[1],
                             v_distractors[2], v_distractors[3]];

          SELECT * INTO v_row
            FROM public.quiz_questions qq
           WHERE qq.owner_user_id = p_partner
             AND lower(qq.prompt) = lower(v_prompt)
           LIMIT 1;

          IF v_row IS NULL THEN
            INSERT INTO public.quiz_questions
                 (prompt, options, correct_index, owner_user_id)
            VALUES (v_prompt, to_jsonb(v_options), 0, p_partner)
            ON CONFLICT DO NOTHING;

            SELECT * INTO v_row
              FROM public.quiz_questions qq
             WHERE qq.owner_user_id = p_partner
               AND lower(qq.prompt) = lower(v_prompt)
             LIMIT 1;
          END IF;

          IF v_row IS NULL THEN
            CONTINUE;
          END IF;

          IF EXISTS (
            SELECT 1 FROM public.match_quiz_attempts a
             WHERE a.match_id = p_match_id
               AND a.question_id = v_row.id
          ) THEN
            CONTINUE;
          END IF;

          IF v_intro ~* ('\y' || v_candidate || '\y') THEN
            RETURN v_row;
          END IF;
        END LOOP;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_row := NULL;
    END;
  END IF;

  -- ------------------------------------------------------------------
  -- Variante 1: Interessen (086, unverändert) ---------------------------
  -- ------------------------------------------------------------------
  v_n := coalesce(array_length(p_interests, 1), 0);
  IF v_n >= 1 AND p_name IS NOT NULL AND p_name <> '' THEN
    FOR v_off IN 0 .. LEAST(v_n - 1, 7) LOOP
      v_idx := 1 + ((coalesce(p_attempt_count, 0) + v_off) % v_n);
      v_correct := p_interests[v_idx];
      IF v_correct IS NULL OR v_correct = '' THEN
        CONTINUE;
      END IF;

      v_prompt := 'Welches dieser Interessen gehört zu ' || p_name || '?';

      SELECT * INTO v_row
        FROM public.quiz_questions q
       WHERE q.owner_user_id = p_partner
         AND lower(q.prompt) = lower(v_prompt)
       LIMIT 1;

      IF v_row IS NULL THEN
        v_options := array[v_correct]
          || public.quiz_personal_distractors(p_partner, v_correct, p_interests);
        IF array_length(v_options, 1) < 4 THEN
          CONTINUE;
        END IF;
        INSERT INTO public.quiz_questions (prompt, options, correct_index, owner_user_id)
        VALUES (v_prompt, to_jsonb(v_options), 0, p_partner)
        ON CONFLICT DO NOTHING;

        SELECT * INTO v_row
          FROM public.quiz_questions q
         WHERE q.owner_user_id = p_partner
           AND lower(q.prompt) = lower(v_prompt)
         LIMIT 1;
      END IF;

      IF v_row IS NULL THEN
        CONTINUE;
      END IF;

      IF EXISTS (
        SELECT 1 FROM public.match_quiz_attempts a
         WHERE a.match_id = p_match_id
           AND a.question_id = v_row.id
      ) THEN
        CONTINUE;
      END IF;

      IF (v_row.options ->> 0) = ANY (p_interests) THEN
        RETURN v_row;
      END IF;
    END LOOP;
  END IF;

  -- ------------------------------------------------------------------
  -- Variante 2: Alter (086, unverändert) --------------------------------
  -- ------------------------------------------------------------------
  IF p_age IS NOT NULL AND p_age BETWEEN 16 AND 99
     AND p_name IS NOT NULL AND p_name <> '' THEN
    v_prompt := 'Wie alt ist ' || p_name || '?';
    v_options := ARRAY[
      p_age::text,
      (p_age + 3)::text,
      (p_age - 4)::text,
      (p_age + 9)::text
    ];

    SELECT * INTO v_row
      FROM public.quiz_questions q
     WHERE q.owner_user_id = p_partner
       AND lower(q.prompt) = lower(v_prompt)
     LIMIT 1;

    IF v_row IS NULL THEN
      INSERT INTO public.quiz_questions (prompt, options, correct_index, owner_user_id)
      VALUES (v_prompt, to_jsonb(v_options), 0, p_partner)
      ON CONFLICT DO NOTHING;

      SELECT * INTO v_row
        FROM public.quiz_questions q
       WHERE q.owner_user_id = p_partner
         AND lower(q.prompt) = lower(v_prompt)
       LIMIT 1;
    END IF;

    IF v_row IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.match_quiz_attempts a
          WHERE a.match_id = p_match_id
            AND a.question_id = v_row.id
       )
       AND v_row.options ->> 0 = p_age::text THEN
      RETURN v_row;
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

-- ==========================================================================
-- 3) start_quiz_attempt: Bio+Stadt einbeziehen, Fallback filtern ------------
-- ==========================================================================
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

  if v_state.last_attempt_at is not null and v_state.failed_attempts > 0 then
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

grant execute on function public.start_quiz_attempt(bigint) to authenticated;
