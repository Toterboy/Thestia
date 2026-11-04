-- 172: Mail-Rubrik automatisch setzen
--
-- BEFUND (04.11.2026, Audit der Edge Functions):
--
-- Die Funktion public.mail_category_for() aus Migration 168 wird
-- NIRGENDS aufgerufen. Das INSERT in der Edge Function "mail-ingest"
-- setzt die Spalte "category" nicht - und die Spalte hat den Default
-- 'sonstiges'.
--
-- Die Folge: JEDE Mail landete in der Rubrik "sonstiges". Die im
-- Admin-Bereich versprochene Gruppierung nach Kinderschutz /
-- Support / Datenschutz / Presse griff nie. Der Bildschirm zeigt die
-- Reiter, aber in jedem Reiter steht dasselbe.
--
-- DIE LOESUNG IST EIN TRIGGER, nicht ein Aufruf in der Function:
--
--   * Ein Aufruf in der Edge Function wuerde nur diesen einen Weg
--     abdecken. Der IMAP-Weg (tool/mail_imap_poll.py) schreibt
--     ebenfalls in dieselbe Tabelle - der Trigger deckt BEIDE Wege ab.
--   * Der Trigger kann die Rubrik nicht vergessen: Es gibt keinen
--     INSERT mehr, der ohne Rubrik in der Tabelle landet.
--
-- Die Trigger-Funktion laeuft SECURITY DEFINER mit gesetztem
-- search_path - wie alle anderen Funktionen in diesem Projekt.
--
-- Zusaetzlich wird der Altbestand nachgezogen: Die bisherigen Mails
-- stehen alle auf 'sonstiges' und wuerden dort bleiben.

BEGIN;

-- -------------------------------------------------------------------------
-- 1) Trigger-Funktion
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mail_messages_set_category()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.category := public.mail_category_for(NEW.recipient);
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.mail_messages_set_category() IS
  'Setzt die Rubrik einer eingehenden Mail automatisch aus der '
  'Empfaengeradresse (BEFORE INSERT auf mail_messages).';

-- Die Funktion haelt keine Berechtigungen fuer sich - sie laeuft nur
-- als Trigger. Wer sie direkt aufruft, koennte nichts bewirken, aber
-- der Grundsatz bleibt: kein oeffentlicher Aufruf.
REVOKE ALL ON FUNCTION public.mail_messages_set_category() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mail_messages_set_category() FROM anon;
REVOKE ALL ON FUNCTION public.mail_messages_set_category() FROM authenticated;

-- -------------------------------------------------------------------------
-- 2) Trigger anlegen
-- -------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_mail_messages_set_category ON public.mail_messages;

CREATE TRIGGER trg_mail_messages_set_category
  BEFORE INSERT ON public.mail_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.mail_messages_set_category();

-- -------------------------------------------------------------------------
-- 3) Altbestand nachziehen
-- -------------------------------------------------------------------------
-- Die bisherigen Mails stehen alle auf 'sonstiges', weil die Rubrik
-- nie gesetzt wurde. Der CHECK-Constraint erlaubt genau die fuenf
-- Rubriken - mail_category_for() liefert nur diese.
UPDATE public.mail_messages
   SET category = public.mail_category_for(recipient)
 WHERE category IS DISTINCT FROM public.mail_category_for(recipient);

COMMIT;
