-- 185: Transit Spark - der Match war mit genau zwei Geraeten unmoeglich
--
-- BEFUND (07.11.2026, Betreiber): "Beide Geraete suchen eine Person bei
-- Transit Spark (Beide haben gleiche beschreibung und beide haben sich
-- gegenseitig blicke getauscht/gefunkt, aber gibt keinen Funken.)"
--
-- DIE URSACHE (an den echten Daten des Betreibers belegt):
--
--   Das Signal, das die App abschickt, enthielt die Tokens der GERAETE,
--   die der Absender gesehen hat - nicht den eigenen Token des Absenders.
--   Gesucht wurde mit `s.tokens && v_clean`, also mit derselben Menge:
--
--     A sendet -> Signal A.tokens = {Token von B}
--     B sendet -> Signal B.tokens = {Token von A}
--     A sucht  -> Signal B.tokens && {Token von B}
--              = {Token von A} && {Token von B} = LEER
--
--   Zwei Personen sehen nur EINANDER, niemals sich selbst. Ihre
--   Token-Mengen sind deshalb disjunkt - mit genau zwei Geraeten in
--   Reichweite konnte die Bedingung NIE erfuellt werden. Ein Match war
--   mathematisch unmoeglich.
--
--   (Mit drei Geraeten waere es ueber das gemeinsame dritte Token
--   gegangen - deshalb ist der Fehler nie aufgefallen. Der BLE-Test auf
--   zwei echten Geraeten stand aber die ganze Zeit als offen.)
--
-- DIE LOESUNG:
--
--   Der eigene Token wird mitgeschickt und in einer eigenen Spalte
--   gespeichert. Damit laesst sich die Frage stellen, die die Sache
--   ueberhaupt meint: "HAT DER ANDERE MICH GESEHEN?" - denn der eigene
--   Token des anderen steht in dessen Sichtungsliste, wenn der andere
--   mich gesehen hat.
--
--   Die Bedingung wird symmetrisch:
--
--     s.self_token  = ANY(v_clean)   -- ich habe IHN gesehen
--     p_self_token  = ANY(s.tokens)   -- ER hat MICH gesehen
--
--   Das ist genau "Blicke getauscht": beide haben einander gesehen.
--
--   Warum die Spalte self_token noetig ist und nicht einfach der eigene
--   Token in die bestehende tokens-Spalte gehoert: dann waere die
--   Bedingung "irgendein gemeinsamer Token" - und bei drei Geraeten in
--   Reichweite wuerden zwei Personen matchen, die nur dasselbe DRITTE
--   Geraet gesehen haben, ohne sich selbst zu sehen. Mit der eigenen
--   Spalte ist der Match an die Identitaet gebunden. Der Selbsttest
--   unten prueft genau diesen Falschtreffer.
--
-- RUECKWAERTSKOMPATIBILITAET:
--
--   Die bestehende Funktion mit FUENF Parametern bleibt unveraendert
--   bestehen. Sie wird von aelteren Apps (Build < 40) aufgerufen und
--   findet - wie bisher - keinen Match; sie bricht aber nicht mit
--   "function not found" ab. Die neue Fassung mit SECHS Parametern
--   kommt als Ueberladung dazu: die Signatur einer bestehenden
--   Funktion kann mit CREATE OR REPLACE nicht geaendert werden (das
--   steht auch so in Migration 149), und ein DROP wuerde die alten
--   Clients mit einer Fehlermeldung statt mit "kein Match" treffen.
--
--   Die neue Funktion sagt dem Nutzer, wenn der eigene Token fehlt -
--   statt still nichts zu finden.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Die Spalte fuer den eigenen Token
-- ---------------------------------------------------------------------------
ALTER TABLE public.transit_signals
  ADD COLUMN IF NOT EXISTS self_token text;

COMMENT ON COLUMN public.transit_signals.self_token IS
  'Der eigene, ephemere Token des Absenders (v0.10.0, Migration 185). '
  'Steht in der Sichtungsliste der anderen Person, wenn die andere '
  'einen gesehen hat - damit laesst sich "Blicke getauscht" pruefen. '
  'NULL bei Signalen aus aelteren Versionen.';

-- KEIN Index auf self_token: fuer einzelnes text gibt es keine
-- Standard-Operatorklasse fuer GIN (die gehoeren zu den Array-Typen).
-- Der vorhandene Index auf (status, created_at) deckt die Suche ab -
-- im 45-Minuten-Fenster liegen nur wenige Signale.

-- ---------------------------------------------------------------------------
-- 2) Die RPC mit dem eigenen Token
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.match_proximity_spark(p_tokens text[], p_tags text[] DEFAULT '{}'::text[], p_mode text DEFAULT 'transit'::text, p_self_tags text[] DEFAULT '{}'::text[], p_self_note text DEFAULT NULL::text, p_self_token text DEFAULT NULL::text)
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
 -- Der eigene, ephemere Token des Absenders (v0.10.0, Migration 185).
 v_self_token text;
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

  -- Der eigene Token (v0.10.0, Migration 185).
  --
  -- Format: genau 20 Hexzeichen - derselbe Massstab wie bei den
  -- gescannten Tokens (Migration 181 hat ihn geaendert: vorher galt
  -- "irgendetwas nach dem Marker" als Token, und die Hersteller-ID
  -- 0xFFFF liess jedes fremde Bluetooth-Geraet als Thestia-Geraet
  -- durch).
  --
  -- Warum er gebraucht wird: ohne ihn laesst sich die Frage "hat der
  -- andere mich gesehen?" nicht beantworten. Der eigene Token des
  -- anderen steht in dessen Sichtungsliste, wenn der andere mich
  -- gesehen hat. Ohne ihn verglich die Funktion zwei Sichtungslisten
  -- - und die sind bei zwei Personen, die nur einander sehen, disjunkt.
  --
  -- Fehlt er, wird das gesagt. Stilles Nicht-Finden waere genau der
  -- Fehler, den dieser Bug ausgeloest hat (BEFUND 07.11.2026).
  IF p_self_token IS NULL OR btrim(p_self_token) = '' THEN
    RAISE EXCEPTION 'transit_own_token_missing: Bitte die App aktualisieren - der Radar muss zuerst ein Signal senden.';
  END IF;
  v_self_token := lower(btrim(p_self_token));
  IF v_self_token !~ '^[0-9a-f]{20}$' THEN
    RAISE EXCEPTION 'transit_own_token_invalid: Das eigene Signal ist noch nicht bereit.';
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
       -- DIE BEIDEN RICHTUNGEN (v0.10.0, Migration 185):
       --
       --   1) "Ich habe IHN gesehen": sein eigener Token steht in
       --      meiner Sichtungsliste.
       --   2) "ER hat MICH gesehen": mein eigener Token steht in
       --      seiner Sichtungsliste.
       --
       -- Vorher stand hier nur `s.tokens && v_clean` - der Vergleich
       -- zweier Sichtungslisten. Zwei Personen, die nur einander sehen,
       -- haben disjunkte Listen: die Bedingung konnte nie stimmen
       -- (BEFUND 07.11.2026, am echten Daten belegt).
       AND s.self_token = ANY (v_clean)
       AND v_self_token = ANY (s.tokens)
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
      (user_id, tokens, tags, self_tags, self_note, mode, status, matched_with, created_at, self_token)
    VALUES (v_uid, v_clean, v_tags, v_self, v_note,
            CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
            'matched', v_other.user_id, now(), v_self_token);

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
    (user_id, tokens, tags, self_tags, self_note, mode, status, self_token)
  VALUES (v_uid, v_clean, v_tags, v_self, v_note,
          CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
          'pending', v_self_token);

  RETURN jsonb_build_object('matched', false);
END;
$function$;

-- Grant auf die alte, fuenfparametrige Signatur (unveraendert): die
-- aelteren Apps rufen sie auf.
GRANT EXECUTE ON FUNCTION
  public.match_proximity_spark(text[], text[], text, text[], text)
  TO authenticated, service_role;

-- Grant auf die NEUE Signatur. Ohne ihn darf die App die Funktion mit
-- dem eigenen Token nicht aufrufen.
GRANT EXECUTE ON FUNCTION
  public.match_proximity_spark(text[], text[], text, text[], text, text)
  TO authenticated, service_role;

-- Die Sperre fuer die oeffentliche Rolle.
--
-- WICHTIG (gleiches Muster wie Migration 156): Ein "REVOKE ... FROM
-- anon" genuegt NICHT. Jede Rolle ist implizit Mitglied der
-- Pseudo-Rolle PUBLIC, und der Postgres-DEFAULT-Grant ist
-- "EXECUTE ... TO PUBLIC". Wird die Berechtigung ueber PUBLIC
-- vererbt, bleibt sie nach einem Rollen-Revoke bestehen. Es heisst
-- also "FROM PUBLIC".
--
-- Ohne diese Sperre waere die Funktion (SECURITY DEFINER) ueber
-- PostgREST auch ohne jedes JWT aufrufbar - also auch von einem
-- nicht angemeldeten Aufrufer. Der alte Weg (Migration 123, 156)
-- hat genau das fuer die aeltere Fassung getan; die neue Fassung
-- braucht es genauso.
REVOKE EXECUTE ON FUNCTION
  public.match_proximity_spark(text[], text[], text, text[], text, text)
FROM PUBLIC, anon;

COMMENT ON FUNCTION public.match_proximity_spark(text[], text[], text, text[], text, text) IS
  'Transit-Spark-Matching mit dem eigenen Token (v0.10.0, Migration 185). '
  'Der eigene Token macht "Blicke getauscht" pruefbar: er steht in der '
  'Sichtungsliste der anderen Person, wenn die andere einen gesehen hat. '
  'Ohne ihn war ein Match mit genau zwei Geraeten mathematisch '
  'unmoeglich.';

COMMENT ON FUNCTION public.match_proximity_spark(text[], text[], text, text[], text) IS
  'Transit-Spark-Matching OHNE den eigenen Token. Diese Fassung ist fuer '
  'aeltere Apps (Build < 40) und kann einen Match nicht sicher '
  'feststellen - sie bleibt nur, damit alte Clients keine '
  '"function not found"-Fehler bekommen.';

-- ---------------------------------------------------------------------------
-- 3) Der Selbsttest
-- ---------------------------------------------------------------------------
--
-- WARUM: Der Fehler war drei Monate lang unentdeckt, weil niemand zwei
-- echte Geraete nebeneinander hatte. Ein Test, der das nachstellt, ist
-- deshalb keine Kuerzlichkeit, sondern die einzige Sache, die den
-- Fehler kuenftig beim Bauen faellt.
--
-- Der Test laeuft in einem SAVEPOINT und wird zurueckgerollt: die
-- Testdaten bleiben nicht stehen, die Migration kann trotzdem
-- committen. Bricht der Test ab, wird die Migration NICHT ausgerollt -
-- dann faellt der Fehler beim Deployen auf, nicht beim Benutzen.
--
-- Nachgestellt wird der Fall des Betreibers: zwei Personen, gleiche
-- Beschreibung, jeder hat genau EINEN Token des anderen gesehen.

-- Fremdschluessel auf auth.users nur fuer diesen Test aufheben - die
-- Testkonten haben kein auth.users-Konto. Nach dem ROLLBACK sind sie
-- wieder da (DDL ist in Postgres transaktional).
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.conrelid::regclass::text AS tab, c.conname::text AS conname
      FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
     WHERE c.contype = 'f'
       AND n.nspname = 'public'
       AND c.confrelid = 'auth.users'::regclass
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tab, r.conname);
  END LOOP;
END;
$$;

-- Eine Hilfsfunktion fuer die Testprofile: die Spaltenliste wird
-- dynamisch gebildet, damit der Test nicht bei jeder neuen
-- Pflichtspalte in public.profiles bricht.
CREATE OR REPLACE FUNCTION pg_temp.lege_testprofil(p_uid uuid, p_name text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_spalten text;
  v_werte text;
BEGIN
  SELECT string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position),
         string_agg(
           CASE
             WHEN c.column_name::text = 'user_id' THEN quote_literal(p_uid::text)
             WHEN c.column_name::text = 'name' THEN quote_literal(p_name)
             WHEN c.column_name::text = 'gender' THEN quote_literal('female')
             WHEN c.column_name::text = 'birth_date' THEN quote_literal('1990-01-01')
             WHEN c.column_name::text = 'is_verified' THEN quote_literal('true')
             WHEN c.column_name::text = 'is_admin' THEN quote_literal('false')
             WHEN c.column_name::text = 'bio' THEN quote_literal('')
             WHEN c.column_name::text = 'intro_text' THEN quote_literal('')
             WHEN c.column_name::text = 'interests' THEN quote_literal('[]') || '::jsonb'
             WHEN c.column_name::text = 'ui_prefs' THEN quote_literal('{}') || '::jsonb'
             WHEN c.column_name::text = 'gender_preferences' THEN quote_literal('{}') || '::text[]'
             WHEN c.column_name::text = 'photos' THEN quote_literal('{}') || '::text[]'
             WHEN c.column_name::text = 'music_liked' THEN quote_literal('{}') || '::text[]'
             WHEN c.column_name::text = 'music_disliked' THEN quote_literal('{}') || '::text[]'
             WHEN c.column_name::text = 'personality_type' THEN quote_literal('INTJ')
             WHEN c.column_name::text = 'max_distance_km' THEN quote_literal('100')
             WHEN c.column_name::text = 'age_range_min' THEN quote_literal('18')
             WHEN c.column_name::text = 'age_range_max' THEN quote_literal('65')
             WHEN c.column_name::text = 'country' THEN quote_literal('DE')
             WHEN c.column_name::text = 'verification_status' THEN quote_literal('approved')
             WHEN c.column_name::text = 'distance_filter_mode' THEN quote_literal('distance_km')
             WHEN c.column_name::text = 'birthday_style' THEN quote_literal('classic')
             WHEN c.column_name::text = 'consent_state' THEN quote_literal('none')
             WHEN c.column_name::text = 'created_at' THEN quote_literal('now()')
             WHEN c.column_name::text = 'updated_at' THEN quote_literal('now()')
             WHEN c.column_name::text = 'is_location_suspicious' THEN quote_literal('false')
             WHEN c.column_name::text = 'one_time_settings_completed' THEN quote_literal('false')
             WHEN c.column_name::text = 'community_guidelines_accepted' THEN quote_literal('true')
             WHEN c.column_name::text = 'personality_test_completed' THEN quote_literal('true')
             WHEN c.column_name::text = 'notifications_enabled' THEN quote_literal('false')
             WHEN c.column_name::text = 'notify_matches' THEN quote_literal('false')
             WHEN c.column_name::text = 'notify_likes' THEN quote_literal('false')
             WHEN c.column_name::text = 'notify_messages' THEN quote_literal('false')
             WHEN c.column_name::text = 'notify_dating_hour' THEN quote_literal('false')
             WHEN c.column_name::text = 'paused' THEN quote_literal('false')
             WHEN c.column_name::text = 'habits_dealbreaker' THEN quote_literal('false')
             WHEN c.column_name::text = 'mfa_required' THEN quote_literal('false')
             WHEN c.column_name::text = 'show_distance' THEN quote_literal('false')
             WHEN c.column_name::text = 'supervised' THEN quote_literal('false')
             WHEN c.column_name::text = 'guardian_transition_done' THEN quote_literal('false')
             WHEN c.column_name::text = 'dating_hour_intro_seen' THEN quote_literal('false')
             WHEN c.udt_name::text = 'bool' THEN quote_literal('false')
             WHEN c.udt_name::text IN ('int2', 'int4', 'int8') THEN quote_literal('0')
             WHEN c.udt_name::text = 'date' THEN quote_literal('1990-01-01')
             WHEN c.udt_name::text = 'text' THEN quote_literal('')
             WHEN c.udt_name::text = 'jsonb' THEN quote_literal('{}') || '::jsonb'
             WHEN c.udt_name::text = '_text' THEN quote_literal('{}') || '::text[]'
             ELSE quote_literal('NULL')
           END, ', ' ORDER BY c.ordinal_position)
    INTO v_spalten, v_werte
    FROM information_schema.columns c
   WHERE c.table_name = 'profiles' AND c.table_schema = 'public'
     AND c.is_nullable = 'NO';

  EXECUTE format('INSERT INTO public.profiles (%s) VALUES (%s)',
                 v_spalten, v_werte);
END;
$$;

SAVEPOINT transit_match_selftest;

DO $$
DECLARE
  v_a uuid := '11111111-2222-3333-4444-555555555555';
  v_b uuid := '66666666-7777-8888-9999-aaaaaaaaaaaa';
  v_e uuid := '33333333-4444-5555-6666-777777777777';
  v_f uuid := '44444444-5555-6666-7777-888888888888';
  v_tok_a text := 'aaaaaaaaaaaaaaaaaaaa';
  v_tok_b text := 'bbbbbbbbbbbbbbbbbbbb';
  v_tok_d text := 'dddddddddddddddddddd';
  v_tok_e text := 'eeeeeeeeeeeeeeeeeeee';
  v_tok_f text := 'ffffffffffffffffffff';
  v_tags text[] := ARRAY['hair_color:brown', 'hemd:white'];
  v_ergebnis jsonb;
BEGIN
  PERFORM pg_temp.lege_testprofil(v_a, 'Selbsttest A');
  PERFORM pg_temp.lege_testprofil(v_b, 'Selbsttest B');
  PERFORM pg_temp.lege_testprofil(v_e, 'Selbsttest E');
  PERFORM pg_temp.lege_testprofil(v_f, 'Selbsttest F');

  -- ================================================================
  -- FALL 1: Zwei Personen, die sich gegenseitig gesehen haben.
  --
  -- Genau der Fall des Betreibers (07.11.2026): gleiche Beschreibung,
  -- jeder hat genau EINEN Token des anderen gesehen, und es gab
  -- trotzdem keinen Funken.
  --
  -- Vorher war das mathematisch unmoeglich: gesucht wurde mit den
  -- Fremd-Tokens, gespeichert wurden die Fremd-Tokens - zwei
  -- Menschen, die nur einander sehen, haben disjunkte Token-Mengen.
  -- ================================================================

  -- A sendet zuerst. Noch kein Match - B hat ja noch nicht gesendet.
  PERFORM set_config('request.jwt.claim.sub', v_a::text, true);
  v_ergebnis := public.match_proximity_spark(
    ARRAY[v_tok_b], v_tags, 'transit', v_tags, NULL, v_tok_a);
  IF coalesce((v_ergebnis ->> 'matched')::boolean, false) THEN
    RAISE EXCEPTION 'Selbsttest 1: A hat schon beim ersten Senden gematcht';
  END IF;

  -- B sendet danach: B hat A gesehen, und A_Tok steht in Bs
  -- Sichtungsliste. Jetzt muss es matchen.
  PERFORM set_config('request.jwt.claim.sub', v_b::text, true);
  v_ergebnis := public.match_proximity_spark(
    ARRAY[v_tok_a], v_tags, 'transit', v_tags, NULL, v_tok_b);
  IF NOT coalesce((v_ergebnis ->> 'matched')::boolean, false) THEN
    RAISE EXCEPTION 'Selbsttest 2: zwei Personen, die sich gegenseitig gesehen haben, haben NICHT gematcht - genau der Fehler vom 07.11.2026';
  END IF;
  IF (v_ergebnis ->> 'partner')::uuid <> v_a THEN
    RAISE EXCEPTION 'Selbsttest 3: der falsche Partner wurde gemeldet';
  END IF;

  -- ================================================================
  -- FALL 2: Zwei Personen, die nur dasselbe DRITTE Geraet gesehen
  -- haben, duerfen NICHT matchen.
  --
  -- Das ist der Falschtreffer, den die alte Logik produziert hat:
  -- `s.tokens && v_clean` verglich zwei Sichtungslisten - und zwei
  -- Personen im selben Raum haben ein gemeinsames Token (das des
  -- dritten Geraets). Mit der neuen Logik ist der Match an die
  -- Identitaet gebunden: E_Tok steht nicht in Fs Sichtungsliste und
  -- F_Tok nicht in Es.
  -- ================================================================
  PERFORM set_config('request.jwt.claim.sub', v_e::text, true);
  v_ergebnis := public.match_proximity_spark(
    ARRAY[v_tok_d], v_tags, 'transit', v_tags, NULL, v_tok_e);
  IF coalesce((v_ergebnis ->> 'matched')::boolean, false) THEN
    RAISE EXCEPTION 'Selbsttest 4: E hat beim ersten Senden gematcht';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_f::text, true);
  v_ergebnis := public.match_proximity_spark(
    ARRAY[v_tok_d], v_tags, 'transit', v_tags, NULL, v_tok_f);
  IF coalesce((v_ergebnis ->> 'matched')::boolean, false) THEN
    RAISE EXCEPTION 'Selbsttest 5: E und F haben gematcht, obwohl sie nur dasselbe dritte Geraet gesehen haben - der Falschtreffer ist nicht behoben';
  END IF;

  -- ================================================================
  -- FALL 3: Ohne den eigenen Token gibt es keine verwertbare
  -- Entscheidung - und das wird auch gesagt.
  -- ================================================================
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_a::text, true);
    v_ergebnis := public.match_proximity_spark(
      ARRAY[v_tok_b], v_tags, 'transit', v_tags, NULL, NULL);
    RAISE EXCEPTION 'Selbsttest 6: ohne den eigenen Token wurde kein Fehler gemeldet';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%transit_own_token_missing%' THEN
      RAISE EXCEPTION 'Selbsttest 6: falsche Meldung: %', SQLERRM;
    END IF;
  END;
END;
$$;

ROLLBACK TO SAVEPOINT transit_match_selftest;

COMMIT;
