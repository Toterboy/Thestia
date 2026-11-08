-- Migration 200: eine Benachrichtigung pro Ereignis
--
-- BEFUND (08.11.2026, Betreiber): "Keine doppelten Benachrichtigungen
-- fuer das Selbe."
--
-- DIE URSACHE (live gemessen, nicht vermutet):
-- `tool/measure_push_duplicates.sql` zaehlt die Push-Aufrufe, ohne dass
-- eine einzige Nachricht rausgeht (Transaktion + ROLLBACK). Vorher:
--
--   EIN Transit-Funke -> 4 Push-Aufrufe:
--     "Du hast ein neues Like!"  an A
--     "Du hast ein neues Like!"  an B
--     "Neuer Funke!"              an A
--     "Neuer Funke!"              an B
--
-- Beide Seiten bekamen also ZWEI Meldungen fuer EIN Ereignis - und die
-- Like-Meldung war inhaltlich falsch: im Radar wird kein Profil geliked,
-- sondern gefunkt.
--
-- Zusaetzlich doppelt: die App rief `notify-user` mit kind='likes' selbst
-- auf (QR-Scan, Zufallschat, gespeicherter Kontakt) - obwohl der
-- DB-Trigger den Like-Versand schon macht. Dazu kam der gegenseitige
-- Profil-Like: 4 Aufrufe (2x Like, 2x Funke).
--
-- DIE REGEL AB JETZT: Ein Ereignis, eine Meldung.
--
--   1. Ein technischer Transit-Like (kein Profil-Like) erzeugt KEINE
--      Meldung. Er ist ueber likes.source = 'transit' markiert.
--   2. Ein Like, aus dem ein Funke wird, erzeugt NUR die
--      Funke-Meldung. Der Match entsteht darum VOR dem Like-Insert.
--   3. Ein Soft-Ping, zu dem es schon einen Funke gibt, erzeugt KEINE
--      Meldung (der Ping bleibt fuer den Radar sichtbar).
--   4. `notify-user` lehnt Like-Pushes von Clients ab: der
--      Like-Versand ist Sache des Servers (der Trigger), sonst kommt
--      die Doppelmeldung zurueck.
--
-- Dazu ein Fund, der dabei auffiel: `notify_soft_ping_trigger` war seit
-- der Secret-Umbenennung (Migration 146) TOT - es suchte
-- 'wisp_internal_secret' (existiert nicht mehr) und schickte den
-- alten Header 'x-wisp-internal'. Der manuelle "Zuzwinken" hat darum
-- seit dem 06.11.2026 keine Meldung mehr erzeugt.
--
-- NACHWEIS: `python tool/check_push_duplicates.py` (misst live) und
-- `tool/measure_push_duplicates.sql` (manuell).

BEGIN;

-- =========================================================================
-- 1) Die Spalte source: 'profile' = echter Profil-Like, 'transit' =
--    technischer Like aus dem Radar (kein Profil geliked).
-- =========================================================================

ALTER TABLE public.likes
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'profile';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'likes_source_check'
  ) THEN
    ALTER TABLE public.likes
      ADD CONSTRAINT likes_source_check
      CHECK (source IN ('profile', 'transit'));
  END IF;
END;
$$;

-- =========================================================================
-- 2) Der Like-Trigger: nur echte Profil-Likes, und nur solange kein
--    Funke daraus entstanden ist.
-- =========================================================================

CREATE OR REPLACE FUNCTION public.notify_push_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_url text;
  v_secret text := NULL;
BEGIN
  -- Secret aus Vault lesen. Falls Vault/das Secret fehlt, wird KEIN Push
  -- versendet (fail-closed fuer das Feature, sicher gegen Missbrauch).
  BEGIN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'thestia_internal_secret'
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'notify_push_trigger: Secret thestia_internal_secret fehlt in Vault - kein Push-Versand.';
    RETURN NEW;
  END IF;

  v_url := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/notify-user';

  IF TG_TABLE_NAME = 'matches' THEN
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-thestia-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'matches',
        'target_user_id', NEW.user_one_id,
        'title', 'Neuer Funke!',
        'body', 'Du hast einen neuen Funken - schau in deine Funken!'
      )
    );
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-thestia-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'matches',
        'target_user_id', NEW.user_two_id,
        'title', 'Neuer Funke!',
        'body', 'Du hast einen neuen Funken - schau in deine Funken!'
      )
    );
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'likes' THEN
    -- BEFUND (08.11.2026, Betreiber): "Keine doppelten Benachrichtigungen
    -- fuer das Selbe." Live gemessen: EIN Transit-Funke erzeugte 4
    -- Push-Aufrufe - beide Seiten bekamen je zwei Meldungen
    -- ("Du hast ein neues Like!" und "Neuer Funke!"). Live gemessen
    -- mit tool/measure_push_duplicates.sql.
    --
    -- REGEL 1: Nur echte Profil-Likes erzeugen eine Meldung. Der
    -- Transit-Weg legt Like-Zeilen an, die KEIN Profil-Like sind (es
    -- wurde kein Profil geliked, sondern im Radar gefunkt). Die sind
    -- ueber likes.source = 'transit' markiert.
    IF NEW.source IS DISTINCT FROM 'profile' THEN
      RETURN NEW;
    END IF;

    -- REGEL 2: Ist aus dem Like schon ein Funke geworden, informiert
    -- der Funke-Push (matches) beide Seiten. Der Like-Push waere dann
    -- die zweite Meldung fuer dasselbe Ereignis.
    IF EXISTS (
      SELECT 1 FROM public.matches m
       WHERE (m.user_one_id = NEW.user_id AND m.user_two_id = NEW.liked_user_id)
          OR (m.user_two_id = NEW.user_id AND m.user_one_id = NEW.liked_user_id)
    ) THEN
      RETURN NEW;
    END IF;

    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-thestia-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'likes',
        'target_user_id', NEW.liked_user_id,
        'title', 'Thestia',
        'body', 'Jemand hat deine Vorstellung entdeckt.'
      )
    );
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

-- =========================================================================
-- 3) Der Soft-Ping-Trigger: Secret/Header repariert (Migration 146 hat
--    beide umgestellt, diese Funktion nicht) und kein Push, wenn es
--    schon einen Funke gibt.
-- =========================================================================

CREATE OR REPLACE FUNCTION public.notify_soft_ping_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_secret text := NULL;
BEGIN
  -- BEFUND (08.11.2026): Diese Funktion suchte das Secret
  -- 'wisp_internal_secret' und schickte den Header 'x-wisp-internal'.
  -- Beides wurde in Migration 146 auf 'thestia_internal_secret' bzw.
  -- 'x-thestia-internal' umgestellt - diese Funktion wurde aber nicht
  -- mitgezogen. Sie suchte also ein Secret, das es nicht mehr gibt
  -- (fail-closed: kein Push) und haette selbst mit Secret den Push
  -- abgelehnt bekommen (401).
  BEGIN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'thestia_internal_secret'
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;
  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'notify_soft_ping_trigger: Secret thestia_internal_secret fehlt in Vault - kein Push.';
    RETURN NEW;
  END IF;

  -- BEFUND (08.11.2026): Legt der Transit-Pfad einen Soft-Ping an, ist
  -- im selben Vorgang ein FUNKE entstanden. Der Funke-Push informiert
  -- dann beide Seiten - der Ping-Push waere die zweite Meldung fuer
  -- dasselbe Ereignis. Der Ping bleibt (er macht den Funke im Radar
  -- sichtbar), nur die Meldung entfaellt.
  IF EXISTS (
    SELECT 1 FROM public.matches m
     WHERE (m.user_one_id = NEW.sender AND m.user_two_id = NEW.recipient)
        OR (m.user_two_id = NEW.sender AND m.user_one_id = NEW.recipient)
  ) THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/notify-user',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-thestia-internal', v_secret
    ),
    body := jsonb_build_object(
      'kind', 'soft_ping',
      'target_user_id', NEW.recipient,
      'title', 'Transit Spark',
      'body', 'Jemand hat dir nach einer Begegnung gegruesst. Schau in dein Radar.'
    )
  );
  RETURN NEW;
END;
$$;

-- =========================================================================
-- 4) match_proximity_spark (Variante 1 von 2): die technischen
--    Transit-Likes werden als solche markiert.
-- =========================================================================

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

-- =========================================================================
-- 4) match_proximity_spark (Variante 2 von 2): die technischen
--    Transit-Likes werden als solche markiert.
-- =========================================================================

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

-- =========================================================================
-- 5) accept_soft_ping: derselbe Fall - der Ping-Annahme entsteht ein
--    Funke, der Like ist technisch.
-- =========================================================================

CREATE OR REPLACE FUNCTION public.accept_soft_ping(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sender uuid;
  v_match_id bigint;
BEGIN
  SELECT sender INTO v_sender
    FROM public.transit_soft_pings
   WHERE id = p_id
     AND recipient = v_uid
     AND status = 'pending'
     AND expires_at > now();

  IF v_sender IS NULL THEN
    RAISE EXCEPTION 'Ping nicht mehr gueltig';
  END IF;

  -- Blockier-Schutz.
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker = v_uid AND b.blocked = v_sender)
        OR (b.blocker = v_sender AND b.blocked = v_uid)
  ) THEN
    RAISE EXCEPTION 'Nicht moeglich.';
  END IF;

  UPDATE public.transit_soft_pings
     SET status = 'accepted'
   WHERE id = p_id;

  -- Gegenseitige Likes anlegen (neue Beziehung).
  -- Technische Transit-Likes (kein Profil-Like) - siehe
  -- notify_push_trigger: sie erzeugen KEINE "Du hast ein neues Like!".
  INSERT INTO public.likes (user_id, liked_user_id, source)
  VALUES (v_uid, v_sender, 'transit'), (v_sender, v_uid, 'transit')
  ON CONFLICT (user_id, liked_user_id) DO NOTHING;
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
  VALUES (least(v_uid, v_sender), greatest(v_uid, v_sender))
  ON CONFLICT (user_one_id, user_two_id) DO NOTHING;

  -- BESTEHENDEN gekühlten Funken reaktivieren (Fix: "Funke verschwindet
  -- bei Annahme"). Der Funke kommt sofort wieder in die aktive Liste,
  -- ohne dass eine neue Session nötig ist.
  UPDATE public.matches
     SET status = 'active',
         resparked_at = now()
   WHERE status = 'cooled'
     AND ((user_one_id = v_uid AND user_two_id = v_sender)
       OR (user_one_id = v_sender AND user_two_id = v_uid));

  RETURN jsonb_build_object('matched', true, 'partner', v_sender,
    'match_id', (SELECT id FROM public.matches
       WHERE user_one_id = least(v_uid, v_sender)
         AND user_two_id = greatest(v_uid, v_sender)));
END;
$$;

-- =========================================================================
-- 6) like_user: der Match entsteht vor dem eigenen Like.
-- =========================================================================

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

    -- Der eigene Like kommt JETZT (nach dem Match). Dadurch sieht der
    -- Like-Trigger (notify_push_trigger), dass es schon einen Funke
    -- gibt, und schickt KEINE zusaetzliche "Du hast ein neues Like!"-
    -- Meldung - der Funke-Push informiert beide Seiten.
    --
    -- BEFUND (08.11.2026, Betreiber): "Keine doppelten Benachrichtigungen
    -- fuer das Selbe." Live gemessen: der gegenseitige Like erzeugte 4
    -- Push-Aufrufe (2x Like, 2x Funke) - jetzt sind es 2 (je einer pro
    -- Seite, plus der Like, den die Gegenseite schon bekommen hat).
    INSERT INTO public.likes (user_id, liked_user_id, status)
    VALUES (v_user, p_target, 'pending')
    ON CONFLICT (user_id, liked_user_id) DO UPDATE
      SET status = 'pending', responded_at = NULL;

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

  INSERT INTO public.likes (user_id, liked_user_id, status)
  VALUES (v_user, p_target, 'pending')
  ON CONFLICT (user_id, liked_user_id) DO UPDATE
    SET status = 'pending', responded_at = NULL;

  RETURN jsonb_build_object(
    'is_match', false,
    'already_matched', false,
    'match_id', null
  );
END;
$$;

-- =========================================================================
-- 7) create_match_if_mutual: derselbe Fall.
-- =========================================================================

CREATE OR REPLACE FUNCTION public.create_match_if_mutual(p_liked_user_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_existing_like boolean := false;
  v_match_id bigint;
  v_user_one uuid;
  v_user_two uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF v_user_id = p_liked_user_id THEN
    RAISE EXCEPTION 'self_like_not_allowed';
  END IF;

  IF NOT public.consume_rate_limit(
    'likes_hourly:' || v_user_id::text, 30, 3600) THEN
    RAISE EXCEPTION 'like_rate_limited_hourly';
  END IF;
  IF NOT public.consume_rate_limit(
    'likes_daily:' || v_user_id::text, 100, 86400) THEN
    RAISE EXCEPTION 'like_rate_limited_daily';
  END IF;

  -- Alters-Schutz (Audit K-1).
  PERFORM public.assert_age_compatible(v_user_id, p_liked_user_id);

  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
    WHERE (b.blocker = v_user_id AND b.blocked = p_liked_user_id)
       OR (b.blocker = p_liked_user_id AND b.blocked = v_user_id)
  ) THEN
    RAISE EXCEPTION 'blocked';
  END IF;

  -- Der Match entsteht VOR dem eigenen Like (BEFUND 08.11.2026: keine
  -- doppelten Benachrichtigungen fuer das Selbe). Dadurch sieht der
  -- Like-Trigger, dass es schon einen Funke gibt, und schickt keine
  -- zweite Meldung. Die Pruefung auf den gegenseitigen Like ist von
  -- der eigenen Like-Zeile unabhaengig - die Reihenfolge aendert also
  -- nichts am Ergebnis.
  SELECT EXISTS(
    SELECT 1 FROM public.likes
    WHERE user_id = p_liked_user_id AND liked_user_id = v_user_id
  ) INTO v_existing_like;

  IF v_existing_like THEN
    v_user_one := least(v_user_id, p_liked_user_id);
    v_user_two := greatest(v_user_id, p_liked_user_id);

    INSERT INTO public.matches (user_one_id, user_two_id)
    VALUES (v_user_one, v_user_two)
    ON CONFLICT (user_one_id, user_two_id) DO NOTHING
    RETURNING id INTO v_match_id;

    IF v_match_id IS NULL THEN
      SELECT id INTO v_match_id
      FROM public.matches
      WHERE user_one_id = v_user_one AND user_two_id = v_user_two;
    END IF;

    INSERT INTO public.likes (user_id, liked_user_id)
    VALUES (v_user_id, p_liked_user_id)
    ON CONFLICT (user_id, liked_user_id) DO NOTHING;

    RETURN json_build_object('is_match', true, 'match_id', v_match_id);
  END IF;

  INSERT INTO public.likes (user_id, liked_user_id)
  VALUES (v_user_id, p_liked_user_id)
  ON CONFLICT (user_id, liked_user_id) DO NOTHING;

  RETURN json_build_object('is_match', false, 'match_id', null);
END;
$$;

COMMIT;
