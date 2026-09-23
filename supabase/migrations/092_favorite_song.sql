-- 092_favorite_song.sql
--
-- v0.9.1: Lieblingssong/Band wird in der Einrichtung abgefragt und ist
-- für andere sichtbar (Profil + Match-Listen). Reine Textangabe, kein
-- Matching-Kriterium.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS favorite_song text NOT NULL DEFAULT '';

COMMENT ON COLUMN public.profiles.favorite_song IS
  '092: Lieblingssong oder -band (freie Angabe aus der Einrichtung).';

-- public_profiles-View (Basis: 077-Definition + favorite_song am Ende).
create or replace view public.public_profiles as
select
  p.user_id,
  p.name,
  coalesce(p.gender, 'unknown') as gender,
  coalesce(p.bio, '') as bio,
  coalesce(p.interests, '[]'::jsonb) as interests,
  coalesce(p.personality_type, 'INTJ') as personality_type,
  date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int as age,
  round(coalesce(p.location_lat, 0)::numeric, 1)::float8 as lat_approx,
  round(coalesce(p.location_lng, 0)::numeric, 1)::float8 as lng_approx,
  coalesce(p.created_at, now()) as created_at,
  coalesce(p.updated_at, now()) as updated_at,
  um.mood,
  coalesce(p.intro_text, '') as intro_text,
  p.intro_audio_path,
  p.smoking,
  p.alcohol,
  p.drugs,
  coalesce(p.music_liked, '{}'::text[]) as music_liked,
  coalesce(p.music_disliked, '{}'::text[]) as music_disliked,
  p.paused,
  coalesce(p.photos, '{}'::text[]) as photos,
  coalesce(p.favorite_song, '') as favorite_song
from public.profiles p
left join lateral (
  select mood
  from public.user_mood
  where user_id = p.user_id
    and mood_date = current_date
  order by created_at desc
  limit 1
) um on true
where public.age_compatible(
        (select public.profile_age(me.birth_date)
           from public.profiles me
          where me.user_id = auth.uid()),
        date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int);

alter view public.public_profiles set (security_invoker = false);
revoke all on public.public_profiles from anon;
grant select on public.public_profiles to authenticated;

-- RPCs (080) um favorite_song erweitern (additiv, gleiche Schlüssel + neu).
CREATE OR REPLACE FUNCTION public.get_public_profile(p_user_id uuid)
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
           'lat_approx', round(coalesce(p.location_lat, 0)::numeric, 1)::float8,
           'lng_approx', round(coalesce(p.location_lng, 0)::numeric, 1)::float8,
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
           'photos', coalesce(p.photos, '{}'::text[]),
           'favorite_song', coalesce(p.favorite_song, '')
         )
  FROM public.profiles p
  LEFT JOIN LATERAL (
    SELECT mood
    FROM public.user_mood
    WHERE user_id = p.user_id
      AND mood_date = CURRENT_DATE
    ORDER BY created_at DESC
    LIMIT 1
  ) um ON true
  WHERE p.user_id = p_user_id
    AND public.age_compatible(
          (SELECT public.profile_age(me.birth_date)
             FROM public.profiles me
            WHERE me.user_id = auth.uid()),
          date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int);
$$;

CREATE OR REPLACE FUNCTION public.get_public_profiles(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ids uuid[];
  v_result jsonb;
BEGIN
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;
  v_ids := (SELECT array_agg(DISTINCT x) FROM unnest(p_ids) AS x LIMIT 200);

  SELECT coalesce(jsonb_agg(
           jsonb_build_object(
             'user_id', p.user_id,
             'name', p.name,
             'gender', coalesce(p.gender, 'unknown'),
             'bio', coalesce(p.bio, ''),
             'interests', coalesce(p.interests, '[]'::jsonb),
             'personality_type', coalesce(p.personality_type, 'INTJ'),
             'age', date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int,
             'lat_approx', round(coalesce(p.location_lat, 0)::numeric, 1)::float8,
             'lng_approx', round(coalesce(p.location_lng, 0)::numeric, 1)::float8,
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
             'photos', coalesce(p.photos, '{}'::text[]),
             'favorite_song', coalesce(p.favorite_song, '')
           ) ORDER BY p.user_id), '[]'::jsonb)
    INTO v_result
  FROM public.profiles p
  LEFT JOIN LATERAL (
    SELECT mood
    FROM public.user_mood
    WHERE user_id = p.user_id
      AND mood_date = CURRENT_DATE
    ORDER BY created_at DESC
    LIMIT 1
  ) um ON true
  WHERE p.user_id = ANY (v_ids)
    AND public.age_compatible(
          (SELECT public.profile_age(me.birth_date)
             FROM public.profiles me
            WHERE me.user_id = auth.uid()),
          date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int);
  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_profile(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_public_profile(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_public_profiles(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_public_profiles(uuid[]) TO authenticated;
