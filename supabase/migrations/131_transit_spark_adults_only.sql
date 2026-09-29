-- Migration 131: Transit Spark nur ab 18 Jahren (NUTZERWUNSCH Build 30)
--
-- BISHER: Transit Spark war fuer alle Profile nutzbar. Der Client zeigte
-- lediglich einen Hinweistext fuer unter 18-Jaehrige ("Nur fuer
-- Erwachsene sichtbar"), aber es gab KEINE echte Sperre - weder im
-- Client noch in der Datenbank. Eine reine UI-Sperre waere ausserdem
-- umgehbar, weil die BLE-Erkennung nur ein Token erzeugt und der
-- eigentliche Abgleich ueber RPCs laeuft.
--
-- DIESE MIGRATION setzt die Sperre durchgaengig:
--
--   1) Hilfsfunktion public.transit_spark_adult() - die einzige
--      Altersquelle fuer das Gate. Fail-closed: ohne birth_date
--      gilt der Nutzer NICHT als erwachsen.
--   2) transit_presence_heartbeat  - der Radar-Aktivierungspfad.
--   3) match_proximity_spark      - der Match-Pfad.
--   4) send_soft_ping             - der Kontaktaufnahme-Pfad.
--
-- ZUSAETZLICH (wichtig, sonst waere die Sperre halb):
--   Die Kandidatenlisten in match_proximity_spark und send_soft_ping
--   filterten bisher nur ueber public.age_compatible() - ein Erwach-
--   sener (18) haette nach der 2-Jahres-Bandsregel weiterhin eine
--   16-Jaehrige finden koennen. Deshalb wird die Gegenseite
--   ausdruecklich auf >= 18 zusaetzlich geprueft. Transit Spark ist
--   damit ein Feature ausschliesslich zwischen Volljaehrigen.
--
-- DATENBereinIGUNG: vorhandene Signale, Presence-Zeilen und offene
-- Pings von Minderjaehrigen werden entfernt, damit Altbestand nicht
-- die neue Sperre umgeht.
--
-- Datenschutz: Das Geburtsdatum selbst wird hier nicht ausgegeben,
-- nur ein boolean. transit_presence_leave() bleibt bewusst OHNE
-- Gate, damit auch ein juengerer Nutzer seinen Radar sauber
-- abschalten und seine Spuren loeschen kann.

-- ==========================================================================
-- 1) Alterspruefung - fail-closed
-- ==========================================================================
-- bewusst NICHT public.profile_age() verwenden: das coalesct ein
-- fehlendes birth_date auf '2000-01-01' und wuerde damit ohne
-- Geburtsdatum faelschlich "erwachsen" liefern.
CREATE OR REPLACE FUNCTION public.transit_spark_adult(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.profiles p
     WHERE p.user_id = p_user_id
       AND p.birth_date IS NOT NULL
       AND date_part('year', age(p.birth_date))::int >= 18
  );
$$;

REVOKE EXECUTE ON FUNCTION public.transit_spark_adult(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transit_spark_adult(uuid) TO authenticated;

-- ==========================================================================
-- 2) Bestandsdaten von Minderjaehrigen entfernen
-- ==========================================================================
DELETE FROM public.transit_soft_pings
 WHERE status = 'pending'
   AND (
     NOT public.transit_spark_adult(sender)
     OR NOT public.transit_spark_adult(recipient)
   );

DELETE FROM public.transit_signals
 WHERE NOT public.transit_spark_adult(user_id);

DELETE FROM public.transit_presence
 WHERE NOT public.transit_spark_adult(user_id);

-- ==========================================================================
-- 3) Radar-Aktivierung sperren
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.transit_presence_heartbeat(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_clean text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;
  -- Minderjaehrige / Profil ohne Geburtsdatum: kein Radar.
  IF NOT public.transit_spark_adult(v_uid) THEN
    RAISE EXCEPTION 'transit_age_restricted: Transit Spark ist nur ab 18 Jahren nutzbar.';
  END IF;
  v_clean := left(substring(COALESCE(p_token, '') from '[0-9a-fA-F-]{8,64}'), 64);
  IF length(v_clean) < 8 THEN
    RAISE EXCEPTION 'Ungueltiges Token';
  END IF;
  DELETE FROM public.transit_presence WHERE user_id = v_uid;
  INSERT INTO public.transit_presence (user_id, token, updated_at)
  VALUES (v_uid, v_clean, now());
END;
$$;

REVOKE EXECUTE ON FUNCTION public.transit_presence_heartbeat(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transit_presence_heartbeat(text)
  TO authenticated;

-- ==========================================================================
-- 4) Matching sperren
-- ==========================================================================
-- Body identisch zu Migration 110, ergaenzt um:
--   - Gate fuer den aufrufenden Nutzer
--   - zusaetzliches 18+-Gate fuer die gefundene Person
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
  IF v_tags IS NULL OR array_length(v_tags, 1) IS NULL
     OR array_length(v_tags, 1) < 2
     OR array_length(v_tags, 1) > 5 THEN
    RAISE EXCEPTION 'Bitte 2-5 Merkmale waehlen';
  END IF;

  SELECT array_agg(DISTINCT t) INTO v_self
    FROM unnest(COALESCE(p_self_tags, '{}'::text[])) AS t
   WHERE t = ANY (v_allowed);
  IF array_length(coalesce(v_self, '{}'::text[]), 1) > 5 THEN
    RAISE EXCEPTION 'Bitte maximal 5 Merkmale zu dir selbst waehlen';
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

REVOKE EXECUTE ON FUNCTION public.match_proximity_spark(text[], text[], text, text[], text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.match_proximity_spark(text[], text[], text, text[], text)
  TO authenticated;

-- Alte Überladungen ENTFERNEN - sie sind eine echte Umgehung.
--
-- Der Client (supabase_database_service.dart:310-326) probiert
-- match_proximity_spark nacheinander mit 5, 4, 3 und 1 Argument auf und
-- steigt bei PGRST202/203 eine Stufe ab. Diese Fallback-Kette entstand,
-- weil alte Signaturen nie gedroppt wurden (erst in 097 bei anderen
-- Funktionen). Für match_proximity_spark hat sie 081 (1 Parameter),
-- 082 (3), 084 (4) und 104 (1) hinterlassen.
--
-- KRITISCH: Diese alten Bodies kennen die Alterssperre NICHT. Wären sie
-- weiter aufrufbar, könnte ein Minderjähriger die 1-Parameter-Variante
-- aufrufen und das komplette 18+-Gate umgehen - die Sperre in Abschnitt 4
-- wäre dann wertlos. Genau deshalb werden sie hier gedroppt und nicht nur
-- revoked.
--
-- Auswirkung auf den Client: der 5-Parameter-Aufruf bleibt der einzige
-- gültige; die Fallback-Stufen fallen mit PGRST202 weg, was der Client
-- bereits als "Server älter" behandelt (isRpcSignatureMismatch). Da
-- Migration 132 ältere Builds aus dem Support nimmt, ist das der
-- gewollte Zustand: Gegen einen Server ohne 18+-Gate soll ein alter
-- Client ohnehin kein Matching bekommen.
DROP FUNCTION IF EXISTS public.match_proximity_spark(text[]);
DROP FUNCTION IF EXISTS public.match_proximity_spark(text[], text[], text);
DROP FUNCTION IF EXISTS public.match_proximity_spark(text[], text[], text, text[]);

-- ==========================================================================
-- 5) Soft-Ping sperren
-- ==========================================================================
-- Body identisch zu Migration 083, ergaenzt um:
--   - Gate fuer den absendenden Nutzer
--   - zusaetzliches 18+-Gate fuer die empfangende Person
CREATE OR REPLACE FUNCTION public.send_soft_ping(
  p_token text,
  p_message_key text,
  p_custom_line text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_me public.profiles;
  v_clean_token text;
  v_clean_line text;
  v_recipient record;
  v_allowed text[] := ARRAY['wave', 'again', 'coffee'];
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

  -- Blockier-Schutz in beide Richtungen.
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker = v_uid AND b.blocked = v_recipient.user_id)
        OR (b.blocker = v_recipient.user_id AND b.blocked = v_uid)
  ) THEN
    RAISE EXCEPTION 'Nicht moeglich.';
  END IF;

  -- Rate-Limit: max. 1 ausgehender Ping pro 30 Minuten.
  IF EXISTS (
    SELECT 1 FROM public.transit_soft_pings
     WHERE sender = v_uid AND created_at > now() - interval '30 minutes'
  ) THEN
    RAISE EXCEPTION 'Kurz durchatmen: Bitte spaeter erneut.';
  END IF;

  -- Ein Ping pro Encounter-Token (Unique-Index); Zeitfenster 48 h.
  INSERT INTO public.transit_soft_pings
    (sender, recipient, encounter_token, message_key, custom_line, expires_at)
  VALUES
    (v_uid, v_recipient.user_id, v_clean_token, p_message_key, v_clean_line,
     now() + interval '48 hours')
  ON CONFLICT (sender, encounter_token) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.send_soft_ping(text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_soft_ping(text, text, text)
  TO authenticated;
