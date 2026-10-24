-- =============================================================================
-- 156_verification_trigger_repair_and_report_types.sql
-- =============================================================================
-- Security-Audit vom 22.10.2026. Drei Bloecker und drei Nachzuegler.
--
-- BLOECKER 1 (KRITISCH): Der Trigger-Schutz der Verifikationsfelder war
-- fail-open.
--
-- Migration 155 hat die Funktion public.prevent_client_update_verification_fields()
-- mit `pg_has_role(current_user, 'authenticated', 'member')` neu definiert.
-- In einer SECURITY DEFINER-Funktion ist current_user der OWNER der
-- Funktion (postgres), nicht die aufrufende Rolle. pg_has_role(postgres,
-- 'authenticated', 'member') ist false - die Bedingung war damit NIE
-- wahr, und die RAISE EXCEPTION wurde nie ausgeloest.
--
-- Folge: jeder angemeldete Nutzer konnte per Data API sein eigenes
-- Profil setzen: is_verified = true, verified_age = 100,
-- verification_status = 'approved', birth_date beliebig. Damit waeren
-- Badge, Modus-Sperre und der komplette Jugendschutz-Filter
-- client-kontrolliert.
--
-- Der Fehler war im Repo schon einmal da und wurde behoben:
--   061_misc_hardening.sql:165-182 (is_admin) und
--   056_age_safety_enforcement.sql:115-137 (Verifikationsfelder)
-- benutzen den Role-Claim aus dem JWT, nicht pg_has_role. Migration 155
-- hat die gute Fassung durch die schlechte ersetzt - deshalb wird sie
-- hier wiederhergestellt.
--
-- ZWEITER DEFEKT in derselben Funktion: `is_location_suspicious` war in
-- 056 (Zeile 130) und 095 (Zeile 56) geschuetzt, in 155 aber weggefallen.
-- Damit war das Betrugs-/Auffaelligkeits-Flag client-loeschbar.
--
-- BLOECKER 2: Der Meldeweg fuer Kindesmissbrauch funktionierte nicht.
--
-- Der Client sendet ReportType.name (camelCase): 'inappropriateContent',
-- 'fakeProfile', 'wrongAge', 'childSafety'. Die Server-Whitelist in
-- submit_report (Migration 060) kannte nur snake_case und nur fuenf Typen
-- - 'harassment', 'inappropriate_content', 'spam', 'fake_profile', 'other'.
-- Damit wurden vier von sieben Meldetypen serverseitig abgewiesen,
-- darunter childSafety. Die App zeigte dem Nutzer trotzdem die gruene
-- Bestaetigung, weil der Fehler nur geloggt wurde.
--
-- Play verlangt fuer Dating- und Random-Chat-Apps einen funktionierenden
-- Meldeweg fuer Hinweise auf Kindesmissbrauch, und kinderschutz.html
-- sagt ihn oeffentlich zu. Beides ist jetzt wahr.
--
-- BLOECKER 3: Die automatische Freigabe war tot.
--
-- Seit Migration 151 laedt der Client das Video verschluesselt hoch
-- (video.mp4.enc). verify-account pruefte aber auf 'video.mp4' und
-- antwortete deshalb immer mit HTTP 400 "Video nicht gefunden". Und bei
-- einer Ablehnung wurde 'video.mp4' geloescht - das Chiffrat
-- 'video.mp4.enc' blieb liegen (DSGVO Art. 17).
--
-- NACHZUEGLER:
--   * get_find_match_candidates verlangte keine Verifikation des
--     Aufrufers - die Zusage aus Migration 155 galt nur auf dem
--     Umkreis-Pfad.
--   * assert_age_compatible rechnete mit dem deklarierten Alter und nur
--     einseitig - zwei Altersquellen im selben Schutzkonzept.
--   * min_app_version_build stand auf 30, obwohl Migration 138 den
--     Spalten city/location_lat/location_lng entfernt hat. Build-30-
--     Clients fragen diese Spalten ab und bekommen damit einen Fehler.
--   * profile_to_jsonb zeigte das DEKLARIERTE Alter an, gefiltert wurde
--     aber nach dem effektiven Alter. Anzeige und Filter konnten
--     auseinanderlaufen.
-- =============================================================================

-- =============================================================================
-- 1) BLOECKER 1: Der Client-Schreibschutz fuer Verifikationsfelder
-- =============================================================================
-- Gleiches Muster wie 056/095/061: der Role-Claim aus dem JWT ist die
-- verlaessliche Quelle. Im SECURITY DEFINER-Kontext ist current_user der
-- Owner der Funktion, deshalb taugt pg_has_role dort nicht.
--
-- 'service_role' (Edge Functions) und der Cron (kein JWT) sind NICHT in
-- der Liste und duerfen schreiben - nur so kann verify-account das
-- Badge setzen.
CREATE OR REPLACE FUNCTION public.prevent_client_update_verification_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::json->>'role',
    '');
BEGIN
  IF (NEW.is_verified IS DISTINCT FROM OLD.is_verified
      OR NEW.is_location_suspicious IS DISTINCT FROM OLD.is_location_suspicious
      OR NEW.birth_date IS DISTINCT FROM OLD.birth_date
      OR NEW.verification_status IS DISTINCT FROM OLD.verification_status
      OR NEW.verification_estimated_age IS DISTINCT FROM
           OLD.verification_estimated_age
      OR NEW.verified_age IS DISTINCT FROM OLD.verified_age)
  THEN
    IF v_role IN ('authenticated', 'anon') THEN
      RAISE EXCEPTION
        'Gesicherte Profil-Felder (birth_date, verification) sind clientseitig nicht aenderbar.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.prevent_client_update_verification_fields() IS
  'Verhindert, dass Clients is_verified, is_location_suspicious, birth_date, '
  'verification_status, verification_estimated_age oder verified_age selbst '
  'setzen. Erlaubt sind nur service_role (Edge Functions) und der Cron. '
  'Wichtig: die Rollenpruefung liest den Role-Claim aus dem JWT - '
  'pg_has_role(current_user, ...) taugt im SECURITY DEFINER-Kontext nicht, '
  'weil current_user dort der Owner der Funktion ist (v0.10.0, Migration 156).';

-- EIN Trigger statt zwei.
--
-- Migration 002 hat 'prevent_client_update_verification_fields_trigger'
-- angelegt, Migration 155 zusaetzlich 'trg_prevent_client_update_
-- verification_fields'. Beide rufen dieselbe Funktion auf - der zweite
-- ist redundant. Beide werden hier entfernt und einer wieder angelegt,
-- damit die Reihenfolge der Pruefungen eindeutig ist.
DROP TRIGGER IF EXISTS trg_prevent_client_update_verification_fields
  ON public.profiles;
DROP TRIGGER IF EXISTS prevent_client_update_verification_fields_trigger
  ON public.profiles;
CREATE TRIGGER prevent_client_update_verification_fields_trigger
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_client_update_verification_fields();

-- BEWEIS (Fail-Fast): Die Funktion muss den Role-Claim benutzen. Ein
-- Zurueckfallen auf pg_has_role waere wieder fail-open, und dann waere
-- der ganze Jugendschutz client-kontrolliert.
DO $$
DECLARE
  v_src text;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'prevent_client_update_verification_fields';
  IF v_src IS NULL THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: prevent_client_update_verification_fields() fehlt.';
  END IF;
  IF v_src NOT ILIKE '%request.jwt.claims%' THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: der Verifikations-Trigger liest den JWT-Role-Claim nicht. '
      'Er wuerde im SECURITY DEFINER-Kontext nie ausgeloest (fail-open).';
  END IF;
  IF v_src ILIKE '%pg_has_role%' THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: der Verifikations-Trigger benutzt pg_has_role. '
      'Das ist im SECURITY DEFINER-Kontext unwirksam.';
  END IF;
  IF v_src NOT ILIKE '%is_location_suspicious%' THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: is_location_suspicious ist nicht geschuetzt.';
  END IF;
  IF v_src NOT ILIKE '%verified_age%' THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: verified_age ist nicht geschuetzt.';
  END IF;
END;
$$;

-- =============================================================================
-- 2) BLOECKER 2: submit_report akzeptiert die Client-Werte
-- =============================================================================
-- Der Client sendet ReportType.name. Die historische snake_case-Schreibweise
-- bleibt zulaessig, damit bereits installierte aeltere Clients nicht
-- abbrechen - intern gespeichert wird immer camelCase, weil die Admin-
-- Anzeige und die Eskalation genau darauf pruefen.
CREATE OR REPLACE FUNCTION public.submit_report(
  p_reported_user_id UUID,
  p_report_type      TEXT,
  p_description      TEXT,
  p_messages         JSONB
)
RETURNS public.user_reports
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result public.user_reports;
  v_user uuid := auth.uid();
  v_report_type text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- fail-closed: erlaubte Typen.
  --
  -- Beide Schreibweisen werden angenommen, aber auf camelCase
  -- normalisiert: das ist der Name, den der Client sendet (ReportType.name)
  -- und der, den die Admin-Liste und die Eskalation kennen.
  v_report_type := CASE p_report_type
    WHEN 'inappropriate_content' THEN 'inappropriateContent'
    WHEN 'fake_profile'         THEN 'fakeProfile'
    ELSE p_report_type
  END;

  IF v_report_type NOT IN (
    'harassment', 'inappropriateContent', 'spam', 'fakeProfile', 'other',
    'wrongAge', 'childSafety'
  ) THEN
    RAISE EXCEPTION 'Invalid report type: %', p_report_type;
  END IF;

  -- Ziel validieren: muss existieren und darf nicht der Reporter selbst
  -- sein (Audit M-5: NULL-/Fantasie-/Selbst-Meldungen).
  IF p_reported_user_id IS NULL OR p_reported_user_id = v_user THEN
    RAISE EXCEPTION 'invalid_reported_user';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.user_id = p_reported_user_id
  ) THEN
    RAISE EXCEPTION 'invalid_reported_user';
  END IF;

  -- Rate-Limit: 5 Reports/Stunde pro Reporter (Massen-Reporting-Schutz).
  IF NOT public.consume_rate_limit(
       'reports:' || v_user::text, 5, 3600) THEN
    RAISE EXCEPTION 'report_rate_limited';
  END IF;

  -- Dedup: gleiche Meldung (Reporter, Ziel, Typ) innerhalb von 24 h
  -- wird abgelehnt statt endlos dupliziert.
  IF EXISTS (
    SELECT 1 FROM public.user_reports r
     WHERE r.reporter_id = v_user
       AND r.reported_user_id = p_reported_user_id
       AND r.report_type = v_report_type
       AND r.created_at > now() - interval '24 hours'
  ) THEN
    RAISE EXCEPTION 'duplicate_report';
  END IF;

  -- Laenge-Caps: Beschreibung 2000 Zeichen, Evidence-JSON 20k Zeichen.
  IF length(p_description) > 2000 THEN
    p_description := left(p_description, 2000);
  END IF;

  IF p_messages IS NOT NULL AND length(p_messages::text) > 20000 THEN
    RAISE EXCEPTION 'messages_payload_too_large';
  END IF;

  -- fail-closed: maximal die letzten 3 Nachrichten uebernehmen
  IF jsonb_typeof(p_messages) = 'array' AND jsonb_array_length(p_messages) > 3 THEN
    p_messages := (
      SELECT COALESCE(jsonb_agg(elem ORDER BY ord), '[]'::jsonb)
      FROM (
        SELECT elem, ord
        FROM jsonb_array_elements(p_messages) WITH ORDINALITY AS t(elem, ord)
        ORDER BY ord DESC
        LIMIT 3
      ) sub
    );
  END IF;

  INSERT INTO public.user_reports (reporter_id, reported_user_id, report_type, description, messages)
  VALUES (v_user, p_reported_user_id, v_report_type, p_description, p_messages)
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.submit_report(uuid, text, text, jsonb) IS
  'Nimmt Meldungen entgegen. Erlaubte Typen (camelCase, wie der Client sie '
  'sendet): harassment, inappropriateContent, spam, fakeProfile, other, '
  'wrongAge, childSafety. Die historische snake_case-Schreibweise wird '
  'auf camelCase normalisiert (v0.10.0, Migration 156).';

-- Eskalation: Hinweise auf Kindesmissbrauch kommen zuerst.
--
-- kinderschutz.html sagt oeffentlich zu, dass Meldungen mit diesem Grund
-- "gesondert und vorrangig bearbeitet" werden. Bisher war die Admin-
-- Liste rein chronologisch - die Zusage war nicht eingeloest.
CREATE OR REPLACE FUNCTION public.admin_list_user_reports()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(jsonb_agg(
           jsonb_build_object(
             'id', r.id,
             'reportType', r.report_type,
             'description', r.description,
             'messages', r.messages,
             'status', r.status,
             'createdAt', r.created_at,
             'reporterId', r.reporter_id,
             'reportedUserId', r.reported_user_id
           )
           ORDER BY (CASE WHEN r.report_type = 'childSafety' THEN 0 ELSE 1 END),
                    r.created_at DESC), '[]'::jsonb)
  FROM public.user_reports r
  WHERE public.is_current_user_admin();
$$;

COMMENT ON FUNCTION public.admin_list_user_reports() IS
  'Liste der Meldungen fuer Admins. Meldungen vom Typ childSafety stehen '
  'vorn, sonst sind sie chronologisch (v0.10.0, Migration 156).';

-- =============================================================================
-- 3) NACHZUEGLER: get_find_match_candidates verlangt Verifikation
-- =============================================================================
-- Migration 155 hat die Verifikationspflicht nur fuer get_nearby_profiles
-- eingefuehrt. "Find your Match" lief am Schutzwall vorbei: dort konnte
-- ein unbestattigtes Konto Kandidatenlisten abrufen, und die Alterslogik
-- rechnete mit dem deklarierten Geburtsdatum.
--
-- Jetzt gilt derselbe Massstab wie im Umkreis-Pfad: der Aufrufer muss
-- verifiziert sein, der Kandidat ebenfalls, und beide Altersangaben
-- werden ueber profile_effective_age (verifiziertes Alter, sonst
-- deklariertes) gelesen.
CREATE OR REPLACE FUNCTION public.get_find_match_candidates(p_limit int default 20)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_result jsonb;
BEGIN
  -- Ohne Altersnachweis keine Vorschlagsliste (wie get_nearby_profiles).
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
     WHERE user_id = v_user AND is_verified
  ) THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(t) order by t.random_order), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT p.*,
             (select public.profile_distance_km(p.user_id)) as distance_km,
             random() as random_order
        FROM public.public_profiles p
        JOIN public.profiles me ON me.user_id = v_user
        JOIN public.profiles cand ON cand.user_id = p.user_id
       WHERE p.user_id <> v_user
         and (p.intro_text <> '' or p.intro_audio_path is not null)
         -- Der Kandidat muss ebenfalls bestaetigt sein: ein Konto ohne
         -- Altersnachweis darf in keiner Vorschlagsliste auftauchen.
         and coalesce(cand.is_verified, false)
         and not exists (
               select 1 from public.likes l
                where (l.user_id = v_user and l.liked_user_id = p.user_id)
                   or (l.user_id = p.user_id and l.liked_user_id = v_user))
         and not exists (
               select 1 from public.matches m
                where (m.user_one_id = v_user and m.user_two_id = p.user_id)
                   or (m.user_one_id = p.user_id and m.user_two_id = v_user))
         -- Viewer-Filter (bestehend).
         and (me.gender_preferences is null
              or me.gender_preferences = '{}'::text[]
              or p.gender = any(me.gender_preferences))
         -- Altersspanne: mit dem effektiven Alter, nicht mit dem
         -- deklarierten (Migration 155/156).
         and public.profile_effective_age(cand.birth_date, cand.verified_age)
               between me.age_range_min and me.age_range_max
         -- Reziprozitaet: Praferenzen des Kandidaten (Audit M-2).
         and (cand.gender_preferences is null
              or cand.gender_preferences = '{}'::text[]
              or me.gender = any(cand.gender_preferences))
         and public.profile_effective_age(me.birth_date, me.verified_age)
             between cand.age_range_min and cand.age_range_max
         -- Beidseitige Alterskompatibilitaet: dieselbe Regel wie in der
         -- Discovery. Sonst koennte ein Konto ueber "Find your Match"
         -- eine Begegnung aufbauen, die die Umkreis-Liste nie zeigen
         -- wuerde.
         and public.age_compatible_bidirectional_ages(
               public.profile_effective_age(me.birth_date, me.verified_age),
               public.profile_effective_age(cand.birth_date, cand.verified_age))
         -- Konsum-Filter aus 047 (in 050 versehentlich verloren gegangen).
         and (me.smoking is null or me.smoking = ''
              or coalesce(public._habitude_rank(p.smoking), 0)
                 <= public._habitude_rank(me.smoking))
         and (me.alcohol is null or me.alcohol = ''
              or coalesce(public._habitude_rank(p.alcohol), 0)
                 <= public._habitude_rank(me.alcohol))
         and (me.drugs is null or me.drugs = ''
              or coalesce(public._habitude_rank(p.drugs), 0)
                 <= public._habitude_rank(me.drugs))
         -- NEU (088): "Ich suche"-Reziprozitaet. Freunde-Sucher sehen nur
         -- Freunde-Sucher (beide Seiten wollen keine Dates); alle anderen
         -- Beziehungsarten sehen einander, aber nie Freunde-Sucher.
         and ((coalesce(me.relationship_type, 'other') = 'friends')
              = (coalesce(cand.relationship_type, 'other') = 'friends'))
       order by random()
       limit least(p_limit, 50)
    ) t;
  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_find_match_candidates(int) IS
  'Kandidatenliste fuer "Find your Match". Verlangt ein verifiziertes '
  'Aufruferkonto UND ein verifiziertes Kandidatenkonto und rechnet mit '
  'dem effektiven Alter (v0.10.0, Migration 156).';

-- =============================================================================
-- 4) NACHZUEGLER: assert_age_compatible mit dem effektiven Alter
-- =============================================================================
-- Die Like-/Match-Pfade benutzten das deklarierte Geburtsdatum, waehrend
-- die Discovery seit Migration 154/155 das verifizierte Alter benutzt.
-- Zwei Altersquellen im selben Schutzkonzept.
--
-- Zusaetzlich wird die Regel beidseitig angewandt, wie in der Discovery:
-- ein 18-Jaehriger kann danach keinen 17-Jaehrigen mehr liken. Das
-- entspricht dem, was die Umkreis-Liste ohnehin schon zeigt, und
-- verhindert, dass der Like-Pfad die Discovery-Regel umgeht.
CREATE OR REPLACE FUNCTION public.assert_age_compatible(v_viewer uuid, v_target uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_viewer_age int;
  v_target_age int;
BEGIN
  IF v_viewer IS NULL OR v_target IS NULL OR v_viewer = v_target THEN
    RETURN;
  END IF;

  SELECT public.profile_effective_age(p.birth_date, p.verified_age)
    INTO v_viewer_age
    FROM public.profiles p WHERE p.user_id = v_viewer;
  SELECT public.profile_effective_age(p.birth_date, p.verified_age)
    INTO v_target_age
    FROM public.profiles p WHERE p.user_id = v_target;

  IF v_viewer_age IS NULL OR v_target_age IS NULL THEN
    RETURN;  -- Ohne Daten keine Paarung erzwingen (fail-open nur fuer Legacy-Zeilen)
  END IF;

  IF NOT public.age_compatible_bidirectional_ages(v_viewer_age, v_target_age) THEN
    RAISE EXCEPTION 'age_restricted';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_age_compatible(uuid, uuid) IS
  'Prueft die Alterskompatibilitaet fuer Like-/Match-Pfade. Rechnet mit dem '
  'effektiven Alter (verifiziert, sonst deklariert) und beidseitig - '
  'identisch zur Discovery-Regel (v0.10.0, Migration 156).';

-- =============================================================================
-- 5) NACHZUEGLER: Anzeigealter = Filteralter
-- =============================================================================
-- profile_to_jsonb zeigte das deklarierte Alter, gefiltert wurde nach dem
-- effektiven. Ein Konto mit verified_age = 28 und deklariertem Alter 30
-- erschien als 30, wurde aber als 28 gefiltert. Die Anzeige muss die
-- Zahl zeigen, nach der auch entschieden wird.
CREATE OR REPLACE FUNCTION public.profile_to_jsonb(p_user_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
           'user_id', p.user_id,
           'name', p.name,
           'gender', coalesce(p.gender, 'unknown'),
           'bio', coalesce(p.bio, ''),
           'interests', coalesce(p.interests, '[]'::jsonb),
           'personality_type', coalesce(p.personality_type, 'INTJ'),
           'age', public.profile_effective_age(p.birth_date, p.verified_age),
           'created_at', coalesce(p.created_at, now()),
           'updated_at', coalesce(p.updated_at, now()),
           'mood', um.mood,
           'intro_text', coalesce(p.intro_text, ''),
           'intro_audio_path', p.intro_audio_path,
           'smoking', p.smoking,
           'alcohol', p.alcohol,
           'drugs', p.drugs,
           'music_liked', coalesce(p.music_liked, '{}'::text[]),
           'music_disliked', coalesce(p.music_disliked, '{}'::text[]),
           'paused', p.paused,
           'photos', coalesce(ph.cleaned, '{}'::text[]),
           'favorite_song', coalesce(p.favorite_song, ''),
           'birthday_style', coalesce(p.birthday_style, 'classic'),
           'birthday_today', coalesce(
             p.birth_date IS NOT NULL
             AND date_part('month', p.birth_date) = date_part('month', CURRENT_DATE)
             AND date_part('day', p.birth_date) = date_part('day', CURRENT_DATE),
             false),
           'favorite_band', coalesce(p.favorite_band, ''),
           -- Verifikationsstatus (v0.10.0, Migration 144)
           'is_verified', coalesce(p.is_verified, false),
           'verification_state', CASE
             WHEN coalesce(p.is_verified, false) THEN 'verified'
             WHEN p.verification_status IN ('pending', 'pending_minor') THEN 'under_review'
             ELSE 'unverified'
           END
         )
    FROM public.profiles p
    LEFT JOIN LATERAL (
      SELECT mood FROM public.user_mood
       WHERE user_id = p.user_id AND mood_date = CURRENT_DATE
       ORDER BY created_at DESC LIMIT 1
    ) um ON true
    LEFT JOIN LATERAL (
      SELECT array_agg(split_part(entry, '|', 1) ORDER BY ord) AS cleaned
        FROM unnest(coalesce(p.photos, '{}'::text[])) WITH ORDINALITY AS u(entry, ord)
    ) ph ON true
   WHERE p.user_id = p_user_id;
$$;

-- =============================================================================
-- 6) NACHZUEGLER: Mindest-App-Version auf 31
-- =============================================================================
-- Build 31 (v0.10.0) ist der Stand, der die Verifikationssperren, die
-- Transit-Merkmale und das Datenschutz-Modell kennt. Build 30 kann sie
-- nicht: Migration 138 hat city/location_lat/location_lng aus profiles
-- entfernt, und Build 30 fragt diese Spalten ab - die Antwort ist ein
-- Fehler, das Profil bleibt unvollstaendig.
--
-- Migration 132 hatte 30 gesetzt, weil Build 30 damals der unterstuetzte
-- Stand war. Seit Build 31 veroeffentlicht ist, ist 30 abgeloest.
INSERT INTO public.app_config (key, value)
VALUES ('min_app_version_build', '31')
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value;

DO $$
DECLARE
  v_val text;
BEGIN
  SELECT value INTO v_val FROM public.app_config WHERE key = 'min_app_version_build';
  IF v_val IS DISTINCT FROM '31' THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: min_app_version_build ist "%", erwartet "31".', v_val;
  END IF;
END;
$$;

-- =============================================================================
-- 7) Rechte der Funktionen aus 148-155
-- =============================================================================
-- BEFUND (Security-Audit 22.10.2026, beim Deploy von 156):
--
-- Die Funktionen aus den Migrationen 148, 149, 154 und 155 waren fuer
-- die Rolle `anon` aufrufbar. Sie sind reine Rechenfunktionen und geben
-- keine Daten preis - aber `anon` ist die Rolle OHNE JWT, also der
-- oeffentliche Zugriff. Der Grund ist, dass die Default-Privilegien aus
-- Migration 123/147 nur fuer die Rolle wirken, unter der die jeweilige
-- Funktion spaeter tatsaechlich angelegt wurde; fuer die Funktionen aus
-- 148-155 ist das offenbar eine andere Rolle als `postgres`.
--
-- Der Gegenbeweis hat genau das aufgedeckt: der erste Deploy-Versuch von
-- 156 ist an der eigenen Pruefung gescheitert ("profile_effective_age ist
-- fuer anon aufrufbar"). Die Migration hat damit ihren Zweck erfüllt,
-- obwohl sie nicht durchlief.
--
-- Konsequenz: die Rechte werden hier ausdruecklich gesetzt - fuer jede
-- Rolle einzeln. Das ist unabhaengig davon, welche Default-Privilegien
-- gerade gelten. Deshalb steht der REVOKE VOR der Pruefung: sonst prueft
-- die Migration einen Zustand, den sie selbst erst herstellen soll.
--
-- Betroffen sind nur die NEU angelegten Funktionen. Bei
-- CREATE OR REPLACE bleiben die Rechte der bestehenden Funktion erhalten
-- (CREATE OR REPLACE aendert die Berechtigungen nicht) - die in 123
-- gepruefften Funktionen behalten ihre Rechte damit unveraendert.
--
-- Fuer die intern aufgerufenen Helfer (transit_tag_limits,
-- max_age_range_min) ist das Entziehen unkritisch: der Aufruf kommt aus
-- SECURITY-DEFINER-Funktionen und laeuft damit unter dem Owner.
REVOKE EXECUTE ON FUNCTION public.transit_tag_limits() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.max_age_range_min(int) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.age_compatible_bidirectional_ages(int, int) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.profile_effective_age(date, int) FROM PUBLIC, anon, authenticated;

-- Der Trigger-Schutz gehoert niemandem ausser dem Owner.
REVOKE EXECUTE ON FUNCTION public.prevent_client_update_verification_fields()
  FROM PUBLIC, anon, authenticated;

-- match_proximity_spark bleibt fuer angemeldete Nutzer aufrufbar
-- (Migration 149), aber nicht mehr fuer die oeffentliche Rolle.
REVOKE EXECUTE ON FUNCTION
  public.match_proximity_spark(text[], text[], text, text[], text)
  FROM PUBLIC, anon;

-- Die beiden Altersfunktionen braucht die Edge Function match-media -
-- sie laeuft mit service_role.
GRANT EXECUTE ON FUNCTION public.age_compatible_bidirectional_ages(int, int)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.profile_effective_age(date, int)
  TO service_role;

-- Gegenprobe: die Altersfunktionen muessen fuer service_role da sein...
DO $$
BEGIN
  IF NOT has_function_privilege(
       'service_role',
       'public.profile_effective_age(date, integer)',
       'EXECUTE')
     OR NOT has_function_privilege(
       'service_role',
       'public.age_compatible_bidirectional_ages(integer, integer)',
       'EXECUTE') THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: die Altersfunktionen sind fuer '
      'service_role nicht aufrufbar - match-media wuerde mit 42501 scheitern.';
  END IF;
END;
$$;

-- ... und keine der geprueften Funktionen darf fuer anon oder
-- authenticated aufrufbar sein.
DO $$
DECLARE
  v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.transit_tag_limits()',
    'public.max_age_range_min(integer)',
    'public.age_compatible_bidirectional_ages(integer, integer)',
    'public.profile_effective_age(date, integer)',
    'public.prevent_client_update_verification_fields()'
  ]
  LOOP
    IF has_function_privilege('anon', v_sig, 'EXECUTE')
       OR has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION
        'Sicherheitscheck fehlgeschlagen: % ist noch fuer die App-Rollen '
        'aufrufbar.', v_sig;
    END IF;
  END LOOP;

  -- match_proximity_spark: anon nein, authenticated ja.
  IF has_function_privilege('anon',
       'public.match_proximity_spark(text[], text[], text, text[], text)',
       'EXECUTE') THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: match_proximity_spark ist fuer anon '
      'aufrufbar.';
  END IF;
  IF NOT has_function_privilege('authenticated',
       'public.match_proximity_spark(text[], text[], text, text[], text)',
       'EXECUTE') THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: match_proximity_spark ist nicht mehr '
      'fuer angemeldete Nutzer aufrufbar - der Transit Spark waere tot.';
  END IF;
END;
$$;
