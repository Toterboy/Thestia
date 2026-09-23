-- Migration 116: Herzensstärken — Erinnerung, Freundschafts-Modus,
-- gemeinsame Erinnerungsliste (Nutzerwunsch-Ideen 1/3/5)
--
-- 1) ERINNERE-DICH-AN-IT (Jubiläums-Momente): Milestones pro Match
--    (Funke entstanden, Quiz bestanden, 1 Monat, 3 Monate, 1 Jahr).
--    Serverseitig berechnet beim Laden der Funken (kein Cron nötig).
-- 2) FREUNDSCHAFTS-MODUS: matches.kind ('spark' | 'friends') - bei
--    Freundschaft wird das Matching nicht romantisch interpretiert
--    (Texte/UI), Filter im Funken-Tab.
-- 3) GEMEINSAME ERINNERUNGSLISTE: match_bucket_list - Einträge, die
--    beide Seiten pflegen können (wer hat's erlebt?); Erinnerung,
--    wenn die Liste lange unberührt bleibt (Client-Timer, kein Cron).

-- ---------------------------------------------------------------------
-- 2) Freundschafts-Modus: match.kind
-- ---------------------------------------------------------------------
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'spark';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_matches_kind'
  ) THEN
    ALTER TABLE public.matches
      ADD CONSTRAINT chk_matches_kind
      CHECK (kind IN ('spark', 'friends'));
  END IF;
END
$$;

COMMENT ON COLUMN public.matches.kind IS
'v0.9.2: spark = romantisch (Standard), friends = Freundschaft (Idee 3).';

-- ---------------------------------------------------------------------
-- 3) Gemeinsame Erinnerungsliste
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.match_bucket_list (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  match_id bigint NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  text text NOT NULL,
  done_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  done_at timestamptz,
  CONSTRAINT bucket_text_not_empty CHECK (length(trim(text)) BETWEEN 1 AND 200)
);

ALTER TABLE public.match_bucket_list ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.match_bucket_list IS
'v0.9.2 (Idee 5): Gemeinsame Erinnerungsliste pro Funke - "das wollten wir mal tun". done_at leer = offen.';

CREATE POLICY bucket_list_member_read ON public.match_bucket_list
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.matches m
     WHERE m.id = match_id
       AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
  ));

CREATE POLICY bucket_list_member_write ON public.match_bucket_list
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.matches m
     WHERE m.id = match_id
       AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
       AND created_by = auth.uid()
  ));

CREATE POLICY bucket_list_member_update ON public.match_bucket_list
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.matches m
     WHERE m.id = match_id
       AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
  ));

CREATE POLICY bucket_list_creator_delete ON public.match_bucket_list
  FOR DELETE TO authenticated
  USING (created_by = auth.uid());

-- RPCs: Liste lesen (kleinstmögliche Felder), anlegen, abhaken.
CREATE OR REPLACE FUNCTION public.match_bucket_items(p_match_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.matches m
     WHERE m.id = p_match_id
       AND (m.user_one_id = v_uid OR m.user_two_id = v_uid)
  ) THEN
    RAISE EXCEPTION 'Kein Match';
  END IF;
  RETURN coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id,
           'text', b.text,
           'createdBy', b.created_by,
           'done', b.done_at IS NOT NULL,
           'createdAt', b.created_at
         ) ORDER BY b.done_at NULLS FIRST, b.id DESC), '[]'::jsonb)
    FROM public.match_bucket_list b
   WHERE b.match_id = p_match_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.match_bucket_add(
  p_match_id bigint, p_text text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id bigint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.matches m
     WHERE m.id = p_match_id
       AND (m.user_one_id = v_uid OR m.user_two_id = v_uid)
  ) THEN
    RAISE EXCEPTION 'Kein Match';
  END IF;
  IF p_text IS NULL OR length(trim(p_text)) = 0
     OR length(p_text) > 200 THEN
    RAISE EXCEPTION 'Ungueltiger Eintrag';
  END IF;
  INSERT INTO public.match_bucket_list (match_id, created_by, text)
  VALUES (p_match_id, v_uid, left(trim(p_text), 200))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.match_bucket_toggle(p_item_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_item public.match_bucket_list;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;
  SELECT * INTO v_item FROM public.match_bucket_list b
   WHERE b.id = p_item_id
     AND EXISTS (
       SELECT 1 FROM public.matches m
        WHERE m.id = b.match_id
          AND (m.user_one_id = v_uid OR m.user_two_id = v_uid));
  IF v_item.id IS NULL THEN
    RAISE EXCEPTION 'Nicht gefunden';
  END IF;
  IF v_item.done_at IS NULL THEN
    UPDATE public.match_bucket_list
       SET done_at = now(), done_by = v_uid
     WHERE id = v_item.id;
    RETURN jsonb_build_object('id', v_item.id, 'done', true);
  END IF;
  UPDATE public.match_bucket_list
     SET done_at = NULL, done_by = NULL
   WHERE id = v_item.id;
  RETURN jsonb_build_object('id', v_item.id, 'done', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.match_bucket_delete(p_item_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;
  DELETE FROM public.match_bucket_list b
   WHERE b.id = p_item_id
     AND b.created_by = v_uid
     AND EXISTS (
       SELECT 1 FROM public.matches m
        WHERE m.id = b.match_id
          AND (m.user_one_id = v_uid OR m.user_two_id = v_uid));
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_bucket_items(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.match_bucket_add(bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.match_bucket_toggle(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.match_bucket_delete(bigint) TO authenticated;

-- ---------------------------------------------------------------------
-- 1) Erinnerungs-Momente: list_my_matches_with_state liefert den
--    Funken-Typ (kind) mit; Milestones berechnet der CLIENT aus
--    createdAt/passedAt (keine Extra-Tabelle, keine Cron).
-- ---------------------------------------------------------------------
