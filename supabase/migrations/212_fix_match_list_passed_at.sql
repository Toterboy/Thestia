-- =============================================================================
-- 212_fix_match_list_passed_at.sql
-- =============================================================================
-- SOFORT-KORREKTUR zu Migration 210 (live gefunden, 11.11.2026).
--
-- DER FEHLER: Migration 210 hat `list_my_matches_with_state()` neu
-- definiert und dabei zwei Spalten FALSCH adressiert:
--
--     'passedAt',      m.passed_at,      -- gibt es nicht!
--     'lastAttemptAt', m.last_attempt_at -- gibt es dort nicht!
--
-- Beide Spalten liegen in `public.match_quiz_state` (Alias s), nicht in
-- `public.matches` (Alias m). Postgres lehnt die Abfrage ab:
--
--     ERROR: 42703: column m.passed_at does not exist
--     HINT: Perhaps you meant to reference the column "s.passed_at".
--
-- DER EFFEKT: Die Funkenliste liess sich nicht mehr lesen - der
-- Interessen-Screen (alle Funken, die Zaehler) waere leer gewesen.
--
-- WICHTIG: Der Fehler fiel erst beim LIVE-Aufruf auf. Die statische
-- Pruefung von Migration 210 hat den Quelltext angeschaut, nicht das
-- Verhalten - und der Quelltext sah plausibel aus.
--
-- DIE KORREKTUR: `s.passed_at` und `s.last_attempt_at` (so wie es in
-- Migration 178 stand). Zusaetzlich wird der Fail-Fast-Beweis
-- verschaerft: er prueft jetzt, dass die Funktion die Quiz-Spalten aus
-- DER RICHTIGEN TABELLE liest (s_ und nicht m_).
-- =============================================================================

begin;

create or replace function public.list_my_matches_with_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
begin
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'matchId', m.id,
             'partnerId', case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end,
             'createdAt', m.created_at,
             'createdVia', m.created_via,
             'status', m.status,
             'resparkedAt', m.resparked_at,
             'unlockLevel', coalesce(s.unlock_level, 0),
             'failedAttempts', coalesce(s.failed_attempts, 0),
             -- BEFUND (11.11.2026): Diese beiden Spalten liegen in
             -- match_quiz_state (Alias s) - nicht in matches (Alias m).
             -- Migration 210 hatte sie falsch adressiert; die Funktion
             -- liess sich dadurch nicht mehr aufrufen.
             'passedAt', s.passed_at,
             'lastAttemptAt', s.last_attempt_at,
             'distanceKm', public.profile_distance_km(
               case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end),
             'profile', row_to_json(p.*),
             'kind', coalesce(m.kind, 'spark'),
             'autoMatch', coalesce(m.auto_match, false),
             -- v0.10.1 (Migration 210): die Zahl der gesendeten
             -- Nachrichten. 'messageCount' ist die Zahl der PERSON
             -- (des Partners), 'messageCountMine' die eigene. Beide
             -- serverseitig - damit stimmen sie auf allen Geraeten.
             'messageCount', case when m.user_one_id = v_user
                                  then m.messages_from_two
                                  else m.messages_from_one end,
             'messageCountMine', case when m.user_one_id = v_user
                                       then m.messages_from_one
                                       else m.messages_from_two end
           ) order by
             (m.status = 'active') desc,
             m.created_at desc), '[]'::jsonb)
    into v_result
    from public.matches m
    left join public.match_quiz_state s on s.match_id = m.id
    join lateral (
      select q.*
        from public.public_profiles q
       where q.user_id = case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end
    ) p on true
   where (m.user_one_id = v_user or m.user_two_id = v_user)
     and m.status <> 'ended'
     and not (v_user = any(m.hidden_by));
  return v_result;
end;
$$;

comment on function public.list_my_matches_with_state() is
  '212: wie 210, aber die Quiz-Spalten (passed_at, last_attempt_at) aus match_quiz_state - Migration 210 hatte sie falsch adressiert und die Funktion damit unbenutzbar gemacht.';

revoke all on function public.list_my_matches_with_state() from public, anon;
grant execute on function public.list_my_matches_with_state() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast): Die Spalten muessen aus der richtigen Tabelle kommen.
-- -----------------------------------------------------------------------------
do $$
declare
  v_src text;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'list_my_matches_with_state';

  if v_src is null then
    raise exception
      'Sicherheitscheck fehlgeschlagen: list_my_matches_with_state() fehlt.';
  end if;

  -- (a) Die Quiz-Spalten muessen aus match_quiz_state (Alias s) kommen.
  if v_src !~* 'passedAt''?,\s*s\.passed_at' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: passedAt wird nicht aus match_quiz_state gelesen - die Abfrage wuerde mit 42703 scheitern.';
  end if;
  if v_src !~* 'lastAttemptAt''?,\s*s\.last_attempt_at' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: lastAttemptAt wird nicht aus match_quiz_state gelesen - die Abfrage wuerde mit 42703 scheitern.';
  end if;

  -- (b) Und sie duerfen NICHT aus matches (Alias m) kommen.
  if v_src ~* 'm\.passed_at' or v_src ~* 'm\.last_attempt_at' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: Die Funktion liest eine Quiz-Spalte aus matches - die Spalte existiert dort nicht.';
  end if;

  -- (c) Der Nachrichtenzaehler muss mitkommen.
  if v_src not like '%messageCount%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: list_my_matches_with_state() liefert den Nachrichtenzaehler nicht mit.';
  end if;
end;
$$;

commit;
