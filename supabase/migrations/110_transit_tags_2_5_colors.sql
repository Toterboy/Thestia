-- Migration 110: Transit Spark Merkmale 2-5 + Farben Lila/Trkis
--
-- NUTZERWUNSCH (Build 24):
--   1. Mindestens 2, maximal 5 Merkmale (vorher 1-3) - mehr
--      Merkmale schrfen das Matching; 1 allein war zu vage.
--   2. Farbwahl erweitert: Lila + Trkis (vorher fehlten sie).
--   3. (Client parallel: Farbklecks-UI statt Textchips.)
--
-- Die Limits und die Farb-Whitelist leben in match_proximity_spark -
-- Client und Server sind bewusst synchron (2-5). p_self_tags bleibt
-- optional (kein Minimum), bekommt aber dieselbe 5er-Obergrenze.

CREATE OR REPLACE FUNCTION public.match_proximity_spark(
  p_tokens text[],
  p_tags text[] DEFAULT '{}'::text[],
  p_mode text DEFAULT 'transit',
  p_self_tags text[] DEFAULT '{}'::text[],
  p_self_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_me public.profiles;
  v_clean text[];
  v_tags text[];
  v_self text[];
  v_note text;
  v_cutoff timestamptz := now() - interval '45 minutes';
  v_other record;
  v_allowed text[] := ARRAY[
    'tshirt', 'hoodie', 'sweater', 'jacket', 'shorts', 'pants',
    'sporty', 'cap', 'glasses', 'headphones', 'backpack', 'tote_bag',
    'lanyard', 'scarf', 'top'
  ];
  v_colorizable text[] := ARRAY[
    'hoodie', 'jacket', 'cap', 'tote_bag', 'scarf', 'top',
    'tshirt', 'sweater', 'shorts', 'pants'
  ];
  v_colors text[] := ARRAY[
    'black', 'white', 'grey', 'blue', 'green',
    'red', 'yellow', 'orange', 'pink', 'brown',
    'purple', 'teal'
  ];
  v_base text;
  v_color text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE user_id = v_uid;
  IF v_me.user_id IS NULL THEN
    RAISE EXCEPTION 'Kein Profil';
  END IF;

  SELECT array_agg(DISTINCT t) INTO v_clean
    FROM (
      SELECT left(substring(t from '[0-9a-fA-F-]{8,64}'), 64) AS t
      FROM unnest(COALESCE(p_tokens, '{}'::text[])) AS t
    ) sub
   WHERE t IS NOT NULL AND length(t) >= 8;
  IF v_clean IS NULL OR array_length(v_clean, 1) IS NULL THEN
    RAISE EXCEPTION 'Keine gueltigen Tokens';
  END IF;
  v_clean := (SELECT array_agg(x) FROM
    (SELECT t AS x FROM unnest(v_clean) t LIMIT 100) c);

  FOREACH v_base IN ARRAY ARRAY[
    'black_hoodie', 'tshirt', 'hoodie', 'sweater', 'jacket', 'shorts', 'pants',
    'sporty', 'cap', 'glasses', 'headphones', 'backpack', 'tote_bag',
    'lanyard', 'scarf', 'top', 'colorful_top', 'black_hoodie'
  ] LOOP
    v_allowed := array_append(v_allowed, v_base);
    IF v_base = ANY (v_colorizable) THEN
      FOREACH v_color IN ARRAY v_colors LOOP
        v_allowed := array_append(v_allowed, v_base || ':' || v_color);
      END LOOP;
    END IF;
  END LOOP;

  SELECT array_agg(DISTINCT t) INTO v_tags
    FROM unnest(COALESCE(p_tags, '{}'::text[])) AS t
   WHERE t = ANY (v_allowed);
  -- NUTZERWUNSCH: 2-5 Merkmale (vorher 1-3).
  IF v_tags IS NULL OR array_length(v_tags, 1) IS NULL
     OR array_length(v_tags, 1) < 2
     OR array_length(v_tags, 1) > 5 THEN
    RAISE EXCEPTION 'Bitte 2-5 Merkmale waehlen';
  END IF;

  SELECT array_agg(DISTINCT t) INTO v_self
    FROM unnest(COALESCE(p_self_tags, '{}'::text[])) AS t
   WHERE t = ANY (v_allowed);
  -- Selbstdarstellung bleibt optional, aber gleichfalls max. 5.
  IF array_length(coalesce(v_self, '{}'::text[]), 1) > 5 THEN
    RAISE EXCEPTION 'Bitte maximal 5 Merkmale zu dir selbst waehlen';
  END IF;
  v_self := coalesce(v_self, '{}'::text[]);

  -- Freie Ergänzung: sanitisieren (Steuerzeichen raus, max. 140).
  v_note := nullif(trim(regexp_replace(coalesce(p_self_note, ''), '[\r\n\t]+', ' ', 'g')), '');
  IF v_note IS NOT NULL AND length(v_note) > 140 THEN
    v_note := left(v_note, 140);
  END IF;

  -- Rate-Limit: max. 1 Signal pro 2 Minuten.
  IF EXISTS (
    SELECT 1 FROM public.transit_signals
     WHERE user_id = v_uid AND created_at > now() - interval '2 minutes'
  ) THEN
    RAISE EXCEPTION 'Kurz durchatmen: Bitte kurz warten.';
  END IF;

  FOR v_other IN
    SELECT s.id, s.user_id, s.tokens, s.tags, s.self_tags, s.self_note, s.created_at
      FROM public.transit_signals s
      JOIN public.profiles p ON p.user_id = s.user_id
     WHERE s.user_id <> v_uid
       AND s.status = 'pending'
       AND s.created_at > v_cutoff
       AND s.tokens && v_clean
       AND (
             s.self_tags && v_tags
          OR v_self && s.tags
          OR s.tags && v_tags
       )
       AND public.age_compatible(
             (SELECT public.profile_age(me.birth_date)
                FROM public.profiles me
               WHERE me.user_id = v_uid),
             date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int)
       AND NOT EXISTS (
             SELECT 1 FROM public.blocked_users b
              WHERE (b.blocker = v_uid AND b.blocked = s.user_id)
                 OR (b.blocker = s.user_id AND b.blocked = v_uid))
     ORDER BY s.created_at DESC
     LIMIT 1
  LOOP
    UPDATE public.transit_signals
       SET status = 'matched', matched_with = v_other.user_id
     WHERE id = v_other.id;
    INSERT INTO public.transit_signals
      (user_id, tokens, tags, self_tags, self_note, mode, status, matched_with, created_at)
    VALUES (v_uid, v_clean, v_tags, v_self, v_note,
            CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
            'matched', v_other.user_id, now());

    INSERT INTO public.likes (user_id, liked_user_id)
    VALUES (v_uid, v_other.user_id), (v_other.user_id, v_uid)
    ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object(
      'matched', true,
      'partner', v_other.user_id,
      'partnerNote', v_other.self_note
    );
  END LOOP;

  DELETE FROM public.transit_signals
   WHERE user_id = v_uid AND status = 'pending';
  INSERT INTO public.transit_signals
    (user_id, tokens, tags, self_tags, self_note, mode, status)
  VALUES (v_uid, v_clean, v_tags, v_self, v_note,
          CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
          'pending');

  RETURN jsonb_build_object('matched', false);
END;
$function$;
