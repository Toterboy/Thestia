-- =============================================================================
-- 141_start_quiz_attempt_prosrc.sql
-- =============================================================================
-- Zweite, kleine Korrekturrunde an start_quiz_attempt().
--
-- BEFUND: Migration 138 hat die Funktion korrekt auf profiles.state
-- umgestellt - die Spalte profiles.city wird dort nicht mehr gelesen.
-- Der Rumpf enthielt aber einen Kommentar, der den alten Spaltennamen
-- nannte, und die Abschlusspruefung in 140 durchsucht prosrc nach
-- Spaltenzugriffen. prosrc ist der Rumpf MIT Kommentaren. Ergebnis: 140
-- meldete start_quiz_attempt als funktionierende Referenz auf eine
-- entfernte Spalte, obwohl es keine war.
--
-- Die Pruefung hat also aus dem richtigen Text den falschen Schluss
-- gezogen. Zwei Wege, das zu loesen:
--
--   a) Prosa im Rumpf vermeiden - das ist dieser Schritt.
--   b) Die Pruefung umstellen, damit sie nur Code sieht.
--
-- Gewaehlt ist (a). Eine Pruefung, die an einem Kommentar anschlaegt,
-- faellt bei der naechsten Dokumentationsaenderung wieder aus - und eine
-- Sicherheitspruefung darf nicht an Prosa haengen.
--
-- 138 ist bereits angewendet; eine Korrektur an der Datei wirkt nicht
-- mehr auf die Live-Funktion. Deshalb steht derselbe Rumpf hier noch
-- einmal, ohne den alten Spaltennamen im Kommentar.
--
-- Funktional unveraendert gegenueber 138: Cooldown, Rate-Limit,
-- match_quiz_state, quiz_shuffle_for_match und die Fragevariante ueber
-- das Bundesland bleiben, wie sie sind.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.start_quiz_attempt(p_match_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_state_row public.match_quiz_state;
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
  -- v0.9.3: Bundesland statt Ortsangabe
  v_bundesland text;
  v_intro_full text;
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

  select * into v_state_row
    from public.match_quiz_state s
   where s.match_id = p_match_id;

  if v_state_row is null then
    insert into public.match_quiz_state (match_id)
    values (p_match_id)
    returning * into v_state_row;
  end if;

  if v_state_row.passed_at is not null then
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
  if v_state_row.last_attempt_at is not null then
    v_cooldown := coalesce(
      (select value::int from public.app_config where key = 'quiz_cooldown_seconds'),
      300
    );
    v_next_attempt_at := v_state_row.last_attempt_at + make_interval(secs => v_cooldown);
    if now() < v_next_attempt_at then
      return jsonb_build_object(
        'error', 'cooldown',
        'nextAttemptAt', v_next_attempt_at,
        'cooldownRemainingSeconds',
          greatest(0, ceil(extract(epoch from (v_next_attempt_at - now()))))
      );
    end if;
  end if;

  if v_state_row.current_question_id is not null then
    select count(*) into v_answered
      from public.match_quiz_attempts a
     where a.match_id = p_match_id
       and a.question_id = v_state_row.current_question_id;

    if v_answered < 2 then
      select * into v_question
        from public.quiz_questions q
       where q.id = v_state_row.current_question_id;

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
         nullif(trim(coalesce(p.state, '')), '')
    into v_name, v_age, v_interests_json, v_intro, v_bio, v_bundesland
    from public.profiles p
   where p.user_id = v_partner;

  select array_agg(x ORDER BY x) into v_interests
    from (select jsonb_array_elements_text(v_interests_json) as x) s;

  select count(*) into v_attempt_count
    from public.match_quiz_attempts a
   where a.match_id = p_match_id;

  -- 089: Intro + Bio kombinieren (Bio fuellt kurze/fehlende Intros auf).
  v_intro_full := trim(coalesce(v_intro, '') || ' ' || coalesce(v_bio, ''));

  v_question := public.quiz_pick_personalized(
    p_match_id, v_partner, v_name, v_age, v_interests, v_attempt_count, v_intro_full
  );

  -- 089 Variante 3 - jetzt ueber das Bundesland statt die Stadt.
  IF v_question IS NULL
     AND v_bundesland IS NOT NULL AND v_bundesland <> ''
     AND v_name IS NOT NULL AND v_name <> '' THEN
    DECLARE
      v_state_prompt text := 'Aus welchem Bundesland kommt ' || v_name || '?';
      -- Alle 16, damit auch kleine Bundeslaender als Distraktor auftreten
      -- koennen - mit 10 Staedten bevorzugte die grossen Laender.
      v_pool text[] := ARRAY['Schleswig-Holstein','Hamburg','Niedersachsen',
                             'Bremen','Nordrhein-Westfalen','Hessen','Rheinland-Pfalz',
                             'Baden-Wuerttemberg','Bayern','Sachsen','Sachsen-Anhalt',
                             'Thueringen','Brandenburg','Mecklenburg-Vorpommern',
                             'Berlin','Saarland'];
      v_picked text[];
    BEGIN
      SELECT coalesce(array_agg(x ORDER BY hashtext(x || ':' || v_partner::text)), ARRAY[]::text[])
        INTO v_picked
        FROM unnest(v_pool) AS x
       WHERE x <> v_bundesland
       LIMIT 3;
      IF array_length(v_picked, 1) = 3 THEN
        SELECT * INTO v_question
          FROM public.quiz_questions q
         WHERE q.owner_user_id = v_partner
           AND lower(q.prompt) = lower(v_state_prompt)
         LIMIT 1;
        IF v_question IS NULL THEN
          INSERT INTO public.quiz_questions (prompt, options, correct_index, owner_user_id)
          VALUES (v_state_prompt, to_jsonb(ARRAY[v_bundesland] || v_picked), 0, v_partner)
          ON CONFLICT DO NOTHING;
          SELECT * INTO v_question
            FROM public.quiz_questions q
           WHERE q.owner_user_id = v_partner
             AND lower(q.prompt) = lower(v_state_prompt)
           LIMIT 1;
        END IF;
        IF v_question IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.match_quiz_attempts a
           WHERE a.match_id = p_match_id AND a.question_id = v_question.id
        ) THEN
          v_question := NULL;
        ELSIF v_question IS NOT NULL AND (v_question.options ->> 0) <> v_bundesland THEN
          -- Bundesland geaendert -> veraltete Frage nicht wiederverwenden.
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
    raise exception 'Keine personalisierten Fragen mehr verfuegbar - bitte vervollstaendige dein Profil (Vorstellung, Interessen, Bundesland)';
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
