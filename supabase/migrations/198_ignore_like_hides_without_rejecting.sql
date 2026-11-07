-- 198: "Ausblenden" statt "Ablehnen" - der Like verschwindet aus der
--      Liste, ohne die andere Person zu benachrichtigen
--
-- BEFUND (07.11.2026, Betreiber): "Das Auge mit dem Strich ist like
-- abgelehnt, aber man wuerde eher sowas wie ausblenden oder ignorieren
-- darunter verstehen."
--
-- DIE URSACHE: Die Augenschaltflaeche in der Liste der erhaltenen
-- Likes war mit "Ignorieren" beschriftet, rief aber
-- respond_to_like(p_like_id, false) auf - das LEHNT den Like ab. Die
-- andere Person bekommt die Ablehnung zu sehen (und der Nutzer weiss
-- nicht, was er getippt hat).
--
-- Das Auge mit dem Strich bedeutet fuer alle "ausblenden". Also wird
-- es auch so umgesetzt: ein neuer Status 'ignored' nimmt den Like aus
-- der Liste, ohne die Gegenseite zu benachrichtigen.
--
-- Das echte Ablehnen bleibt moeglich (respond_to_like mit false) -
-- nur nicht mehr unter dem Auge.

BEGIN;

-- 1) Der vierte Status: 'ignored' (ausgeblendet, nicht abgelehnt).
ALTER TABLE public.likes
  DROP CONSTRAINT IF EXISTS likes_status_check;

ALTER TABLE public.likes
  ADD CONSTRAINT likes_status_check
  CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text,
                         'rejected'::text, 'ignored'::text])));

-- 2) Die Funktion: der Like ausblenden.
CREATE OR REPLACE FUNCTION public.ignore_like(p_like_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_liker uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Nicht authentifiziert';
  END IF;

  -- Rate-Limit: 60 Antworten/Stunde (wie respond_to_like). Ein
  -- ausgeblendeter Like loest keine Pushes aus - die Grenze ist hier
  -- trotzdem sinnvoll, damit die Funktion kein Werkzeug zum
  -- Massen-Umleeren fremder Listen wird.
  IF NOT public.consume_rate_limit('respond_like:' || v_user::text, 60, 3600) THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  SELECT l.user_id
    INTO v_liker
    FROM public.likes l
   WHERE l.id = p_like_id
     AND l.liked_user_id = v_user
     AND l.status = 'pending';

  IF v_liker IS NULL THEN
    RAISE EXCEPTION 'Like nicht gefunden oder bereits beantwortet';
  END IF;

  -- Der Like verschwindet aus der Liste - OHNE die Gegenseite zu
  -- benachrichtigen. Das ist der Unterschied zum Ablehnen: dort
  -- weiss die andere Person, dass ihr Like abgelehnt wurde.
  UPDATE public.likes
     SET status = 'ignored',
         responded_at = now()
   WHERE id = p_like_id;
END;
$$;

-- 3) Die Kontrolle: die Funktion muss da sein und der Status erlaubt.
DO $$
DECLARE
  v_ok int;
BEGIN
  SELECT count(*) INTO v_ok
    FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'ignore_like';

  IF v_ok = 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: ignore_like fehlt - der Like kann nicht ausgeblendet werden';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.likes'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) LIKE '%ignored%'
  ) THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: der Status ignored ist nicht erlaubt';
  END IF;
END;
$$;

-- Likes ausblenden - nur fuer angemeldete Nutzer.

-- Die Rechte ausdruecklich setzen.
--
-- WICHTIG: Eine Migration, die eine Funktion per DROP/CREATE
-- ersetzt, holt die Rechte NICHT automatisch zurueck - beim DROP
-- gehen sie weg. Wer sie nicht wieder setzt, laesst die Funktion fuer
-- jeden (auch ohne Anmeldung) offen.
REVOKE ALL ON FUNCTION public.ignore_like(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ignore_like(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.ignore_like(bigint) TO authenticated;

COMMIT;
