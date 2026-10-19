-- 144: Verifikations-Zustaende, Kritische RLS-Luecken, oeffentlicher Status
--
-- Drei Themen in einer Migration, weil sie dieselbe Tabelle betreffen
-- und getrennt angewendet Zwischenstaende erzeugen wuerden, in denen
-- die App einen halben Stand sieht.
--
-- ===========================================================================
-- 1) KRITISCH: profiles war fuer JEDEN angemeldeten Nutzer voll lesbar
-- ===========================================================================
--
-- BEFUND (Security-Audit 2026-10-19, Live-DB-Abfrage dokumentiert in
-- 135_location_privacy_expand.sql:6-14): auf public.profiles existiert
-- die Policy "Public profiles are readable" mit qual: true fuer
-- authenticated. Jeder angemeldete Nutzer kann damit jede Zeile lesen:
--
--   GET /rest/v1/profiles?select=*
--
-- Das liefert u.a.:
--   * birth_date        - Art.-9-Datum, im Widerspruch zur Zusage in
--                         SECURITY.md ("nur das Alter, nicht das
--                         Geburtsdatum")
--   * photos            - Pfad | AES-256-Schluessel | IV. Das ist das
--                         vollstaendige Entschlüsselungsmaterial jedes
--                         Profilfotos. Migration 107 wollte genau das
--                         verhindern.
--   * up_endpoint       - UnifiedPush-Ziel: damit Push-Spam an jeden
--                         Nutzer, unter Umgehung ALLER Pruefungen in
--                         notify-user (Beziehungspruefung, Rate-Limit,
--                         SSRF-Guard)
--   * fcm_token, is_admin, verification_video_path, ...
--
-- Damit sind ausserdem saemtliche Discovery-Filter umgangen: Blockliste,
-- Pause, Suchradius, Altersspanne, Geschlechtspraeferenz. Wer einen
-- Nutzer blockiert, bleibt sichtbar.
--
-- WICHTIG - der Policy-Name existiert in KEINER Migrationsdatei. Er
-- wurde ausserhalb des Repos an der Live-DB gesetzt. Deshalb konnte
-- kein Reviewer und kein CI-Check ihn sehen. Diese Migration setzt
-- den Zustand ausdruecklich und haelt ihn damit im Repo.
--
-- Warum das sicher ist: die App liest fremde Profile ausschliesslich
-- ueber SECURITY-DEFINER-RPCs (get_public_profile, get_public_profiles,
-- get_match_partner_profile, get_nearby_profiles). Diese umgehen RLS.
-- Direkte Lesezugriffe auf profiles gibt es in der App ausschliesslich
-- fuer die EIGENE Zeile (user_id = auth.uid()). Der Admin-Bereich
-- arbeitet ueber admin_list_*-RPCs, die Edge Functions ueber
-- service_role (umgeht RLS ebenfalls).
--
-- ===========================================================================
-- 2) KRITISCH: profile_to_jsonb war direkt aufrufbar
-- ===========================================================================
--
-- BEFUND: Migration 126 widerruft profile_to_jsonb von authenticated
-- und grantet es im naechsten Atemzug wieder. Der Body filtert
-- NICHT: keine Blockliste, keine Pause, kein Radius, keine
-- Altersspanne, kein Rate-Limit. Damit:
--
--   POST /rest/v1/rpc/profile_to_jsonb {"p_user_id":"<uuid>"}
--
-- liefert das vollstaendige Profil eines jeden Nutzers, auch
-- blockierter. age + birthday_today erlauben zudem die Rekonstruktion
-- des exakten Geburtsdatums. Kein Rate-Limit -> vollstaendiges
-- Scraping der Nutzerbasis.
--
-- Der Client benutzt die Funktion NICHT - sie wird ausschliesslich
-- intern von get_public_profile aufgerufen. Das geschieht innerhalb
-- einer SECURITY-DEFINER-Funktion, und Ausfuehrungsrechte werden gegen
-- den aktuellen effektiven Benutzer geprueft - also gegen den
-- Funktionsinhaber, nicht gegen den Client. Der Entzug aendert den
-- internen Aufruf deshalb nicht.
--
-- ===========================================================================
-- 3) Verifikations-Zustaende: 'pending_minor' und der oeffentliche Status
-- ===========================================================================
--
-- Bisher: 'none', 'pending', 'approved', 'rejected', 'auto'.
-- Neu: 'pending_minor' - die Person ist juenger als 22 und wird
-- deshalb IMMER von Hand geprueft, nie automatisch freigegeben.
--
-- Oeffentlich sichtbar wird ein abgeleiteter Status statt der
-- Rohspalten: 'unverified' | 'under_review' | 'verified'. Die
-- Unterscheidung ist gewollt: wer sich geprueft hat, aber die
-- Freigabe noch nicht hat, ist nicht "nicht verifiziert", sondern
-- "wird geprueft".

BEGIN;

-- ===========================================================================
-- 1) profiles: SELECT nur auf die eigene Zeile
-- ===========================================================================

-- Der Name "Public profiles are readable" ist im Live-Bestand, nicht im
-- Repo. "Users can read own profile" ist die Repo-Fassung. Beide
-- werden entfernt und durch EINE enge Policy ersetzt.
DROP POLICY IF EXISTS "Public profiles are readable" ON public.profiles;
DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;

CREATE POLICY "Users can read own profile"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Gegenprobe: Die eigene Zeile muss weiterhin lesbar sein, sonst
-- waere die App nach dem Update blind.
DO $$
DECLARE
  v_ok boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'profiles'
       AND policyname = 'Users can read own profile'
  ) INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'profiles-Policy nicht angelegt - Abbruch.';
  END IF;
END $$;

-- ===========================================================================
-- 2) profile_to_jsonb: Ausfuehrungsrecht entziehen
-- ===========================================================================

REVOKE ALL ON FUNCTION public.profile_to_jsonb(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.profile_to_jsonb(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.profile_to_jsonb(uuid) FROM authenticated;

-- Gegenprobe: Der interne Aufruf aus get_public_profile muss weiter
-- funktionieren. get_public_profile ist SECURITY DEFINER, der Aufruf
-- laeuft also mit den Rechten des Inhabers (postgres) - der Entzug
-- betrifft nur direkte Client-Aufrufe.
DO $$
DECLARE
  v_ok boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'get_public_profile'
       AND p.prosecdef
  ) INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'get_public_profile ist nicht SECURITY DEFINER - '
                    'der Entzug von profile_to_jsonb wuerde den internen '
                    'Aufruf brechen. Abbruch.';
  END IF;
END $$;

-- ===========================================================================
-- 3) Verifikationsstatus: 'pending_minor' + oeffentliche Projektion
-- ===========================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'profiles_verification_status_check'
      AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
      DROP CONSTRAINT profiles_verification_status_check;
  END IF;
END $$;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN (
    'none', 'pending', 'pending_minor', 'approved', 'rejected', 'auto'
  ));

-- Bestandsdaten: ein 'pending' ohne Minderjaehrigkeitsverdacht bleibt
-- 'pending'. Eine Umbenennung alter Werte waere eine erfundene
-- Tatsache - ein offener Fall war nicht als Minderjaehrigkeitsfall
-- markiert.
UPDATE public.profiles
   SET verification_status = 'pending'
 WHERE verification_status = 'pending_minor'
   AND verification_estimated_age IS NULL;

-- Fuehrende Warteschlange fuer den Admin-Bereich: offene Faelle
-- zuerst. Partial, weil die Tabelle wächst und die Abfrage selten ist.
CREATE INDEX IF NOT EXISTS profiles_verification_open_idx
  ON public.profiles (verification_status)
  WHERE verification_status IN ('pending', 'pending_minor');

-- Admin-Queue: Minderjaehrigkeitsfaelle MIT aufnehmen.
--
-- Die RPC filterte bisher auf verification_status = 'pending'. Mit dem
-- neuen Status 'pending_minor' waeren genau die Personen, um die es
-- am meisten geht, NICHT in der Warteschlange - sie wuerden nie
-- geprueft. Das ist der wichtigste Einzelfall dieser Migration.
--
-- Zusaetzlich wird der Status mitgeliefert, damit der Admin sieht,
-- ob es ein Minderjaehrigkeitsfall ist oder eine normale Pruefung.
CREATE OR REPLACE FUNCTION public.admin_list_pending_verifications()
RETURNS TABLE (
  user_id uuid,
  name text,
  submitted_at timestamptz,
  estimated_age int,
  stated_age int,
  status text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p.user_id,
         coalesce(p.name, ''),
         p.updated_at,
         p.verification_estimated_age,
         public.profile_age(p.birth_date),
         p.verification_status
    FROM public.profiles p
   WHERE p.verification_status IN ('pending', 'pending_minor')
   ORDER BY p.updated_at ASC;
$$;

-- Oeffentliche Projektion: abgeleiteter Status statt der Rohspalten.
--
-- is_verified war bisher in KEINER oeffentlichen Projektion enthalten -
-- das verifizierte Abzeichen erschien auf fremden Profilen also NIE,
-- obwohl die Spalte in profiles existierte. Mit 'is_verified' plus
-- 'verification_state' ist das behoben und der Dreifachzustand fuer
-- die Anzeige bei der anderen Person verfuegbar.
--
-- 'unverified'    - kein Video eingereicht, keine Pruefung
-- 'under_review'  - eingereicht, Pruefung laeuft oder ausstehend
-- 'verified'      - freigegeben (manuell oder automatisch)
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
           'age', date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int,
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

-- get_match_partner_profile liefert ebenfalls is_verified (139:89), aber
-- noch keinen abgeleiteten Status. Fuer die Anzeige bei der anderen
-- Person wird er hier ergaenzt. Die Funktion liest direkt aus
-- profiles und umgeht RLS als SECURITY DEFINER - deshalb ist die
-- Verkleinerung der profiles-Policy aus Teil 1 fuer sie unkritisch.
CREATE OR REPLACE FUNCTION public.get_match_partner_profile(
  p_match_id bigint,
  p_level integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_partner uuid;
  v_level integer;
BEGIN
  SELECT CASE WHEN m.initiator_id = auth.uid() THEN m.partner_id
              ELSE m.initiator_id END,
         CASE WHEN m.initiator_id = auth.uid() THEN m.quiz_level
              ELSE m.quiz_completed_level END
    INTO v_partner, v_level
    FROM public.matches m
   WHERE m.id = p_match_id
     AND (m.initiator_id = auth.uid() OR m.partner_id = auth.uid())
     AND public.profile_discovery_visible(auth.uid(),
           CASE WHEN m.initiator_id = auth.uid() THEN m.partner_id
                ELSE m.initiator_id END);

  IF v_partner IS NULL THEN
    RETURN jsonb_build_object('unlockLevel', v_level, 'unlocked', false,
                              'profile', NULL);
  END IF;

  IF v_level >= 1 THEN
    RETURN jsonb_build_object(
      'unlockLevel', v_level,
      'unlocked', true,
      'profile', (
        SELECT jsonb_build_object(
                 'user_id', p.user_id,
                 'name', p.name,
                 'interests', coalesce(p.interests, '[]'::jsonb),
                 'state', p.state,
                 'country', p.country,
                 'gender', p.gender,
                 'age', public.profile_age(p.birth_date),
                 'personality_type', p.personality_type,
                 'intro_text', p.intro_text,
                 'intro_audio_path', p.intro_audio_path,
                 'is_verified', coalesce(p.is_verified, false),
                 'verification_state', CASE
                   WHEN coalesce(p.is_verified, false) THEN 'verified'
                   WHEN p.verification_status IN ('pending', 'pending_minor') THEN 'under_review'
                   ELSE 'unverified'
                 END
               )
          FROM public.profiles p
         WHERE p.user_id = v_partner
      )
    );
  END IF;

  -- Gesperrt: die ganze oeffentliche View. Nach 138 ohne Koordinaten.
  RETURN jsonb_build_object(
    'unlockLevel', v_level,
    'unlocked', false,
    'profile', NULL
  );
END;
$$;

COMMIT;
