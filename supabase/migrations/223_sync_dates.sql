-- 223_sync_dates.sql
--
-- "Begegnung statt Bildschirm": die Sync-Dates.
--
-- ZWEI MENSCHEN, DIE WEIT AUSEINANDER WOHNEN, TREFFEN SICH ZUR
-- SELBEN ZEIT AN VERSCHIEDENEN ORTEN: Beide gehen spazieren und
-- telefonieren dabei, beide starten denselben Film zur selben Zeit,
-- beide kochen dasselbe Rezept. Das Date endet, wenn der Anruf endet.
--
-- WARUM DAS SERVERSEITIG LIEGT: Beide Seiten muessen DEN SELBEN
-- Startzeitpunkt sehen (die Geraeteuhren weichen ab) und beide muessen
-- sehen, ob der andere schon angenommen hat. Die Chat-Nachrichten selbst
-- sind E2E/P2P und stehen nicht in der DB - der Termin des Dates aber
-- schon (er ist ein gemeinsamer Zustand, kein Inhalt).
--
-- DER KATALOG: Die Ideen stehen in der App (mit den Texten). Die
-- CHECK-Bedingung unten haelt fest, welche Ideen es gibt - so kann
-- niemand unsinnige Werte in die Zeile schreiben. Kommt eine Idee
-- dazu, kommt sie hier hinein.
--
-- Die App fragt den Stand ueber get_sync_date() und aendert ihn ueber
-- set_sync_date(). Beide Funktionen sind SECURITY DEFINER mit festem
-- search_path und pruefen selbst, dass der Aufrufer zu dem Match
-- gehoert.

-- -----------------------------------------------------------------------------
-- 1) Die Tabelle: pro Match genau ein Date.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sync_dates (
  match_id     bigint PRIMARY KEY REFERENCES public.matches(id) ON DELETE CASCADE,
  idea         text NOT NULL,
  start_at     timestamptz NOT NULL,
  proposed_by  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  accepted_by  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sync_dates_idea_check CHECK (
    idea IN (
      'spaziergangAnruf',
      'gleicherFilm',
      'kochDuell',
      'sterneGucken'
    )
  )
);

COMMENT ON TABLE public.sync_dates IS
  'Das Sync-Date eines Matches: die Idee, der gemeinsame Startzeitpunkt '
  'und die Annahme. Pro Match gibt es hoechstens eines.';

-- -----------------------------------------------------------------------------
-- 2) RLS: nur die beiden Match-Teilnehmer duerfen lesen und schreiben.
-- -----------------------------------------------------------------------------
ALTER TABLE public.sync_dates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Participants can select sync_date" ON public.sync_dates;
CREATE POLICY "Participants can select sync_date"
  ON public.sync_dates FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.matches m
       WHERE m.id = sync_dates.match_id
         AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Participants can insert sync_date" ON public.sync_dates;
CREATE POLICY "Participants can insert sync_date"
  ON public.sync_dates FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.matches m
       WHERE m.id = sync_dates.match_id
         AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Participants can update sync_date" ON public.sync_dates;
CREATE POLICY "Participants can update sync_date"
  ON public.sync_dates FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.matches m
       WHERE m.id = sync_dates.match_id
         AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.matches m
       WHERE m.id = sync_dates.match_id
         AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Participants can delete sync_date" ON public.sync_dates;
CREATE POLICY "Participants can delete sync_date"
  ON public.sync_dates FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.matches m
       WHERE m.id = sync_dates.match_id
         AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
    )
  );

-- -----------------------------------------------------------------------------
-- 3) RPC: der Stand aus der Sicht des Aufrufers.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_sync_date(p_match_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_one  uuid;
  v_two  uuid;
  v_row  public.sync_dates%rowtype;
  v_result jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Nicht authentifiziert';
  END IF;

  SELECT m.user_one_id, m.user_two_id
    INTO v_one, v_two
    FROM public.matches m
   WHERE m.id = p_match_id;

  IF v_one IS NULL THEN
    RAISE EXCEPTION 'Match nicht gefunden';
  END IF;

  IF v_user <> v_one AND v_user <> v_two THEN
    RAISE EXCEPTION 'Kein Zugriff auf dieses Match';
  END IF;

  SELECT * INTO v_row
    FROM public.sync_dates
   WHERE match_id = p_match_id;

  IF v_row.match_id IS NULL THEN
    RETURN NULL;
  END IF;

  v_result := jsonb_build_object(
    'matchId', p_match_id,
    'idea', v_row.idea,
    'startAt', v_row.start_at,
    'proposedByMe', v_row.proposed_by = v_user,
    'acceptedByMe', v_row.accepted_by = v_user,
    'acceptedByPartner', v_row.accepted_by IS NOT NULL AND v_row.accepted_by <> v_user,
    'bothAccepted', v_row.accepted_by IS NOT NULL
  );
  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_sync_date(bigint) IS
  'Der Stand des Sync-Dates eines Matches aus der Sicht des Aufrufers. '
  'NULL, wenn es keines gibt.';

-- -----------------------------------------------------------------------------
-- 4) RPC: vorschlagen, annehmen oder absagen.
--
--    p_idea + p_start_at -> ein Date vorschlagen (ersetzt ein altes).
--    p_accept          -> ich nehme an.
--    p_decline          -> ich sage ab (das Date loescht sich).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_sync_date(
  p_match_id bigint,
  p_idea text DEFAULT NULL,
  p_start_at timestamptz DEFAULT NULL,
  p_accept boolean DEFAULT NULL,
  p_decline boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_one  uuid;
  v_two  uuid;
  v_row  public.sync_dates%rowtype;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Nicht authentifiziert';
  END IF;

  SELECT m.user_one_id, m.user_two_id
    INTO v_one, v_two
    FROM public.matches m
   WHERE m.id = p_match_id;

  IF v_one IS NULL THEN
    RAISE EXCEPTION 'Match nicht gefunden';
  END IF;

  IF v_user <> v_one AND v_user <> v_two THEN
    RAISE EXCEPTION 'Kein Zugriff auf dieses Match';
  END IF;

  -- ABSAGEN: Das Date loescht sich (beide sehen danach wieder keins).
  IF p_decline IS TRUE THEN
    DELETE FROM public.sync_dates WHERE match_id = p_match_id;
    RETURN NULL;
  END IF;

  -- VORSCHLAGEN: Die Idee und der Zeitpunkt muessen zusammen kommen.
  IF p_idea IS NOT NULL OR p_start_at IS NOT NULL THEN
    IF p_idea IS NULL OR p_start_at IS NULL THEN
      RAISE EXCEPTION 'Idee und Zeitpunkt gehoeren zusammen';
    END IF;
    IF p_start_at < (now() - interval '1 hour') THEN
      RAISE EXCEPTION 'Der Zeitpunkt liegt in der Vergangenheit';
    END IF;

    INSERT INTO public.sync_dates (match_id, idea, start_at, proposed_by)
    VALUES (p_match_id, p_idea, p_start_at, v_user)
    ON CONFLICT (match_id) DO UPDATE
      SET idea = excluded.idea,
          start_at = excluded.start_at,
          proposed_by = excluded.proposed_by,
          accepted_by = NULL,
          updated_at = now();
  END IF;

  -- ANNEHMEN: Wer annimmt, ist der Annehmer - der Vorschlagende muss
  -- auch annehmen (er hat ja selbst vorgeschlagen).
  IF p_accept IS TRUE THEN
    SELECT * INTO v_row
      FROM public.sync_dates
     WHERE match_id = p_match_id;

    IF v_row.match_id IS NULL THEN
      RAISE EXCEPTION 'Es gibt kein Date zum Annehmen';
    END IF;

    UPDATE public.sync_dates
       SET accepted_by = v_user,
           updated_at = now()
     WHERE match_id = p_match_id;
  END IF;

  RETURN public.get_sync_date(p_match_id);
END;
$$;

COMMENT ON FUNCTION public.set_sync_date(bigint, text, timestamptz, boolean, boolean) IS
  'Ein Sync-Date vorschlagen, annehmen oder absagen. Gibt den neuen '
  'Stand aus der Sicht des Aufrufers zurueck (NULL, wenn es keines '
  'mehr gibt).';

GRANT EXECUTE ON FUNCTION public.get_sync_date(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_sync_date(bigint, text, timestamptz, boolean, boolean) TO authenticated;
