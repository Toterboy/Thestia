-- =============================================================================
-- 204_find_match_categories.sql
-- =============================================================================
-- DIE KATEGORIEN MIT IHRER ZAHL (BEFUND 09.11.2026, Betreiber):
-- "dann entweder Zufallsvorstellung oder Vorstellungen anderer nach
--  Kategorien ansehen. Also Kategorien sind die Interessens-Kategorien."
--
-- Ohne die Zahlen waere das Stoebern blind: man tippt auf "Sport" und
-- sieht niemanden - und weiss nicht, ob die Funktion kaputt ist oder ob
-- es in dem Bereich schlicht niemanden gibt.
--
-- DIE ZAHLEN respects DIESELBEN Altersregeln wie die Kandidaten
-- selbst: Die Funktion liest aus derselben Sicht
-- (`public_profiles` -> `profile_discovery_visible_full`) und wendet
-- dieselben Filter an (kein Like, kein Funke, Geschlechter-
-- praeferenzen beide Richtungen, Altersspanne, Konsum, Beziehungsart).
-- Wer 16 oder 17 ist, sieht also auch in den Zahlen ausschliesslich
-- Minderjaehrige.
--
-- Die Altersspanne [p_age_min]/[p_age_max] ist die Zusatz-Spanne des
-- Browsers; serverseitig begrenzt auf das, was der Betrachter
-- ueberhaupt sehen darf (16/17 fuer Minderjaehrige, 18-99 fuer
-- Erwachsene).
-- =============================================================================

begin;

create or replace function public.get_find_match_categories(
  p_age_min int,
  p_age_max int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
  v_alter int;
  v_grenze_unten int;
  v_grenze_oben int;
  v_min int;
  v_max int;
begin
  if v_user is null then
    raise exception 'Nicht authentifiziert';
  end if;

  select public.profile_effective_age(me.birth_date, me.verified_age)
    into v_alter
    from public.profiles me
   where me.user_id = v_user;

  -- Fail-closed: ohne belegtes Alter keine Zahlen.
  if v_alter is null then
    return '[]'::jsonb;
  end if;

  v_grenze_unten := public.max_age_range_min(v_alter);
  if v_alter < 18 then
    v_grenze_oben := 17;
  else
    v_grenze_oben := 99;
  end if;

  v_min := greatest(coalesce(p_age_min, v_grenze_unten), v_grenze_unten);
  v_max := least(coalesce(p_age_max, v_grenze_oben), v_grenze_oben);
  if v_max < v_min then
    v_max := v_min;
  end if;

  select coalesce(
           jsonb_agg(jsonb_build_object('category', k.kategorie, 'cnt', k.anzahl)
                     order by k.anzahl desc, k.kategorie),
           '[]'::jsonb)
    into v_result
    from (
      select je.kategorie, count(distinct p.user_id) as anzahl
        from public.public_profiles p
        join public.profiles me on me.user_id = v_user
        join public.profiles cand on cand.user_id = p.user_id
        cross join lateral jsonb_array_elements_text(
          coalesce(p.interests, '[]'::jsonb)) je(kategorie)
       where p.user_id <> v_user
         and (p.intro_text <> '' or p.intro_audio_path is not null)
         and p.age between v_min and v_max
         and not exists (
               select 1 from public.likes l
                where (l.user_id = v_user and l.liked_user_id = p.user_id)
                   or (l.user_id = p.user_id and l.liked_user_id = v_user))
         and not exists (
               select 1 from public.matches m
                where (m.user_one_id = v_user and m.user_two_id = p.user_id)
                   or (m.user_one_id = p.user_id and m.user_two_id = v_user))
         and (me.gender_preferences is null
              or me.gender_preferences = '{}'::text[]
              or p.gender = any(me.gender_preferences))
         and (cand.gender_preferences is null
              or cand.gender_preferences = '{}'::text[]
              or me.gender = any(cand.gender_preferences))
         and public.profile_effective_age(me.birth_date, me.verified_age)
             between cand.age_range_min and cand.age_range_max
         and (me.smoking is null or me.smoking = ''
              or coalesce(public._habitude_rank(p.smoking), 0)
                 <= public._habitude_rank(me.smoking))
         and (me.alcohol is null or me.alcohol = ''
              or coalesce(public._habitude_rank(p.alcohol), 0)
                 <= public._habitude_rank(me.alcohol))
         and (me.drugs is null or me.drugs = ''
              or coalesce(public._habitude_rank(p.drugs), 0)
                 <= public._habitude_rank(me.drugs))
         and ((coalesce(me.relationship_type, 'other') = 'friends')
              = (coalesce(cand.relationship_type, 'other') = 'friends'))
       group by je.kategorie
    ) k;
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast): dieselbe Sicht, dieselbe Altersgrenze.
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'get_find_match_categories'
       and p.prosrc like '%public_profiles%'
  ) then
    raise exception
      'Sicherheitscheck fehlgeschlagen: get_find_match_categories liest nicht aus public_profiles - die Altersgrenze waere umgangen.';
  end if;
end;
$$;

revoke all on function public.get_find_match_categories(int, int) from public;
grant execute on function public.get_find_match_categories(int, int) to authenticated;

commit;
