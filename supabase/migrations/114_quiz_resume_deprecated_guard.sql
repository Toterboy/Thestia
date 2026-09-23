-- Migration 114: Quiz-Resume-Branch respektiert is_deprecated
--
-- ROOT CAUSE (Build 29-Verifikation, live bewiesen): start_quiz_attempt
-- lieferte die Smoothie-Trivia AUS ("Was ist ein Smoothie?"), obwohl
-- Migration 089 sie als is_deprecated markiert. Ursache: Der Resume-
-- Branch (laufende Runde via current_question_id) prüfte das Flag nie -
-- ein VOR der Deprecation gespeicherter State (z. B. Match 1 seit
-- 2026-09-09) servierte die Altfrage EWIG (roundInProgress=true).
--
-- FIX: Resume nur bei nicht-deprecated Frage, sonst frisch wählen.
-- Plus Einmal-Cleanup aller stale deprecated States.

-- 1) Einmal-Cleanup: stale States auf deprecated Fragen zurücksetzen.
UPDATE public.match_quiz_state s
   SET current_question_id = NULL
 WHERE s.current_question_id IS NOT NULL
   AND EXISTS (
     SELECT 1 FROM public.quiz_questions q
      WHERE q.id = s.current_question_id
        AND (q.is_deprecated IS NOT FALSE)
   );

-- 2) Chirurgischer Funktions-Patch (statt Voll-Rewrite): Der Resume-
-- Branch greift nur noch bei nicht-deprecated Frage.
DO $$
DECLARE
  v_def text;
  v_old text := '    if v_answered < 2 then';
  v_new text := '    -- 114: Deprecated Fragen (z. B. Smoothie-Trivia) nie aus
    -- einem stale State servieren - stattdessen frisch wählen.
    IF v_answered < 2 AND EXISTS (
         SELECT 1 FROM public.quiz_questions q
          WHERE q.id = v_state.current_question_id
            AND (q.is_deprecated IS DISTINCT FROM true)
       ) THEN';
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def
    FROM pg_proc
   WHERE proname = 'start_quiz_attempt'
     AND pronamespace = 'public'::regnamespace;

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'start_quiz_attempt nicht gefunden';
  END IF;
  IF position(v_old in v_def) = 0 THEN
    RAISE EXCEPTION 'Patch-Ziel nicht gefunden (Funktion geändert?)';
  END IF;

  v_def := replace(v_def, v_old, v_new);
  EXECUTE v_def;
END
$$;
