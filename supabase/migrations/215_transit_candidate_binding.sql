-- 215_transit_candidate_binding.sql
--
-- BEFUND (13.11.2026, Sicherheits-Review der App):
--
--   Die Kandidatenliste (list_transit_candidates) und der Soft-Ping im
--   Empfaenger-Weg (send_soft_ping) haben die BESCHREIBUNG vom Client
--   uebernommen, ohne sie zu pruefen:
--
--     and (s.tags && coalesce(p_tags, '{}'::text[])
--          or s.self_tags && coalesce(p_tags, '{}'::text[])
--          or s.tags && coalesce(p_self_tags, '{}'::text[])
--          or s.self_tags && coalesce(p_self_tags, '{}'::text[]))
--
--   p_tags/p_self_tags sind Argumente des Aufrufers - ungeprueft.
--
-- WORAUS DAS EIN PROBLEM WIRD:
--
--   Der Merkmals-Katalog (public.transit_tag_catalog) ist fuer jeden
--   angemeldeten Nutzer lesbar (Policy USING (true), Migration 148).
--   Wer den ganzen Katalog (~600 Slugs) als p_tags uebergibt, trifft
--   damit JEDES aktive Signal. Die Kandidatenliste lieferte dann also
--   alle Personen im 45-Minuten-Fenster - mit echter user_id, mit der
--   freien Notiz und mit dem selbst genannten Ort. Der Name bleibt zu
--   Recht an transit_show_name gebunden, aber die UUID genuegt, um
--   "diese Person war um 14:32 im Transit Spark" zu sagen.
--
--   Und: der Soft-Ping im Empfaenger-Weg benutzte dieselben ungeprueften
--   Arrays fuer die Naehe-Pruefung. Damit waren 5 Zuwinke je 30
--   Minuten an beliebige nahe Erwachsene moeglich - eine Kontaktaufnahme
--   ohne jede echte Uebereinstimmung (Push-Spam, Belaestigung).
--
-- DIE LOESUNG:
--
--   Der Server nimmt die Beschreibung NICHT mehr vom Client, sondern aus
--   dem EIGENEN Signal des Aufrufers (public.transit_signals, status
--   'pending'). Das eigene Signal schreibt match_proximity_spark beim
--   "Blicke getauscht" - und dort werden die Merkmale gegen den Katalog
--   geprueft (Migration 213). Was der Client behauptet, kann damit
--   nichts mehr ueber die Kandidatenliste oder den Ping entscheiden.
--
--   Fuer den ehrlichen Client aendert sich NICHTS: das eigene Signal
--   enthaelt genau die Merkmale, die er gerade gewaehlt hat (tags) und
--   seine eigene Selbstbeschreibung (self_tags).
--
--   Die beiden Argumente p_tags/p_self_tags bleiben in der Signatur
--   (der Client ruft die Funktion so auf) - sie werden aber NICHT mehr
--   ausgewertet.
--
-- ZUSAETZLICH: DAS LIMIT 20 WAR WIRKLUNGSLOS
--
--   list_transit_candidates hatte "limit 20" HINTER dem jsonb_agg. Ein
--   Aggregat ohne GROUP BY liefert genau eine Zeile - das LIMIT galt
--   dieser einen Zeile und nicht den Kandidaten. Die im Kommentar
--   zugesagte Obergrenze "Hoechstens 20 Kandidaten" existierte nicht.
--   Jetzt begrenzt ein Inner-Subselect die Menge auf 20.
--
-- -----------------------------------------------------------------------------
-- 1) Die Kandidatenliste: die Beschreibung kommt aus dem eigenen Signal
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
  -- DIE BESCHREIBUNG DES AUFRUFERS - serverseitig, nicht vom Client.
  v_own_tags text[];
  v_own_self text[];
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

  -- DAS EIGENE SIGNAL: der einzige Ort, aus dem die Beschreibung kommt.
  --
  -- match_proximity_spark schreibt es beim "Blicke getauscht" - mit den
  -- dort gegen den Merkmals-Katalog geprueften Werten. Der Client kann
  -- deshalb nichts behaupten, was nicht auf dem Server steht.
  select s.tags, s.self_tags into v_own_tags, v_own_self
    from public.transit_signals s
   where s.user_id = v_user
     and s.status = 'pending'
     and s.created_at > v_cutoff
   order by s.created_at desc
   limit 1;

  -- Ohne eigenes Signal gibt es keine Kandidaten. Die Kandidatenliste ist
  -- die Antwort auf "Blicke getauscht"; das eigene Signal ist der
  -- Nachweis, dass der Aufrufer ueberhaupt am Radar teilnimmt.
  if v_own_tags is null and v_own_self is null then
    return '[]'::jsonb;
  end if;

  -- Das LIMIT 20 sitzt jetzt im Inner-Subselect: ein Aggregat ohne
  -- GROUP BY liefert genau eine Zeile, ein LIMIT dahinter begrenzt also
  -- nichts (BEFUND 13.11.2026).
  select coalesce(jsonb_agg(x.obj order by x.since desc), '[]'::jsonb)
    into v_result
    from (
      select s.user_id as id,
             s.created_at as since,
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
             ) as obj
        from public.transit_signals s
        join public.profiles p on p.user_id = s.user_id
       where s.user_id <> v_user
         and s.status = 'pending'
         and s.created_at > v_cutoff
         -- Die Beschreibung passt zu MEINER (serverseitig, aus meinem
         -- eigenen Signal) - nicht zu einer vom Client behaupteten.
         and (s.tags && coalesce(v_own_tags, '{}'::text[])
              or s.self_tags && coalesce(v_own_tags, '{}'::text[])
              or s.tags && coalesce(v_own_self, '{}'::text[])
              or s.self_tags && coalesce(v_own_self, '{}'::text[]))
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
       order by s.created_at desc
       limit 20
    ) x;

  return v_result;
end;
$$;

comment on function public.list_transit_candidates(text[], text[]) is
  '215: Die Personen in der Naehe, deren Beschreibung zu MEINER EIGENEN (serverseitig aus dem eigenen Signal) passt. Hoechstens 20. Die Argumente p_tags/p_self_tags werden NICHT ausgewertet - die Beschreibung kommt immer vom Server.';

revoke all on function public.list_transit_candidates(text[], text[]) from public, anon;
grant execute on function public.list_transit_candidates(text[], text[]) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2) Der Soft-Ping: die Naehe-Pruefung im Empfaenger-Weg nutzt das eigene
--    Signal des Absenders
-- -----------------------------------------------------------------------------
create or replace function public.send_soft_ping(
  p_token text,
  p_message_key text,
  p_custom_line text,
  p_recipient uuid DEFAULT NULL,
  p_place_kind text DEFAULT NULL,
  p_place_text text DEFAULT NULL,
  p_tags text[] DEFAULT '{}'::text[],
  p_self_tags text[] DEFAULT '{}'::text[]
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
  -- DIE BESCHREIBUNG DES ABSENDERS - serverseitig (BEFUND 13.11.2026).
  v_own_tags text[];
  v_own_self text[];
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

  -- BEFUND (11.11.2026): Der Token ist nur im Token-Weg die Eingangsgroesse.
  -- Im Empfaenger-Weg loest der Server den Begegnungs-Token selbst auf -
  -- vorher brach die Funktion hier ab und der neue Weg waere unbenutzbar.
  IF p_recipient IS NULL AND length(v_clean_token) < 8 THEN
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

    -- BEFUND (13.11.2026): DIE BESCHREIBUNG KOMMT VOM SERVER.
    --
    -- Frueher stand hier der Vergleich mit den Merkmals-Arrays aus dem
    -- Aufruf - die Merkmale kamen ungeprueft vom Client. Mit dem ganzen
    -- Merkmals-Katalog als Argument war die Naehe-Pruefung damit
    -- bedeutungslos (und 5 Zuwinke je 30 Minuten an beliebige nahe
    -- Personen moeglich).
    --
    -- Jetzt gilt: Der Empfaenger muss ein frisches Signal haben, dessen
    -- Beschreibung zu MEINER EIGENEN passt - und meine Beschreibung
    -- kommt aus MEINEM Signal, das der Server selbst geschrieben hat
    -- (match_proximity_spark, mit den gegen den Katalog geprueften
    -- Merkmalen).
    select s.tags, s.self_tags into v_own_tags, v_own_self
      from public.transit_signals s
     where s.user_id = v_uid
       and s.status = 'pending'
       and s.created_at > now() - interval '45 minutes'
     order by s.created_at desc
     limit 1;

    IF v_own_tags IS NULL AND v_own_self IS NULL THEN
      RAISE EXCEPTION 'Kein eigenes Signal - erst "Blicke getauscht" senden.';
    END IF;

    -- DIE NAEHE-PRUEFUNG: ein frisches Signal (45 min) mit einer
    -- passenden Beschreibung. Ohne sie kein Ping.
    SELECT s.id, s.user_id, s.self_token INTO v_signal
      FROM public.transit_signals s
     WHERE s.user_id = p_recipient
       AND s.status = 'pending'
       AND s.created_at > now() - interval '45 minutes'
       AND (s.tags && coalesce(v_own_tags, '{}'::text[])
            OR s.self_tags && coalesce(v_own_tags, '{}'::text[])
            OR s.tags && coalesce(v_own_self, '{}'::text[])
            OR s.self_tags && coalesce(v_own_self, '{}'::text[]))
     ORDER BY s.created_at DESC
     LIMIT 1;

    IF v_signal.user_id IS NULL THEN
      RAISE EXCEPTION 'Person ist nicht (mehr) in der Naehe.';
    END IF;

    -- DER BEGEGNUNGS-TOKEN (BEFUND 11.11.2026): Er ist NOT NULL. Im
    -- Empfaenger-Weg kommt er nicht ueber den Aufruf - der Server loest
    -- ihn selbst auf: aus dem BLE-Presence des Empfaengers (der
    -- Empfangernachweis) oder sonst aus dessen Signal.
    SELECT pr.token INTO v_clean_token
      FROM public.transit_presence pr
     WHERE pr.user_id = p_recipient
       AND pr.updated_at > now() - interval '45 minutes'
     ORDER BY pr.updated_at DESC
     LIMIT 1;

    IF v_clean_token IS NULL OR length(v_clean_token) < 8 THEN
      v_clean_token := v_signal.self_token;
    END IF;
    IF v_clean_token IS NULL OR length(v_clean_token) < 8 THEN
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

  -- Rate-Limit: BEFUND (11.11.2026) - "die Moeglichkeit hat auch mehrere
  -- anzuschreiben". Vorher war auf EINEN Ping je 30 Minuten begrenzt.
  -- Jetzt sind es fuenf - der Schutz gegen Spam bleibt.
  IF (SELECT count(*) FROM public.transit_soft_pings
       WHERE sender = v_uid AND created_at > now() - interval '30 minutes') >= 5 THEN
    RAISE EXCEPTION 'Kurz durchatmen: Bitte spaeter erneut.';
  END IF;

  -- Ein Ping pro Begegnungs-Token (Unique-Index); Zeitfenster 48 h.
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
comment on function public.send_soft_ping(text, text, text, uuid, text, text, text[], text[]) is
  '215: Der Zuwink an eine benannte Person wird gegen die BESCHRIBUNG DES ABSENDERS geprueft - und die kommt aus dem eigenen Signal des Absenders (serverseitig). Die Argumente p_tags/p_self_tags werden NICHT ausgewertet.';

revoke all on function public.send_soft_ping(text, text, text, uuid, text, text, text[], text[]) from public, anon;
grant execute on function public.send_soft_ping(text, text, text, uuid, text, text, text[], text[]) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3) Beweis (Fail-Fast): die Migration darf nicht "halb" angekommen sein
-- -----------------------------------------------------------------------------
do $$
declare
  v_liste text;
  v_ping text;
  -- DER CODE OHNE KOMMENTARE: ein Kommentar, der einen alten
  -- Parameternamen nennt, darf den Beweis nicht ausloesen (und umgekehrt
  -- soll der Beweis nur den echten Code pruefen).
  v_liste_code text;
  v_ping_code text;
begin
  select p.prosrc into v_liste
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'list_transit_candidates'
     and pg_get_function_identity_arguments(p.oid) = 'p_tags text[], p_self_tags text[]';

  if v_liste is null then
    raise exception 'Sicherheitscheck fehlgeschlagen: list_transit_candidates() fehlt.';
  end if;

  v_liste_code := regexp_replace(v_liste, '--[^\n]*', '', 'g');

  -- (a) Die Client-Argumente duerfen NICHT mehr ausgewertet werden.
  if v_liste_code ~* 'p_tags|p_self_tags' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: list_transit_candidates() wertet die Client-Argumente p_tags/p_self_tags noch aus - damit waere die Enumeration wieder moeglich.';
  end if;

  -- (b) Die Beschreibung muss aus dem eigenen Signal kommen.
  if v_liste_code !~* 'v_own_tags' or v_liste_code !~* 'transit_signals' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: list_transit_candidates() holt die Beschreibung nicht aus dem eigenen Signal.';
  end if;

  -- (c) Das 18+-Gate und der Blockierschutz muessen bleiben.
  if v_liste_code !~* 'transit_spark_adult' or v_liste_code !~* 'blocked_users' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: list_transit_candidates() verliert das 18+-Gate oder den Blockierschutz.';
  end if;

  -- (d) Die Obergrenze von 20 Kandidaten muss im Inner-Subselect stehen.
  if v_liste_code !~* 'limit\s+20' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: list_transit_candidates() begrenzt die Kandidatenliste nicht auf 20.';
  end if;

  select p.prosrc into v_ping
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'send_soft_ping'
     and pg_get_function_identity_arguments(p.oid) =
         'p_token text, p_message_key text, p_custom_line text, '
         'p_recipient uuid, p_place_kind text, p_place_text text, '
         'p_tags text[], p_self_tags text[]';

  if v_ping is null then
    raise exception 'Sicherheitscheck fehlgeschlagen: send_soft_ping() fehlt.';
  end if;

  v_ping_code := regexp_replace(v_ping, '--[^\n]*', '', 'g');

  -- (e) Auch im Ping darf der Client die Beschreibung nicht bestimmen.
  if v_ping_code ~* 'p_tags|p_self_tags' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: send_soft_ping() wertet die Client-Argumente p_tags/p_self_tags noch aus - ein Zuwink an eine beliebige nahe Person waere wieder moeglich.';
  end if;

  -- (f) Die Naehe-Pruefung und der Blockierschutz bleiben.
  if v_ping_code !~* 'transit_signals' or v_ping_code !~* 'blocked_users' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: send_soft_ping() verliert die Naehe-Pruefung oder den Blockierschutz.';
  end if;

  -- (g) Der Begegnungs-Token wird weiterhin selbst aufgeloest.
  if v_ping_code !~* 'transit_presence' or v_ping_code !~* 'self_token' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: send_soft_ping() loest den Begegnungs-Token nicht selbst auf.';
  end if;
end;
$$;
