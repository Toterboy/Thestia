-- =============================================================================
-- 213_transit_candidates_and_place.sql
-- =============================================================================
-- DER BETREIBER (11.11.2026): "Vielleicht kann man auch machen, dass wenn
-- es bei Transit Spark mehrere mit der selben Beschreibung geben sollte,
-- dass man dann alle dafuer vorgeschlagen bekommt und die Moeglichkeit hat
-- auch mehrere anzuschreiben. Man soll auch seinen ungefaehren Standort
-- angeben koennen, also wenn man im Zug ist z.B. Wagen 3 oder so oder wenn
-- man auf ner Messe ist z.B. Halle 2 und da dann vielleicht bei den
-- Toiletten oder Stand xy und so."
--
-- WAS BISHER PASSIERT (live geprueft): `match_proximity_spark` nimmt EINEN
-- Kandidaten (`LIMIT 1`) und legt sofort einen Funke an. Wer mehrere
-- Menschen mit derselben Beschreibung hat, sieht nur eine Person - und
-- die Liste der Nahen Menschen zeigt nur "vor X Minuten gesehen" ohne
-- jede Beschreibung.
--
-- DIE LOESUNG (dieser Block):
--
-- 1) **Die Ortsangabe** (`self_place_kind` / `self_place_text`): Der
--    Nutzer sagt, wo er ist - "Zug, Wagen 3" oder "Messe, Halle 2 bei den
--    Toiletten". Sie geht mit seinem Signal zum Server und steht bei den
--    Kandidaten dabei. Frei eingegeben, KEIN Standort (der Nutzer nennt
--    selbst nur, was er nennen will).
--
-- 2) **Die Kandidatenliste** (`list_transit_candidates`): Alle Personen
--    in der Naehe, deren Beschreibung zu meiner passt. Sie sind
--    pseudonym - der Name erscheint NUR, wenn die Person ihn freigegeben
--    hat (`transit_show_name`, Migration 208). Wer seinen Namen nicht
--    freigibt, ist trotzdem auffindbar - nur eben ohne Namen.
--
-- 3) **Mehrere anschreiben** (`send_soft_ping` mit `p_recipient`): Bisher
--    war der Empfaenger ueber den BLE-Token aufgeloest und der Ping auf
--    EINEN alle 30 Minuten begrenzt. Jetzt kann man mehrere Personen
--    anschreiben (bis 5 in 30 Minuten). Der Server prueft dabei IMMER
--    die Naehe: der Empfaenger muss ein frisches Signal mit passender
--    Beschreibung haben. Ein Ping an eine beliebige Person ist damit
--    nicht moeglich.
--
-- DIE FUNKTIONEN: `match_proximity_spark` bekommt zwei zusaetzliche
-- Parameter (mit Default - alte Aufrufe bleiben gueltig) und wird aus
-- der LIVE-Fassung abgeleitet. Die alte 5-Parameter-Variante wird
-- ENTFERNT: zwei Ueberladungen mit Default-Parametern machen den
-- PostgREST-Aufruf mehrdeutig (PGRST203) - die App wuerde dann auf
-- eine aeltere Variante zurueckfallen und der Ort ginge verloren.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Die Spalten: der Ort am Signal und am Zuwinken
-- -----------------------------------------------------------------------------
alter table public.transit_signals
  add column if not exists self_place_kind text,
  add column if not exists self_place_text text;

comment on column public.transit_signals.self_place_kind is
  'v0.10.1: Die Art des ungefaehren Ortes, den der Nutzer selbst nennt (z. B. "zug", "messe"). Frei gewaehlt - das ist KEIN Standort.';

comment on column public.transit_signals.self_place_text is
  'v0.10.1: Der ungefaehre Ort in den eigenen Worten (z. B. "Wagen 3", "Halle 2 bei den Toiletten"). Frei eingegeben - maximal 60 Zeichen.';

alter table public.transit_soft_pings
  add column if not exists place_kind text,
  add column if not exists place_text text;

comment on column public.transit_soft_pings.place_kind is
  'v0.10.1: Der Ort, den der Absender beim Zuwinken genannt hat.';

comment on column public.transit_soft_pings.place_text is
  'v0.10.1: Der Ort in den Worten des Absenders (z. B. "Wagen 3").';

-- Die alte 5-Parameter-Variante wird ENTFERNT: mit zwei
-- Ueberladungen und Default-Parametern wird der PostgREST-Aufruf
-- mehrdeutig (PGRST203) - die App wuerde auf eine aeltere
-- Variante zurueckfallen und der Ort ginge verloren.
-- BEFUND (11.11.2026, Push-Reife-Gate): Eine Signaturliste im DROP darf
-- KEINE Default-Werte enthalten - Postgres lehnt "DROP FUNCTION ... DEFAULT"
-- ab. Mit den Defaults waere die Migration beim Apply gescheitert und die
-- alte Variante waere geblieben (PGRST203: der Aufruf waere mehrdeutig).
drop function if exists public.match_proximity_spark(text[], text[], text, text[], text);
-- BEFUND (11.11.2026, Fail-Fast im Apply): AUCH die 6-Parameter-Variante
-- (mit p_self_token) muss weg. Ein CREATE OR REPLACE mit ANDERER Signatur
-- legt eine NEUE Funktion an - die alte bleibt stehen. Dann gibt es zwei
-- Varianten und der Aufruf der App ist mehrdeutig (PGRST203).
drop function if exists public.match_proximity_spark(text[], text[], text, text[], text, text);

CREATE OR REPLACE FUNCTION public.match_proximity_spark(p_tokens text[], p_tags text[] DEFAULT '{}'::text[], p_mode text DEFAULT 'transit'::text, p_self_tags text[] DEFAULT '{}'::text[], p_self_note text DEFAULT NULL::text, p_self_token text DEFAULT NULL::text, p_place_kind text DEFAULT NULL::text, p_place_text text DEFAULT NULL::text)
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
  -- BEFUND (11.11.2026): Der ungefaehre Ort, den der Nutzer SELBST nennt
  -- ("Zug, Wagen 3"). Frei eingegeben - das ist kein Standort.
  v_place_kind text;
  v_place_text text;
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

  -- BEFUND (11.11.2026): Der ungefaehre Ort. Die Art ist eine kurze
  -- Kennung ("zug", "messe", ...), der Text frei (max. 60 Zeichen).
  -- KEIN Standort - der Nutzer nennt selbst, was er nennen will.
  v_place_kind := nullif(trim(coalesce(p_place_kind, '')), '');
  IF v_place_kind IS NOT NULL THEN
    v_place_kind := left(regexp_replace(v_place_kind, '[^a-zA-Z0-9_\-]', '', 'g'), 20);
    IF v_place_kind = '' THEN
      v_place_kind := NULL;
    END IF;
  END IF;
  v_place_text := nullif(trim(regexp_replace(coalesce(p_place_text, ''), '[\r\n\t]+', ' ', 'g')), '');
  IF v_place_text IS NOT NULL AND length(v_place_text) > 60 THEN
    v_place_text := left(v_place_text, 60);
  END IF;
  IF v_place_text IS NULL THEN
    v_place_kind := NULL;
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
      (user_id, tokens, tags, self_tags, self_note, mode, status, matched_with, created_at, self_token, self_place_kind, self_place_text)
    VALUES (v_uid, v_clean, v_tags, v_self, v_note,
            CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
            'matched', v_other.user_id, now(), v_self_token, v_place_kind, v_place_text);
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
    (user_id, tokens, tags, self_tags, self_note, mode, status, self_token, self_place_kind, self_place_text)
  VALUES (v_uid, v_clean, v_tags, v_self, v_note,
            CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
            'pending', v_self_token, v_place_kind, v_place_text);
  RETURN jsonb_build_object('matched', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.send_soft_ping(p_token text, p_message_key text, p_custom_line text, p_recipient uuid DEFAULT NULL, p_place_kind text DEFAULT NULL, p_place_text text DEFAULT NULL, p_tags text[] DEFAULT '{}'::text[], p_self_tags text[] DEFAULT '{}'::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_me public.profiles;
  v_clean_token text;
  v_clean_line text;
  v_recipient record;
  v_allowed text[] := ARRAY['wave', 'again', 'coffee'];
  -- BEFUND (11.11.2026): Der Empfaenger kann auch direkt benannt werden
  -- (die Kandidatenliste liefert die Person). Der Server prueft dann die
  -- Naehe selbst - ein Ping an eine beliebige Person ist NICHT moeglich.
  v_place_kind text;
  v_place_text text;
  v_signal record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE user_id = v_uid;
  IF v_me.user_id IS NULL THEN
    RAISE EXCEPTION 'Kein Profil';
  END IF;

  -- Minderjaehrige / Profil ohne Geburtsdatum: keine Kontaktaufnahme.
  IF NOT public.transit_spark_adult(v_uid) THEN
    RAISE EXCEPTION 'transit_age_restricted: Transit Spark ist nur ab 18 Jahren nutzbar.';
  END IF;

  v_clean_token := left(substring(COALESCE(p_token, '') from '[0-9a-fA-F-]{8,64}'), 64);
  IF length(v_clean_token) < 8 THEN
    RAISE EXCEPTION 'Ungueltiges Token';
  END IF;

  IF NOT (COALESCE(p_message_key, '') = ANY (v_allowed)) THEN
    RAISE EXCEPTION 'Ungueltige Nachricht';
  END IF;

  -- Eigene Zeile: optional, maximal 140 Zeichen, Steuerzeichen raus.
  v_clean_line := NULL;
  IF p_custom_line IS NOT NULL AND length(trim(p_custom_line)) > 0 THEN
    v_clean_line := left(
      regexp_replace(p_custom_line, '[\x00-\x1f\x7f]', '', 'g'), 140);
  END IF;

  -- BEFUND (11.11.2026): Der Ort, den der Absender nennt (frei, max. 60).
  v_place_kind := nullif(trim(coalesce(p_place_kind, '')), '');
  IF v_place_kind IS NOT NULL THEN
    v_place_kind := left(regexp_replace(v_place_kind, '[^a-zA-Z0-9_\-]', '', 'g'), 20);
    IF v_place_kind = '' THEN
      v_place_kind := NULL;
    END IF;
  END IF;
  v_place_text := nullif(trim(regexp_replace(coalesce(p_place_text, ''), '[\r\n\t]+', ' ', 'g')), '');
  IF v_place_text IS NOT NULL AND length(v_place_text) > 60 THEN
    v_place_text := left(v_place_text, 60);
  END IF;
  IF v_place_text IS NULL THEN
    v_place_kind := NULL;
  END IF;

  -- BEFUND (11.11.2026): Zwei Wege zum Empfaenger.
  --
  -- (a) Ueber das BLE-Token (wie bisher) - der Empfangernachweis.
  -- (b) Ueber die Kandidatenliste (p_recipient). DANN prueft der Server
  --     die Naehe selbst: der Empfaenger muss ein frisches Signal mit
  --     passender Beschreibung haben. Ohne diese Pruefung waere ein Ping
  --     an JEDE Person im System moeglich - das waere eine Rechte-
  --     ausweitung (und Spam).
  IF p_recipient IS NOT NULL THEN
    SELECT p.* INTO v_recipient
      FROM public.profiles p
     WHERE p.user_id = p_recipient
       AND p.user_id <> v_uid
       AND public.transit_spark_adult(p.user_id)
       AND public.age_compatible(
             (SELECT public.profile_age(me.birth_date)
                FROM public.profiles me
               WHERE me.user_id = v_uid),
             date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int);

    IF v_recipient.user_id IS NULL THEN
      RAISE EXCEPTION 'Person nicht erreichbar.';
    END IF;

    -- DIE NAEHE-PRUEFUNG: ein frisches Signal (45 min) mit einer
    -- passenden Beschreibung. Ohne sie kein Ping.
    SELECT s.id, s.user_id INTO v_signal
      FROM public.transit_signals s
     WHERE s.user_id = p_recipient
       AND s.status = 'pending'
       AND s.created_at > now() - interval '45 minutes'
       AND (s.tags && coalesce(p_tags, '{}'::text[])
            OR s.self_tags && coalesce(p_self_tags, '{}'::text[]))
     ORDER BY s.created_at DESC
     LIMIT 1;

    IF v_signal.user_id IS NULL THEN
      RAISE EXCEPTION 'Person ist nicht (mehr) in der Naehe.';
    END IF;
  ELSE
    -- Empfaenger ueber das frische Presence-Token aufloesen.
    -- Zusaetzlich 18+-Gate: ein Erwachsener darf keinen Minderjaehrigen
    -- ueber Transit Spark anschreiben.
    SELECT p.* INTO v_recipient
      FROM public.transit_presence pr
      JOIN public.profiles p ON p.user_id = pr.user_id
     WHERE pr.token = v_clean_token
       AND pr.updated_at > now() - interval '45 minutes'
       AND pr.user_id <> v_uid
       AND public.transit_spark_adult(pr.user_id)
       AND public.age_compatible(
             (SELECT public.profile_age(me.birth_date)
                FROM public.profiles me
               WHERE me.user_id = v_uid),
             date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int)
     LIMIT 1;

    IF v_recipient.user_id IS NULL THEN
      RAISE EXCEPTION 'Person nicht mehr erreichbar (Radar veraltet).';
    END IF;
  END IF;

  -- Blockier-Schutz in beide Richtungen.
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker = v_uid AND b.blocked = v_recipient.user_id)
        OR (b.blocker = v_recipient.user_id AND b.blocked = v_uid)
  ) THEN
    RAISE EXCEPTION 'Nicht moeglich.';
  END IF;

  -- Rate-Limit: max. 1 ausgehender Ping pro 30 Minuten.
  -- BEFUND (11.11.2026): "die Moeglichkeit hat auch mehrere
  -- anzuschreiben". Vorher war auf EINEN Ping je 30 Minuten begrenzt.
  -- Jetzt sind es fuenf - der Schutz gegen Spam bleibt.
  IF (SELECT count(*) FROM public.transit_soft_pings
       WHERE sender = v_uid AND created_at > now() - interval '30 minutes') >= 5 THEN
    RAISE EXCEPTION 'Kurz durchatmen: Bitte spaeter erneut.';
  END IF;

  -- Ein Ping pro Encounter-Token (Unique-Index); Zeitfenster 48 h.
  INSERT INTO public.transit_soft_pings
    (sender, recipient, encounter_token, message_key, custom_line, expires_at,
     place_kind, place_text)
  VALUES
    (v_uid, v_recipient.user_id, v_clean_token, p_message_key, v_clean_line,
     now() + interval '48 hours',
     v_place_kind, v_place_text)
  ON CONFLICT (sender, encounter_token) DO NOTHING;
END;
$$;

-- -----------------------------------------------------------------------------
-- 3a) Die Rechte der neuen match_proximity_spark-Signatur.
--
-- BEFUND (11.11.2026, Push-Reife-Gate): Die Funktion hat zwei Parameter
-- bekommen - die alte Berechtigung gilt fuer die alte Signatur. Ohne
-- eigenes GRANT waere die neue Variante fuer niemanden aufrufbar.
-- -----------------------------------------------------------------------------
revoke all on function public.match_proximity_spark(text[], text[], text, text[], text, text, text, text) from public, anon;
grant execute on function public.match_proximity_spark(text[], text[], text, text[], text, text, text, text) to authenticated, service_role;

comment on function public.match_proximity_spark(text[], text[], text, text[], text, text, text, text) is
  '213: der Transit-Treffer. Neu: die Ortsangabe (place_kind/place_text) und die Ein-Variante-Regel (Migration 207).';

-- -----------------------------------------------------------------------------
-- 3b) Die alte 3-Parameter-Funktion von send_soft_ping entfernen.
--
-- BEFUND (11.11.2026): Die Funktion bekommt neue Parameter. OHNE das
-- Entfernen gabe es zwei Ueberladungen - und der Aufruf der App (mit
-- drei benannten Argumenten) waere MEHRDEUTIG (PGRST203: "could not
-- choose the best candidate"). Die App wuerde dann mit einem Fehler
-- abbrechen.
--
-- Die Signaturliste im DROP darf KEINE Default-Werte enthalten.
drop function if exists public.send_soft_ping(text, text, text);

-- -----------------------------------------------------------------------------
-- 3c) Die Rechte der neuen send_soft_ping-Signatur.
--
-- BEFUND (11.11.2026, Push-Reife-Gate): Die Funktion hat jetzt MEHR
-- Parameter - die alte Berechtigung gilt fuer die alte Signatur. Ohne
-- eigenes GRANT waere die neue Variante fuer niemanden aufrufbar (und
-- die alte waere weiterhin offen).
-- -----------------------------------------------------------------------------
revoke all on function public.send_soft_ping(text, text, text, uuid, text, text, text[], text[]) from public, anon;
grant execute on function public.send_soft_ping(text, text, text, uuid, text, text, text[], text[]) to authenticated, service_role;

comment on function public.send_soft_ping(text, text, text, uuid, text, text, text[], text[]) is
  '213: der Transit-Zuwinken. Neu: der Empfaenger kann direkt benannt werden (p_recipient) - der Server prueft dann die Naehe selbst. Neu: der Ort (place_kind/place_text). Neu: bis fuenf Zuwinke in 30 Minuten.';

-- -----------------------------------------------------------------------------
-- 4) Die Kandidatenliste: alle Personen in der Naehe, deren Beschreibung
--    zu meiner passt.
--
--    BEFUND (11.11.2026): "wenn es bei Transit Spark mehrere mit der selben
--    Beschreibung geben sollte, dass man dann alle dafuer vorgeschlagen
--    bekommt".
--
--    DER PRIVATHEITSAUFLAS:
--    * Der Name erscheint NUR, wenn die Person ihn freigegeben hat
--      (`transit_show_name`, Migration 208). Wer ihn nicht freigibt, ist
--      trotzdem auffindbar - nur eben ohne Namen.
--    * Angezeigt werden nur die MERKMALE (Haarfarbe, Brille, Hemd ...) und
--      der Ort, den die PERSON SELBST genannt hat ("Wagen 3"). Das ist
--      keine Ortung: der Ort ist eine Selbstauskunft.
--    * Keine Koordinaten, keine Entfernung, kein Alter ueber das, was die
--      Altersregel ohnehin erlaubt.
--    * Hoechstens 20 Kandidaten (eine Liste, die man lesen kann).
-- -----------------------------------------------------------------------------
create or replace function public.list_transit_candidates(
  p_tags text[] DEFAULT '{}'::text[],
  p_self_tags text[] DEFAULT '{}'::text[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
  v_me public.profiles;
  v_cutoff timestamptz := now() - interval '45 minutes';
begin
  if v_user is null then
    raise exception 'Nicht angemeldet';
  end if;

  -- Das 18+-Gate gilt auch fuer die Kandidatenliste (Migration 131).
  if not public.transit_spark_adult(v_user) then
    raise exception 'transit_age_restricted: Transit Spark ist nur ab 18 Jahren nutzbar.';
  end if;

  select * into v_me from public.profiles where user_id = v_user;
  if v_me.user_id is null then
    raise exception 'Kein Profil';
  end if;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             -- Pseudonym: eine Kennung fuer diese Anfrage, kein Name.
             'id', s.user_id,
             -- Die Merkmale der Person (ihre Beschreibung).
             'tags', coalesce(s.tags, '{}'::text[]),
             'selfTags', coalesce(s.self_tags, '{}'::text[]),
             -- Die freie Notiz der Person.
             'note', s.self_note,
             -- Der Ort, den die PERSON selbst genannt hat.
             'placeKind', s.self_place_kind,
             'placeText', s.self_place_text,
             -- Der Name NUR bei Freigabe (Migration 208).
             'name', case
               when coalesce(p.transit_show_name, true) then p.name
               else null
             end,
             'showName', coalesce(p.transit_show_name, true),
             -- Wann das Signal kam (fuer die Anzeige "vor X Minuten").
             'since', s.created_at
           ) order by s.created_at desc), '[]'::jsonb)
    into v_result
    from public.transit_signals s
    join public.profiles p on p.user_id = s.user_id
   where s.user_id <> v_user
     and s.status = 'pending'
     and s.created_at > v_cutoff
     -- Die Beschreibung passt zu meiner (Merkmale oder Selbstbeschreibung).
     and (s.tags && coalesce(p_tags, '{}'::text[])
          or s.self_tags && coalesce(p_tags, '{}'::text[])
          or s.tags && coalesce(p_self_tags, '{}'::text[])
          or s.self_tags && coalesce(p_self_tags, '{}'::text[]))
     -- Die Altersgrenze gilt in BEIDEN Richtungen.
     and public.transit_spark_adult(s.user_id)
     and public.age_compatible(
           (select public.profile_age(me.birth_date)
              from public.profiles me
             where me.user_id = v_user),
           date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int)
     -- Blockierte Personen (in beide Richtungen) sind draussen.
     and not exists (
       select 1 from public.blocked_users b
        where (b.blocker = v_user and b.blocked = s.user_id)
           or (b.blocker = s.user_id and b.blocked = v_user)
     )
     -- Wer schon ein Funke ist, braucht keinen Transit-Zuwinken.
     and not exists (
       select 1 from public.matches m
        where (m.user_one_id = v_user and m.user_two_id = s.user_id)
           or (m.user_one_id = s.user_id and m.user_two_id = v_user)
     )
   limit 20;
  return v_result;
end;
$$;

comment on function public.list_transit_candidates(text[], text[]) is
  '213: Die Personen in der Naehe, deren Beschreibung passt - pseudonym, der Name nur bei Freigabe (transit_show_name).';

revoke all on function public.list_transit_candidates(text[], text[]) from public, anon;
grant execute on function public.list_transit_candidates(text[], text[]) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5) Der Ping-Eingang: der Ort des Absenders kommt mit
-- -----------------------------------------------------------------------------
create or replace function public.list_my_soft_pings()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', s.id,
             'messageKey', s.message_key,
             'customLine', s.custom_line,
             'createdAt', s.created_at,
             'expiresAt', s.expires_at,
             -- BEFUND (11.11.2026): Der Name kommt NUR, wenn der Absender
             -- ihn freigegeben hat. Sonst bleibt es bei "Jemand winkt dir
             -- zu" - die Anonymitaet ist der Normalzustand.
             'senderName', case
               when coalesce(p.transit_show_name, true) then p.name
               else null
             end,
             -- Der Ort, den der Absender genannt hat ("Wagen 3").
             'placeKind', s.place_kind,
             'placeText', s.place_text
           ) order by s.created_at desc), '[]'::jsonb)
  from public.transit_soft_pings s
  join public.profiles p on p.user_id = s.sender
  where s.recipient = auth.uid()
    and s.status = 'pending'
    and s.expires_at > now();
$$;

comment on function public.list_my_soft_pings() is
  '213: die Transit-Zuwinke - mit dem Ort des Absenders und dem Namen nur bei Freigabe.';

revoke all on function public.list_my_soft_pings() from public, anon;
grant execute on function public.list_my_soft_pings() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast)
-- -----------------------------------------------------------------------------
do $$
declare
  v_src text;
  v_anzahl int;
begin
  -- (a) Es darf nur EINE Variante von match_proximity_spark geben - sonst
  --     ist der PostgREST-Aufruf mehrdeutig (PGRST203) und die App faellt
  --     auf eine aeltere Variante zurueck (der Ort gaenge verloren).
  select count(*) into v_anzahl
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'match_proximity_spark';
  if v_anzahl <> 1 then
    raise exception
      'Sicherheitscheck fehlgeschlagen: match_proximity_spark() hat % Varianten - der Aufruf waere mehrdeutig (PGRST203).', v_anzahl;
  end if;

  -- (b) Die Variante muss die Ortsangabe annehmen.
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'match_proximity_spark';
  if v_src is null or v_src not like '%p_place_kind%' or v_src not like '%p_place_text%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: match_proximity_spark() nimmt die Ortsangabe nicht an.';
  end if;

  -- (c) Die Kandidatenliste muss den Namen nur bei Freigabe liefern.
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'list_transit_candidates';
  if v_src is null or v_src not like '%transit_show_name%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: list_transit_candidates() liefert den Namen ohne Freigabe.';
  end if;

  -- (d) Der Ping muss die Naehe pruefen (kein Ping an beliebige Personen).
  --
  --     WICHTIG (BEFUND 11.11.2026): Die Abfrage muss die EXAKTE
  --     Signatur treffen. Nimmt sie "die Funktion mit dem Namen", ist das
  --     Ergebnis vom Zufall der Zeilenreihenfolge abhaengig - und der
  --     Beweis prueft dann womöglich die alte Variante.
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'send_soft_ping'
     and pg_get_function_identity_arguments(p.oid) =
         'p_token text, p_message_key text, p_custom_line text, '
         'p_recipient uuid, p_place_kind text, p_place_text text, '
         'p_tags text[], p_self_tags text[]';
  if v_src is null or v_src not like '%p_recipient%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: send_soft_ping() kann keinen Empfaenger annehmen.';
  end if;
  if v_src not like '%transit_signals%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: send_soft_ping() prueft die Naehe nicht - ein Ping waere an beliebige Personen moeglich.';
  end if;

  -- (e) Die alte 3-Parameter-Variante darf nicht mehr existieren -
  --     sonst waere der Aufruf der App mehrdeutig (PGRST203).
  select count(*) into v_anzahl
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'send_soft_ping'
     and pg_get_function_identity_arguments(p.oid) = 'p_token text, p_message_key text, p_custom_line text';
  if v_anzahl > 0 then
    raise exception
      'Sicherheitscheck fehlgeschlagen: Die alte send_soft_ping-Variante besteht noch - der Aufruf waere mehrdeutig (PGRST203).';
  end if;

  -- (f) Die Altersgrenze (18+) und der Blockierschutz bleiben.
  if v_src not like '%transit_spark_adult%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: send_soft_ping() verliert das 18+-Gate.';
  end if;
  if v_src not like '%blocked_users%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: send_soft_ping() verliert den Blockierschutz.';
  end if;
end;
$$;

commit;
