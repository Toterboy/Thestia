-- 176: E-Mail im Profil, Zeitzone, serverseitige Nutzungszeit
--
-- UND: ein Fund, der die Dating Hour gerettet hat.
--
-- =========================================================================
-- TEIL 1: DER FUND - die Dating Hour hat seit Migration 161 nicht mehr
--          gepaart (und niemand hat es gemerkt)
-- =========================================================================
--
-- BEWEIS:
--
--   * Die App ruft NUR public.join_dating_hour auf
--     (lib/services/dating_hour_service.dart:76). Die Paarung
--     passiert ausschliesslich ueber den Cron-Job
--     "dating-hour-matcher" (alle 30 Sekunden), der
--     public.run_dating_hour_scheduler() aufruft - und diese wiederum
--     public.match_dating_hour_round(v_event.id).
--
--   * match_dating_hour_round prueft seit Migration 161:
--
--         IF NOT public.verification_granted(auth.uid()) THEN
--           RAISE EXCEPTION 'verification_required';
--         END IF;
--
--   * Der Cron laeuft OHNE JWT. auth.uid() ist dort NULL.
--     public.verification_granted(NULL) liest
--     "WHERE p.user_id = NULL" - keine Zeile - ALSO FALSE.
--
--   ==> Der Cron wirft bei der ERSTEN aktiven Veranstaltung
--       'verification_required'. Die Ausnahme verlaesst die gesamte
--       run_dating_hour_scheduler - es wird also nicht nur EIN Event
--       uebersprungen, sondern KEIN einziges gepaart.
--
--   ==> Die Dating Hour - das woechentliche Event mit
--       Fuenf-Minuten-Gespraechen - hat seit dem 03.11.2026 KEINE
--       Paarung mehr erzeugt. Im Repo ist das nicht aufgefallen,
--       weil die Funktionen "gruen" sind und die App ihren Teil
--       (join_dating_hour) korrekt aufruft.
--
-- DIE URSACHE: Die Verifikationspruefung pruefte den AUFRUFER. Fuer
-- einen vom Client ausgeloesten Aufruf ist das richtig (wer die
-- Funktion aufruft, muss verifiziert sein). Fuer die vom Cron
-- ausgeloeste Runde ist es sinnlos - dort gibt es keinen Aufrufer,
-- den man pruefen koennte. Richtig ist: die TEILNEHMER werden
-- geprueft, und das passiert bereits in der Schleife
-- (public.verification_granted(v_user.user_id)).
--
-- DIE LOESUNG: Der Aufrufer wird nur geprueft, wenn er selbst
-- handelt (auth.uid() IS NOT NULL). Im Cron-Fall uebernimmt die
-- Teilnehmerpruefung in der Schleife - die ist bereits da.
--
-- =========================================================================
-- TEIL 2: profiles.email - damit admin-ban nicht die GoTrue-Nutzerliste
--          abklopfen muss
-- =========================================================================
--
-- admin-ban brauchte die User-ID zu einer E-Mail-Adresse. Die
-- GoTrue-Admin-API kann nicht nach E-Mail suchen - nur blättern. Die
-- Funktion hat deshalb bis zu 25 Seiten a 200 Nutzer durchsucht
-- (5 000 listUsers-Aufrufe im schlimmsten Fall), um eine einzige
-- Adresse zu finden.
--
-- profiles.user_id IST die GoTrue-User-ID. Es fehlte nur die
-- E-Mail-Adresse, um darauf zu suchen. Mit dieser Spalte wird die
-- Suche eine indizierte Abfrage.
--
-- Die Spalte wird aus auth.users gespeist (Trigger auf INSERT/UPDATE
-- von auth.users) - dieselbe Quelle, aus der auch handle_new_user die
-- Profildaten holt. Es gibt damit nur EINE Quelle fuer die Wahrheit.
--
-- Datenschutz: Die E-Mail-Adresse steht jetzt in profiles. Die Zeile
-- ist ueber die RLS ohnehin nur fuer den Eigentuemer und den Admin
-- lesbar. Fuer die Anzeige wird sie NICHT gebraucht - sie dient
-- ausschliesslich der Adminsuche, und der Adminzugriff ist ohnehin
-- schon ueber profiles.is_admin geregelt.
--
-- =========================================================================
-- TEIL 3: profiles.timezone und die serverseitige Nutzungszeit
-- =========================================================================
--
-- Die elterliche Nutzungszeit wurde AUSSCHLIESSLICH im Client
-- geprueft. Der Client ist patchbar - die Zusage gegenueber dem
-- Elternteil war damit nicht belastbar.
--
-- Warum das ueberhaupt geht: Die Nutzungszeit sind "Minuten seit
-- Mitternacht in der Zeitzone des Geraets". Der Server wusste die
-- Zeitzone nicht. Mit dieser Spalte kennt er sie.
--
-- Die Zeitzone kommt aus der App (flutter_timezone, IANA-Name wie
-- "Europe/Berlin") und wird bei jedem Start gemeldet (RPC
-- report_my_timezone). Ein IANA-Name ist unmissverstaendlich: Es gibt
-- keine Sommerzeit-Umrechnung, die der Server selbst machen muss - er
-- rechnet mit now() AT TIME ZONE 'Europe/Berlin' und bekommt die
-- lokale Zeit des Geraets, inklusive Sommerzeit.
--
-- EHRLICHE GRENZE: Der Chat selbst laeuft Ende-zu-Ende verschluesselt
-- ueber WebRTC - der Server ist da NICHT im Pfad. Er kann einen Chat
-- also nicht unterbinden. Die clientseitige Sperre bleibt fuer den
-- Chat die einzige Schranke. Das steht so auch in den Bekannten
-- Grenzen.
--
-- FAIL-CLOSED bei unbekannter Zeitzone: Ist eine Beschraenkung
-- gesetzt, die Zeitzone aber unbekannt, wird die Nutzung gesperrt.
-- Die Alternative waere, die Beschraenkung stillschweigend fallen zu
-- lassen - das waere eine leere Zusage. Der Client meldet die
-- Zeitzone bei jedem Start, der Fall ist also selten.

BEGIN;

-- =========================================================================
-- 1) profiles.email
-- =========================================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS email text;

COMMENT ON COLUMN public.profiles.email IS
  'Die E-Mail-Adresse des Kontos. Quelle ist auth.users (Trigger '
  'profiles_sync_email). Dient ausschliesslich der Adminsuche in der '
  'Edge Function admin-ban - ohne diese Spalte musste die GoTrue-'
  'Nutzerliste abgesucht werden (v0.10.0, Migration 176).';

-- Fuellung des Bestands aus auth.users.
--
-- Die Migration laeuft mit Eigentuemerrechten, darf also auth.users
-- lesen. Fuer bestehende Konten wird die Adresse so einmalig uebernommen.
UPDATE public.profiles p
   SET email = u.email
  FROM auth.users u
 WHERE u.id = p.user_id
   AND p.email IS DISTINCT FROM u.email;

-- Indiziert: die Adminsuche ist eine Gleichheitsabfrage auf email.
CREATE INDEX IF NOT EXISTS idx_profiles_email
  ON public.profiles (lower(email))
  WHERE email IS NOT NULL;

-- =========================================================================
-- 2) profiles.timezone
-- =========================================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS timezone text;

COMMENT ON COLUMN public.profiles.timezone IS
  'Die IANA-Zeitzone des Geraets (z. B. "Europe/Berlin"). Wird vom '
  'Client bei jedem Start gemeldet (RPC report_my_timezone) und '
  'benoetigt, damit der Server die elterliche Nutzungszeit in der '
  'LOKALEN Zeit des Geraets pruefen kann (v0.10.0, Migration 176).';

-- =========================================================================
-- 3) Trigger: E-Mail aus auth.users spiegeln
-- =========================================================================
CREATE OR REPLACE FUNCTION public.profiles_sync_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.email IS DISTINCT FROM OLD.email THEN
    UPDATE public.profiles
       SET email = NEW.email,
           updated_at = now()
     WHERE user_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.profiles_sync_email() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.profiles_sync_email() FROM anon;
REVOKE ALL ON FUNCTION public.profiles_sync_email() FROM authenticated;

DROP TRIGGER IF EXISTS trg_auth_users_sync_email ON auth.users;
CREATE TRIGGER trg_auth_users_sync_email
  AFTER INSERT OR UPDATE OF email ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.profiles_sync_email();

-- =========================================================================
-- 4) handle_new_user: die E-Mail gleich mitgeben
-- =========================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.profiles (
    user_id,
    name,
    gender,
    gender_preferences,
    birth_date,
    bio,
    interests,
    personality_type,
    max_distance_km,
    age_range_min,
    age_range_max,
    email
  ) VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'name', 'Unbekannt'),
    COALESCE(NEW.raw_user_meta_data ->> 'gender', 'unknown'),
    '{}'::text[],
    -- Kein erfundenes Geburtsdatum (v0.10.0, Migration 161).
    --
    -- Vorher stand hier COALESCE(..., '2000-01-01'::date): ohne
    -- Altersangabe galt damit Alter 26. Die 18+-Pruefung von Transit
    -- Spark war dadurch nicht fail-closed, obwohl ihr Kommentar genau
    -- das verlangt hat. NULL heisst jetzt: Alter unbekannt.
    NULLIF(NEW.raw_user_meta_data ->> 'birth_date', '')::date,
    '',
    '[]'::jsonb,
    'INTJ',
    100,
    18,
    65,
    -- Die E-Mail aus auth.users (Migration 176): eine Quelle fuer die
    -- Wahrheit, und der Admin muss die GoTrue-Nutzerliste nicht mehr
    -- abklopfen.
    NEW.email
  );
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Legt die Profildaten bei der Registrierung an. Setzt die E-Mail '
  'aus auth.users (Migration 176).';

-- =========================================================================
-- 5) Die Zeitzone melden
-- =========================================================================
CREATE OR REPLACE FUNCTION public.report_my_timezone(p_timezone text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Nur gueltige IANA-Namen annehmen. Ein unbekannter Name wuerde in
  -- "now() AT TIME ZONE" einen FEHLER ausloesen (und damit jede
  -- Nutzungszeit-Pruefung kippen). Die Liste der bekannten Zonen
  -- kommt aus der PostgreSQL-Zeitzonendatenbank.
  IF p_timezone IS NOT NULL AND length(p_timezone) > 0 THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_timezone_names WHERE name = p_timezone
    ) THEN
      -- still ignorieren: ein unbekannter Name darf den Nutzer nicht
      -- aussperren. Die alte Zeitzone bleibt erhalten.
      RETURN;
    END IF;
  END IF;

  UPDATE public.profiles
     SET timezone = NULLIF(p_timezone, ''),
         updated_at = now()
   WHERE user_id = v_uid;
END;
$$;

COMMENT ON FUNCTION public.report_my_timezone(text) IS
  'Meldet die Zeitzone des Geraets (IANA-Name). Der Server braucht sie, '
  'um die elterliche Nutzungszeit in der lokalen Zeit des Geraets zu '
  'pruefen (v0.10.0, Migration 176).';

REVOKE ALL ON FUNCTION public.report_my_timezone(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_my_timezone(text) TO authenticated;

-- =========================================================================
-- 6) Die Gate-Funktion (mit der Person, um die es geht)
-- =========================================================================
CREATE OR REPLACE FUNCTION public.guardian_usage_time_allows(
  p_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_start     int;
  v_end       int;
  v_tz        text;
  v_now_local timestamp;
  v_minutes   int;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT c.usage_start_min, c.usage_end_min
    INTO v_start, v_end
    FROM public.guardian_consents c
   WHERE c.child_user_id = p_user_id
     AND c.status = 'active'
     AND c.usage_limit_enabled
   ORDER BY c.requested_at DESC
   LIMIT 1;

  -- Keine Beschraenkung -> alles erlaubt.
  IF NOT FOUND THEN
    RETURN true;
  END IF;

  -- Beschraenkung aktiv, aber keine Zeit gesetzt: die Einstellung
  -- ist unvollstaendig. Dann gibt es nichts zu pruefen - der
  -- Client zeigt in diesem Fall ebenfalls keine Sperre.
  IF v_start IS NULL OR v_end IS NULL THEN
    RETURN true;
  END IF;

  SELECT p.timezone INTO v_tz
    FROM public.profiles p
   WHERE p.user_id = p_user_id;

  -- Keine Zeitzone bekannt: fail-closed. Eine aktive Beschraenkung
  -- darf nicht stillschweigend wegfallen, nur weil der Server die
  -- Zeit nicht berechnen kann.
  IF v_tz IS NULL OR NOT EXISTS (
    SELECT 1 FROM pg_timezone_names WHERE name = v_tz
  ) THEN
    RETURN false;
  END IF;

  -- Die LOKALE Zeit des Geraets. now() ist ein Zeitstempel mit
  -- Zeitzone; AT TIME ZONE rechnet ihn in die angegebene Zone um -
  -- inklusive Sommerzeit.
  v_now_local := now() AT TIME ZONE v_tz;
  v_minutes := EXTRACT(HOUR FROM v_now_local)::int * 60
             + EXTRACT(MINUTE FROM v_now_local)::int;

  -- Das Fenster darf ueber Mitternacht laufen (z. B. 22:00 bis 02:00).
  IF v_start <= v_end THEN
    RETURN v_minutes >= v_start AND v_minutes < v_end;
  END IF;
  RETURN v_minutes >= v_start OR v_minutes < v_end;
END;
$$;

COMMENT ON FUNCTION public.guardian_usage_time_allows(uuid) IS
  'Prueft die elterliche Nutzungszeit fuer eine Person in der LOKALEN '
  'Zeit des Geraets (v0.10.0, Migration 176). Bis hierher wurde die '
  'Zeit nur im Client geprueft - der Client ist patchbar, die Zusage '
  'gegenueber dem Elternteil war damit nicht belastbar.';

REVOKE ALL ON FUNCTION public.guardian_usage_time_allows(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.guardian_usage_time_allows(uuid)
  TO authenticated, service_role;

-- =========================================================================
-- 7) join_dating_hour: die Nutzungszeit davor pruefen
-- =========================================================================
--
-- Diese Funktion wird ausschliesslich vom Client aufgerufen (ein
-- Aufruf pro Person). Ein Gate vor dem Aufruf ist hier also genau
-- richtig: Der Aufrufer ist die betroffene Person.
--
-- Umsetzung ohne den Koerper zu kopieren: Die bestehende Funktion
-- bekommt einen internen Namen (ALTER FUNCTION ... RENAME TO). Der
-- Koerper, die Rechte und alle Abhaengigkeiten bleiben unveraendert
-- - es ist derselbe OID. Darueber legt ein duennes Gate.
--
-- Warum nicht einfach den Koerper umkopieren: Jede Kopie laeuft
-- auseinander. Die Variante mit dem Rename kann das nicht.
ALTER FUNCTION public.join_dating_hour(uuid, jsonb)
  RENAME TO join_dating_hour_ohne_nutzungszeit;

CREATE OR REPLACE FUNCTION public.join_dating_hour(
  p_event_id uuid,
  p_preferences jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Serverseitige Nutzungszeit (v0.10.0, Migration 176).
  IF NOT public.guardian_usage_time_allows(auth.uid()) THEN
    RAISE EXCEPTION 'usage_time_exceeded'
      USING ERRCODE = 'check_violation',
            MESSAGE = 'Die erlaubte Nutzungszeit ist gerade nicht aktiv.';
  END IF;
  PERFORM public.join_dating_hour_ohne_nutzungszeit(p_event_id, p_preferences);
END;
$$;

COMMENT ON FUNCTION public.join_dating_hour(uuid, jsonb) IS
  'Dating Hour beitreten. Prueft zusaetzlich die elterliche '
  'Nutzungszeit (Migration 176).';

GRANT EXECUTE ON FUNCTION public.join_dating_hour(uuid, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.join_dating_hour(uuid, jsonb) FROM PUBLIC, anon;

-- Die innere Funktion bleibt fuer das Gate erreichbar, aber nicht
-- fuer die Clients.
REVOKE ALL ON FUNCTION public.join_dating_hour_ohne_nutzungszeit(uuid, jsonb)
  FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- 8) match_dating_hour_round: Cron-Fix + Nutzungszeit je Teilnehmer
-- =========================================================================
--
-- Der Koerper ist der aus Migration 161, mit zwei Aenderungen:
--
--   a) Der Aufrufer wird NUR geprueft, wenn er selbst handelt. Im
--      Cron-Fall (auth.uid() IS NULL) prueft die Teilnehmerpruefung in
--      der Schleife - die ist bereits vorhanden und wird jetzt
--      durchweg genutzt. Vorher hat der Cron bei der ersten aktiven
--      Veranstaltung 'verification_required' geworfen und damit die
--      GANZE Runde abgebrochen - es wurde also seit dem 03.11.2026
--      niemals gepaart.
--
--   b) Die Nutzungszeit wird je Teilnehmer geprueft - nicht je
--      Veranstaltung. Eine Beschraenkung darf nur die betroffene
--      Person betreffen, nicht die ganze Runde.
CREATE OR REPLACE FUNCTION public.match_dating_hour_round(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_event public.dating_hour_event%rowtype;
  v_user record;
  v_pair record;
  v_user_birth date;
BEGIN
  SELECT * INTO v_event FROM public.dating_hour_event WHERE id = p_event_id;
  IF NOT FOUND OR v_event.status != 'active' THEN
    RETURN;
  END IF;

  -- Verifikationspflicht (v0.10.0, Migration 161) - NUR fuer den
  -- Aufrufer, der selbst handelt.
  --
  -- BEFUND 04.11.2026: Vorher stand hier ohne Einschraenkung
  --     IF NOT public.verification_granted(auth.uid()) THEN RAISE ...
  -- Der Cron ruft diese Funktion OHNE JWT auf - auth.uid() ist NULL,
  -- verification_granted(NULL) ist false - also hat der Cron bei der
  -- ERSTEN aktiven Veranstaltung 'verification_required' geworfen und
  -- die gesamte Runde abgebrochen. Die Dating Hour hat damit seit dem
  -- 03.11.2026 nicht mehr gepaart.
  --
  -- Die Teilnehmer werden in der Schleife geprueft (unten). Das ist
  -- die Pruefung, die fuer eine Runde ueberhaupt zaehlt.
  IF auth.uid() IS NOT NULL
     AND NOT public.verification_granted(auth.uid()) THEN
    RAISE EXCEPTION 'verification_required';
  END IF;

  FOR v_user IN
    SELECT p.user_id, p.preferences
    FROM public.dating_hour_participant p
    WHERE p.event_id = p_event_id
      AND p.left_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = p.user_id OR s.user_b = p.user_id)
      )
      -- Die elterliche Nutzungszeit (v0.10.0, Migration 176). Je
      -- Teilnehmer, nicht je Veranstaltung: eine Beschraenkung darf
      -- nur die betroffene Person betreffen.
      AND public.guardian_usage_time_allows(p.user_id)
    ORDER BY random()
  LOOP
    -- Beide Seiten muessen verifiziert sein.
    IF NOT public.verification_granted(v_user.user_id) THEN
      CONTINUE;
    END IF;

    SELECT birth_date INTO v_user_birth
      FROM public.profiles WHERE user_id = v_user.user_id;

    SELECT q.user_id INTO v_pair
    FROM public.dating_hour_participant q
    LEFT JOIN public.profiles qp ON qp.user_id = q.user_id
    WHERE q.event_id = p_event_id
      AND q.left_at IS NULL
      AND q.user_id <> v_user.user_id
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = q.user_id OR s.user_b = q.user_id)
      )
      -- H-1 (Regression aus 055): Blockier-Schutz wiederhergestellt.
      AND NOT EXISTS (
        SELECT 1 FROM public.blocked_users b
        WHERE (b.blocker = v_user.user_id AND b.blocked = q.user_id)
           OR (b.blocker = q.user_id AND b.blocked = v_user.user_id)
      )
      -- K-1: beidseitige Alters-Kompatibilitaet (Minderjaehrigen-Schutz).
      AND public.age_compatible_bidirectional(v_user_birth, qp.birth_date)
      -- N-15: Alters-Praferenzen des Viewers aus den Preferences.
      AND (
        v_user.preferences->>'ageMin' IS NULL
        OR public.profile_age(qp.birth_date) >= (v_user.preferences->>'ageMin')::int
      )
      AND (
        v_user.preferences->>'ageMax' IS NULL
        OR public.profile_age(qp.birth_date) <= (v_user.preferences->>'ageMax')::int
      )
      -- Die elterliche Nutzungszeit auch fuer die Gegenseite.
      AND public.guardian_usage_time_allows(q.user_id)
    LIMIT 1;

    IF v_pair.user_id IS NOT NULL THEN
      -- Beide sind verifiziert (Pruefung oben und in der Schleife).
      INSERT INTO public.dating_hour_session(event_id, user_a, user_b)
      VALUES (p_event_id, v_user.user_id, v_pair.user_id)
      ON CONFLICT (event_id, user_a, user_b) DO NOTHING;
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.match_dating_hour_round(uuid) IS
  'Paart Teilnehmer eines Dating-Hour-Events. v0.10.0, Migration 161: '
  'beide Seiten muessen verifiziert sein (serverseitig geprueft). '
  'Migration 176: der Aufrufer wird nur geprueft, wenn er selbst '
  'handelt - der Cron rief die Funktion ohne JWT auf und brach dadurch '
  'die ganze Runde ab (seit 03.11.2026 wurde nicht mehr gepaart). '
  'Ausserdem wird die elterliche Nutzungszeit je Teilnehmer geprueft.';

REVOKE EXECUTE ON FUNCTION public.match_dating_hour_round(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.match_dating_hour_round(uuid) TO authenticated;

COMMIT;
