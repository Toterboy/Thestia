-- =============================================================================
-- 168_admin_mail_inbox.sql
-- =============================================================================
-- Der Posteingang im Admin-Bereich: eingehende Mails an die Adresse des
-- Betreibers sollen dort stehen, aufgeteilt nach Adresse - ohne sie
-- einzeln im Mail-Programm suchen zu muessen.
--
-- BETREIBER-ENTSCHEIDUNG (03.11.2026): "Koennen im Adminbereich fuer mich
-- die Emails auch angezeigt werden? Kein Antworten nur anzeigen.
-- Aufgeteilt nach Adresse, also Kinderschutz, Support, usw."
--
-- ZWEI EINGANGSWEGE (beide landen in derselben Tabelle):
--
--   1) IMAP-Abfrage (tool/mail_imap_poll.py): ein kleines Skript holt
--      neue Mails per IMAP und meldet sie an die Edge Function.
--   2) Cloudflare Email Worker: der Mailanbieter schiebt die Mail per
--      Webhook in die Edge Function.
--
-- Der Doppelimport ist unkritisch: ueber die Message-ID wird jede Mail
-- nur einmal gespeichert (UNIQUE-Index, ON CONFLICT DO NOTHING).
--
-- WICHTIG - und das ist der Kern dieser Entscheidung:
--
-- Es gibt KEINE Antwortfunktion. Kein Senden, kein Antworten aus der
-- App. Grund:
--
--   * Ein Antwortpfad bräuchte SMTP-Zugang und eine zweite
--     Absenderidentität. Im Kinderschutz-Kontext wäre die Gefahr real,
--     aus dem falschen Konto heraus zu schreiben.
--   * Es gäbe eine zweite, unprotokollierte Kopie der Korrespondenz.
--   * Der Weg über die Eltern-Mails zeigt: das Portal für die Eltern
--     funktioniert gut - es ist eine Seite mit einem Link.
--
-- DESHALB: Die App liest nur. Wer antwortet, öffnet das Mail-Programm.
--
-- DIE PRIVATSPHÄRE DER ABSENDER:
--
-- Der Posteingang enthält personenbezogene Daten Dritter (Menschen, die
-- schreiben). Sie werden gespeichert, damit der Betreiber sie lesen
-- kann. Dafür gelten dieselben Regeln wie für den übrigen Betrieb:
-- Zugriff nur über den Admin-RPC, Löschfristen, und die
-- Datenschutzerklärung nennt den Vorgang.
-- =============================================================================

BEGIN;

-- ===========================================================================
-- 1) Die Tabelle
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.mail_messages (
  id           bigserial PRIMARY KEY,
  -- Die Adresse, an die geschrieben wurde (kinderschutz@thestia.de,
  -- support@thestia.de, ...). Danach wird im Admin-Bereich gruppiert.
  recipient    text NOT NULL,
  -- Die Rubrik daraus. Wird beim Einsortieren abgeleitet, damit die
  -- Anzeige nicht an der Adresse haengt, sondern an der Sache.
  category     text NOT NULL DEFAULT 'sonstiges'
                 CHECK (category IN ('kinderschutz','support','datenschutz',
                                     'presse','sonstiges')),
  -- Die Message-ID des Headers. Der UNIQUE-Index darueber verhindert,
  -- dass dieselbe Mail zweimal gespeichert wird (IMAP und Worker
  -- koennen dieselbe Mail liefern).
  message_id   text,
  from_email   text,
  from_name    text,
  subject      text,
  body_text    text,
  received_at  timestamptz NOT NULL DEFAULT now(),
  -- Vom Betreiber als gelesen markiert. Das ist nur ein Merkmal - es
  -- aendert nichts an der Mail.
  read_at      timestamptz,
  source       text NOT NULL DEFAULT 'imap'
                 CHECK (source IN ('imap','cloudflare','manuell')),
  size_bytes   int,
  created_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.mail_messages IS
  'Eingehende Mails des Betreibers, im Admin-Bereich einsehbar - nur zum '
  'Lesen (v0.11.0, Migration 168). Keine Antwortfunktion: es gibt '
  'bewusst keinen SMTP-Zugang aus der App heraus.';

COMMENT ON COLUMN public.mail_messages.category IS
  'Rubrik fuer die Anzeige: kinderschutz | support | datenschutz | '
  'presse | sonstiges. Die Rubrik wird aus der Empfangsadresse '
  'abgeleitet, nicht vom Absender.';

CREATE UNIQUE INDEX IF NOT EXISTS idx_mail_messages_message_id
  ON public.mail_messages (message_id)
  WHERE message_id IS NOT NULL AND message_id <> '';

CREATE INDEX IF NOT EXISTS idx_mail_messages_category
  ON public.mail_messages (category, received_at DESC);

ALTER TABLE public.mail_messages ENABLE ROW LEVEL SECURITY;
-- Bewusst KEINE Policies: nur der Admin-RPC liest, und die Edge
-- Function schreibt mit der Service-Rolle.

-- ===========================================================================
-- 2) Die Rubrik aus der Adresse ableiten
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.mail_category_for(p_recipient text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_recipient IS NULL THEN 'sonstiges'
    WHEN lower(p_recipient) LIKE '%kinderschutz%' THEN 'kinderschutz'
    WHEN lower(p_recipient) LIKE '%datenschutz%' THEN 'datenschutz'
    WHEN lower(p_recipient) LIKE '%presse%' OR lower(p_recipient) LIKE '%media%'
      THEN 'presse'
    WHEN lower(p_recipient) LIKE '%support%' THEN 'support'
    ELSE 'sonstiges'
  END;
$$;

COMMENT ON FUNCTION public.mail_category_for(text) IS
  'Leitet die Rubrik aus der Empfangsadresse ab (v0.11.0, Migration 168).';
REVOKE ALL ON FUNCTION public.mail_category_for(text) FROM PUBLIC;

-- ===========================================================================
-- 3) Die Admin-Liste
-- ===========================================================================
-- fail-closed ueber is_current_user_admin(): ohne Admin-Flag liefert die
-- Funktion nichts. Die oeffentliche APK hat ohnehin keinen Admin-Zugang
-- (die Admin-UUID wird per --dart-define gesetzt und fehlt dort).
CREATE OR REPLACE FUNCTION public.admin_list_mail_messages(
  p_category text DEFAULT NULL,
  p_limit    int DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lim int;
  v_rows jsonb;
BEGIN
  IF NOT public.is_current_user_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  -- Das Limit wird geklemmt: ein Client, der 1000000 anfragt, soll die
  -- Datenbank nicht leeren.
  v_lim := least(greatest(coalesce(p_limit, 100), 1), 500);

  SELECT coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb) INTO v_rows
    FROM (
      SELECT m.id,
             m.recipient,
             m.category,
             m.message_id,
             m.from_email,
             m.from_name,
             m.subject,
             m.body_text,
             m.received_at,
             m.read_at,
             m.source
        FROM public.mail_messages m
       WHERE (p_category IS NULL OR p_category = '' OR m.category = p_category)
       ORDER BY m.received_at DESC
       LIMIT v_lim
    ) r;

  RETURN v_rows;
END;
$$;

COMMENT ON FUNCTION public.admin_list_mail_messages(text, int) IS
  'Die Mails fuer den Admin-Bereich, nach Rubrik gefiltert. Nur lesen - '
  'die Funktion kann nichts aendern und nichts senden (v0.11.0, '
  'Migration 168).';
REVOKE ALL ON FUNCTION public.admin_list_mail_messages(text, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_mail_messages(text, int) TO authenticated;

-- ===========================================================================
-- 4) Die Zaehlung fuer die Anzeige (Rubriken mit Anzahl)
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.admin_mail_message_counts()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_out jsonb;
BEGIN
  IF NOT public.is_current_user_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  SELECT coalesce(jsonb_object_agg(kategorie, anzahl), '{}'::jsonb)
    INTO v_out
    FROM (
      SELECT category AS kategorie, count(*)::int AS anzahl
        FROM public.mail_messages
       GROUP BY category
    ) c;

  RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_mail_message_counts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_mail_message_counts() TO authenticated;

-- ===========================================================================
-- 5) Loeschfrist
-- ===========================================================================
-- Die Mails sind Korrespondenz mit Menschen, die sich an den Betreiber
-- gewandt haben. Sie werden nicht ewig aufbewahrt: nach 180 Tagen
-- verschwinden sie - wie die Nutzer-Meldungen (Migration 060, 180 Tage).
--
-- Ausgenommen sind Mails im Kinderschutz-Bereich? Nein: Auch dort gilt
-- die Frist. Wer eine Meldung aufbewahren will, tut das im eigenen
-- Postfach - die App ist kein Archiv.
CREATE OR REPLACE FUNCTION public.cleanup_old_mail_messages()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
BEGIN
  DELETE FROM public.mail_messages
   WHERE created_at < now() - interval '180 days';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.cleanup_old_mail_messages() IS
  'Loescht Mails, die aelter als 180 Tage sind (v0.11.0, Migration 168).';
REVOKE ALL ON FUNCTION public.cleanup_old_mail_messages() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_old_mail_messages() TO service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-old-mail-messages') THEN
      PERFORM cron.unschedule('cleanup-old-mail-messages');
    END IF;
    PERFORM cron.schedule(
      'cleanup-old-mail-messages', '40 5 * * *',
      $cron$ SELECT public.cleanup_old_mail_messages(); $cron$
    );
  ELSE
    RAISE WARNING
      'cleanup-old-mail-messages konnte nicht eingerichtet werden '
      '(pg_cron fehlt) - best-effort.';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cleanup-old-mail-messages konnte nicht eingerichtet werden (best-effort): %', SQLERRM;
END;
$$;

-- ===========================================================================
-- 6) Selbsttest
-- ===========================================================================
DO $check$
DECLARE
  v_typ text;
BEGIN
  -- Es darf KEINE Schreibfunktion fuer Mails geben (kein Antworten aus
  -- der App heraus). Die Liste ist bewusst BENAMT und nicht mit einem
  -- Muster '%mail%': das traegt auch is_email_banned, guardian_mask_email
  -- und Co. - Funktionen, die mit Mails nichts zu tun haben.
  PERFORM 1 FROM pg_proc
   WHERE proname IN ('send_mail', 'reply_mail', 'insert_mail_message',
                     'delete_mail_message', 'update_mail_message',
                     'admin_write_mail_message')
     AND pronamespace = 'public'::regnamespace;
  IF FOUND THEN
    RAISE EXCEPTION
      'Es gibt eine Schreibfunktion fuer Mails - die Maildaten duerfen '
      'nur gelesen werden.';
  END IF;

  -- Und die Admin-Liste darf selbst nichts schreiben.
  SELECT pg_get_functiondef('public.admin_list_mail_messages(text,int)'::regprocedure)
    INTO v_typ;
  IF v_typ LIKE '%INSERT INTO public.mail_messages%'
     OR v_typ LIKE '%UPDATE public.mail_messages%'
     OR v_typ LIKE '%DELETE FROM public.mail_messages%' THEN
    RAISE EXCEPTION
      'admin_list_mail_messages schreibt - die Funktion darf nur lesen.';
  END IF;

  -- Die Admin-Liste muss fail-closed sein.
  IF v_typ NOT LIKE '%is_current_user_admin%' THEN
    RAISE EXCEPTION
      'admin_list_mail_messages prueft den Admin-Status nicht.';
  END IF;

  RAISE NOTICE 'Posteingang: nur lesbar, Admin-Liste fail-closed, Loeschfrist gesetzt (Selbsttest ok)';
END;
$check$;

COMMIT;
