-- 179: Der Eltern-Link gilt 24 Stunden, und die E-Mail des
-- Elternteils wird mit dem Ende der Freigabe geloescht.
--
-- NUTZERWUNSCH (04.11.2026), zwei Punkte:
--
--   1. "der Link statt 14 Tagen nur 24 Stunden gueltig sein" -
--      nicht nur im Text, sondern im Server. Ein Freigabe-Link, der
--      zwei Wochen lang lebt, ist ein Link, der im Postkasten
--      versackt und dann irgendwann von einer fremden Person
--      benutzt wird. 24 Stunden reichen fuer "Mama, schau mal".
--
--   2. "die Emailadresse des Elternteils auch mit Beendigung der
--      Freigabe geloescht" - mit einer Ausnahme: Wer als Jugendlicher
--      "noch 1 Monat behalten" waehlt, hat die Freigabe noch nicht
--      beendet. Dann wird die Adresse erst nach dem Monat geloescht
--      (und nicht sofort).
--
-- WAS HIER PASSIERT:
--
--   * guardian_email wird optional (NULL ist erlaubt). Sonst
--     koennte die Adresse gar nicht geloescht werden.
--   * email_deleted_at merkt sich, WANN geloescht wurde. Das ist
--     der Nachweis, dass das passiert ist - ohne ihn koennte man
--     nur behaupten, es sei passiert.
--   * Die drei Beendigungswege loeschen die Adresse sofort:
--       - revoke_guardian_consent (Jugendlicher beendet)
--       - revoke_guardian_consent_by_token (Elternteil widerruft)
--       - set_guardian_access_policy('ended') (Zugriff endet sofort)
--   * Die Nachfrist ("noch 1 Monat") loescht NICHT sofort:
--     public.purge_guardian_emails() loescht die Adresse, sobald
--     access_until abgelaufen ist. Der Cron ruft die Funktion taeglich
--     auf.
--   * Der Bestand wird nachgezogen: offene Links werden auf 24
--     Stunden gekuerzt, und bereits beendete Freigaben werden
--     nachgeloescht.
--
-- WICHTIG: Der Elternteil hat bei Thestia KEIN Konto. Die Adresse
-- wird nur gebraucht, um ihm den Link zu schicken und ihm
-- Benachrichtigungen zu schicken. Ist die Freigabe beendet, gibt es
-- beides nicht mehr - dann ist die Adresse ueberfluessig.

BEGIN;

-- =========================================================================
-- 1) Die Adresse wird optional, und der Loeschzeitpunkt wird gemerkt
-- =========================================================================
ALTER TABLE public.guardian_consents
  ALTER COLUMN guardian_email DROP NOT NULL;

ALTER TABLE public.guardian_consents
  ADD COLUMN IF NOT EXISTS email_deleted_at timestamptz;

COMMENT ON COLUMN public.guardian_consents.guardian_email IS
  'Die Adresse des Elternteils. Sie wird mit dem Ende der Freigabe '
  'geloescht (Migration 179). NULL = keine Adresse gespeichert.';
COMMENT ON COLUMN public.guardian_consents.email_deleted_at IS
  'Wann die Adresse des Elternteils geloescht wurde. Der Nachweis, '
  'dass die Freigabe auch ihre Daten zurueckgibt (Migration 179).';

-- =========================================================================
-- 2) Der Link gilt 24 Stunden (nicht 14 Tage)
-- =========================================================================
CREATE OR REPLACE FUNCTION public.request_guardian_consent(
  p_guardian_email text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_email      text := lower(trim(coalesce(p_guardian_email, '')));
  v_own_email  text;
  v_age        int;
  v_token      text;
  v_consent_id uuid;
  v_secret     text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
    RAISE EXCEPTION 'invalid_email';
  END IF;

  -- Massstab ist das VERIFIZIERTE Alter (Migration 155). Die Alters-
  -- angabe im Profil allein genuegt nicht - sonst koennte ein 14-Jaehriger
  -- eine Freigabe fuer 16/17 anlegen.
  v_age := public.guardian_eligible_age(v_uid);
  IF v_age IS NULL OR v_age < 16 OR v_age > 17 THEN
    RAISE EXCEPTION 'not_eligible';
  END IF;

  -- Die Elternadresse muss eine ANDERE sein als die Kontoadresse.
  -- Sonst "bestaetigt" sich der Jugendliche selbst - das waere die
  -- einfachste Art, die ganze Aufsicht zu umgehen.
  SELECT lower(coalesce(u.email, '')) INTO v_own_email
    FROM auth.users u WHERE u.id = v_uid;
  IF v_own_email = '' THEN
    v_own_email := lower(coalesce(auth.jwt() ->> 'email', ''));
  END IF;
  IF v_email <> '' AND v_email = v_own_email THEN
    RAISE EXCEPTION 'same_email';
  END IF;

  -- Rate-Limit: 5 Anfragen pro Stunde und Konto.
  IF NOT public.consume_rate_limit(
       'guardian_consent:' || v_uid::text, 5, 3600) THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  -- Token: 32 Zufallsbytes. Gespeichert wird nur der SHA-256-Hash.
  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  SELECT id INTO v_consent_id
    FROM public.guardian_consents
   WHERE child_user_id = v_uid
     AND status IN ('pending','active')
   ORDER BY requested_at DESC
   LIMIT 1;

  IF v_consent_id IS NULL THEN
    INSERT INTO public.guardian_consents
      (child_user_id, guardian_email, status, token_hash, token_expires_at)
    VALUES
      (v_uid, v_email, 'pending',
       encode(sha256(convert_to(v_token, 'UTF8')), 'hex'),
       now() + interval '24 hours')
    RETURNING id INTO v_consent_id;
  ELSE
    -- Eine bestehende Freigabe wird erneuert: neue Adresse, neuer Token,
    -- zurueck auf "pending" (die alte Bestaetigung gilt fuer die alte
    -- Adresse nicht mehr).
    UPDATE public.guardian_consents
       SET guardian_email   = v_email,
           status           = 'pending',
           token_hash       = encode(sha256(convert_to(v_token, 'UTF8')), 'hex'),
           token_expires_at = now() + interval '24 hours',
           requested_at     = now(),
           confirmed_at     = NULL,
           revoked_at       = NULL,
           revoked_by       = NULL,
           updated_at       = now()
     WHERE id = v_consent_id;
  END IF;

  UPDATE public.profiles
     SET supervised           = true,
         consent_state        = 'pending',
         consent_parent_ref   = v_consent_id,
         consent_revoked_at   = NULL,
         updated_at           = now()
   WHERE user_id = v_uid;

  INSERT INTO public.guardian_consent_audit
    (consent_id, child_user_id, actor, action, detail)
  VALUES
    (v_consent_id, v_uid, 'youth', 'requested',
     jsonb_build_object('domain', split_part(v_email, '@', 2)));

  -- Mail an den Elternteil. Der Klartext-Token geht ueber HTTPS an die
  -- Edge Function ( internes Secret ) und von dort in die Mail. Der
  -- Trigger laeuft asynchron - die Anfrage ist auch dann erfolgreich,
  -- wenn der Versand spaeter scheitert.
  BEGIN
    SELECT decrypted_secret INTO v_secret
      FROM vault.decrypted_secrets
     WHERE name = 'thestia_internal_secret'
     LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;

  IF v_secret IS NOT NULL AND v_secret <> '' THEN
    PERFORM net.http_post(
      url := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/guardian-consent',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-thestia-internal', v_secret
      ),
      body := jsonb_build_object(
        'action',         'send_consent_mail',
        'consentId',      v_consent_id,
        'childUserId',    v_uid,
        'guardianEmail',  v_email,
        'token',          v_token
      )
    );
  ELSE
    RAISE WARNING
      'request_guardian_consent: Secret thestia_internal_secret fehlt - '
      'keine Mail versendet.';
  END IF;

  RETURN jsonb_build_object(
    'consentId',     v_consent_id,
    'status',        'pending',
    'guardianEmail', v_email
  );
END;
$$;

COMMENT ON FUNCTION public.request_guardian_consent(text) IS
  'Der Jugendliche bittet einen Elternteil um die Freigabe. Der Link '
  'im Laufwerk ist 24 Stunden gueltig (vorher 14 Tage, Migration 179).';

-- =========================================================================
-- 3) Beenden loescht die E-Mail-Adresse des Elternteils
-- =========================================================================
CREATE OR REPLACE FUNCTION public.revoke_guardian_consent(
  p_actor text DEFAULT 'youth'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_row        record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_actor NOT IN ('youth','guardian') THEN
    RAISE EXCEPTION 'invalid_actor';
  END IF;

  SELECT * INTO v_row
    FROM public.guardian_consents
   WHERE child_user_id = v_uid
     AND status IN ('pending','active')
   ORDER BY requested_at DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'changed', false);
  END IF;

  UPDATE public.guardian_consents
     SET status     = 'revoked',
         revoked_at = now(),
         revoked_by = p_actor,
         -- NUTZERWUNSCH 04.11.2026: Mit dem Ende der Freigabe wird
         -- auch die E-Mail-Adresse des Elternteils geloescht. Sie wird
         -- fuer nichts mehr gebraucht - und das Ende der Freigabe
         -- heisst: keine Daten des Elternteils mehr aufbewahren.
         guardian_email  = NULL,
         email_deleted_at = now(),
         updated_at = now()
   WHERE id = v_row.id;

  UPDATE public.profiles
     SET supervised         = false,
         consent_state      = 'revoked',
         consent_revoked_at = now(),
         updated_at         = now()
   WHERE user_id = v_uid;

  INSERT INTO public.guardian_consent_audit
    (consent_id, child_user_id, actor, action, detail)
  VALUES
    (v_row.id, v_uid, p_actor, 'revoked', '{}'::jsonb);

  RETURN jsonb_build_object('ok', true, 'changed', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_guardian_consent_by_token(
  p_token text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row record;
BEGIN
  IF p_token IS NULL OR length(p_token) < 16 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  -- BEFUND 04.11.2026: Die Ablaufpruefung fehlte hier (die anderen
  -- drei Portal-Funktionen haben sie seit Migration 165/166).
  SELECT * INTO v_row
    FROM public.guardian_consents
   WHERE token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
     AND status IN ('pending','active')
     AND token_expires_at > now()
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  UPDATE public.guardian_consents
     SET status     = 'revoked',
         revoked_at = now(),
         revoked_by = 'guardian',
         -- NUTZERWUNSCH 04.11.2026: Auch beim Widerruf durch den
         -- Elternteil wird die E-Mail-Adresse geloescht. Die Freigabe
         -- ist damit beendet - es gibt keinen Grund, sie weiter
         -- aufzubewahren.
         guardian_email  = NULL,
         email_deleted_at = now(),
         updated_at = now()
   WHERE id = v_row.id;

  UPDATE public.profiles
     SET supervised         = false,
         consent_state      = 'revoked',
         consent_revoked_at = now(),
         updated_at         = now()
   WHERE user_id = v_row.child_user_id;

  INSERT INTO public.guardian_consent_audit
    (consent_id, child_user_id, actor, action, detail)
  VALUES
    (v_row.id, v_row.child_user_id, 'guardian', 'revoked',
     jsonb_build_object('via', 'token'));

  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_guardian_access_policy(
  p_policy       text,
  p_grace_months int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_row        record;
  v_birth      date;
  v_until      timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_policy NOT IN ('ended','grace','indefinite') THEN
    RAISE EXCEPTION 'invalid_policy';
  END IF;

  IF p_policy = 'grace'
     AND (p_grace_months IS NULL OR p_grace_months < 1 OR p_grace_months > 6) THEN
    RAISE EXCEPTION 'invalid_grace';
  END IF;

  SELECT * INTO v_row
    FROM public.guardian_consents
   WHERE child_user_id = v_uid
     AND status IN ('pending','active')
   ORDER BY requested_at DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_consent');
  END IF;

  SELECT birth_date INTO v_birth FROM public.profiles WHERE user_id = v_uid;

  IF p_policy = 'ended' THEN
    UPDATE public.guardian_consents
       SET status       = 'revoked',
           access_policy= 'ended',
           access_until = NULL,
           revoked_at   = now(),
           revoked_by   = 'youth',
           -- NUTZERWUNSCH 04.11.2026: Der Zugriff endet sofort, also
           -- endet auch die Freigabe - und damit die E-Mail-Adresse
           -- des Elternteils. Sie wird mitgeloescht.
           guardian_email  = NULL,
           email_deleted_at = now(),
           updated_at   = now()
     WHERE id = v_row.id;

    UPDATE public.profiles
       SET supervised         = false,
           consent_state      = 'revoked',
           consent_revoked_at = now(),
           guardian_transition_done = true,
           updated_at         = now()
     WHERE user_id = v_uid;

  ELSIF p_policy = 'grace' THEN
    -- Der Zugriff endet X Monate NACH dem 18. Geburtstag. Ist der
    -- Geburtstag bereits vorbei (der Screen erscheint ja erst mit 18),
    -- zaehlt die Frist ab jetzt.
    IF v_birth IS NOT NULL THEN
      v_until := (v_birth + interval '18 years') + (p_grace_months || ' months')::interval;
      IF v_until <= now() THEN
        v_until := now() + (p_grace_months || ' months')::interval;
      END IF;
    ELSE
      v_until := now() + (p_grace_months || ' months')::interval;
    END IF;

    -- NUTZERWUNSCH 04.11.2026: Bei einer Nachfrist ("noch 1 Monat
    -- behalten") endet die Freigabe NICHT sofort. Deshalb bleibt die
    -- E-Mail-Adresse des Elternteils zuerst stehen - sie wird erst
    -- geloescht, wenn die Nachfrist abgelaufen ist. Das erledigt
    -- public.purge_guardian_emails() (Cron, taeglich).
    UPDATE public.guardian_consents
       SET access_policy = 'grace',
           grace_months  = p_grace_months,
           access_until  = v_until,
           updated_at    = now()
     WHERE id = v_row.id;

    UPDATE public.profiles
       SET guardian_transition_done = true,
           updated_at         = now()
     WHERE user_id = v_uid;

  ELSE
    UPDATE public.guardian_consents
       SET access_policy = 'indefinite',
           access_until  = NULL,
           updated_at    = now()
     WHERE id = v_row.id;

    UPDATE public.profiles
       SET guardian_transition_done = true,
           updated_at         = now()
     WHERE user_id = v_uid;
  END IF;

  INSERT INTO public.guardian_consent_audit
    (consent_id, child_user_id, actor, action, detail)
  VALUES
    (v_row.id, v_uid, 'youth', 'access_policy',
     jsonb_build_object('policy', p_policy, 'graceMonths', p_grace_months));

  RETURN jsonb_build_object('ok', true, 'policy', p_policy,
                            'accessUntil', v_until);
END;
$$;

COMMENT ON FUNCTION public.revoke_guardian_consent(text) IS
  'Beendet die elterliche Freigabe. Loescht dabei auch die '
  'E-Mail-Adresse des Elternteils (Migration 179).';

COMMENT ON FUNCTION public.revoke_guardian_consent_by_token(text) IS
  'Der Elternteil widerruft die Freigabe ueber sein Token. Loescht '
  'dabei auch die E-Mail-Adresse des Elternteils (Migration 179).';

COMMENT ON FUNCTION public.set_guardian_access_policy(text, int) IS
  'Die Entscheidung mit 18: ended (sofort), grace (Nachfrist) oder '
  'indefinite. Bei "ended" wird die E-Mail-Adresse des Elternteils '
  'geloescht, bei "grace" erst nach Ablauf der Nachfrist '
  '(Migration 179).';

-- =========================================================================
-- 4) Die Nachfrist: die E-Mail bleibt bis zum Ende der Frist
-- =========================================================================
--
-- Der Jugendliche kann "noch 1 Monat behalten" waehlen. Dann endet
-- die Freigabe erst nach diesem Monat - und die E-Mail-Adresse des
-- Elternteils wird erst dann geloescht, nicht sofort.
--
-- Die Funktion macht beides:
--   * die Nachfrist ist abgelaufen -> die Freigabe endet (Status
--     "expired") und die Adresse wird geloescht
--   * die Freigabe ist beendet (revoked) -> die Adresse wird geloescht
--
-- Sie ist idempotent: ein zweiter Aufruf loescht nichts mehr.
CREATE OR REPLACE FUNCTION public.purge_guardian_emails()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer := 0;
  v_ended integer := 0;
BEGIN
  -- (1) Die Nachfrist ist abgelaufen: die Freigabe endet JETZT.
  UPDATE public.guardian_consents
     SET status          = 'expired',
         access_policy   = 'ended',
         guardian_email  = NULL,
         email_deleted_at = now(),
         updated_at      = now()
   WHERE status IN ('pending','active')
     AND access_until IS NOT NULL
     AND access_until <= now();
  GET DIAGNOSTICS v_ended = ROW_COUNT;

  -- Die Profile muss mitziehen, sonst behauptet die App weiter, das
  -- Konto sei beaufsichtigt.
  UPDATE public.profiles p
     SET supervised       = false,
         consent_state    = 'expired',
         updated_at       = now()
    FROM public.guardian_consents c
   WHERE c.child_user_id = p.user_id
     AND c.status = 'expired'
     AND c.access_until IS NOT NULL
     AND c.access_until <= now()
     AND p.supervised;

  -- (2) Beendete Freigaben: die Adresse wird geloescht. Das ist der
  --     Nachlauf fuer die Wege, die den Status direkt setzen
  --     (Widerruf durch den Elternteil, "ended" durch den
  --     Jugendlichen) - und fuer Bestandsdaten aus alten
  --     Migrationen.
  UPDATE public.guardian_consents
     SET guardian_email  = NULL,
         email_deleted_at = now(),
         updated_at      = now()
   WHERE guardian_email IS NOT NULL
     AND status IN ('revoked','expired')
     AND (access_until IS NULL OR access_until <= now());
  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN v_ended + v_count;
END;
$$;

COMMENT ON FUNCTION public.purge_guardian_emails() IS
  'Loescht die E-Mail-Adresse des Elternteils, wenn die Freigabe '
  'beendet ist - und beendet die Freigabe, wenn die Nachfrist '
  'abgelaufen ist (Migration 179).';

REVOKE ALL ON FUNCTION public.purge_guardian_emails()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_guardian_emails() TO service_role;

-- =========================================================================
-- 5) Der Cron: taeglich nachsehen, ob eine Nachfrist abgelaufen ist
-- =========================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'guardian-email-purge') THEN
      PERFORM cron.unschedule('guardian-email-purge');
    END IF;
    PERFORM cron.schedule(
      'guardian-email-purge', '30 3 * * *',
      $cron$ SELECT public.purge_guardian_emails(); $cron$
    );
  ELSE
    RAISE WARNING
      'guardian-email-purge-Cron konnte nicht eingerichtet werden '
      '(pg_cron fehlt) - best-effort, wie bei den uebrigen Cleanups.';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING
    'guardian-email-purge-Cron konnte nicht eingerichtet werden '
    '(best-effort): %', SQLERRM;
END;
$$;

-- =========================================================================
-- 6) Der Bestand wird nachgezogen
-- =========================================================================

-- Offene Links: die noch laufenden 14 Tage werden auf 24 Stunden
-- gekuerzt. Sonst waere der alte Link weiterhin gueltig.
UPDATE public.guardian_consents
   SET token_expires_at = least(token_expires_at, now() + interval '24 hours')
 WHERE status = 'pending'
   AND token_expires_at > now() + interval '24 hours';

-- Beendete Freigaben: die Adresse wird jetzt geloescht.
UPDATE public.guardian_consents
   SET guardian_email  = NULL,
       email_deleted_at = now(),
       updated_at      = now()
 WHERE guardian_email IS NOT NULL
   AND status IN ('revoked','expired')
   AND (access_until IS NULL OR access_until <= now());

COMMIT;
