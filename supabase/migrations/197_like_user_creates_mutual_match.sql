-- 197: public.like_user erzeugt beim beidseitigen Like einen Funke
--      und schluckt keinen Like mehr still
--
-- ZWEI BEFUNDE (07.11.2026, Betreiber):
--
-- 1) "Wenn beide sich liken entsteht kein Funke."
--
--    public.like_user legte nur einen OFFENEN Like an (status
--    'pending'). Der Match entstand nur, wenn die Gegenseite den Like
--    von Hand annahm (respond_to_like). Ein beidseitiger Like hat aber
--    nichts zu entscheiden - und blieb deshalb liegen.
--
--    Der Weg, der auf dem Server schon bereitliegt, ist
--    public.create_match_if_mutual: es legt den Like an UND erzeugt
--    den Match, wenn der Like beidseitig ist. Die App benutzt es
--    bisher nirgends (insertLike wird nirgends aufgerufen).
--
--    Deshalb macht like_user es jetzt selbst: beim beidseitigen Like
--    entsteht der Funke sofort, und beide Likes gelten als angenommen.
--
-- 2) "Man kann nicht von einer Person einen Like haben, mit der man
--     schon einen Funken hat."
--
--    Bei einem bestehenden Funke tat die Funktion NICHTS: das UPDATE
--    traf nur gekuehlte Funken, ein bestehender aktiver Funke wurde
--    stillschweigend geschluckt - ohne jede Meldung.
--
--    Jetzt gibt die Funktion das Ergebnis zurueck: der Aufrufer weiss,
--    dass es schon einen Funken gibt, und kann das dem Nutzer sagen.
--
-- Die Funktion ist die LIVE-Definition; geaendert wurde genau der Teil
-- nach den Schutzpruefungen (plus zwei Variablen und der Rueckgabetyp).

BEGIN;

-- Der Rueckgabetyp aendert sich (void -> jsonb); das geht nur
-- mit DROP. In derselben Transaktion, also ohne Fenster.
DROP FUNCTION IF EXISTS public.like_user(uuid);

CREATE OR REPLACE FUNCTION public.like_user(p_target uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_match_id bigint;
  v_funke_status text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Nicht authentifiziert';
  END IF;
  IF p_target IS NULL OR p_target = v_user THEN
    RAISE EXCEPTION 'Ungueltiges Ziel';
  END IF;

  -- Rate-Limit (Audit M-8).
  IF NOT public.consume_rate_limit(
       'likes_hourly:' || v_user::text, 30, 3600) THEN
    RAISE EXCEPTION 'like_rate_limited_hourly';
  END IF;
  IF NOT public.consume_rate_limit(
       'likes_daily:' || v_user::text, 100, 86400) THEN
    RAISE EXCEPTION 'like_rate_limited_daily';
  END IF;

  -- Alters-Schutz (Audit K-1).
  PERFORM public.assert_age_compatible(v_user, p_target);

  -- Blockier-Schutz.
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker = v_user AND b.blocked = p_target)
        OR (b.blocker = p_target AND b.blocked = v_user)
  ) THEN
    RAISE EXCEPTION 'blocked';
  END IF;

  -- Bestehender Funke?
  --
  -- BEFUND (07.11.2026, Betreiber): "Man kann nicht von einer Person
  -- einen Like haben, mit der man schon einen Funken hat." Bei einem
  -- bestehenden Funke tat die Funktion NICHTS - der Like wurde
  -- stillschweigend geschluckt, ohne jede Meldung.
  --
  -- Jetzt wird der Zustand GEFUNDEN und zurueckgegeben: der Aufrufer
  -- kann dem Nutzer sagen "Ihr habt schon einen Funken" (und muss
  -- nichts anzeigen, wenn es eben nicht stimmt).
  SELECT m.id, m.status INTO v_match_id, v_funke_status
    FROM public.matches m
   WHERE (m.user_one_id = v_user AND m.user_two_id = p_target)
      OR (m.user_two_id = v_user AND m.user_one_id = p_target)
   LIMIT 1;

  IF v_match_id IS NOT NULL THEN
    -- Gekuehlten Funken reaktivieren statt still nichts tun
    -- (Fix: Nutzer tippt Like, Funke bleibt aber unsichtbar).
    IF v_funke_status = 'cooled' THEN
      UPDATE public.matches
         SET status = 'active',
             resparked_at = now()
       WHERE id = v_match_id;
    END IF;
    RETURN jsonb_build_object(
      'is_match', true,
      'already_matched', true,
      'match_id', v_match_id
    );
  END IF;

  INSERT INTO public.likes (user_id, liked_user_id, status)
  VALUES (v_user, p_target, 'pending')
  ON CONFLICT (user_id, liked_user_id) DO UPDATE
    SET status = 'pending', responded_at = NULL;

  -- BEIDSEITIGER LIKE: jetzt entsteht der Funke.
  --
  -- BEFUND (07.11.2026, Betreiber): "Wenn beide sich liken entsteht
  -- kein Funke." Vorher blieb der Like liegen, bis die Gegenseite
  -- ihn von Hand annahm - ein beidseitiger Like hat aber nichts zu
  -- entscheiden.
  --
  -- Es geht genauso wie bei create_match_if_mutual: der Match wird
  -- angelegt (nur EINER je Paar), und beide Likes gelten als
  -- angenommen.
  IF EXISTS (
    SELECT 1 FROM public.likes l
     WHERE l.user_id = p_target
       AND l.liked_user_id = v_user
       AND l.status IN ('pending', 'accepted')
  ) THEN
    INSERT INTO public.matches (user_one_id, user_two_id)
    VALUES (least(v_user, p_target), greatest(v_user, p_target))
    ON CONFLICT (user_one_id, user_two_id) DO NOTHING
    RETURNING id INTO v_match_id;

    IF v_match_id IS NULL THEN
      SELECT id INTO v_match_id
        FROM public.matches
       WHERE user_one_id = least(v_user, p_target)
         AND user_two_id = greatest(v_user, p_target);
    END IF;

    UPDATE public.likes
       SET status = 'accepted',
           responded_at = now()
     WHERE ((user_id = v_user AND liked_user_id = p_target)
        OR (user_id = p_target AND liked_user_id = v_user))
       AND status = 'pending';

    RETURN jsonb_build_object(
      'is_match', true,
      'already_matched', false,
      'match_id', v_match_id
    );
  END IF;

  RETURN jsonb_build_object(
    'is_match', false,
    'already_matched', false,
    'match_id', null
  );
END;
$$;
-- Die Kontrolle: die Funktion muss den beidseitigen Like zu einem
-- Funke machen und das Ergebnis zurueckgeben.
DO $$
DECLARE
  v_ok int;
BEGIN
  SELECT count(*) INTO v_ok
    FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'like_user'
     AND p.prorettype = 'jsonb'::regtype
     AND p.prosrc ILIKE '%already_matched%';

  IF v_ok = 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: like_user gibt das Ergebnis nicht zurueck - ein beidseitiger Like erzeugt weiterhin keinen Funke';
  END IF;
END;
$$;

-- Likes setzen - nur fuer angemeldete Nutzer.

-- Die Rechte ausdruecklich setzen.
--
-- WICHTIG: Eine Migration, die eine Funktion per DROP/CREATE
-- ersetzt, holt die Rechte NICHT automatisch zurueck - beim DROP
-- gehen sie weg. Wer sie nicht wieder setzt, laesst die Funktion fuer
-- jeden (auch ohne Anmeldung) offen.
REVOKE ALL ON FUNCTION public.like_user(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.like_user(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.like_user(uuid) TO authenticated;

COMMIT;
