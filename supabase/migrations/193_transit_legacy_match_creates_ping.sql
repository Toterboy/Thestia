-- 193: die Legacy-Fassung der Transit-Paarung legt auch einen
--     Soft-Ping fuer die Gegenseite an
--
-- BEFUND (07.11.2026, Betreiber): "Der Funke entsteht, aber es ist
-- nichts sichtbar."
--
-- DIE URSACHE (beim Abschluss-Nachweis aufgefallen): Es gibt ZWEI
-- Ueberladungen von public.match_proximity_spark:
--
--   * match_proximity_spark(text[],text[],text,text[],text,text)
--     - die aktuelle Fassung (mit dem eigenen Token). Migration 191
--     hat ihr den Soft-Ping fuer die Gegenseite gegeben.
--
--   * match_proximity_spark(text[],text[],text,text[],text)
--     - der Legacy-Stand fuer Clients, die den eigenen Token noch
--     nicht schicken. DER HAT KEINEN SOFT-PING.
--
-- Funkt ein aelterer Client, entsteht der Match zwar, aber die
-- Gegenseite (aktuelle App) sieht nichts. Das Verhalten darf nicht
-- davon abhaengen, welche App-Version funk(t) - deshalb bekommen
-- beide Ueberladungen dasselbe.
--
-- Die Funktion ist die LIVE-Definition; geaendert wurde genau eine
-- Stelle (der Soft-Ping hinter den Likes).

BEGIN;

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
    VALUES (v_uid, v_other.user_id), (v_other.user_id, v_uid) ON CONFLICT DO NOTHING;

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
$$;
-- Die Kontrolle: BEIDE Ueberladungen muessen den Soft-Ping anlegen.
DO $$
DECLARE
  v_ohne int;
BEGIN
  SELECT count(*) INTO v_ohne
    FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'match_proximity_spark'
     AND p.prosrc NOT ILIKE '%insert into public.transit_soft_pings%';

  IF v_ohne > 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: % Ueberladung(en) der Transit-Paarung legen keinen Soft-Ping an - fuer die Gegenseite bleibt der Funke unsichtbar', v_ohne;
  END IF;
END;
$$;

COMMIT;
