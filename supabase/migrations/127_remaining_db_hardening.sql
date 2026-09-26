-- =============================================================================
-- 127_remaining_db_hardening.sql
-- =============================================================================
-- Sicherheitsaudit 2026-09-26: restliche DB-Befunde.
--
-- 1) `match_bucket_list`:/match_id` und `created_by` waren per UPDATE
--    beliebig umschreibbar (Policy 116:71-77 hatte `USING`, aber kein
--    `WITH CHECK`). Ein Match-Teilnehmer konnte die Zeile in ein BELIEBIGES
--    fremdes Match umhaengen und `created_by` auf eine fremde UUID setzen -
--    was ueber `bucket_list_creator_delete` auch das Loeschrecht verschiebt.
--    Geloest ueber einen BEFORE-UPDATE-Trigger auf IMMUTABLEN Spalten: das ist
--    unabhaengig von der Policy und kann durch kein spaeteres
--    `CREATE OR REPLACE` verloren gehen. Die bekannten Statuswechsel
--    (`done_at`/`done_by`) bleiben erlaubt.
--
-- 2) `match_bucket_add` ohne Rate-Limit, ohne Row-Cap und OHNE Retention-Cron
--    - anders als `user_reports` (180 Tage) und `direct_message_relay`
--    (30 Tage). Unbegrenztes Wachstum = unbegrenzte Storage-Kosten.
--
-- 3) `check_email_ban_status` ist bewusst anon-aufrufbar (Registrierungs-
--    Vorpruefung), gab aber den internen Moderations-Freitext `reason` zurueck
--    (045:87-97). Der Client braucht nur `banned: true/false`.
--
-- 4) Fehlende Wert-Domaenen: `relationship_type`, `preferred_state`,
--    `distance_filter_mode` hatten dokumentierte Wertelisten, aber keine
--    CHECK-Constraints. Der Kommentar in 085 definiert die Liste, nichts hat
--    sie erzwungen.
--
-- 5) Statuswechsel auf `matches` waren ungedrosselt. `end_match` erzeugt
--    serverseitig Pushes (notify_push_trigger, 040) - ein Spamming-Vektor.
--    geloest ueber einen BEFORE-UPDATE-Trigger auf `matches`, der ALLE Pfade
--    erfasst (cool_match/respark_match/end_match/hide_match UND direkte
--    UPDATEs) - die Funktionskoerper bleiben unangetastet.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Unveraenderliche Spalten in match_bucket_list
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_bucket_list_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.match_id IS DISTINCT FROM OLD.match_id THEN
    RAISE EXCEPTION 'bucket_immutable: match_id ist unveraenderlich';
  END IF;
  IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'bucket_immutable: created_by ist unveraenderlich';
  END IF;
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'bucket_immutable: created_at ist unveraenderlich';
  END IF;
  -- `done_by` darf nur der aktuelle Nutzer oder NULL sein (kein Spoofing).
  IF NEW.done_by IS NOT NULL AND NEW.done_by <> auth.uid() THEN
    RAISE EXCEPTION 'bucket_forbidden: done_by muss der eigene Nutzer sein';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bucket_list_immutable ON public.match_bucket_list;
CREATE TRIGGER trg_bucket_list_immutable
  BEFORE UPDATE ON public.match_bucket_list
  FOR EACH ROW EXECUTE FUNCTION public.guard_bucket_list_immutable();

-- Policy bleibt (Betrueber muss Match-Teilnehmer sein), jetzt aber mit
-- WITH CHECK auf die Match-Zugehoerigkeit der NEUEN Zeile.
DROP POLICY IF EXISTS bucket_list_member_update ON public.match_bucket_list;

CREATE POLICY bucket_list_member_update ON public.match_bucket_list
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.matches m
     WHERE m.id = match_id
       AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.matches m
     WHERE m.id = match_id
       AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
  ));

-- -----------------------------------------------------------------------------
-- 2) Rate-Limit + Row-Cap + Retention fuer match_bucket_add
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.match_bucket_add(p_match_id bigint, p_text text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id bigint;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht authentifiziert';
  END IF;

  -- 200 Eintraege pro Stunde (vorher unbegrenzt).
  IF NOT public.consume_rate_limit('bucket_add:' || v_uid::text, 200, 3600) THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.matches m
     WHERE m.id = p_match_id
       AND (m.user_one_id = v_uid OR m.user_two_id = v_uid)
  ) THEN
    RAISE EXCEPTION 'Kein eigenes Match';
  END IF;

  -- Row-Cap je Match: 200 Eintraege. Ohne Cap konnte ein Client die Liste
  -- beliebig aufblaehen.
  SELECT count(*) INTO v_count
    FROM public.match_bucket_list WHERE match_id = p_match_id;

  IF v_count >= 200 THEN
    RAISE EXCEPTION 'bucket_full: Maximal 200 Eintraege pro Match';
  END IF;

  INSERT INTO public.match_bucket_list (match_id, created_by, text)
  VALUES (p_match_id, v_uid, left(trim(p_text), 200))
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_bucket_add(bigint, text) TO authenticated;

-- Retention: abgehakte Eintraege nach 180 Tagen loeschen, offene bleiben.
-- Spalten laut 116: `done_at` (nicht `done`/`updated_at`).
SELECT cron.schedule(
  'cleanup_old_bucket_list',
  '20 4 * * *',
  $$ DELETE FROM public.match_bucket_list
     WHERE done_at IS NOT NULL
       AND done_at < now() - interval '180 days' $$
);

-- -----------------------------------------------------------------------------
-- 3) check_email_ban_status: kein Freitext mehr nach aussen
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_email_ban_status(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_banned boolean := false;
BEGIN
  IF p_email IS NULL OR btrim(p_email) = '' THEN
    RETURN jsonb_build_object('banned', false);
  END IF;

  IF NOT public.consume_rate_limit('ban_check:' || lower(btrim(p_email)), 30, 3600) THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  SELECT true INTO v_banned
    FROM public.banned_emails
   WHERE email = lower(btrim(p_email));

  -- NUR das Flag. Vorher wurde zusaetzlich `reason` (interner
  -- Moderations-Freitext, bis 1000 Zeichen) zurueckgegeben - eine
  -- Informationsleckage an unauthentifizierte Aufrufer.
  RETURN jsonb_build_object('banned', coalesce(v_banned, false));
END;
$$;

REVOKE ALL ON FUNCTION public.check_email_ban_status(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_email_ban_status(text) TO anon, service_role;

-- -----------------------------------------------------------------------------
-- 4) Wert-Domaenen als CHECK-Constraints
--    Werte 1:1 nach den Kommentaren in 066:11-13 und 085:9-10.
--    Alt-Daten werden vorher bereinigt, damit ADD CONSTRAINT nicht scheitert.
-- -----------------------------------------------------------------------------
UPDATE public.profiles
   SET relationship_type = 'unspecified'
 WHERE relationship_type IS NOT NULL
   AND relationship_type NOT IN ('unspecified', 'long_term', 'short_term',
                                 'open_to_anything', 'figuring_out', 'other');

UPDATE public.profiles
   SET distance_filter_mode = 'distance_km'
 WHERE distance_filter_mode IS NULL
    OR distance_filter_mode NOT IN ('distance_km', 'state', 'germany');

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'profiles_relationship_type_check'
                    AND conrelid = 'public.profiles'::regclass) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_relationship_type_check
      CHECK (relationship_type IS NULL
             OR relationship_type IN ('unspecified', 'long_term', 'short_term',
                                      'open_to_anything', 'figuring_out', 'other'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'profiles_preferred_state_check'
                    AND conrelid = 'public.profiles'::regclass) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_preferred_state_check
      CHECK (preferred_state IS NULL
             OR preferred_state IN ('single', 'polyamory', 'open', 'unspecified'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'profiles_distance_filter_mode_check'
                    AND conrelid = 'public.profiles'::regclass) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_distance_filter_mode_check
      CHECK (distance_filter_mode IN ('distance_km', 'state', 'germany'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'profiles_max_distance_km_check'
                    AND conrelid = 'public.profiles'::regclass) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_max_distance_km_check
      CHECK (max_distance_km IS NULL OR (max_distance_km BETWEEN 1 AND 500));
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5) Rate-Limit fuer Statuswechsel auf `matches` (alle Pfade, ein Trigger)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_match_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
BEGIN
  -- Nur echte Statuswechsel interessieren (updated_at/timestamp-Beruehrungen
  -- nicht - sonst wuerde jedes Hochfahren eines Screens das Limit verbrauchen).
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  v_actor := auth.uid();
  IF v_actor IS NULL THEN
    -- Kein Nutzerkontext = Scheduler/Cron. Der darf paaren (Dating Hour,
    -- Zufallschat, Transit-Spark); diese Pfare pruefen die Regeln selbst.
    RETURN NEW;
  END IF;

  IF NOT (NEW.user_one_id = v_actor OR NEW.user_two_id = v_actor) THEN
    RAISE EXCEPTION 'forbidden: nicht Teil dieses Matches';
  END IF;

  -- 60 Statuswechsel pro Stunde. Ein normaler Nutzer kuehlt/endet wenige
  -- Funken pro Stunde; 60 laesst das voll zu und schneidet Automatisiertes
  -- (Flickern, Push-Flut ueber notify_push_trigger) ab.
  IF NOT public.consume_rate_limit('match_status:' || v_actor::text, 60, 3600) THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_match_status_change ON public.matches;
CREATE TRIGGER trg_guard_match_status_change
  BEFORE UPDATE OF status ON public.matches
  FOR EACH ROW EXECUTE FUNCTION public.guard_match_status_change();

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_bucket_list_immutable' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Sicherheitscheck fehlgeschlagen: trg_bucket_list_immutable fehlt.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_guard_match_status_change' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Sicherheitscheck fehlgeschlagen: trg_guard_match_status_change fehlt.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename = 'match_bucket_list'
       AND policyname = 'bucket_list_member_update'
       AND with_check IS NOT NULL) THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: bucket_list_member_update hat kein WITH CHECK.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'check_email_ban_status'
       -- Nur die SQL-Zeichenkette 'reason' MIT Anfuehrungszeichen zaehlt:
      -- das ist die Form eines jsonb-Keys oder Spaltenbezugs im Code.
      -- `prosrc` enthaelt die Kommentare des Bodies MIT - ein Kommentar,
      -- der das Wort nennt, darf den Check nicht ausloesen.
      AND p.prosrc LIKE '%' || chr(39) || 'reason' || chr(39) || '%') THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: check_email_ban_status gibt reason weiter.';
  END IF;
END;
$$;
