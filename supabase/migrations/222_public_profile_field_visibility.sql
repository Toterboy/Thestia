-- 222_public_profile_field_visibility.sql
--
-- NUTZERWUNSCH (22.11.2026): "Musik Genres, die man mag und
-- Lieblings-Song und Künstler werden alle nicht im Profil angezeigt
-- (öffentlich). Man soll diese Punkte und die Gewohnheiten einzeln fürs
-- öffentliche Profil an und aus machen können."
--
-- ZWEI SACHEN IN EINER MIGRATION:
--
-- 1) DIE SCHALTER: je Punkt eine Spalte auf public.profiles. Der
--    Nutzer entscheidet, was andere sehen. Der Server wertet die Spalten
--    in der Projektion aus - der Client kann nichts erzwingen.
--
-- 2) DIE IN MIGRATION 219 VERLORENEN FELDER (wiederhergestellt):
--    Migration 219 hat public.profile_to_jsonb und die View
--    public_profiles neu geschrieben und dabei drei Dinge verloren:
--      * 'is_verified' und 'verification_state' - das
--        Verifikations-Abzeichen bei fremden Profilen war wieder weg.
--      * das Alter kam wieder aus dem DEKLARIERTEN Geburtsdatum
--        statt aus public.profile_effective_age(birth_date,
--        verified_age) - das ist der Jugendschutz (Migration 155/156).
--      * die ZEITZONE DES BETRACHTENDEN - der Geburtstag wurde wieder
--        nach UTC gerechnet (Migration 195), also zwischen 22:00 und
--        Mitternacht sah der Nutzer seinen Geburtstag, die andere Person
--        aber nicht.
--
--    Jede neue Projektion muss ALLE Felder enthalten. Der Fail-Fast-Block
--    unten prueft das nach - eine Projektion, die ein Feld verliert,
--    bricht die Migration ab.
--
-- DIE GRENZE BLEIBT (Audit 16.11.2026): Der Geburtstag wird nur bei
-- eigener Beziehung geliefert (public.profile_has_relationship), und
-- die View filtert weiterhin ueber
-- public.profile_discovery_visible_full(auth.uid(), p.user_id).
-- Koordinaten und das genaue Geburtsdatum bleiben draussen.

-- ---------------------------------------------------------------------------
-- 1) Die Schalter
-- ---------------------------------------------------------------------------
-- DER DEFAULT "true": Das bisherige Verhalten bleibt erhalten - die Musik
-- ist heute oeffentlich, die Gewohnheiten nicht (sie wurden nirgends
-- angezeigt). Mit "false" wuerden bei allen Bestandskonten die Angaben
-- still verschwinden; das entscheidet der Betreiber, nicht die Migration.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS show_music_liked boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_music_disliked boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_favorite_song boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_favorite_band boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_habits_smoking boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_habits_alcohol boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_habits_drugs boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.profiles.show_music_liked IS
  'true, wenn die gemagten Musik-Genres im oeffentlichen Profil stehen.';
COMMENT ON COLUMN public.profiles.show_music_disliked IS
  'true, wenn die abgelehnten Musik-Genres im oeffentlichen Profil stehen.';
COMMENT ON COLUMN public.profiles.show_favorite_song IS
  'true, wenn der Lieblingssong im oeffentlichen Profil steht.';
COMMENT ON COLUMN public.profiles.show_favorite_band IS
  'true, wenn der Lieblings-Kuenstler (Lieblingsband) im oeffentlichen '
  'Profil steht.';
COMMENT ON COLUMN public.profiles.show_habits_smoking IS
  'true, wenn die Gewohnheit "Rauchen" im oeffentlichen Profil steht.';
COMMENT ON COLUMN public.profiles.show_habits_alcohol IS
  'true, wenn die Gewohnheit "Alkohol" im oeffentlichen Profil steht.';
COMMENT ON COLUMN public.profiles.show_habits_drugs IS
  'true, wenn die Gewohnheit "Drogen" im oeffentlichen Profil steht.';

-- ---------------------------------------------------------------------------
-- 2) Die Projektion (die RPC get_public_profile / get_public_profiles)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.profile_to_jsonb(p_user_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
           'user_id', p.user_id,
           'name', p.name,
           'gender', coalesce(p.gender, 'unknown'),
           'bio', coalesce(p.bio, ''),
           'interests', coalesce(p.interests, '[]'::jsonb),
           'personality_type', coalesce(p.personality_type, 'INTJ'),
           -- Das Alter aus dem WIRKLICHEN Alter (Migration 155/156) - vor
           -- 219 stand hier das deklarierte Geburtsdatum (Jugendschutz!).
           'age', public.profile_effective_age(p.birth_date, p.verified_age),
           'created_at', coalesce(p.created_at, now()),
           'updated_at', coalesce(p.updated_at, now()),
           'mood', um.mood,
           'intro_text', coalesce(p.intro_text, ''),
           'intro_audio_path', p.intro_audio_path,
           -- Die Gewohnheiten: nur wenn der Nutzer sie freigibt.
           'smoking', CASE WHEN p.show_habits_smoking THEN p.smoking ELSE NULL END,
           'alcohol', CASE WHEN p.show_habits_alcohol THEN p.alcohol ELSE NULL END,
           'drugs', CASE WHEN p.show_habits_drugs THEN p.drugs ELSE NULL END,
           -- Die Musik: nur wenn der Nutzer sie freigibt.
           'music_liked', CASE WHEN p.show_music_liked
                               THEN coalesce(p.music_liked, '{}'::text[])
                               ELSE '{}'::text[] END,
           'music_disliked', CASE WHEN p.show_music_disliked
                                 THEN coalesce(p.music_disliked, '{}'::text[])
                                 ELSE '{}'::text[] END,
           'paused', p.paused,
           'photos', coalesce(ph.cleaned, '{}'::text[]),
           'favorite_song', CASE WHEN p.show_favorite_song
                                 THEN coalesce(p.favorite_song, '')
                                 ELSE '' END,
           'birthday_style', coalesce(p.birthday_style, 'classic'),
           -- Der Geburtstag: nur bei eigener Beziehung (Audit 16.11.2026)
           -- UND in der Zeitzone des BETRACHTENDEN (Migration 195).
           'birthday_today', coalesce(
               public.profile_has_relationship(auth.uid(), p.user_id)
               AND p.birth_date IS NOT NULL
               AND date_part('month', p.birth_date) = date_part('month',
                     (now() AT TIME ZONE coalesce((
                       SELECT v.timezone FROM public.profiles v
                        WHERE v.user_id = auth.uid()
                          AND v.timezone IN (SELECT name FROM pg_timezone_names)
                     ), 'UTC'))::date)
               AND date_part('day', p.birth_date) = date_part('day',
                     (now() AT TIME ZONE coalesce((
                       SELECT v.timezone FROM public.profiles v
                        WHERE v.user_id = auth.uid()
                          AND v.timezone IN (SELECT name FROM pg_timezone_names)
                     ), 'UTC'))::date),
               false),
           'favorite_band', CASE WHEN p.show_favorite_band
                                 THEN coalesce(p.favorite_band, '')
                                 ELSE '' END,
           -- Verifikationsstatus (Migration 144) - in 219 verloren gegangen.
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

COMMENT ON FUNCTION public.profile_to_jsonb(uuid) IS
  'Oeffentliche Profilprojektion. Musik und Gewohnheiten stehen nur '
  'darin, wenn der Nutzer sie freigibt (show_*). Der Geburtstag nur bei '
  'eigener Beziehung, das Alter aus dem wirksamen Alter und in der '
  'Zeitzone des Betrachtenden (Migration 222).';

-- ---------------------------------------------------------------------------
-- 3) Die View: dieselbe Regel
-- ---------------------------------------------------------------------------
-- WICHTIG: Die View wird NEU erzeugt (DROP + CREATE), weil sich die
-- Spaltenliste in der Mitte aendert - "CREATE OR REPLACE VIEW" darf nur
-- Spalten am ENDE ergaenzen. Danach werden die Rechte WIEDER entzogen
-- (wie in 219) - sonst kaeme die View wieder fuer alle lesbar.
DROP VIEW IF EXISTS public.public_profiles;

CREATE VIEW public.public_profiles AS
SELECT
  p.user_id,
  p.name,
  coalesce(p.gender, 'unknown') AS gender,
  coalesce(p.bio, '') AS bio,
  coalesce(p.interests, '[]'::jsonb) AS interests,
  coalesce(p.personality_type, 'INTJ') AS personality_type,
  -- Das wirksame Alter (Migration 155/156), nicht das deklarierte.
  public.profile_effective_age(p.birth_date, p.verified_age) AS age,
  coalesce(p.created_at, now()) AS created_at,
  coalesce(p.updated_at, now()) AS updated_at,
  um.mood,
  coalesce(p.intro_text, '') AS intro_text,
  p.intro_audio_path,
  -- Die Gewohnheiten: nur wenn der Nutzer sie freigibt.
  CASE WHEN p.show_habits_smoking THEN p.smoking ELSE NULL END AS smoking,
  CASE WHEN p.show_habits_alcohol THEN p.alcohol ELSE NULL END AS alcohol,
  CASE WHEN p.show_habits_drugs THEN p.drugs ELSE NULL END AS drugs,
  -- Die Musik: nur wenn der Nutzer sie freigibt.
  CASE WHEN p.show_music_liked
       THEN coalesce(p.music_liked, '{}'::text[]) ELSE '{}'::text[] END AS music_liked,
  CASE WHEN p.show_music_disliked
       THEN coalesce(p.music_disliked, '{}'::text[]) ELSE '{}'::text[] END AS music_disliked,
  p.paused,
  coalesce(ph.cleaned, '{}'::text[]) AS photos,
  CASE WHEN p.show_favorite_song
       THEN coalesce(p.favorite_song, '') ELSE '' END AS favorite_song,
  coalesce(p.birthday_style, 'classic') AS birthday_style,
  -- Nur bei eigener Beziehung UND in der Zeitzone des Betrachtenden.
  coalesce(
    public.profile_has_relationship(auth.uid(), p.user_id)
    AND p.birth_date IS NOT NULL
    AND date_part('month', p.birth_date) = date_part('month',
          (now() AT TIME ZONE coalesce((
            SELECT v.timezone FROM public.profiles v
             WHERE v.user_id = auth.uid()
               AND v.timezone IN (SELECT name FROM pg_timezone_names)
          ), 'UTC'))::date)
    AND date_part('day', p.birth_date) = date_part('day',
          (now() AT TIME ZONE coalesce((
            SELECT v.timezone FROM public.profiles v
             WHERE v.user_id = auth.uid()
               AND v.timezone IN (SELECT name FROM pg_timezone_names)
          ), 'UTC'))::date),
    false
  ) AS birthday_today,
  CASE WHEN p.show_favorite_band
       THEN coalesce(p.favorite_band, '') ELSE '' END AS favorite_band,
  -- Verifikationsstatus (Migration 144) - in 219 verloren gegangen.
  coalesce(p.is_verified, false) AS is_verified,
  CASE
    WHEN coalesce(p.is_verified, false) THEN 'verified'
    WHEN p.verification_status IN ('pending', 'pending_minor') THEN 'under_review'
    ELSE 'unverified'
  END AS verification_state
FROM public.profiles p
LEFT JOIN LATERAL (
  SELECT mood FROM public.user_mood
   WHERE user_id = p.user_id AND mood_date = current_date
   ORDER BY created_at DESC LIMIT 1
) um ON true
LEFT JOIN LATERAL (
  SELECT array_agg(split_part(entry, '|', 1) ORDER BY ord) AS cleaned
    FROM unnest(coalesce(p.photos, '{}'::text[])) WITH ORDINALITY AS u(entry, ord)
) ph ON true
WHERE public.profile_discovery_visible_full(auth.uid(), p.user_id);

REVOKE ALL ON public.public_profiles FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) Fail-Fast: die Projektionen muessen vollstaendig sein
-- ---------------------------------------------------------------------------
-- BEFUND (22.11.2026): Migration 219 hat drei Felder verloren, ohne dass
-- es jemand gemerkt hat - die Migrationen waren gruen, die Tests kannten
-- den Server nicht. Dieser Block bricht die Migration ab, wenn eine
-- Projektion ein Feld nicht mehr liefert.
DO $$
DECLARE
  v_fehler text := '';
BEGIN
  IF pg_get_functiondef('public.profile_to_jsonb(uuid)'::regprocedure)
       NOT LIKE '%is_verified%' THEN
    v_fehler := v_fehler || ' profile_to_jsonb: is_verified fehlt.';
  END IF;
  IF pg_get_functiondef('public.profile_to_jsonb(uuid)'::regprocedure)
       NOT LIKE '%verification_state%' THEN
    v_fehler := v_fehler || ' profile_to_jsonb: verification_state fehlt.';
  END IF;
  IF pg_get_functiondef('public.profile_to_jsonb(uuid)'::regprocedure)
       NOT LIKE '%profile_effective_age%' THEN
    v_fehler := v_fehler || ' profile_to_jsonb: das wirksame Alter fehlt.';
  END IF;
  IF pg_get_functiondef('public.profile_to_jsonb(uuid)'::regprocedure)
       NOT LIKE '%AT TIME ZONE%' THEN
    v_fehler := v_fehler || ' profile_to_jsonb: die Zeitzone des Betrachtenden fehlt.';
  END IF;
  IF pg_get_viewdef('public.public_profiles'::regclass)
       NOT LIKE '%is_verified%' THEN
    v_fehler := v_fehler || ' public_profiles: is_verified fehlt.';
  END IF;
  IF pg_get_viewdef('public.public_profiles'::regclass)
       NOT LIKE '%profile_effective_age%' THEN
    v_fehler := v_fehler || ' public_profiles: das wirksame Alter fehlt.';
  END IF;
  IF pg_get_viewdef('public.public_profiles'::regclass)
       NOT LIKE '%profile_discovery_visible_full%' THEN
    v_fehler := v_fehler || ' public_profiles: die Sichtbarkeits-Filterung fehlt.';
  END IF;
  IF pg_get_viewdef('public.public_profiles'::regclass)
       NOT LIKE '%show_music_liked%' THEN
    v_fehler := v_fehler || ' public_profiles: die Musik-Schalter fehlen.';
  END IF;
  IF v_fehler <> '' THEN
    RAISE EXCEPTION 'Sicherheitscheck fehlgeschlagen:%', v_fehler;
  END IF;
END;
$$;
