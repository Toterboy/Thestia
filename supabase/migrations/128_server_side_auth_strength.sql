-- =============================================================================
-- 128_server_side_auth_strength.sql
-- =============================================================================
-- Sicherheitsaudit 2026-09-26: MFA und E-Mail-Verifizierung waren ausschliesslich
-- CLIENT-Gates.
--
-- BEFUND (verifiziert):
--   * `mfaStatusProvider` ist ein `StateProvider` (lib/services/mfa_service.dart:233),
--     die Challenge wird nur im Router erzwungen (lib/routing/app_router.dart:412).
--   * Suche ueber ALLE Migrationen nach `aal`, `aal2`,
--     `auth.jwt()->>'aal'`, `factors`  ->  0 Treffer.
--   * Suche nach `email_confirmed_at` / `email_verified` -> 0 Treffer.
--   Ein Angreifer mit dem Passwort erhaelt von GoTrue einen gueltigen AAL1-JWT
--   und konnte damit jede RLS-erlaubte Operation direkt gegen PostgREST fahren.
--
-- LÖSUNG
--   1) `profiles.email_verified_at` als Spiegel von `auth.users` (RLS kann
--      `auth.users` nicht direkt lesen). Synchron per Trigger.
--   2) `profiles.mfa_required` (Default false) - AAL2 wird fuer die Nutzer
--      erzwungen, die es sich WUENSCHEN. Eine pauschale AAL2-Pflicht wuerde
--      alle Nutzer ohne MFA aussperren (Produktentscheidung, keine
--      Sicherheitskorrektur) - deshalb wird es profilindividuell erzwungen und
--      ist ab dem Moment aktiv, in dem ein Nutzer es einschaltet.
--   3) `public.session_meets_auth_requirements()` als EIN Pruefpunkt, der in
--      den sensibelsten Pfaden hängt: Relay (Chat) - komplett ueber RPC, ohne
--      Policies - sowie in matches/likes/Sessions.
--
-- BETRIEBS-SCHALTER (app_config, Muster wie `quiz_cooldown_seconds`):
--   enforce_email_confirmed = 'on'   (Default: an)
--   enforce_aal2            = 'on'   (Default: an)
--   NOT-AKTIVIEREN im Notfall:  UPDATE public.app_config SET value='off'
--   WHERE key='enforce_email_confirmed';
--   Ein Datenbank-Fix ohne Deploy ist damit moeglich.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0) Spiegel-Spalten + Konfiguration
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS email_verified_at timestamptz;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS mfa_required boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.email_verified_at IS
  'Spiegel von auth.users.email_confirmed_at. RLS kann auth.users nicht lesen, '
  'darum wird der Status hier per Trigger gespiegelt (128).';
COMMENT ON COLUMN public.profiles.mfa_required IS
  'Wenn true, verlangen die sensiblen Pfade serverseitig AAL2 (128).';

INSERT INTO public.app_config (key, value) VALUES
  ('enforce_email_confirmed', 'on'),
  ('enforce_aal2', 'on')
ON CONFLICT (key) DO NOTHING;

-- Bestandsnutzer spiegeln, damit niemand durch die neue Pruefung gesperrt
-- wird, der eigentlich bestaetigt ist.
UPDATE public.profiles p
   SET email_verified_at = u.email_confirmed_at
  FROM auth.users u
 WHERE u.id = p.user_id
   AND u.email_confirmed_at IS NOT NULL
   AND p.email_verified_at IS NULL;

-- -----------------------------------------------------------------------------
-- 1) Trigger: auth.users -> profiles.email_verified_at
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_email_verified_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.profiles
     SET email_verified_at = NEW.email_confirmed_at
   WHERE user_id = NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_email_verified_at ON auth.users;
CREATE TRIGGER trg_sync_email_verified_at
  AFTER INSERT OR UPDATE OF email_confirmed_at ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.sync_email_verified_at();

-- Neu registrierte Nutzer: Default greift sofort.
CREATE OR REPLACE FUNCTION public.init_profile_auth_flags()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.profiles
     SET email_verified_at = NEW.email_confirmed_at
   WHERE user_id = NEW.id
     AND email_verified_at IS DISTINCT FROM NEW.email_confirmed_at;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_init_profile_auth_flags ON public.profiles;
CREATE TRIGGER trg_init_profile_auth_flags
  AFTER INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.init_profile_auth_flags();

-- -----------------------------------------------------------------------------
-- 2) Der eine Pruefpunkt
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.session_meets_auth_requirements()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    -- Nicht angemeldet -> erfuellt nicht (RLSPolicies laufen auch fuer anon).
    auth.uid() IS NOT NULL
    AND (
      -- E-Mail-Bestaetigung
      coalesce(
        (SELECT value FROM public.app_config WHERE key = 'enforce_email_confirmed'),
        'on'
      ) <> 'on'
      OR EXISTS (
        SELECT 1 FROM public.profiles p
         WHERE p.user_id = auth.uid()
           AND p.email_verified_at IS NOT NULL
      )
    )
    AND (
      -- AAL2 nur fuer Konten, die es verlangen
      coalesce(
        (SELECT value FROM public.app_config WHERE key = 'enforce_aal2'),
        'on'
      ) <> 'on'
      OR NOT EXISTS (
        SELECT 1 FROM public.profiles p
         WHERE p.user_id = auth.uid() AND p.mfa_required
      )
      OR coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
    );
$$;

REVOKE ALL ON FUNCTION public.session_meets_auth_requirements()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.session_meets_auth_requirements()
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3) Relay (Chat) - hoechste Sensibilitaet, komplett RPC-gesteuert
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.relay_store(
  p_receiver uuid,
  p_ciphertext text,
  p_msg_type int DEFAULT 3,
  p_kind text DEFAULT 'text'
)
-- RETURNS bigint ist die bestehende Signatur aus 106. Ein CREATE OR REPLACE
-- kann den Rueckabetyp nicht aendern (42P13); die App nutzt den Wert nicht,
-- aber die Signatur bleibt Teil des Vertrags.
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_msg_type int;
  v_kind text;
  v_seen record;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  -- NEU (128): E-Mail-Bestaetigung + ggf. AAL2 serverseitig.
  IF NOT public.session_meets_auth_requirements() THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'auth_strength_insufficient';
  END IF;

  IF length(p_ciphertext) > 32768 THEN
    RAISE EXCEPTION 'ciphertext_too_large';
  END IF;

  IF length(p_ciphertext) < 8 THEN
    RAISE EXCEPTION 'ciphertext_too_short';
  END IF;

  IF p_receiver = v_user THEN
    RAISE EXCEPTION 'self_send';
  END IF;

  -- Beziehung in beide Richtungen: Match ODER aktive Zufallschat-Session
  -- ODER aktive Dating-Hour-Session (106).
  SELECT true INTO v_seen
    FROM public.matches m
   WHERE (m.user_one_id = v_user AND m.user_two_id = p_receiver)
      OR (m.user_two_id = v_user AND m.user_one_id = p_receiver);

  IF v_seen IS NULL THEN
    SELECT true INTO v_seen
      FROM public.random_chat_sessions s
     WHERE s.status = 'active'
       AND ((s.user_a = v_user AND s.user_b = p_receiver)
         OR (s.user_a = p_receiver AND s.user_b = v_user));

    IF v_seen IS NULL THEN
      SELECT true INTO v_seen
        FROM public.dating_hour_session s
       WHERE s.ended_at IS NULL
         AND ((s.user_a = v_user AND s.user_b = p_receiver)
           OR (s.user_b = v_user AND s.user_a = p_receiver));
    END IF;
  END IF;

  IF v_seen IS NULL THEN
    RAISE EXCEPTION 'no_relationship';
  END IF;

  v_msg_type := CASE
    WHEN p_msg_type IS NULL OR p_msg_type < 0 THEN 0
    WHEN p_msg_type > 7 THEN 7
    ELSE p_msg_type
  END;

  v_kind := CASE
    WHEN p_kind IS NULL OR p_kind = '' THEN 'text'
    WHEN p_kind IN ('text', 'icebreaker', 'image', 'voice', 'file') THEN p_kind
    ELSE 'text'
  END;

  INSERT INTO public.direct_message_relay
    (sender_id, receiver_id, ciphertext, msg_type, kind)
  VALUES
    (v_user, p_receiver, p_ciphertext, v_msg_type, v_kind)
  RETURNING id;
END;
$$;

CREATE OR REPLACE FUNCTION public.relay_fetch()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  -- NEU (128)
  IF NOT public.session_meets_auth_requirements() THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'auth_strength_insufficient';
  END IF;

  SELECT coalesce(jsonb_agg(x.obj ORDER BY x.created), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT jsonb_build_object(
               'id', r.id,
               'sender', r.sender_id,
               'ciphertext', r.ciphertext,
               'msgType', r.msg_type,
               'kind', r.kind,
               'createdAt', r.created_at
             ) AS obj,
             r.created_at AS created
        FROM public.direct_message_relay r
       WHERE r.receiver_id = v_uid
         AND r.delivered = false
       ORDER BY r.created_at
       LIMIT 100
    ) x;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.relay_ack(p_ids bigint[])
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

  -- AUDIT 2026-09-26: relay_ack war die EINZIGE Relay-Funktion ohne diese
  -- Pruefung - ein Konto ohne bestaetigte E-Mail / ohne AAL2 konnte den
  -- Posteingang trotzdem leeren. Gleiche Regel wie store/fetch.
  IF NOT public.session_meets_auth_requirements() THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'auth_strength_insufficient';
  END IF;
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RETURN;
  END IF;
  DELETE FROM public.direct_message_relay
   WHERE receiver_id = v_uid
     AND id = ANY (p_ids);
END;
$$;

-- -----------------------------------------------------------------------------
-- 4) matches / likes / Sessions: Policy-Ebene
--
--    WICHTIG: Permissive Policies werden per ODER verknuepft. Eine ZUSAETZLICHE,
--    einschraenkende Policy wuerde daher NICHTS bewirken, solange die alte
--    weiter besteht. Deshalb wird JEDE bestehende Policy unter demselben
--    Namen ersetzt (DROP + CREATE) statt eine neue zu erfinden.
--    Namen: 007:54 "Users can view own matches", 007:22 likes-SELECT,
--            021:82 dh_session_self_select, 032 Random-Chat-SELECT.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can view own matches" ON public.matches;
CREATE POLICY "Users can view own matches" ON public.matches
  FOR SELECT TO authenticated
  USING (
    (user_one_id = auth.uid() OR user_two_id = auth.uid())
    AND public.session_meets_auth_requirements()
  );

DROP POLICY IF EXISTS "Users can view own likes and likes received" ON public.likes;
CREATE POLICY "Users can view own likes and likes received" ON public.likes
  FOR SELECT TO authenticated
  USING (
    (user_id = auth.uid() OR liked_user_id = auth.uid())
    AND public.session_meets_auth_requirements()
  );

DROP POLICY IF EXISTS dh_session_self_select ON public.dating_hour_session;
CREATE POLICY dh_session_self_select ON public.dating_hour_session
  FOR SELECT TO authenticated
  USING (
    (user_a = auth.uid() OR user_b = auth.uid())
    AND public.session_meets_auth_requirements()
  );

-- Random-Chat: NUR eine bestehende SELECT-Policy unter ihrem echten Namen
-- ersetzen. Es wird KEINE neue Policy erfunden - der Client liest seine
-- Zufallschat-Session ueber `get_my_active_random_chat()` (111), ein
-- zusaetzlicher Direkt-SELECT waere eine Rechteausweitung.
DO $$
DECLARE
  v_old text;
BEGIN
  SELECT policyname INTO v_old
    FROM pg_policies
   WHERE tablename = 'random_chat_sessions'
     AND cmd = 'SELECT'
   LIMIT 1;

  IF v_old IS NOT NULL THEN
    EXECUTE format('DROP POLICY %I ON public.random_chat_sessions', v_old);
    EXECUTE $p$CREATE POLICY random_chat_self_read ON public.random_chat_sessions
      FOR SELECT TO authenticated
      USING (
        (user_a = auth.uid() OR user_b = auth.uid())
        AND public.session_meets_auth_requirements()
      )$p$;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5) Der Client darf `mfa_required` nur fuer sich setzen (kein Fremd-Flag).
--    Das bestehende `prevent_client_update_verification_fields`-Trigger
--    deckt die Verification-Spalten ab; dieses hier ist unabhängig davon und
--    kann nicht per UPDATE manipuliert werden, um someone_anderes zu markieren
--    (die Policy erlaubt ohnehin nur die eigene Zeile).
-- -----------------------------------------------------------------------------
-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_src text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_sync_email_verified_at' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Sicherheitscheck fehlgeschlagen: trg_sync_email_verified_at fehlt.';
  END IF;

  SELECT p.prosrc INTO v_src FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'session_meets_auth_requirements';
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'Sicherheitscheck fehlgeschlagen: session_meets_auth_requirements fehlt.';
  END IF;

  -- Die ersetzten Policies muessen die Pruefung wirklich enthalten.
  -- `random_chat_self_read` wird nur dann existieren, wenn es dort vorher
  -- eine SELECT-Policy gab - deshalb wird es nicht mitgezaehlt.
  IF (SELECT count(*) FROM pg_policies
       WHERE policyname IN ('Users can view own matches',
                            'Users can view own likes and likes received',
                            'dh_session_self_select')
         AND qual LIKE '%session_meets_auth_requirements%') < 3 THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: nicht alle Auth-Policies erzwingen die Auth-Staerke.';
  END IF;

  -- Und es darf keine alte, unrestringierte SELECT-Policy daneben liegen.
  IF EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename IN ('matches', 'likes', 'dating_hour_session', 'random_chat_sessions')
       AND cmd = 'SELECT'
       AND qual NOT LIKE '%session_meets_auth_requirements%') THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: unrestringierte SELECT-Policy auf einer Match-/Chat-Tabelle.';
  END IF;

  -- Relay muss die Pruefung in ALLEN drei Funktionen aufrufen.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public'
         AND p.proname IN ('relay_store', 'relay_fetch', 'relay_ack')
         AND p.prosrc LIKE '%session_meets_auth_requirements%') < 3 THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: Relay erzwingt die Auth-Staerke nicht in allen Pfaden.';
  END IF;
END;
$$;
