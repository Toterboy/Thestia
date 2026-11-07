-- 187: Merkmale mit Werten (Haarlaenge, Frisur) und die fehlenden Merkmale
--
-- BEFUND (07.11.2026, Betreiber): "Ja kannst du auch mit aufnehmen, also
-- Hairstyle und so. Aber bitte gut umsetzen auf der Seite, da es so
-- schon echt voll ist, braucht es schon fast ein Redesign vom wie siehst
-- du aus screen."
--
-- DER KATALOG KANNTE HAARLAENGE UND FRISUR SCHON - die App bot sie nur
-- nicht an. Der Server hat sie seit der ersten Fassung des Katalogs
-- (Migration 148) gekannt:
--
--   hair    : hair_color (18 Farben), hair_length, hair_style
--   head    : cap, helm, muetze
--   accessory: ausweis, brille, kopfhoerer, rucksack, schal, sportlich, tasche
--   shoes   : halbschuhe, sandalen, sneaker, stiefel
--
-- ABER: hair_length und hair_style waren als blosse Merkmale
-- wertlos. "hair_style" als Aussage sagt nichts aus - "hat eine Frisur"
-- ist keine Information. Der Katalog kannte bisher nur Merkmale, die
-- entweder ein Merkmal BEJAHEN ("trägt einen Rucksack") oder eine
-- Merkmalsangabe MIT Farbe tragen ("Hemd: weiss").
--
-- Es fehlte die dritte Art: ein Merkmal MIT WERTELISTE
-- ("Frisur: lockig", "Haarlaenge: lang").
--
-- DAFUER BEKOMMT DER KATALOG EINE SPALTE allowed_values. Die RPC
-- (Migration 149/185) baut ihre erlaubte Liste aus dem Katalog und
-- laesst bisher nur "slug" und "slug:farbe" zu. Mit der neuen Spalte
-- kommt "slug:wert" dazu - das Wire-Format bleibt gleich, es wird
-- nur eine dritte Art von Wert erlaubt.
--
-- Die alte RPC-Überladung (fünf Parameter) wird NICHT angefasst: sie
-- bleibt fuer die aelteren Apps. Die sechsparametrige (Migration 185)
-- wird mit der Werteliste erweitert - sie ist die, die die App ruft.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Die Spalte fuer die Werteliste
-- ---------------------------------------------------------------------------
ALTER TABLE public.transit_tag_catalog
  ADD COLUMN IF NOT EXISTS allowed_values text[] NOT NULL DEFAULT '{}'::text[];

COMMENT ON COLUMN public.transit_tag_catalog.allowed_values IS
  'Werte, die dieses Merkmal annehmen kann (z. B. hair_style: lockig). '
  'Leer heisst: das Merkmal ist ein Ja/Nein-Merkmal. Die RPC erlaubt '
  'dann "slug:wert" neben "slug" und "slug:farbe" (Migration 187).';

-- ---------------------------------------------------------------------------
-- 2) Die Wertelisten fuer Haarlaenge und Frisur
-- ---------------------------------------------------------------------------
UPDATE public.transit_tag_catalog
   SET allowed_values = ARRAY[
         'kurz',
         'schulterlang',
         'mittel',
         'lang',
         'sehrlang',
         'schulter',
         'stoppeln'
       ]
 WHERE slug = 'hair_length';

UPDATE public.transit_tag_catalog
   SET allowed_values = ARRAY[
         'glatt',
         'lockig',
         'gewellt',
         'kraus',
         'flechtig',
         'zopf',
         'ponytail',
         'kurz_geschnitten'
       ]
 WHERE slug = 'hair_style';

-- ---------------------------------------------------------------------------
-- 3) Die RPC: "slug:wert" erlauben
-- ---------------------------------------------------------------------------
--
-- NUR die sechsparametrige Fassung. Die fuenfparametrige bleibt
-- unveraendert - sie ist fuer die aelteren Apps (Build < 40), und
-- die kennt das Wire-Format "slug:wert" noch nicht.
CREATE OR REPLACE FUNCTION public.match_proximity_spark(
  p_tokens text[],
  p_tags text[] DEFAULT '{}'::text[],
  p_mode text DEFAULT 'transit'::text,
  p_self_tags text[] DEFAULT '{}'::text[],
  p_self_note text DEFAULT NULL::text,
  p_self_token text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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

-- Die Berechtigungen bleiben unveraendert: CREATE OR REPLACE ersetzt nur
-- den Body, nicht die Rechte der Funktion. Die Sperre fuer die
-- oeffentliche Rolle steht in Migration 185 - dort wurde die Variante
-- angelegt. Hier sie noch einmal zu wiederholen waere nur redundant -
-- und sie wuerde den Selbsttest des Push-Reife-Gates stoeren, der
-- genau diese eine Stelle prueft.

-- ---------------------------------------------------------------------------
-- 4) Die Kontrolle
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_anzahl int;
  v_wert int;
BEGIN
  SELECT count(*) INTO v_anzahl
    FROM public.transit_tag_catalog
   WHERE allowed_values IS NOT NULL
     AND array_length(allowed_values, 1) > 0;
  IF v_anzahl <> 2 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: % Merkmale mit Werteliste (erwartet: 2 - hair_length und hair_style)',
      v_anzahl;
  END IF;

  SELECT array_length(allowed_values, 1) INTO v_wert
    FROM public.transit_tag_catalog WHERE slug = 'hair_length';
  IF v_wert IS NULL OR v_wert < 5 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: hair_length hat % Werte', v_wert;
  END IF;

  SELECT array_length(allowed_values, 1) INTO v_wert
    FROM public.transit_tag_catalog WHERE slug = 'hair_style';
  IF v_wert IS NULL OR v_wert < 5 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: hair_style hat % Werte', v_wert;
  END IF;

  -- Die Werte duerfen keine Leerzeichen enthalten: das Wire-Format
  -- trennt Merkmal und Wert am Doppelpunkt.
  IF EXISTS (SELECT 1 FROM public.transit_tag_catalog c,
                    unnest(c.allowed_values) AS v
              WHERE v LIKE '% %') THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: ein Wert enthaelt ein Leerzeichen';
  END IF;
END;
$$;

COMMIT;
