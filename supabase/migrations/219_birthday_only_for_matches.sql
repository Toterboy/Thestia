-- 219_birthday_only_for_matches.sql
--
-- Sicherheits-Audit 16.11.2026 (P2): "birthday_today" aus dem
-- oeffentlichen Profilvertrag entfernen.
--
-- BEFUND: Die Projektion public.profile_to_jsonb lieferte das Flag
-- "birthday_today" an JEDEN, der das Profil sehen durfte. Zusammen mit
-- dem ebenfalls oeffentlichen Alter ergibt sich daraus das GENAUE
-- Geburtsdatum: Das Alter verraet das Jahr, das Flag den Monat und den
-- Tag (weil der Geburtstag in diesem Jahr bereits stattgefunden hat).
-- Das Geburtsdatum ist in der DSGVO ein Datumskategorie-Sondermerkmal
-- (Art. 9) - es wurde damit an Fremde ausgegeben.
--
-- DIE LOESUNG: Das Flag wird nur noch fuer das eigene Profil und fuer
-- Personen geliefert, mit denen bereits ein Match besteht. Fuer
-- Fremde in der Suche (Find your Match, Interessen-Screen) faellt es
-- weg. Die Funktion bleibt erhalten - der Geburtstags-Rahmen und der
-- "Geburtstag"-Chip im Chat mit einem Match bleiben erhalten.
--
-- Die eigentliche Funktion (public.profile_has_relationship) ist
-- SECURITY DEFINER mit festem search_path und wird nur intern
-- benutzt (die Clients lesen sie nicht).
--
-- Rollback: die beiden Definitionen mit dem alten Ausdruck ersetzen
-- (siehe Migrationsdatei 138).

-- -----------------------------------------------------------------------------
-- 1) Die Beziehungspruefung
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.profile_has_relationship(
  p_viewer uuid,
  p_other   uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    p_viewer IS NOT NULL
    AND p_other IS NOT NULL
    AND (
      -- Das eigene Profil (der eigene Geburtstag wird lokal berechnet,
      -- aber der Vertrag soll vollstaendig bleiben).
      p_viewer = p_other
      -- Ein Match: die beiden sind im Chat - der Geburtstag darf
      -- gefeiert werden.
      OR EXISTS (
        SELECT 1
          FROM public.matches m
         WHERE (m.user_one_id = p_viewer AND m.user_two_id = p_other)
            OR (m.user_two_id = p_viewer AND m.user_one_id = p_other)
      )
    );
$$;

COMMENT ON FUNCTION public.profile_has_relationship(uuid, uuid) IS
  'true, wenn der Betrachter das eigene Profil oder ein Match ist. '
  'Steuert, ob das Geburtstags-Flag im oeffentlichen Profilvertrag '
  'erscheint (Audit 16.11.2026: Alter + Flag ergaeben das genaue '
  'Geburtsdatum).';

REVOKE ALL ON FUNCTION public.profile_has_relationship(uuid, uuid)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.profile_has_relationship(uuid, uuid)
  TO service_role;

-- -----------------------------------------------------------------------------
-- 2) Die Projektion: Flag nur noch bei eigener Beziehung
-- -----------------------------------------------------------------------------
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
           -- NUR bei eigener Beziehung (Audit 16.11.2026): sonst ergibt
           -- die Kombination aus Alter und Flag das genaue Geburtsdatum.
           'birthday_today', coalesce(
             public.profile_has_relationship(auth.uid(), p.user_id)
             AND p.birth_date IS NOT NULL
             AND date_part('month', p.birth_date) = date_part('month', CURRENT_DATE)
             AND date_part('day', p.birth_date) = date_part('day', CURRENT_DATE),
             false),
           'favorite_band', coalesce(p.favorite_band, '')
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
  'Oeffentliche Profilprojektion. Ohne Koordinaten. Das Feld '
  'birthday_today wird nur geliefert, wenn der Betrachter das eigene '
  'Profil oder ein Match ist (Audit 16.11.2026: sonst ergaeben Alter '
  'und Flag das genaue Geburtsdatum).';

-- -----------------------------------------------------------------------------
-- 3) Die View: gleiche Regel
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.public_profiles;

CREATE VIEW public.public_profiles AS
SELECT
  p.user_id,
  p.name,
  coalesce(p.gender, 'unknown') AS gender,
  coalesce(p.bio, '') AS bio,
  coalesce(p.interests, '[]'::jsonb) AS interests,
  coalesce(p.personality_type, 'INTJ') AS personality_type,
  date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int AS age,
  coalesce(p.created_at, now()) AS created_at,
  coalesce(p.updated_at, now()) AS updated_at,
  um.mood,
  coalesce(p.intro_text, '') AS intro_text,
  p.intro_audio_path,
  p.smoking,
  p.alcohol,
  p.drugs,
  coalesce(p.music_liked, '{}'::text[]) AS music_liked,
  coalesce(p.music_disliked, '{}'::text[]) AS music_disliked,
  p.paused,
  coalesce(ph.cleaned, '{}'::text[]) AS photos,
  coalesce(p.favorite_song, '') AS favorite_song,
  coalesce(p.birthday_style, 'classic') AS birthday_style,
  -- NUR bei eigener Beziehung (Audit 16.11.2026) - siehe Kommentar oben.
  coalesce(
    public.profile_has_relationship(auth.uid(), p.user_id)
    AND p.birth_date IS NOT NULL
    AND date_part('month', p.birth_date) = date_part('month', CURRENT_DATE)
    AND date_part('day', p.birth_date) = date_part('day', CURRENT_DATE),
    false
  ) AS birthday_today,
  coalesce(p.favorite_band, '') AS favorite_band
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
