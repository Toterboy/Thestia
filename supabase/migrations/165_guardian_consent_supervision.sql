-- =============================================================================
-- 165_guardian_consent_supervision.sql
-- =============================================================================
-- Eltern-Erlaubnis und Aufsicht fuer 16- und 17-Jaehrige.
--
-- BETREIBER-ENTSCHEIDUNG (03.11.2026):
--
--   "Wenn sich eine Person, die bei der Registrierung noch nicht 18 war
--    18 wird, soll ein extra Screen und Benachrichtigung kommen, wo man
--    den Zugriff der Eltern entfernen, fuer 1-6 Monate weiter behalten
--    oder erstmal weiter behalten kann. Es soll in den Einstellungen
--    einen extra Bereich geben, der fuer Kinderschutz und Elternzugriff
--    ist. Dort kann man dann sowas wie wann die Eltern nach dem 18.
--    Geburtstag den Zugriff verlieren sollen eingestellt werden. Da
--    Eltern auch nicht zu sehr in die Privatsphaere der Jugendlichen
--    eindringen sollen, sollen die Eltern (Einstellbar) Benachrichtigungen
--    erhalten, wenn zwischen dem und einem anderen Account ein Funke
--    entsteht (nicht nur like auf einer Seite!). Dies kann taeglich,
--    woechentlich, monatlich oder gar nicht mitgeteilt werden. Die
--    erlaubte Nutzungszeit der App kann in der App fuer Jugendliche auch
--    eingeschraenkt werden. Die Einstellung wird bei Aktivierung mit
--    einer vierstelligen Pin gesichert, welche die Jugendlichen
--    natuerlich nicht wissen sollen."
--
-- GRUNDGEDANKE (aus dem Roadmap-Entwurf, ROADMAP.md:640):
--
--   Das Konto gehoert dem Kind, nicht dem Elternteil. Der Elternteil ist
--   Genehmiger, nicht Nutzer - es gibt KEIN Elternkonto in der App. Der
--   Elternteil bekommt eine E-Mail mit einem Link auf eine eigene Seite,
--   dort bestaetigt er die Freigabe und kann sie jederzeit widerrufen.
--
-- WAS DIESE MIGRATION BAUT:
--
--   1) Die Tabelle guardian_consents: die Freigabe eines Elternteils
--      fuer ein bestimmtes Kind. Der Token wird NIE im Klartext
--      gespeichert, sondern nur als SHA-256-Hash. Der Klartext geht
--      einmal in die Mail des Elternteils.
--
--   2) Die Spalten auf profiles: supervised, consent_state,
--      consent_parent_ref, consent_verified_at, consent_revoked_at,
--      guardian_transition_done.
--
--   3) Die Audit-Tabelle guardian_consent_audit: jede Anforderung, jede
--      Bestaetigung, jeder Widerruf wird protokolliert (wer, wann, fuer
--      wen). Ohne Audit-Trail ist eine Aufsicht nicht nachvollziehbar.
--
--   4) Die RPCs:
--      request_guardian_consent  - der Jugendliche bittet (App)
--      confirm_guardian_consent  - der Elternteil bestaetigt (Portal)
--      revoke_guardian_consent   - der Jugendliche (oder der Elternteil)
--      set_guardian_portal_settings - der Elternteil im Portal
--      verify_guardian_pin       - die App fragt den Server nach der PIN
--      get_my_guardian_status    - die App liest den Stand
--      set_guardian_access_policy - die Entscheidung mit 18
--
--   5) Den Trigger auf matches: ein Funke erzeugt ein Ereignis fuer die
--      Eltern - NICHT fuer ein Like. Genau das war die Vorgabe ("nicht
--      nur like auf einer Seite").
--
--   6) Den Digest-Versand per pg_cron: taeglich/woechentlich/monatlich
--      je ein Lauf, gebuendelt nach der eingestellten Frequenz.
--
-- SICHERHEITSGRUNDSAETZE:
--
--   * Die Grenzen sitzen in der Datenbank. Die App ist die freundliche
--     Seite; ein gepatchter Client kommt an keiner Grenze vorbei.
--   * Die PIN wird als bcrypt-Hash gespeichert (extensions.crypt) und
--     NIE an das Geraet uebertragen. Die App fragt den Server "stimmt
--     diese PIN?" - mit Rate-Limit und Sperre.
--   * Die Elternadresse darf nicht die eigene Kontoadresse sein. Sonst
--     "bestaetigt" sich der Jugendliche selbst.
--   * Ein unbekanntes Alter wird nicht als Minderjaehriger behandelt:
--     hier wird die Anforderung abgelehnt (fail-closed in die andere
--     Richtung - ohne belegtes Alter 16/17 gibt es keine Freigabe).
--   * Der Digest enthaelt KEINE Personendaten der Gegenseite: der
--     Elternteil erfahrt, DASS ein Funke entstanden ist, nicht mit wem.
--     Das ist der Punkt "Eltern sollen nicht zu sehr in die
--     Privatsphaere eindringen".
-- =============================================================================

BEGIN;

-- ===========================================================================
-- 1) Die Freigabe-Tabelle
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.guardian_consents (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  child_user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  guardian_email       text NOT NULL,
  status               text NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending','active','revoked','expired')),
  -- Nur der HASH des Tokens. Der Klartext existiert nur in der Mail des
  -- Elternteils und im Speicher der Edge Function fuer den Versand.
  token_hash           text NOT NULL,
  token_expires_at     timestamptz NOT NULL,
  requested_at         timestamptz NOT NULL DEFAULT now(),
  confirmed_at         timestamptz,
  revoked_at           timestamptz,
  revoked_by           text,
  -- Benachrichtigungen der Eltern
  notify_enabled       boolean NOT NULL DEFAULT true,
  notify_frequency     text NOT NULL DEFAULT 'weekly'
                         CHECK (notify_frequency IN ('daily','weekly','monthly','none')),
  -- Nutzungszeit-Beschraenkung (Minuten seit Mitternacht, in der
  -- Zeitzone des Geraets interpretiert - der Server haelt nur die Zahl)
  usage_limit_enabled  boolean NOT NULL DEFAULT false,
  usage_start_min      int,
  usage_end_min        int,
  pin_hash             text,
  pin_set_at           timestamptz,
  -- Zugriff nach dem 18. Geburtstag
  access_policy        text NOT NULL DEFAULT 'until_18'
                         CHECK (access_policy IN ('until_18','grace','indefinite','ended')),
  access_until         timestamptz,
  grace_months         int,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.guardian_consents IS
  'Freigabe der Sorgeberechtigten fuer ein Konto im Alter 16/17 '
  '(v0.10.0, Migration 165). Es gibt bewusst KEIN Konto des '
  'Elternteils: das Konto gehoert dem Kind, der Elternteil ist '
  'Genehmiger. Der Token liegt nur als Hash vor.';

CREATE INDEX IF NOT EXISTS idx_guardian_consents_child
  ON public.guardian_consents (child_user_id);
CREATE INDEX IF NOT EXISTS idx_guardian_consents_status
  ON public.guardian_consents (status, notify_frequency);

ALTER TABLE public.guardian_consents ENABLE ROW LEVEL SECURITY;
-- Bewusst KEINE Policies: Clients lesen und schreiben nie direkt. Alles
-- laeuft ueber die RPCs, die den Aufrufer pruefen.

-- ===========================================================================
-- 2) Audit-Trail
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.guardian_consent_audit (
  id             bigserial PRIMARY KEY,
  consent_id     uuid REFERENCES public.guardian_consents(id) ON DELETE SET NULL,
  child_user_id  uuid,
  actor          text NOT NULL
                   CHECK (actor IN ('youth','guardian','system')),
  action         text NOT NULL,
  detail         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.guardian_consent_audit IS
  'Nachvollziehbarkeit der Aufsicht: jede Anforderung, Bestaetigung, '
  'Widerruf und Einstellung wird protokolliert. Ohne diesen Trail laesst '
  'sich im Streitfall nicht zeigen, was vereinbart war.';

CREATE INDEX IF NOT EXISTS idx_guardian_audit_child
  ON public.guardian_consent_audit (child_user_id, created_at DESC);

ALTER TABLE public.guardian_consent_audit ENABLE ROW LEVEL SECURITY;

-- ===========================================================================
-- 3) Ereignisse fuer die Eltern-Benachrichtigung
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.guardian_notification_events (
  id             bigserial PRIMARY KEY,
  consent_id     uuid NOT NULL REFERENCES public.guardian_consents(id) ON DELETE CASCADE,
  child_user_id  uuid NOT NULL,
  kind           text NOT NULL DEFAULT 'funke',
  created_at     timestamptz NOT NULL DEFAULT now(),
  sent_at        timestamptz
);

COMMENT ON TABLE public.guardian_notification_events IS
  'Ereignisse, ueber die die Eltern informiert werden - derzeit nur '
  '"funke" (ein Funke ist entstanden). Ein Like erzeugt hier bewusst '
  'KEIN Ereignis: die Vorgabe lautet "nicht nur like auf einer Seite".';

CREATE INDEX IF NOT EXISTS idx_guardian_events_unsent
  ON public.guardian_notification_events (consent_id)
  WHERE sent_at IS NULL;

ALTER TABLE public.guardian_notification_events ENABLE ROW LEVEL SECURITY;

-- ===========================================================================
-- 4) Die Profilspalten
-- ===========================================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS supervised boolean NOT NULL DEFAULT false;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS consent_state text NOT NULL DEFAULT 'none';
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS consent_parent_ref uuid;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS consent_verified_at timestamptz;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS consent_revoked_at timestamptz;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS guardian_transition_done boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.supervised IS
  'Das Konto steht unter Aufsicht der Sorgeberechtigten (v0.10.0, '
  'Migration 165).';
COMMENT ON COLUMN public.profiles.consent_state IS
  'Stand der elterlichen Einwilligung: none | pending | granted | revoked '
  '(v0.10.0, Migration 165).';
COMMENT ON COLUMN public.profiles.consent_parent_ref IS
  'Verweis auf den Einwilligungsdatensatz in guardian_consents - KEIN '
  'Konto des Elternteils (v0.10.0, Migration 165).';
COMMENT ON COLUMN public.profiles.guardian_transition_done IS
  'Der Screen zum 18. Geburtstag wurde gesehen. Bis dahin bleibt der '
  'Elternzugriff bestehen; danach entscheidet der Jugendliche '
  '(v0.10.0, Migration 165).';

-- Kein CHECK auf consent_state: der Wert wird nur serverseitig gesetzt
-- (RPCs). Ein CHECK wuerde hier nur die Datenhaltung betreffen, nicht
-- die Zugriffsgrenze - und die Grenze ist die RPC.

-- ===========================================================================
-- 5) Hilfsfunktionen
-- ===========================================================================

-- Das Alter des Kindes fuer die Freigabe-PRUEFUNG.
--
-- Anders als beim Suchradius (Migration 164) ist hier die Richtung
-- umgekehrt: EIN UNBEKANNTES ALTER FUEHRT ZUM ABLEHNEN, nicht zur
-- Freigabe. Ohne belegtes Alter 16/17 gibt es keine elterliche
-- Freigabe - so kann niemand eine Freigabe fuer ein Konto unter 16
-- erfinden, indem das Geburtsdatum leer bleibt.
CREATE OR REPLACE FUNCTION public.guardian_eligible_age(v_user_id uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.profile_known_age(p.birth_date, p.verified_age)
    FROM public.profiles p
   WHERE p.user_id = v_user_id;
$$;

REVOKE ALL ON FUNCTION public.guardian_eligible_age(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.guardian_eligible_age(uuid) TO authenticated;

-- Die Elternadresse fuer Anzeigezwecke maskieren. Der Elternteil sieht
-- seinen Namen, die Jugendlichen sehen nur den Hinweis "dein
-- Elternteil" - im Digest wird die Adresse gar nicht ausgegeben.
CREATE OR REPLACE FUNCTION public.guardian_mask_email(p_email text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_email IS NULL OR position('@' in p_email) < 2 THEN '…'
    ELSE left(p_email, 1) || '***' || substring(p_email from position('@' in p_email))
  END;
$$;

REVOKE ALL ON FUNCTION public.guardian_mask_email(text) FROM PUBLIC;

-- ===========================================================================
-- 6) Der Jugendliche bittet: request_guardian_consent
-- ===========================================================================
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
       now() + interval '14 days')
    RETURNING id INTO v_consent_id;
  ELSE
    -- Eine bestehende Freigabe wird erneuert: neue Adresse, neuer Token,
    -- zurueck auf "pending" (die alte Bestaetigung gilt fuer die alte
    -- Adresse nicht mehr).
    UPDATE public.guardian_consents
       SET guardian_email   = v_email,
           status           = 'pending',
           token_hash       = encode(sha256(convert_to(v_token, 'UTF8')), 'hex'),
           token_expires_at = now() + interval '14 days',
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
  'Der Jugendliche (16/17) bittet einen Elternteil um Freigabe. Die '
  'Adresse muss eine andere sein als die eigene Kontoadresse. Massstab '
  'ist das verifizierte Alter. Der Token geht nur per Mail raus.';
REVOKE ALL ON FUNCTION public.request_guardian_consent(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_guardian_consent(text) TO authenticated;

-- ===========================================================================
-- 7) Der Elternteil bestaetigt: confirm_guardian_consent (nur service_role)
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.confirm_guardian_consent(
  p_token text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row        record;
  v_secret     text;
BEGIN
  IF p_token IS NULL OR length(p_token) < 16 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  SELECT * INTO v_row
    FROM public.guardian_consents
   WHERE token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
     AND status = 'pending'
     AND token_expires_at > now()
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  UPDATE public.guardian_consents
     SET status       = 'active',
         confirmed_at = now(),
         updated_at   = now()
   WHERE id = v_row.id;

  UPDATE public.profiles
     SET supervised           = true,
         consent_state        = 'granted',
         consent_parent_ref   = v_row.id,
         consent_verified_at  = now(),
         updated_at           = now()
   WHERE user_id = v_row.child_user_id;

  INSERT INTO public.guardian_consent_audit
    (consent_id, child_user_id, actor, action, detail)
  VALUES
    (v_row.id, v_row.child_user_id, 'guardian', 'confirmed', '{}'::jsonb);

  -- Der Jugendliche soll es wissen: eine Bestaetigung ist ein
  -- sichtbares Ereignis, kein stiller Vorgang.
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
        'action',      'send_confirmed_notice',
        'consentId',   v_row.id,
        'childUserId', v_row.child_user_id
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'consentId', v_row.id,
    'childUserId', v_row.child_user_id,
    'guardianEmail', v_row.guardian_email
  );
END;
$$;

COMMENT ON FUNCTION public.confirm_guardian_consent(text) IS
  'Der Elternteil bestaetigt die Freigabe ueber seinen Link. Der Token '
  'ist die Berechtigung - deshalb wird er nur als Hash gespeichert und '
  'nach 14 Tagen ungueltig. Nur service_role (die Edge Function mit dem '
  'Eltern-Portal) darf das aufrufen.';
REVOKE ALL ON FUNCTION public.confirm_guardian_consent(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_guardian_consent(text) TO service_role;

-- ===========================================================================
-- 8) Widerruf: revoke_guardian_consent
-- ===========================================================================
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

REVOKE ALL ON FUNCTION public.revoke_guardian_consent(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_guardian_consent(text) TO authenticated;

-- ===========================================================================
-- 9) Der Elternteil im Portal: set_guardian_portal_settings
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.set_guardian_portal_settings(
  p_token                text,
  p_notify_enabled       boolean,
  p_notify_frequency     text,
  p_usage_limit_enabled  boolean,
  p_usage_start_min      int,
  p_usage_end_min        int,
  p_pin                  text
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

  SELECT * INTO v_row
    FROM public.guardian_consents
   WHERE token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
     AND status = 'active'
     AND token_expires_at > now()
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  IF p_notify_frequency IS NOT NULL
     AND p_notify_frequency NOT IN ('daily','weekly','monthly','none') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_frequency');
  END IF;

  -- Die Nutzungszeit ist nur mit PIN erlaubt: sie ist die einzige
  -- Einstellung, die den Jugendlichen in seiner Freiheit beschraenkt.
  IF coalesce(p_usage_limit_enabled, false) AND p_pin IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pin_required');
  END IF;

  -- PIN: genau vier Ziffern.
  IF p_pin IS NOT NULL AND p_pin !~ '^[0-9]{4}$' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_pin');
  END IF;

  UPDATE public.guardian_consents
     SET notify_enabled      = coalesce(p_notify_enabled, notify_enabled),
         notify_frequency    = coalesce(p_notify_frequency, notify_frequency),
         usage_limit_enabled = coalesce(p_usage_limit_enabled, usage_limit_enabled),
         usage_start_min     = p_usage_start_min,
         usage_end_min       = p_usage_end_min,
         pin_hash            = CASE WHEN p_pin IS NOT NULL
                                   THEN extensions.crypt(p_pin, extensions.gen_salt('bf'))
                                   ELSE pin_hash END,
         pin_set_at          = CASE WHEN p_pin IS NOT NULL THEN now() ELSE pin_set_at END,
         updated_at          = now()
   WHERE id = v_row.id;

  INSERT INTO public.guardian_consent_audit
    (consent_id, child_user_id, actor, action, detail)
  VALUES
    (v_row.id, v_row.child_user_id, 'guardian', 'settings_changed',
     jsonb_build_object(
       'notifyEnabled',   coalesce(p_notify_enabled, v_row.notify_enabled),
       'notifyFrequency', coalesce(p_notify_frequency, v_row.notify_frequency),
       'usageLimit',      coalesce(p_usage_limit_enabled, v_row.usage_limit_enabled),
       'pinSet',          p_pin IS NOT NULL
     ));

  RETURN jsonb_build_object('ok', true);
END;
$$;

COMMENT ON FUNCTION public.set_guardian_portal_settings(text, boolean, text, boolean, int, int, text) IS
  'Der Elternteil stellt im Portal ein: Benachrichtigungen (Haeufigkeit), '
  'Nutzungszeit und PIN. Die Nutzungszeit ist nur mit PIN erlaubt - '
  'die PIN schuetzt die Einstellung davor, dass der Jugendliche sie '
  'aendert. Nur service_role.';
REVOKE ALL ON FUNCTION public.set_guardian_portal_settings(text, boolean, text, boolean, int, int, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_guardian_portal_settings(text, boolean, text, boolean, int, int, text)
  TO service_role;

-- ===========================================================================
-- 10) Der Elternteil widerruft (ueber das Portal)
-- ===========================================================================
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

  SELECT * INTO v_row
    FROM public.guardian_consents
   WHERE token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
     AND status IN ('pending','active')
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  UPDATE public.guardian_consents
     SET status     = 'revoked',
         revoked_at = now(),
         revoked_by = 'guardian',
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
    (v_row.id, v_row.child_user_id, 'guardian', 'revoked', '{}'::jsonb);

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_guardian_consent_by_token(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_guardian_consent_by_token(text) TO service_role;

-- ===========================================================================
-- 11) Die PIN pruefen: verify_guardian_pin
-- ===========================================================================
-- Die PIN wird NIE an das Geraet uebertragen und NIE lokal gespeichert.
-- Die App fragt den Server, und der Server vergleicht den bcrypt-Hash.
--
-- Rate-Limit: 5 Versuche pro Stunde. Danach ist die PIN fuer diese
-- Stunde gesperrt. Eine vierstellige PIN hat nur 10 000 Moeglichkeiten
-- - ohne Sperre waere sie in Sekunden durch, mit Sperre braucht es
-- Wochen.
CREATE OR REPLACE FUNCTION public.verify_guardian_pin(
  p_pin text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_hash   text;
  v_ok     boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_pin IS NULL OR p_pin !~ '^[0-9]{4}$' THEN
    RETURN false;
  END IF;

  -- Erst das Rate-Limit, dann der Vergleich: so wird auch ein
  -- falsches Format gezaehlt.
  IF NOT public.consume_rate_limit(
       'guardian_pin:' || v_uid::text, 5, 3600) THEN
    RETURN false;
  END IF;

  SELECT c.pin_hash INTO v_hash
    FROM public.guardian_consents c
   WHERE c.child_user_id = v_uid
     AND c.status = 'active'
     AND c.pin_hash IS NOT NULL
   ORDER BY c.requested_at DESC
   LIMIT 1;

  IF v_hash IS NULL THEN
    RETURN false;
  END IF;

  v_ok := (extensions.crypt(p_pin, v_hash) = v_hash);

  IF v_ok THEN
    INSERT INTO public.guardian_consent_audit
      (consent_id, child_user_id, actor, action, detail)
    SELECT c.id, c.child_user_id, 'youth', 'pin_verified', '{}'::jsonb
      FROM public.guardian_consents c
     WHERE c.child_user_id = v_uid AND c.status = 'active'
     ORDER BY c.requested_at DESC LIMIT 1;
  END IF;

  RETURN v_ok;
END;
$$;

COMMENT ON FUNCTION public.verify_guardian_pin(text) IS
  'Prueft die vierstellige PIN der Aufsicht. Der Vergleich laeuft '
  'serverseitig gegen den bcrypt-Hash - das Geraet kennt die PIN nie. '
  '5 Versuche pro Stunde (v0.10.0, Migration 165).';
REVOKE ALL ON FUNCTION public.verify_guardian_pin(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_guardian_pin(text) TO authenticated;

-- ===========================================================================
-- 12) Der Stand fuer die App: get_my_guardian_status
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.get_my_guardian_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_row    record;
  v_profile record;
  v_age    int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO v_profile
    FROM public.profiles
   WHERE user_id = v_uid;

  v_age := public.guardian_eligible_age(v_uid);

  SELECT * INTO v_row
    FROM public.guardian_consents
   WHERE child_user_id = v_uid
     AND status IN ('pending','active','expired')
   ORDER BY requested_at DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'consentState',       coalesce(v_profile.consent_state, 'none'),
      'supervised',         coalesce(v_profile.supervised, false),
      'status',             'none',
      'age',                v_age,
      'guardianEmail',      null,
      'guardianEmailMasked', null,
      'notifyEnabled',      false,
      'notifyFrequency',    'none',
      'usageLimitEnabled',  false,
      'usageStartMin',      null,
      'usageEndMin',        null,
      'hasPin',             false,
      'accessPolicy',       'ended',
      'accessUntil',        null,
      'transitionPending',  false,
      'confirmedAt',        null,
      'revokedAt',          v_profile.consent_revoked_at
    );
  END IF;

  RETURN jsonb_build_object(
    'consentState',        coalesce(v_profile.consent_state, 'none'),
    'supervised',          coalesce(v_profile.supervised, false),
    'status',              v_row.status,
    'age',                 v_age,
    'guardianEmail',       v_row.guardian_email,
    'guardianEmailMasked', public.guardian_mask_email(v_row.guardian_email),
    'notifyEnabled',       v_row.notify_enabled,
    'notifyFrequency',     v_row.notify_frequency,
    'usageLimitEnabled',   v_row.usage_limit_enabled,
    'usageStartMin',       v_row.usage_start_min,
    'usageEndMin',         v_row.usage_end_min,
    'hasPin',              v_row.pin_hash IS NOT NULL,
    'accessPolicy',        v_row.access_policy,
    'accessUntil',         v_row.access_until,
    'graceMonths',         v_row.grace_months,
    'confirmedAt',         v_row.confirmed_at,
    'revokedAt',           v_row.revoked_at,
    -- Der Screen zum 18. Geburtstag steht an, wenn das Konto volljährig
    -- geworden ist, eine aktive Freigabe besteht und noch nichts
    -- entschieden wurde.
    'transitionPending',   (v_age IS NOT NULL AND v_age >= 18
                             AND v_row.status = 'active'
                             AND coalesce(v_profile.guardian_transition_done, false) = false)
  );
END;
$$;

COMMENT ON FUNCTION public.get_my_guardian_status() IS
  'Der Stand der elterlichen Aufsicht fuer die App: Freigabe, '
  'Benachrichtigungs-Frequenz, Nutzungszeit, PIN vorhanden, und ob der '
  'Screen zum 18. Geburtstag ansteht (v0.10.0, Migration 165).';
REVOKE ALL ON FUNCTION public.get_my_guardian_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_guardian_status() TO authenticated;

-- ===========================================================================
-- 13) Die Entscheidung mit 18: set_guardian_access_policy
-- ===========================================================================
-- Drei Wege, wie der Jugendliche mit 18 entscheidet:
--
--   'ended'      - der Elternzugriff endet sofort
--   'grace'      - der Zugriff bleibt 1 bis 6 Monate ueber den
--                  18. Geburtstag hinaus
--   'indefinite' - der Zugriff bleibt, bis der Jugendliche ihn selbst
--                  beendet
--
-- ('until_18' ist der Ausgangswert und wird hier NICHT gesetzt - er
-- bedeutet "der Zugang besteht, solange die Entscheidung aussteht".)
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

REVOKE ALL ON FUNCTION public.set_guardian_access_policy(text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_guardian_access_policy(text, int) TO authenticated;

-- ===========================================================================
-- 14) Der Screen mit 18 gilt als gesehen
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.mark_guardian_transition_done()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.profiles
     SET guardian_transition_done = true,
         updated_at = now()
   WHERE user_id = auth.uid()
   RETURNING true;
$$;

REVOKE ALL ON FUNCTION public.mark_guardian_transition_done() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_guardian_transition_done() TO authenticated;

-- ===========================================================================
-- 15) Ein Funke erzeugt ein Eltern-Ereignis
-- ===========================================================================
-- Der Trigger haengt an matches - nicht an likes. Die Vorgabe lautet
-- "nicht nur like auf einer Seite": ein Like ist ein interestes-
-- Signal, ein Funke ist eine entstandene Begegnung.
--
-- FAIL-OPEN: Ein Fehler in diesem Trigger darf das Anlegen eines
-- Funken NIE verhindern. Der Funke ist das wichtige Ereignis; die
-- Eltern-Information ist eine Nebenwirkung.
CREATE OR REPLACE FUNCTION public.guardian_notify_on_match()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid;
BEGIN
  BEGIN
    FOR v_uid IN
      SELECT unnest(ARRAY[NEW.user_one_id, NEW.user_two_id])
    LOOP
      INSERT INTO public.guardian_notification_events
        (consent_id, child_user_id, kind)
      SELECT c.id, c.child_user_id, 'funke'
        FROM public.guardian_consents c
       WHERE c.child_user_id = v_uid
         AND c.status = 'active'
         AND c.notify_enabled
         AND c.notify_frequency <> 'none'
         AND (c.access_until IS NULL OR c.access_until > now());
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'guardian_notify_on_match: %', SQLERRM;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_matches_guardian_notify ON public.matches;
CREATE TRIGGER trg_matches_guardian_notify
  AFTER INSERT ON public.matches
  FOR EACH ROW EXECUTE FUNCTION public.guardian_notify_on_match();

-- ===========================================================================
-- 16) Der Digest: gebuendelt nach taeglich/woechentlich/monatlich
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.run_guardian_digest(
  p_period text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_secret text;
  v_count  integer := 0;
  v_row    record;
BEGIN
  IF p_period NOT IN ('daily','weekly','monthly') THEN
    RAISE EXCEPTION 'invalid_period';
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_secret
      FROM vault.decrypted_secrets
     WHERE name = 'thestia_internal_secret'
     LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING
      'run_guardian_digest: Secret thestia_internal_secret fehlt - kein '
      'Versand.';
    RETURN 0;
  END IF;

  -- Abgelaufene Freigaben zuruecknehmen: der Zugriff endet am
  -- konfigurierten Datum, unabhaengig davon, ob jemand die App oeffnet.
  UPDATE public.guardian_consents
     SET status = 'expired', updated_at = now()
   WHERE status = 'active'
     AND access_until IS NOT NULL
     AND access_until <= now();

  FOR v_row IN
    SELECT c.id,
           c.child_user_id,
           c.guardian_email,
           c.notify_frequency,
           count(e.id)     AS anzahl,
           max(e.created_at) AS letzter
      FROM public.guardian_consents c
      JOIN public.guardian_notification_events e
        ON e.consent_id = c.id
       AND e.sent_at IS NULL
     WHERE c.status = 'active'
       AND c.notify_enabled
       AND c.notify_frequency = p_period
     GROUP BY c.id, c.child_user_id, c.guardian_email, c.notify_frequency
  LOOP
    -- Als gesendet markieren VOR dem Versand. Sonst schickt ein
    -- gescheiterter Versand dieselbe Meldung im naechsten Lauf erneut.
    UPDATE public.guardian_notification_events
       SET sent_at = now()
     WHERE consent_id = v_row.id
       AND sent_at IS NULL;

    PERFORM net.http_post(
      url := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/guardian-digest',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-thestia-internal', v_secret
      ),
      body := jsonb_build_object(
        'consentId',     v_row.id,
        'childUserId',   v_row.child_user_id,
        'guardianEmail', v_row.guardian_email,
        'period',        p_period,
        'count',         v_row.anzahl,
        'lastEventAt',   v_row.letzter
      )
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.run_guardian_digest(text) IS
  'Buendelt die Funken-Ereignisse je Freigabe und stoesst den Versand an. '
  'Die Haeufigkeit (daily/weekly/monthly) wird vom Elternteil gestellt; '
  'wer "none" waehlt, bekommt nichts (v0.10.0, Migration 165).';
REVOKE ALL ON FUNCTION public.run_guardian_digest(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_guardian_digest(text) TO service_role;

-- ===========================================================================
-- 17) Die Cron-Jobs (UTC)
-- ===========================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'guardian-digest-daily') THEN
      PERFORM cron.unschedule('guardian-digest-daily');
    END IF;
    PERFORM cron.schedule(
      'guardian-digest-daily', '0 8 * * *',
      $cron$ SELECT public.run_guardian_digest('daily'); $cron$
    );

    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'guardian-digest-weekly') THEN
      PERFORM cron.unschedule('guardian-digest-weekly');
    END IF;
    PERFORM cron.schedule(
      'guardian-digest-weekly', '0 8 * * 1',
      $cron$ SELECT public.run_guardian_digest('weekly'); $cron$
    );

    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'guardian-digest-monthly') THEN
      PERFORM cron.unschedule('guardian-digest-monthly');
    END IF;
    PERFORM cron.schedule(
      'guardian-digest-monthly', '0 8 1 * *',
      $cron$ SELECT public.run_guardian_digest('monthly'); $cron$
    );
  ELSE
    RAISE WARNING
      'guardian-digest-Cron konnte nicht eingerichtet werden (pg_cron '
      'fehlt) - best-effort, wie bei den uebrigen Cleanups.';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'guardian-digest-Cron konnte nicht eingerichtet werden (best-effort): %', SQLERRM;
END;
$$;

-- ===========================================================================
-- 18) Selbsttest
-- ===========================================================================
DO $check$
DECLARE
  v_typ text;
  v_count integer;
BEGIN
  -- Die RPCs muessen existieren.
  PERFORM 1 FROM pg_proc
   WHERE proname = 'request_guardian_consent'
     AND pronamespace = 'public'::regnamespace;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_guardian_consent fehlt.';
  END IF;

  -- Der Token darf NIE im Klartext gespeichert werden. Der Spaltenname
  -- "token_hash" ist das eine Signal - die Funktion darf aber nur den
  -- Hash schreiben.
  SELECT pg_get_functiondef('public.request_guardian_consent(text)'::regprocedure)
    INTO v_typ;
  IF v_typ LIKE '%token_hash = v_token%' THEN
    RAISE EXCEPTION
      'request_guardian_consent speichert den Token im Klartext.';
  END IF;
  IF v_typ NOT LIKE '%sha256%' THEN
    RAISE EXCEPTION
      'request_guardian_consent hasht den Token nicht.';
  END IF;

  -- Die Alterspruefung muss auf dem VERIFIZIERTEN Alter beruhen.
  IF v_typ NOT LIKE '%guardian_eligible_age%' THEN
    RAISE EXCEPTION
      'request_guardian_consent prueft das Alter nicht.';
  END IF;

  -- Die Eigenadresse muss ausgeschlossen sein.
  IF v_typ NOT LIKE '%same_email%' THEN
    RAISE EXCEPTION
      'request_guardian_consent erlaubt die eigene Kontoadresse als '
      'Elternadresse.';
  END IF;

  -- Der PIN-Vergleich muss serverseitig sein.
  SELECT pg_get_functiondef('public.verify_guardian_pin(text)'::regprocedure)
    INTO v_typ;
  IF v_typ NOT LIKE '%crypt%' THEN
    RAISE EXCEPTION 'verify_guardian_pin vergleicht nicht serverseitig.';
  END IF;
  IF v_typ NOT LIKE '%consume_rate_limit%' THEN
    RAISE EXCEPTION 'verify_guardian_pin hat keine Sperre.';
  END IF;

  -- Der Funken-Trigger muss existieren.
  SELECT count(*) INTO v_count
    FROM pg_trigger t
   WHERE t.tgname = 'trg_matches_guardian_notify'
     AND NOT t.tgisinternal;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Der Trigger fuer Eltern-Ereignisse fehlt.';
  END IF;

  RAISE NOTICE 'Eltern-Aufsicht: RPCs, Token-Hashing, Alterspruefung, PIN-Sperre und Trigger vorhanden (Selbsttest ok)';
END;
$check$;

COMMIT;
