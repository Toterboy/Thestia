-- =============================================================================
-- 211_fix_bump_match_message_counter_type.sql
-- =============================================================================
-- SOFORT-KORREKTUR zu Migration 210 (live gefunden, 11.11.2026).
--
-- DER FEHLER: In `bump_match_message_count` war die Variable fuer
-- `GET DIAGNOSTICS ... ROW_COUNT` als BOOLEAN deklariert:
--
--     v_neu boolean;
--     ...
--     get diagnostics v_neu = row_count;
--
-- `ROW_COUNT` ist ein INTEGER. Postgres lehnt die Zuweisung ab:
--
--     ERROR: 42883: operator does not exist: boolean = integer
--     CONTEXT: PL/pgSQL function bump_match_message_count(bigint,text)
--
-- DER EFFEKT: JEDER Aufruf der Funktion ist gescheitert - der
-- Nachrichtenzaehler waere nie gestiegen, und der Aufrufer haette
-- (fire-and-forget) nichts gemerkt. Die statische Pruefung in Migration
-- 210 hat das NICHT gesehen: sie prueft den Quelltext, nicht das
-- Verhalten. Erst der Live-Aufruf hat es gezeigt.
--
-- DIE KORREKTUR: v_neu ist ein INTEGER.
--
-- ZUSAETZLICH: Der Fail-Fast-Beweis prueft jetzt die Typdeklaration -
-- damit kann derselbe Fehler nicht noch einmal unbemerkt hineinkommen.
-- =============================================================================

begin;

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
  -- BEFUND (11.11.2026): ROW_COUNT ist ein INTEGER. Mit BOOLEAN
  -- scheiterte JEDER Aufruf (42883). Die statische Pruefung in
  -- Migration 210 hat das nicht gesehen - erst der Live-Aufruf.
  v_neu integer;
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
  '210+211: Zaehlt eine gesendete Nachricht je Funke - genau einmal je Nachrichten-ID. Kein Inhalt.';

revoke all on function public.bump_match_message_count(bigint, text) from public, anon;
grant execute on function public.bump_match_message_count(bigint, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast): Der Typ von ROW_COUNT muss INTEGER sein.
-- -----------------------------------------------------------------------------
do $$
declare
  v_src text;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'bump_match_message_count';

  if v_src is null then
    raise exception
      'Sicherheitscheck fehlgeschlagen: bump_match_message_count() fehlt.';
  end if;

  -- (a) ROW_COUNT braucht ein INTEGER. Mit BOOLEAN scheitert JEDER
  --     Aufruf (42883) - das war der Fehler aus Migration 210.
  if v_src !~* 'v_neu\s+integer' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: Die Variable fuer ROW_COUNT ist nicht als INTEGER deklariert - jeder Aufruf wuerde mit 42883 scheitern.';
  end if;

  -- (b) Und die Zuweisung muss es auch benutzen.
  if v_src !~* 'get\s+diagnostics\s+v_neu\s*=\s*row_count' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: bump_match_message_count() liest ROW_COUNT nicht aus.';
  end if;

  -- (c) Die Idempotenz muss erhalten bleiben.
  if v_src !~* 'on\s+conflict\s*\(match_id,\s*message_id\)\s*do\s+nothing' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: bump_match_message_count() zaehlt nicht idempotent.';
  end if;
end;
$$;

commit;
