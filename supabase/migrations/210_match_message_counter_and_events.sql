-- =============================================================================
-- 210_match_message_counter_and_events.sql
-- =============================================================================
-- ZWEI DINGE, DIE DER BETREIBER WOLLTE (11.11.2026):
--
-- 1) "die kleine Zahl ... wie viele Nachrichten die Person geschrieben hat"
--    - und zwar RICHTIG.
--
--    DER GRUND (live geprueft): Die App speichert Nachrichten bewusst nur
--    auf dem Geraet (E2E, Audit N-8 - so ist es entschieden). Die kleine
--    Zahl in der Kachel las bisher den LOKALEN Verlauf. Und der lokale
--    Verlauf eines Server-Funken entsteht erst, wenn der Chat auf diesem
--    Geraet geoeffnet wurde. Bei einem Funken, dessen Chat man nie
--    geoeffnet hat, stand deshalb KEINE Zahl - nicht etwa eine zu kleine.
--    Und auf zwei Geraeten standen verschiedene Zahlen.
--
--    DIE LOESUNG: Ein serverseitiger Zaehler je Funke. KEIN Inhalt - nur
--    eine Zahl. Das ist dieselbe Art von Metadaten, die der Server
--    schon sieht, wenn eine Nachricht durch das Relay geht.
--
-- 2) "3. Ist kein Nachrichtenloeschen wie bei z. B. Whatsapp moeglich?
--    Also da kann man die Nachricht ja irgendwie fuer beide loeschen,
--    aber ein Hinweis steht dann da, dass es fuer alle geloescht wurde.
--    Ist das gegen den Datenschutz? Wenn ja nicht machen."
--
--    DIE ANTWORT: Das ist mit dem bestehenden E2E-Modell vereinbar -
--    wenn der Server ausschliesslich die TATSACHE speichert, dass eine
--    Nachricht geloescht wurde. Kein Text, keine Chiffre, kein Inhalt.
--    Der Server wuerde damit nichts ueber den Inhalt wissen, das er nicht
--    schon beim Zustellen sieht.
--
--    DIE UMSETZUNG (in dieser Migration):
--    * `public.match_message_events` - eine Zeile je Nachricht:
--      (match_id, message_id, sender, created_at, deleted).
--      Sie hat zwei Aufgaben:
--        - Sie macht den Zaehler EXAKT: `bump_match_message_count` zaehlt
--          nur, wenn die Nachricht-ID neu ist (ON CONFLICT DO NOTHING).
--          Ohne das waere die Zahl bei jedem Netzwerk-Fehler um eins
--          daneben.
--        - Sie ist der "Tombstone": `deleted = true` heisst "diese
--          Nachricht ist fuer alle geloescht". Der Empfaenger fragt die
--          Liste ab und ersetzt die Nachricht durch einen Hinweis.
--
--    DIE EHRENTLICHE GRENZE (steht auch im Text der App):
--    Das Loeschen entfernt die Nachricht auf DEINEN Geraeten und die
--    Zustellung, falls sie noch unterwegs war. Die bereits zugestellte
--    Kopie beim anderen kann nicht zurueckgerufen werden - die hat er
--    schon gelesen. Das ist bei WhatsApp genauso so. Der Server
--    speichert weiterhin KEINEN Inhalt.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Die Zaehler an den Funken
-- -----------------------------------------------------------------------------
alter table public.matches
  add column if not exists messages_from_one integer not null default 0,
  add column if not exists messages_from_two integer not null default 0;

comment on column public.matches.messages_from_one is
  'v0.10.1: Anzahl der Nachrichten, die user_one_id in diesem Funke gesendet hat. Ein Zaehler, kein Inhalt - damit die Zahl der gesendeten Nachrichten auf allen Geraeten gleich ist.';

comment on column public.matches.messages_from_two is
  'v0.10.1: Anzahl der Nachrichten, die user_two_id in diesem Funke gesendet hat.';

-- -----------------------------------------------------------------------------
-- 2) Die Ereignis-Tabelle: Zaehler-Genauigkeit + Loesch-Tombstones
-- -----------------------------------------------------------------------------
create table if not exists public.match_message_events (
  match_id bigint not null references public.matches(id) on delete cascade,
  message_id text not null,
  sender uuid not null,
  created_at timestamptz not null default now(),
  deleted boolean not null default false,
  deleted_at timestamptz,
  primary key (match_id, message_id)
);

comment on table public.match_message_events is
  'v0.10.1: Eine Zeile je gesendeter Nachricht - OHNE Inhalt. Zweck: (a) der Nachrichtenzaehler je Funke soll exakt sein (eine Nachricht-ID zaehlt nur einmal), (b) ein "fuer alle geloescht"-Hinweis fuer den Empfaenger. Aufraeumung nach 180 Tagen (cron unten).';

create index if not exists idx_match_message_events_match
  on public.match_message_events (match_id, created_at desc);

alter table public.match_message_events enable row level security;

-- Die Ereignisse sind ausschliesslich ueber die RPCs erreichbar (der
-- Aufrufer muss Teil des Funkes sein). Es gibt KEIN direktes Lesen.
revoke all on table public.match_message_events from anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3) Der Zaehler: exakt und idempotent
-- -----------------------------------------------------------------------------
create or replace function public.bump_match_message_count(
  p_match_id bigint,
  p_message_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_one uuid;
  v_two uuid;
  v_neu boolean;
  v_mine int := 0;
  v_partner int := 0;
begin
  if v_user is null then
    raise exception 'Nicht angemeldet';
  end if;
  if p_message_id is null or btrim(p_message_id) = '' then
    raise exception 'Ungueltige Nachricht';
  end if;

  select m.user_one_id, m.user_two_id into v_one, v_two
    from public.matches m
   where m.id = p_match_id
     and m.status <> 'ended';

  if v_one is null then
    raise exception 'Funke nicht gefunden';
  end if;
  if v_user <> v_one and v_user <> v_two then
    raise exception 'Kein Zugriff auf diesen Funke';
  end if;

  -- Die Ereignis-Zeile zaehlt NUR beim ersten Mal (ON CONFLICT DO
  -- NOTHING). Darum zaehlt dieselbe Nachricht nicht zweimal, auch wenn
  -- der Aufrufer es nach einem Netzwerkfehler wiederholt.
  insert into public.match_message_events (match_id, message_id, sender)
  values (p_match_id, p_message_id, v_user)
  on conflict (match_id, message_id) do nothing;

  get diagnostics v_neu = row_count;
  if v_neu = 0 then
    -- Bereits gezaehlt: nichts aendern, nur den Stand melden.
    select case when m.user_one_id = v_user then m.messages_from_one
                else m.messages_from_two end,
           case when m.user_one_id = v_user then m.messages_from_two
                else m.messages_from_one end
      into v_mine, v_partner
      from public.matches m where m.id = p_match_id;
    return jsonb_build_object('mine', v_mine, 'partner', v_partner, 'counted', false);
  end if;

  if v_user = v_one then
    update public.matches
       set messages_from_one = messages_from_one + 1
     where id = p_match_id
    returning messages_from_one, messages_from_two into v_mine, v_partner;
  else
    update public.matches
       set messages_from_two = messages_from_two + 1
     where id = p_match_id
    returning messages_from_one, messages_from_two into v_partner, v_mine;
  end if;

  return jsonb_build_object('mine', v_mine, 'partner', v_partner, 'counted', true);
end;
$$;

comment on function public.bump_match_message_count(bigint, text) is
  '210: Zaehlt eine gesendete Nachricht je Funke - genau einmal je Nachrichten-ID. Kein Inhalt.';

revoke all on function public.bump_match_message_count(bigint, text) from public, anon;
grant execute on function public.bump_match_message_count(bigint, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4) Fuer alle loeschen: der Tombstone
-- -----------------------------------------------------------------------------
create or replace function public.delete_message_for_all(
  p_match_id bigint,
  p_message_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_one uuid;
  v_two uuid;
  v_gesendet boolean;
begin
  if v_user is null then
    raise exception 'Nicht angemeldet';
  end if;
  if p_message_id is null or btrim(p_message_id) = '' then
    raise exception 'Ungueltige Nachricht';
  end if;

  select m.user_one_id, m.user_two_id into v_one, v_two
    from public.matches m
   where m.id = p_match_id and m.status <> 'ended';

  if v_one is null then
    raise exception 'Funke nicht gefunden';
  end if;
  if v_user <> v_one and v_user <> v_two then
    raise exception 'Kein Zugriff auf diesen Funke';
  end if;

  -- Nur EIGENE Nachrichten duerfen geloescht werden. Eine fremde
  -- Nachricht zu loeschen waere eine Rechteausweitung: man koennte so
  -- die Nachrichten des anderen unlesbar machen.
  select exists (
    select 1 from public.match_message_events e
     where e.match_id = p_match_id
       and e.message_id = p_message_id
       and e.sender = v_user
  ) into v_gesendet;

  if not v_gesendet then
    raise exception 'Nur eigene Nachrichten koennen geloescht werden';
  end if;

  -- Der Tombstone: nur die TATSACHE, kein Inhalt.
  update public.match_message_events
     set deleted = true, deleted_at = now()
   where match_id = p_match_id
     and message_id = p_message_id
     and sender = v_user;

  return jsonb_build_object('deleted', true, 'matchId', p_match_id,
                            'messageId', p_message_id);
end;
$$;

comment on function public.delete_message_for_all(bigint, text) is
  '210: Loescht eine EIGENE Nachricht fuer alle. Der Server speichert nur die Tatsache (keinen Inhalt); der Empfaenger ersetzt die Nachricht durch einen Hinweis.';

revoke all on function public.delete_message_for_all(bigint, text) from public, anon;
grant execute on function public.delete_message_for_all(bigint, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5) Die Tombstones des Empfaengers abfragen
-- -----------------------------------------------------------------------------
create or replace function public.list_message_deletions(p_match_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'messageId', e.message_id,
           'deletedAt', e.deleted_at
         ) order by e.deleted_at desc), '[]'::jsonb)
    from public.match_message_events e
   where e.match_id = p_match_id
     and e.deleted = true
     and e.deleted_at is not null
     and (
       exists (
         select 1 from public.matches m
          where m.id = e.match_id
            and (m.user_one_id = auth.uid() or m.user_two_id = auth.uid())
       )
     );
$$;

comment on function public.list_message_deletions(bigint) is
  '210: Die "fuer alle geloescht"-Hinweise eines Funkes (nur fuer Teilnehmer).';

revoke all on function public.list_message_deletions(bigint) from public, anon;
grant execute on function public.list_message_deletions(bigint) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 6) Die Funkenliste: der Zaehler kommt mit
-- -----------------------------------------------------------------------------
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
             'passedAt', m.passed_at,
             'lastAttemptAt', m.last_attempt_at,
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
  '210: wie vorher, plus der serverseitige Nachrichtenzaehler je Funke (messageCount = die Person, messageCountMine = ich).';

revoke all on function public.list_my_matches_with_state() from public, anon;
grant execute on function public.list_my_matches_with_state() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7) Aufraeumung: die Ereignisse sind Metadaten, kein Archiv
-- -----------------------------------------------------------------------------
-- 180 Tage: so lange bleibt ein "fuer alle geloescht"-Hinweis erhalten
-- (laenger als der Relay-Aufraeum mit 30 Tagen). Danach verschwinden
-- auch die Zaehler-Ereignisse - die Zaehler selbst stehen in
-- public.matches und bleiben.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (
      select 1 from cron.job where jobname = 'cleanup_match_message_events'
    ) then
      perform cron.schedule('cleanup_match_message_events', '25 4 * * *', $cron$
        delete from public.match_message_events
         where created_at < now() - interval '180 days'
      $cron$);
    end if;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 8) BEWEIS (Fail-Fast)
-- -----------------------------------------------------------------------------
do $$
declare
  v_src text;
begin
  -- (a) Die Spalten existieren.
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'matches'
       and column_name = 'messages_from_one'
  ) or not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'matches'
       and column_name = 'messages_from_two'
  ) then
    raise exception
      'Sicherheitscheck fehlgeschlagen: Die Nachrichtenzaehler an public.matches fehlen.';
  end if;

  -- (b) Die Ereignis-Tabelle hat KEINEN direkten Lesezugriff fuer
  --     angemeldete Nutzer - nur die RPCs.
  if exists (
    select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'match_message_events'
       and c.relrowsecurity
       and exists (
         select 1 from pg_roles
          where rolname = 'authenticated'
            and has_table_privilege('authenticated', 'public.match_message_events', 'SELECT')
       )
  ) then
    raise exception
      'Sicherheitscheck fehlgeschlagen: match_message_events ist fuer angemeldete Nutzer direkt lesbar - sie muessen ueber die RPCs laufen.';
  end if;

  -- (c) Der Zaehler zaehlt nur einmal je Nachrichten-ID.
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'bump_match_message_count';
  if v_src is null or v_src not like '%on conflict (match_id, message_id) do nothing%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: bump_match_message_count() zaehlt nicht idempotent - dieselbe Nachricht wuerde mehrfach gezaehlt.';
  end if;

  -- (d) Loeschen ist auf eigene Nachrichten beschraenkt.
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'delete_message_for_all';
  if v_src is null or v_src not like '%e.sender = v_user%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: delete_message_for_all() prueft nicht, dass die Nachricht dem Aufrufer gehoert.';
  end if;

  -- (e) Die Funkenliste liefert den Zaehler mit.
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'list_my_matches_with_state';
  if v_src is null or v_src not like '%messageCount%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: list_my_matches_with_state() liefert den Nachrichtenzaehler nicht mit.';
  end if;
end;
$$;

commit;
