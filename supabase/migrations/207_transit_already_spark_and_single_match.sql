-- =============================================================================
-- 207_transit_already_spark_and_single_match.sql
-- =============================================================================
-- TRANSIT SPARK (BEFUND 09.11.2026, Betreiber):
--
-- 1) "Wenn man bei Transit Spark schon die Person als Funken hat, soll
--     darauf hingewiesen werden."
--
--    DER GRUND (live geprueft): Bei einem Transit-Treffer legt der
--    Server IMMER Likes in beide Richtungen an und macht daraus ueber
--    den Mutual-Like-Trigger einen Match:
--
--      INSERT INTO public.likes (user_id, liked_user_id, source) ...
--      INSERT INTO public.matches (user_one_id, user_two_id) ...
--        ON CONFLICT (user_one_id, user_two_id) DO NOTHING;
--
--    Das "DO NOTHING" heisst: Ein bestehender Funke bleibt EINER. Der
--    Client bekam aber trotzdem 'matched: true' und zeigte den
--    Erfolgs-Dialog - der Nutzer wusste nicht, dass es dieselbe Person
--    wie vorher war.
--
--    JETZT: Das Ergebnis traegt 'alreadySpark'. Der Client weist darauf
--    hin ("Ihr habt schon einen Funken") statt den Erfolgs-Dialog zu
--    zeigen.
--
-- 2) "Was machen wir, wenn zwei Personen genau die selben eigenschaften
--     haben? Finde ich dann zwei Personen auf einmal? Da muss es eine
--     gute Regelung irgendwie geben."
--
--    DIE ANTWORT: NEIN - genau EINE Person pro Signal.
--
--    DER GRUND (live geprueft): Die Kandidatensuche hatte weder eine
--    Zeilensperre noch eine atomare Beanspruchung:
--
--      FOR v_other IN
--        SELECT ... WHERE s.status = 'pending' ... ORDER BY s.created_at DESC LIMIT 1
--      LOOP
--        UPDATE public.transit_signals SET status = 'matched' ...
--
--    Zwei gleichzeitige Aufrufe konnten DIESELBE Zeile sehen und
--    BEIDE sie beanspruchen: die erste UPDATE-Anweisung gewinnt, die
--    zweite schreibt trotzdem ihren Match. Ergebnis: die Person bekam
--    ZWEI Funken - genau die Frage des Betreibers.
--
--    DIE REGEL (jetzt durchgesetzt):
--    (a) `FOR UPDATE OF s SKIP LOCKED` - die Zeile wird beim Lesen
--        gesperrt. Ein zweiter Aufruf ueberspringt sie (SKIP LOCKED)
--        und nimmt den naechsten Kandidaten.
--    (b) Die Beanspruchung ist bedingt: `WHERE id = ... AND status =
--        'pending'`. Wer nicht mehr zuerst war, bekommt die Zeile
--        nicht - der Treffer wird verworfen, statt doppelt zu zuschlagen.
--    (c) `ORDER BY s.created_at DESC, s.id` - bei zwei Personen mit
--        GLEICHEN Eigenschaften ist die Auswahl damit eindeutig
--        (sonst entschied die Zeilenreihenfolge des Plans).
--    (d) Ein bereits vorhandener Funke wird nicht doppelt erzeugt,
--        sondern gemeldet (alreadySpark).
--
--    Die Definitionen sind programmatisch aus der LIVE-Fassung
--    abgeleitet (pg_get_functiondef) - so weicht die Migration nicht
--    ungewollt vom Server-Stand ab.
-- =============================================================================

begin;
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
  -- BEFUND (09.11.2026): True, wenn mit der gefundenen Person
  -- BEREITS ein Funke bestand. Wird VOR dem Match-INSERT geprueft.
  v_already_spark boolean;
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
      -- Eindeutige Reihenfolge (BEFUND 09.11.2026): Bei zwei Personen
      -- mit GLEICHEN Eigenschaften entschied sonst die Zeilenreihenfolge
      -- des Plans. Mit s.id als zweitem Schluessel ist die Auswahl
      -- deterministisch - und immer dieselbe Person.
      ORDER BY s.created_at DESC, s.id
      LIMIT 1
      -- DIE SPERRE (BEFUND 09.11.2026): Ohne sie konnten zwei
      -- gleichzeitige Aufrufe DIESELBE Person beanspruchen - sie
      -- bekam dann zwei Funken. SKIP LOCKED ueberspringt gesperrte
      -- Zeilen: der zweite Aufruf nimmt den naechsten Kandidaten.
      FOR UPDATE OF s SKIP LOCKED
  LOOP
    -- DIE BEANSPRUCHUNG (BEFUND 09.11.2026): Sie ist BEDINGT - nur wer
    -- zuerst war, bekommt die Person. Wer zu spaet kommt, greift ins
    -- Leere (die Zeile ist dann nicht mehr 'pending') und der Treffer
    -- wird verworfen - statt einen zweiten Funken zu erzeugen.
    UPDATE public.transit_signals
       SET status = 'matched', matched_with = v_other.user_id
     WHERE id = v_other.id
       AND status = 'pending';

    -- BEFUND (09.11.2026): Gab es mit dieser Person SCHON einen
    -- Funke? Das wird VOR dem Match-INSERT festgehalten - der
    -- Nutzer soll erfahren, dass es dieselbe Person ist.
    SELECT EXISTS (
      SELECT 1 FROM public.matches m
       WHERE (m.user_one_id = least(v_uid, v_other.user_id)
              AND m.user_two_id = greatest(v_uid, v_other.user_id))
          OR (m.user_one_id = greatest(v_uid, v_other.user_id)
              AND m.user_two_id = least(v_uid, v_other.user_id))
    ) INTO v_already_spark;
    INSERT INTO public.transit_signals
      (user_id, tokens, tags, self_tags, self_note, mode, status, matched_with, created_at, self_token)
    VALUES (v_uid, v_clean, v_tags, v_self, v_note,
            CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
            'matched', v_other.user_id, now(), v_self_token);
    INSERT INTO public.likes (user_id, liked_user_id, source)
    VALUES (v_uid, v_other.user_id, 'transit'), (v_other.user_id, v_uid, 'transit') ON CONFLICT DO NOTHING;
    -- DER MATCH (BEFUND 07.11.2026: "Der Funke entsteht, aber es ist
    -- nichts sichtbar."): Ein Match entsteht ausschliesslich durch einen
    -- INSERT in public.matches - den macht nur create_match_if_mutual.
    -- Diese Funktionen legen aber nur LIKES an; die App liest ihre
    -- Chatliste aus public.matches. Ohne diese Zeile bleibt der Funke
    -- fuer beide unsichtbar.
    --
    -- Dieselben Regeln wie create_match_if_mutual: ON CONFLICT DO NOTHING
    -- (es bleibt EIN Match je Paar), und die Reihenfolge ist dieselbe
    -- (least/greatest), damit der Unique-Index greift.
    INSERT INTO public.matches (user_one_id, user_two_id)
    VALUES (least(v_uid, v_other.user_id), greatest(v_uid, v_other.user_id))
    ON CONFLICT (user_one_id, user_two_id) DO NOTHING;

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
    'partnerNote', v_other.self_note,
    -- BEFUND (09.11.2026): Gab es den Funke schon? Dann ist es kein
    -- NEUER Funke - der Client weist darauf hin.
    'alreadySpark', coalesce(v_already_spark, false),
    'match_id', (SELECT id FROM public.matches
       WHERE user_one_id = least(v_uid, v_other.user_id)
         AND user_two_id = greatest(v_uid, v_other.user_id)));
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
CREATE OR REPLACE FUNCTION public.match_proximity_spark(p_tokens text[], p_tags text[] DEFAULT '{}'::text[], p_mode text DEFAULT 'transit'::text, p_self_tags text[] DEFAULT '{}'::text[], p_self_note text DEFAULT NULL::text)
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
  v_cutoff timestamptz := now() - interval '45 minutes';
  v_other record;
  -- BEFUND (09.11.2026): True, wenn mit der gefundenen Person
  -- BEREITS ein Funke bestand. Wird VOR dem Match-INSERT geprueft.
  v_already_spark boolean;
  -- Erlaubte Merkmale aus dem Katalog (v0.10.0, Migration 148/149).
  --
  -- BISHER stand hier ein hart codiertes Array mit 15 Slugs, das in
  -- SIEBEN Migrationen als Volltextkopie dupliziert war. Mit Kategorien
  -- und eigenen Haar-/Augenfarben waere die Liste auf ueber 600
  -- Eintraege angewachsen - als Array im Quelltext nicht mehr
  -- wartbar.
  --
  -- Die Tabelle public.transit_tag_catalog ist die einzige Quelle.
  -- Ein neuer Wert braucht damit EINE Zeile in der Katalog-Migration
  -- statt einer achten Volltextkopie der RPC.
  --
  -- 'slug:farbe' entsteht aus dem Katalog: fuer jeden farbfaehigen
  -- Wert jede Farbe seiner Palette.
  v_allowed text[];
  v_base text;
  v_color text;
BEGIN
  -- Erlaubte Merkmale aus dem Katalog (v0.10.0, Migration 148/149).
  --
  -- BISHER stand hier ein hart codiertes Array mit 15 Slugs, das in
  -- SIEBEN Migrationen als Volltextkopie dupliziert war. Mit Kategorien
  -- und eigenen Haar- und Augenfarben waere die Liste auf ueber 600
  -- Eintraege gewachsen - als Quelltext-Array nicht mehr wartbar.
  --
  -- Die Tabelle public.transit_tag_catalog ist die einzige Quelle.
  -- Ein neuer Wert braucht damit EINE Zeile in der Katalog-Migration
  -- statt einer achten Volltextkopie der RPC.
  --
  -- 'slug:farbe' entsteht aus dem Katalog: fuer jeden farbfaehigen
  -- Wert jede Farbe seiner Palette.
  --
  -- ZUSAMMENFASSUNG per ARRAY(...), bewusst OHNE "SELECT ... INTO" und
  -- ausserhalb des DECLARE-Blocks. PL/pgSQL parst
  -- "SELECT <ausdruck> INTO <variable> FROM (Subquery)" fehlerhaft und
  -- meldet je nach Form "invalid type name array_agg(...) INTO ..." oder
  -- "syntax error at or near INTO". ARRAY(<Unterabfrage>) ist ein
  -- reiner Ausdruck und umgeht die Zuordnungs-Sonderregel komplett.
  v_allowed := ARRAY(
    SELECT DISTINCT u.t
      FROM (
        SELECT c.slug AS t
          FROM public.transit_tag_catalog c
        UNION
        SELECT c.slug || ':' || col AS t
          FROM public.transit_tag_catalog c
          CROSS JOIN LATERAL unnest(c.allowed_colors) AS col
      ) u
     WHERE u.t IS NOT NULL
  );
  v_allowed := coalesce(v_allowed, '{}'::text[]);

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE user_id = v_uid;
  IF v_me.user_id IS NULL THEN
    RAISE EXCEPTION 'Kein Profil';
  END IF;

  -- Minderjaehrige / Profil ohne Geburtsdatum: kein Matching.
  IF NOT public.transit_spark_adult(v_uid) THEN
    RAISE EXCEPTION 'transit_age_restricted: Transit Spark ist nur ab 18 Jahren nutzbar.';
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


  SELECT array_agg(DISTINCT t) INTO v_tags
    FROM unnest(COALESCE(p_tags, '{}'::text[])) AS t
   WHERE t = ANY (v_allowed);
  -- Grenzen (v0.10.0, Migration 148/149): hoechstens 1 Wert je
  -- Kategorie und insgesamt hoechstens 8. Vorher 2-5 ohne
  -- Kategoriegrenze - mit den neuen Werten (Haarfarbe UND Haarlaenge
  -- UND Augenfarbe) waere 5 zu eng.
  IF v_tags IS NULL OR array_length(v_tags, 1) IS NULL
     OR array_length(v_tags, 1) < 2
     OR array_length(v_tags, 1) > 8 THEN
    RAISE EXCEPTION 'Bitte 2-8 Merkmale waehlen';
  END IF;

  -- Hoechstens ein Wert je Kategorie. Sonst koennte jemand "Hemd" UND
  -- "Bluse" waehlen - das ist keine Angabe mehr, sondern Unsinn, und
  -- es verwischt die Aussage fuer die andere Person.
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
    FROM unnest(COALESCE(p_self_tags, '{}'::text[])) AS t
   WHERE t = ANY (v_allowed);
  IF array_length(coalesce(v_self, '{}'::text[]), 1) > 8 THEN
    RAISE EXCEPTION 'Bitte maximal 8 Merkmale zu dir selbst waehlen';
  END IF;

  -- Auch bei der Selbstbeschreibung: ein Wert je Kategorie.
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

  -- Freie Ergaenzung: sanitisieren (Steuerzeichen raus, max. 140).
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
       -- Transit Spark ausschliesslich zwischen Volljaehrigen:
       -- die gefundene Person muss selbst 18+ sein. age_compatible
       -- allein reicht nicht, das 2-Jahres-Band wuerde sonst auch
       -- 16-Jaehrige zulassen.
       AND public.transit_spark_adult(s.user_id)
       AND public.age_compatible(
             (SELECT public.profile_age(me.birth_date)
                FROM public.profiles me
               WHERE me.user_id = v_uid),
             date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int)
       AND NOT EXISTS (
             SELECT 1 FROM public.blocked_users b
              WHERE (b.blocker = v_uid AND b.blocked = s.user_id)
                 OR (b.blocker = s.user_id AND b.blocked = v_uid))
     -- Eindeutige Reihenfolge (BEFUND 09.11.2026): Bei zwei Personen
     -- mit GLEICHEN Eigenschaften entschied sonst die Zeilenreihenfolge
     -- des Plans. Mit s.id als zweitem Schluessel ist die Auswahl
     -- deterministisch - und immer dieselbe Person.
     ORDER BY s.created_at DESC, s.id
     LIMIT 1
     -- DIE SPERRE (BEFUND 09.11.2026): Ohne sie konnten zwei
     -- gleichzeitige Aufrufe DIESELBE Person beanspruchen - sie
     -- bekam dann zwei Funken. SKIP LOCKED ueberspringt gesperrte
     -- Zeilen: der zweite Aufruf nimmt den naechsten Kandidaten.
     FOR UPDATE OF s SKIP LOCKED
  LOOP
    -- DIE BEANSPRUCHUNG (BEFUND 09.11.2026): Sie ist BEDINGT - nur wer
    -- zuerst war, bekommt die Person. Wer zu spaet kommt, greift ins
    -- Leere (die Zeile ist dann nicht mehr 'pending') und der Treffer
    -- wird verworfen - statt einen zweiten Funken zu erzeugen.
    UPDATE public.transit_signals
       SET status = 'matched', matched_with = v_other.user_id
     WHERE id = v_other.id
       AND status = 'pending';

    -- BEFUND (09.11.2026): Gab es mit dieser Person SCHON einen
    -- Funke? Das wird VOR dem Match-INSERT festgehalten - der
    -- Nutzer soll erfahren, dass es dieselbe Person ist.
    SELECT EXISTS (
      SELECT 1 FROM public.matches m
       WHERE (m.user_one_id = least(v_uid, v_other.user_id)
              AND m.user_two_id = greatest(v_uid, v_other.user_id))
          OR (m.user_one_id = greatest(v_uid, v_other.user_id)
              AND m.user_two_id = least(v_uid, v_other.user_id))
    ) INTO v_already_spark;
    INSERT INTO public.transit_signals
      (user_id, tokens, tags, self_tags, self_note, mode, status, matched_with, created_at)
    VALUES (v_uid, v_clean, v_tags, v_self, v_note,
            CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
            'matched', v_other.user_id, now());

    INSERT INTO public.likes (user_id, liked_user_id, source)
    VALUES (v_uid, v_other.user_id, 'transit'), (v_other.user_id, v_uid, 'transit') ON CONFLICT DO NOTHING;
    -- DER MATCH (BEFUND 07.11.2026: "Der Funke entsteht, aber es ist
    -- nichts sichtbar."): Ein Match entsteht ausschliesslich durch einen
    -- INSERT in public.matches - den macht nur create_match_if_mutual.
    -- Diese Funktionen legen aber nur LIKES an; die App liest ihre
    -- Chatliste aus public.matches. Ohne diese Zeile bleibt der Funke
    -- fuer beide unsichtbar.
    --
    -- Dieselben Regeln wie create_match_if_mutual: ON CONFLICT DO NOTHING
    -- (es bleibt EIN Match je Paar), und die Reihenfolge ist dieselbe
    -- (least/greatest), damit der Unique-Index greift.
    INSERT INTO public.matches (user_one_id, user_two_id)
    VALUES (least(v_uid, v_other.user_id), greatest(v_uid, v_other.user_id))
    ON CONFLICT (user_one_id, user_two_id) DO NOTHING;

    -- BEFUND (07.11.2026, Betreiber): "Der Funke entsteht, aber es ist
    -- nichts sichtbar." Die Paarung meldete den Treffer nur dem
    -- Absender. Fuer die GEGENSEITE entsteht dadurch kein sichtbarer
    -- Eintrag: kein Soft-Ping, keine Meldung.
    --
    -- Migration 191 hat das fuer die aktuelle Fassung (mit dem
    -- eigenen Token) behoben. Diese hier ist der Legacy-Stand fuer
    -- aeltere Clients - sie muss sich genauso verhalten, sonst
    -- sieht die Gegenseite nichts, wenn ein aelterer Client funkt.
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

    RETURN jsonb_build_object(
      'matched', true,
      'partner', v_other.user_id,
      'partnerNote', v_other.self_note,
      -- BEFUND (09.11.2026): Gab es den Funke schon? Dann ist es kein
      -- NEUER Funke - der Client weist darauf hin.
      'alreadySpark', coalesce(v_already_spark, false)
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
$$;

-- -----------------------------------------------------------------------------
-- 4) Die Rechte bleiben erhalten (wie live geprueft):
--    {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
-- -----------------------------------------------------------------------------
revoke all on function public.match_proximity_spark(text[], text[], text, text[], text, text) from public, anon;
grant execute on function public.match_proximity_spark(text[], text[], text, text[], text, text) to authenticated, service_role;

revoke all on function public.match_proximity_spark(text[], text[], text, text[], text) from public, anon;
grant execute on function public.match_proximity_spark(text[], text[], text, text[], text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast): Die neuen Regeln muessen wirklich drinstehen.
-- -----------------------------------------------------------------------------
do $$
declare
  v_src text;
  v_anzahl int;
begin
  -- Beide Ueberladungen pruefen.
  for v_anzahl in 1..2 loop
    select p.prosrc into v_src
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'match_proximity_spark'
     order by length(pg_get_function_identity_arguments(p.oid)) desc
     limit 1
     offset (v_anzahl - 1);

    if v_src is null then
      raise exception
        'Sicherheitscheck fehlgeschlagen: match_proximity_spark (Variante %) fehlt.', v_anzahl;
    end if;

    -- (a) Das Ergebnis meldet den bestehenden Funke.
    if v_src not like '%alreadySpark%' then
      raise exception
        'Sicherheitscheck fehlgeschlagen: match_proximity_spark (Variante %) meldet kein alreadySpark - der Nutzer wuerde nicht erfahren, dass es die gleiche Person ist.', v_anzahl;
    end if;

    -- (b) Die Kandidatensuche sperrt die Zeile (kein Doppelzugriff).
    if v_src !~* 'for\s+update\s+of\s+s\s+skip\s+locked' then
      raise exception
        'Sicherheitscheck fehlgeschlagen: match_proximity_spark (Variante %) sperrt die Kandidatenzeile nicht - zwei gleichzeitige Aufrufe koennten dieselbe Person beanspruchen.', v_anzahl;
    end if;

    -- (c) Die Beanspruchung ist bedingt (nur noch 'pending').
    if v_src !~* 'and\s+status\s*=\s*''pending''' then
      raise exception
        'Sicherheitscheck fehlgeschlagen: match_proximity_spark (Variante %) beansprucht das Signal nicht bedingt - ein zweiter Aufruf wuerde trotzdem zuschlagen.', v_anzahl;
    end if;

    -- (d) Die Reihenfolge ist eindeutig (gleiche Eigenschaften -> gleiche Person).
    if v_src !~* 'order\s+by\s+s\.created_at\s+desc,\s*s\.id' then
      raise exception
        'Sicherheitscheck fehlgeschlagen: match_proximity_spark (Variante %) hat keine eindeutige Reihenfolge - bei gleichen Eigenschaften waere die Auswahl vom Zufall abhaengig.', v_anzahl;
    end if;

    -- (e) Die Altersgrenze (18+) und der Blockierschutz bleiben erhalten.
    if v_src not like '%transit_spark_adult%' then
      raise exception
        'Sicherheitscheck fehlgeschlagen: match_proximity_spark (Variante %) verliert das 18+-Gate.', v_anzahl;
    end if;
    if v_src not like '%blocked_users%' then
      raise exception
        'Sicherheitscheck fehlgeschlagen: match_proximity_spark (Variante %) verliert den Blockierschutz.', v_anzahl;
    end if;
  end loop;
end;
$$;

commit;
