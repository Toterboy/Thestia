-- =============================================================================
-- 214_fix_send_soft_ping_encounter_token.sql
-- =============================================================================
-- SOFORT-KORREKTUR zu Migration 213 (live gefunden, 11.11.2026).
--
-- DER FEHLER: Beim Zuwinken an einen BENANNTEN Empfaenger (p_recipient)
-- ist der Begegnungs-Token (encounter_token) leer - der kam ja gerade
-- nicht ueber den BLE-Token. Der INSERT verletzt dadurch die
-- NOT-NULL-Bedingung:
--
--     ERROR: 23502: null value in column "encounter_token" of relation
--     "transit_soft_pings" violates not-null constraint
--
-- DER EFFEKT: Der Ping an einen Kandidaten (die neue Funktion) ging
-- NIEMALS durch - die Ortsangabe und "mehrere anschreiben" waeren
-- unbenutzbar.
--
-- DIE LOESUNG: Der Begegnungs-Token wird beim Empfaenger-Weg selbst
-- aufgeloest:
--   1. aus dem BLE-Presence des Empfaengers (der eigentliche
--      Empfangernachweis - so wie im Token-Weg), sonst
--   2. aus dem Signal des Empfaengers (dessen eigener Token).
--
-- Und: Die Token-Pflicht gilt nur noch im Token-Weg. Im Empfaenger-Weg
-- ist der Token nicht die Eingangsgroesse (sonst waere die ganze
-- Funktion unbenutzbar).
-- =============================================================================

begin;

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

    -- DIE NAEHE-PRUEFUNG: ein frisches Signal (45 min) mit einer
    -- passenden Beschreibung. Ohne sie kein Ping.
    SELECT s.id, s.user_id, s.self_token INTO v_signal
      FROM public.transit_signals s
     WHERE s.user_id = p_recipient
       AND s.status = 'pending'
       AND s.created_at > now() - interval '45 minutes'
       AND (s.tags && coalesce(p_tags, '{}'::text[])
            OR s.self_tags && coalesce(p_tags, '{}'::text[])
            OR s.tags && coalesce(p_self_tags, '{}'::text[])
            OR s.self_tags && coalesce(p_self_tags, '{}'::text[]))
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
  '214: der Transit-Zuwinken. Neu: der Empfaenger kann direkt benannt werden (p_recipient) - der Server prueft die Naehe und den Begegnungs-Token selbst.';

revoke all on function public.send_soft_ping(text, text, text, uuid, text, text, text[], text[]) from public, anon;
grant execute on function public.send_soft_ping(text, text, text, uuid, text, text, text[], text[]) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast)
-- -----------------------------------------------------------------------------
do $$
declare
  v_src text;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'send_soft_ping'
     and pg_get_function_identity_arguments(p.oid) =
         'p_token text, p_message_key text, p_custom_line text, '
         'p_recipient uuid, p_place_kind text, p_place_text text, '
         'p_tags text[], p_self_tags text[]';

  if v_src is null then
    raise exception
      'Sicherheitscheck fehlgeschlagen: send_soft_ping() (neue Signatur) fehlt.';
  end if;

  -- (a) Der Begegnungs-Token muss im Empfaenger-Weg selbst aufgeloest
  --     werden - sonst verletzt der INSERT die NOT-NULL-Bedingung.
  if v_src !~* 'transit_presence' or v_src !~* 'self_token' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: send_soft_ping() loest den Begegnungs-Token nicht selbst auf - der INSERT wuerde an NOT NULL scheitern.';
  end if;

  -- (b) Die Token-Pflicht darf nur im Token-Weg gelten.
  if v_src !~* 'p_recipient\s+is\s+null\s+and\s+length\(v_clean_token\)' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: Die Token-Pflicht gilt auch im Empfaenger-Weg - der neue Weg waere unbenutzbar.';
  end if;

  -- (c) Die Naehe-Pruefung und der Blockierschutz bleiben.
  if v_src not like '%transit_signals%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: send_soft_ping() prueft die Naehe nicht.';
  end if;
  if v_src not like '%blocked_users%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: send_soft_ping() verliert den Blockierschutz.';
  end if;
end;
$$;

commit;
