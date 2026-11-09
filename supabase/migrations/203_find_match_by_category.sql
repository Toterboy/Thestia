-- =============================================================================
-- 203_find_match_by_category.sql
-- =============================================================================
-- "FIND YOUR SPARK" ERWEITERT: STOEBERN NACH INTERESSENS-KATEGORIEN
-- (BEFUND 09.11.2026, Betreiber):
--
-- "Der Modus Find your Spark soll erweitert werden. Wenn man auf ihn
--  drauf drueckt, kommt wie gehabt erst, dass man seine Vorstellung
--  machen muss (Muss geprueft werden, ob man schon gemacht hat oder
--  nicht, damit nicht doppelt), dann entweder Zufallsvorstellung oder
--  Vorstellungen anderer nach Kategorien ansehen. Also Kategorien sind
--  die Interessens-Kategorien. Auf diesen neuen Teil mit den Kategorien
--  soll ein Bereich mit 18+ sein, wo von 18 bis 99+ alle gesehen
--  werden (Aber man kann nach Alter filtern mit Regler) und ein 16-17
--  Bereich ohne Vorstellung mit Alter darueber. Wichtig ist, dass diese
--  Grenze wirklich klappt, wie auch ueberall anders auch, damit die
--  Kinder/Jugend geschuetzt sind. Natuerlich da dann E2E immer.
--  Verschluesselt auf Server speichern."
--
-- DIE FUNKTION liefert die Kandidaten einer Kategorie - mit ALLEN
-- Filtern der bestehenden Zufalls-Vorstellung (kein Like, kein Funke,
-- Geschlechterpräferenzen beide Richtungen, Altersspanne, Konsum,
-- Beziehungsart) und ZUSÄTZLICH dem Kategorie-Filter und der
-- Altersspanne des Browsers.
--
-- DIE ALTERSSGRENZE (der Punkt, der hier wirklich zaehlt):
--
-- Die Funktion liest aus `public_profiles` - und DIE Sicht filtert
-- ueber `profile_discovery_visible_full(auth.uid(), p.user_id)`:
--
--   * `age_compatible_bidirectional_ages(viewer, ziel)` - die
--     beidseitige Regel: Minderjaehrige sehen ausschliesslich
--     Minderjaehrige, Erwachsene ausschliesslich Erwachsene.
--   * `max_age_range_min(viewer_age)` - die untere Grenze: 16 fuer
--     Minderjaehrige, ab 18 nie unter 18 (und hoechstens 10 Jahre
--     unter dem eigenen Alter).
--   * die Altersspanne des Betrachters aus den Einstellungen.
--
-- Die Kategorie-Sicht kann diese Grenze also NICHT umgehen: sie
-- benutzt dieselbe Sicht. Ein manipulierter Client, der eine zu
-- weite Altersspanne sendet, wird zusaetzlich hier begrenzt
-- (`v_grenze_oben`/`v_grenze_unten`) - und die Grenzen sind
-- serverseitig gesetzt, nicht aus dem Client uebernommen.
--
-- E2E: Die Funktion liefert KEIN Audio. Die Vorstellung wird als TEXT
-- angezeigt; die Aufnahme ist optional und wird - wie bisher - erst
-- beim Funke freigegeben (match-media, serverseitig geprueft). Der
-- Weg ist also derselbe wie bei der Zufalls-Vorstellung.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Die Kategorie-Sicht
-- -----------------------------------------------------------------------------
create or replace function public.get_find_match_by_category(
  p_category text,
  p_age_min int,
  p_age_max int,
  p_limit int default 20
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

  if p_category is null or btrim(p_category) = '' then
    raise exception 'Keine Kategorie angegeben';
  end if;

  -- Das ALTER des Betrachters - dieselbe Groesse, die auch die Sicht
  -- verwendet (`profile_effective_age`: das verifizierte Alter hat Vorrang
  -- vor dem Geburtsdatum, Migration 155).
  select public.profile_effective_age(me.birth_date, me.verified_age)
    into v_alter
    from public.profiles me
   where me.user_id = v_user;

  -- KEIN ALTER -> fail-closed: ohne belegtes Alter wird nichts geliefert.
  if v_alter is null then
    return '[]'::jsonb;
  end if;

  -- DIE GRENZEN (serverseitig, nicht aus dem Client):
  --   unten: 16 fuer Minderjaehrige, ab 18 nie unter 18
  --   oben:  17 fuer Minderjaehrige, sonst 99
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

  select coalesce(jsonb_agg(row_to_json(t) order by t.random_order), '[]'::jsonb)
    into v_result
    from (
      select p.*,
             (select public.profile_distance_km(p.user_id)) as distance_km,
             random() as random_order
        from public.public_profiles p
        join public.profiles me on me.user_id = v_user
        join public.profiles cand on cand.user_id = p.user_id
       where p.user_id <> v_user
         -- Die Vorstellung: Text ODER Audio (das Audio ist optional -
         -- der Betreiber am 09.11.2026: "Es kann jedoch, wenn man sich
         -- vorstellt nur eine textliche Vorstellung sein").
         and (p.intro_text <> '' or p.intro_audio_path is not null)
         -- DIE KATEGORIE: `interests` ist ein JSONB-Array aus Strings
         -- (["Musik","Gaming",...]). Der @>-Operator prueft die
         -- Enthaltenheit - unabhaengig von der Reihenfolge.
         and coalesce(p.interests, '[]'::jsonb) @> jsonb_build_array(p_category)
         -- Die Altersspanne DES BROWSERS (zusaetzlich zu den Grenzen
         -- der Sicht und zu den Einstellungen des Betrachters).
         and p.age between v_min and v_max
         -- Kein Like in beide Richtungen, kein Funke.
         and not exists (
               select 1 from public.likes l
                where (l.user_id = v_user and l.liked_user_id = p.user_id)
                   or (l.user_id = p.user_id and l.liked_user_id = v_user))
         and not exists (
               select 1 from public.matches m
                where (m.user_one_id = v_user and m.user_two_id = p.user_id)
                   or (m.user_one_id = p.user_id and m.user_two_id = v_user))
         -- Geschlechterpraeferenzen (meine und seine, Audit M-2).
         and (me.gender_preferences is null
              or me.gender_preferences = '{}'::text[]
              or p.gender = any(me.gender_preferences))
         and (cand.gender_preferences is null
              or cand.gender_preferences = '{}'::text[]
              or me.gender = any(cand.gender_preferences))
         -- Reziprozitaet der Altersspanne.
         and public.profile_effective_age(me.birth_date, me.verified_age)
             between cand.age_range_min and cand.age_range_max
         -- Konsum-Filter (wie in der Zufalls-Vorstellung).
         and (me.smoking is null or me.smoking = ''
              or coalesce(public._habitude_rank(p.smoking), 0)
                 <= public._habitude_rank(me.smoking))
         and (me.alcohol is null or me.alcohol = ''
              or coalesce(public._habitude_rank(p.alcohol), 0)
                 <= public._habitude_rank(me.alcohol))
         and (me.drugs is null or me.drugs = ''
              or coalesce(public._habitude_rank(p.drugs), 0)
                 <= public._habitude_rank(me.drugs))
         -- "Ich suche"-Reziprozitaet (Freunde-Sucher sehen nur
         -- Freunde-Sucher) - wie in der Zufalls-Vorstellung.
         and ((coalesce(me.relationship_type, 'other') = 'friends')
              = (coalesce(cand.relationship_type, 'other') = 'friends'))
       order by random()
       limit least(coalesce(p_limit, 20), 50)
    ) t;
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast): Die Sicht MUSS die Schutzabfrage enthalten.
--
-- Ohne diesen Check koennte eine spaetere Aenderung an der Sicht (oder
-- ein neues Release ohne diese Migration) die Kategorie-Sicht zur
-- Luecke machen: die Kandidaten kaemen dann OHNE die Altersgrenze aus.
-- Genau das ist die Sorte Regression, die zweimal still passiert ist.
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
      from pg_views
     where schemaname = 'public'
       and viewname = 'public_profiles'
       and definition like '%profile_discovery_visible_full%'
  ) then
    raise exception
      'Sicherheitscheck fehlgeschlagen: public_profiles filtert nicht mehr ueber profile_discovery_visible_full - die Kategorie-Sicht wuerde die Altersgrenze umgehen. Die Sicht wiederherstellen (Migration 154/164/169).';
  end if;

  -- Die Funktion MUSS ueber die Sicht gehen - nicht direkt ueber
  -- profiles. Sonst waere die Altersgrenze weg.
  if not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'get_find_match_by_category'
       and p.prosrc like '%public_profiles%'
  ) then
    raise exception
      'Sicherheitscheck fehlgeschlagen: get_find_match_by_category liest nicht aus public_profiles - die Altersgrenze waere umgangen.';
  end if;
end;
$$;

revoke all on function public.get_find_match_by_category(text, int, int, int) from public;
grant execute on function public.get_find_match_by_category(text, int, int, int) to authenticated;

commit;
