-- 191: der Transit-Funke wird auch fuer die GEGENSEITE sichtbar
--
-- BEFUND (07.11.2026, Betreiber): "Der Funke entsteht, aber es ist
-- nichts sichtbar."
--
-- DIE URSACHE (live gelesen): Die Paarungsfunktion
-- public.match_proximity_spark meldet den Treffer nur dem ABSENDER
-- ('matched: true' -> Dialog in der App). Fuer die Gegenseite
-- entsteht dabei kein sichtbarer Eintrag: kein Soft-Ping, keine
-- Meldung, nichts. Der Match lag zwar in der Datenbank (die
-- gegenseitigen Likes), aber die App laedt die Chatliste nur beim
-- Oeffnen - und ohne Realtime (die Publication ist leer) blieb die
-- Liste der Gegenseite alt, bis sie neu geoeffnet wurde.
--
-- DIE LOESUNG: Bei einem Treffer legt die Paarung fuer die
-- Gegenseite zusaetzlich einen Soft-Ping an - genau so, wie es bei
-- einem ausdruecklichen "Zuzwinken" (send_soft_ping) passiert. Der
-- Eingang des Transit-Radars pollt alle 15 Sekunden: der Funke ist
-- damit binnen Sekunden sichtbar. "Annehmen" legt die Likes
-- idempotent an (ON CONFLICT DO NOTHING) - es gibt also kein
-- doppeltes Match.
--
-- Die Funktion ist die LIVE-Definition; geaendert wurde genau eine
-- Stelle (der Soft-Ping hinter den Likes).

BEGIN;

CREATE OR REPLACE FUNCTION public.match_proximity_spark(p_tokens text[], p_tags text[] DEFAULT '{}'::text[], p_mode text DEFAULT 'transit'::text, p_self_tags text[] DEFAULT '{}'::text[], p_self_note text DEFAULT NULL::text, p_self_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_me public.profiles;
  v_clean text[];
  v_tags text[];
  v_self text[];
  v_note text;
  v_self_token text;
  v_cutoff timestamptz := now() - interval '45 minutes';
  v_other record;
  v_allowed text[];
BEGIN
  v_allowed := ARRAY(
    SELECT DISTINCT u.t FROM (
      SELECT c.slug AS t FROM public.transit_tag_catalog c
      UNION
      SELECT c.slug || ':' || col AS t FROM public.transit_tag_catalog c
      CROSS JOIN LATERAL unnest(c.allowed_colors) AS col
      -- DIE DRITTE ART (Migration 187): "slug:wert" aus der Werteliste.
      -- Beispiel: "hair_style:lockig".
      UNION
      SELECT c.slug || ':' || val AS t FROM public.transit_tag_catalog c
      CROSS JOIN LATERAL unnest(c.allowed_values) AS val
    ) u WHERE u.t IS NOT NULL
  );
  v_allowed := coalesce(v_allowed, '{}'::text[]);

  IF v_uid IS NULL THEN RAISE EXCEPTION 'Nicht eingeloggt'; END IF;
  SELECT * INTO v_me FROM public.profiles WHERE user_id = v_uid;
  IF v_me.user_id IS NULL THEN RAISE EXCEPTION 'Kein Profil'; END IF;
  IF NOT public.transit_spark_adult(v_uid) THEN
    RAISE EXCEPTION 'transit_age_restricted: Transit Spark ist nur ab 18 Jahren nutzbar.';
  END IF;

  IF p_self_token IS NULL OR btrim(p_self_token) = '' THEN
    RAISE EXCEPTION 'transit_own_token_missing: Bitte die App aktualisieren - der Radar muss zuerst ein Signal senden.';
  END IF;
  v_self_token := lower(btrim(p_self_token));
  IF v_self_token !~ '^[0-9a-f]{20}$' THEN
    RAISE EXCEPTION 'transit_own_token_invalid: Das eigene Signal ist noch nicht bereit.';
  END IF;

  SELECT array_agg(DISTINCT t) INTO v_clean FROM (
    SELECT left(substring(t from '[0-9a-fA-F-]{8,64}'), 64) AS t
    FROM unnest(COALESCE(p_tokens, '{}'::text[])) AS t
  ) sub WHERE t IS NOT NULL AND length(t) >= 8;
  IF v_clean IS NULL OR array_length(v_clean, 1) IS NULL THEN
    RAISE EXCEPTION 'Keine gueltigen Tokens';
  END IF;
  v_clean := (SELECT array_agg(x) FROM
    (SELECT t AS x FROM unnest(v_clean) t LIMIT 100) c);

  SELECT array_agg(DISTINCT t) INTO v_tags
    FROM unnest(COALESCE(p_tags, '{}'::text[])) AS t WHERE t = ANY (v_allowed);
  IF v_tags IS NULL OR array_length(v_tags, 1) IS NULL
     OR array_length(v_tags, 1) < 2 OR array_length(v_tags, 1) > 8 THEN
    RAISE EXCEPTION 'Bitte 2-8 Merkmale waehlen';
  END IF;

  -- Je Kategorie nur ein Wert - auch bei den Merkmalen mit Werteliste
  -- ("Haarlaenge: lang" UND "Frisur: lockig" sind verschiedene
  -- Kategorien und duerfen beide gewaehlt werden, "Haarlaenge: lang"
  -- und "Haarlaenge: kurz" aber natuerlich nicht).
  IF EXISTS (
       SELECT 1
         FROM unnest(v_tags) AS t
         JOIN public.transit_tag_catalog c
           ON c.slug = split_part(t, ':', 1)
        GROUP BY c.category
       HAVING count(*) > 1
     ) THEN
    RAISE EXCEPTION 'Je Kategorie nur ein Merkmal waehlen';
  END IF;

  SELECT array_agg(DISTINCT t) INTO v_self
    FROM unnest(COALESCE(p_self_tags, '{}'::text[])) AS t WHERE t = ANY (v_allowed);
  IF array_length(coalesce(v_self, '{}'::text[]), 1) > 8 THEN
    RAISE EXCEPTION 'Bitte maximal 8 Merkmale zu dir selbst waehlen';
  END IF;

  IF EXISTS (
       SELECT 1
         FROM unnest(coalesce(v_self, '{}'::text[])) AS t
         JOIN public.transit_tag_catalog c
           ON c.slug = split_part(t, ':', 1)
        GROUP BY c.category
       HAVING count(*) > 1
     ) THEN
    RAISE EXCEPTION 'Je Kategorie nur ein Merkmal waehlen';
  END IF;
  v_self := coalesce(v_self, '{}'::text[]);

  v_note := nullif(trim(regexp_replace(coalesce(p_self_note, ''), '[\r\n\t]+', ' ', 'g')), '');
  IF v_note IS NOT NULL AND length(v_note) > 140 THEN
    v_note := left(v_note, 140);
  END IF;

  IF EXISTS (SELECT 1 FROM public.transit_signals
              WHERE user_id = v_uid AND created_at > now() - interval '2 minutes') THEN
    RAISE EXCEPTION 'Kurz durchatmen: Bitte kurz warten.';
  END IF;

  FOR v_other IN
    SELECT s.id, s.user_id, s.tokens, s.tags, s.self_tags, s.self_note, s.created_at
      FROM public.transit_signals s
      JOIN public.profiles p ON p.user_id = s.user_id
     WHERE s.user_id <> v_uid
       AND s.status = 'pending'
       AND s.created_at > v_cutoff
       AND s.self_token = ANY (v_clean)
       AND v_self_token = ANY (s.tokens)
       AND (s.self_tags && v_tags OR v_self && s.tags OR s.tags && v_tags)
       AND public.transit_spark_adult(s.user_id)
       AND public.age_compatible(
             (SELECT public.profile_age(me.birth_date) FROM public.profiles me
               WHERE me.user_id = v_uid),
             date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int)
       AND NOT EXISTS (
             SELECT 1 FROM public.blocked_users b
              WHERE (b.blocker = v_uid AND b.blocked = s.user_id)
                 OR (b.blocker = s.user_id AND b.blocked = v_uid))
      ORDER BY s.created_at DESC
      LIMIT 1
  LOOP
    UPDATE public.transit_signals SET status = 'matched', matched_with = v_other.user_id
     WHERE id = v_other.id;
    INSERT INTO public.transit_signals
      (user_id, tokens, tags, self_tags, self_note, mode, status, matched_with, created_at, self_token)
    VALUES (v_uid, v_clean, v_tags, v_self, v_note,
            CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
            'matched', v_other.user_id, now(), v_self_token);
    INSERT INTO public.likes (user_id, liked_user_id)
    VALUES (v_uid, v_other.user_id), (v_other.user_id, v_uid) ON CONFLICT DO NOTHING;

    -- BEFUND (07.11.2026, Betreiber): "Der Funke entsteht, aber es ist
    -- nichts sichtbar." Bis hierher war der Fund nur auf der SENDER-
    -- seite sichtbar: der Absender bekam 'matched: true' und einen
    -- Dialog, die GEGENSEITE bekam nichts - kein Soft-Ping, keine
    -- Meldung. Der Match lag zwar in der Datenbank (die Likes), aber
    -- ohne Realtime (die Publication ist leer) blieb die Chatliste der
    -- Gegenseite alt, bis sie neu geoeffnet wurde.
    --
    -- Deshalb legt die Paarung jetzt fuer die Gegenseite einen
    -- Soft-Ping an - so, wie es bei einem ausdruecklichen "Zuzwinken"
    -- passiert. Der Eingang des Transit-Radars pollt alle 15 Sekunden:
    -- der Funke ist damit binnen Sekunden sichtbar, und "annehmen"
    -- erzeugt die Likes idempotent (ON CONFLICT DO NOTHING).
    --
    -- Der eigene Token dient als Encounter-Token: der Unique-Index
    -- uq_soft_ping_once_per_token (sender, encounter_token) sorgt dafuer,
    -- dass es pro Radar-Signal hoechstens einen Ping gibt.
    INSERT INTO public.transit_soft_pings
    (sender, recipient, encounter_token, message_key, custom_line, expires_at)
    VALUES
    (v_uid, v_other.user_id, v_self_token, 'wave', v_note,
     now() + interval '48 hours')
    ON CONFLICT (sender, encounter_token) DO NOTHING;
    RETURN jsonb_build_object('matched', true, 'partner', v_other.user_id,
                               'partnerNote', v_other.self_note);
  END LOOP;

  DELETE FROM public.transit_signals WHERE user_id = v_uid AND status = 'pending';
  INSERT INTO public.transit_signals
    (user_id, tokens, tags, self_tags, self_note, mode, status, self_token)
  VALUES (v_uid, v_clean, v_tags, v_self, v_note,
            CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
            'pending', v_self_token);
  RETURN jsonb_build_object('matched', false);
END;
$$;
-- Die Kontrolle: die Funktion muss den Soft-Ping anlegen. Ohne sie
-- entsteht der Zustand wieder, der zum Befund gefuehrt hat - und
-- niemand wuerde es merken.
DO $$
DECLARE
  v_ok int;
BEGIN
  SELECT count(*) INTO v_ok
    FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'match_proximity_spark'
     AND p.prosrc ILIKE '%insert into public.transit_soft_pings%';

  IF v_ok = 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: die Paarungsrunde legt keinen Soft-Ping an - der Funke bleibt fuer die Gegenseite unsichtbar';
  END IF;
END;
$$;

COMMIT;
