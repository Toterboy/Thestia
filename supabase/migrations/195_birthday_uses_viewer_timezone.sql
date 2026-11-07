-- 195: der Geburtstag wird in der Zeitzone des BETRACHTENDEN gerechnet
--
-- BEFUND (07.11.2026, Betreiber): "Geburtstagsvorschau."
--
-- DIE URSACHE (live gemessen, nicht vermutet):
--
--   Der Server rechnet in UTC (TimeZone des Projekts: UTC). Die App
--   rechnet den Geburtstag lokal (DateTime.now()). Deshalb gilt:
--
--     * 00:00 - 01:00/02:00 Ortszeit: Der Nutzer sieht SEINEN
--       Geburtstag (Rahmen, Chip), die andere Person aber nicht - der
--       Server rechnet noch den Vortag.
--     * Ab 22:00 UTC ist es umgekehrt.
--
--   Der Betreiber hat an seinem Geburtstag (07.11.) in der App seinen
--   Geburtstagsstil gesehen, bei der anderen Person aber nicht.
--
-- DIE LOESUNG:
--
--   Die Datenbank kennt die Zeitzone jedes Nutzers
--   (profiles.timezone). Das Profil, das ANGEZEIGT wird, wird fuer
--   den BETRACHTENDEN berechnet - also wird auch sein Geburtstag in
--   seiner Zeizone berechnet.
--
--   Die gespeicherte Zone wird nur verwendet, wenn sie ein echter
--   Zonenname ist (pg_timezone_names). Sonst wuerde ein manipulierter
--   Spaltenwert die ganze Profilabfrage scheitern lassen (AT TIME
--   ZONE wirft bei einem ungueltigen Zonennamen). Ohne Zone gilt UTC
--   wie bisher.
--
--   Die Funktion ist die LIVE-Definition; an ihr wurde genau eine
--   Stelle geaendert.

BEGIN;

CREATE OR REPLACE FUNCTION public.profile_to_jsonb(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
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
-- Die Kontrolle: die Funktion muss die Zeitzone benutzen. Ohne sie
-- waere der Befund wieder da - und niemand wuerde es merken, weil
-- der Geburtstag ja fast immer stimmt.
DO $$
DECLARE
  v_ok int;
BEGIN
  SELECT count(*) INTO v_ok
    FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'profile_to_jsonb'
     AND p.prosrc ILIKE '%pg_timezone_names%';

  IF v_ok = 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: die Geburtags-Berechnung nutzt die Zeitzone des Betrachters nicht - der Geburtstag ist in der Nacht falsch';
  END IF;
END;
$$;

COMMIT;
