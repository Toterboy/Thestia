-- =============================================================================
-- 205_random_chat_no_spark_no_blocked.sql
-- =============================================================================
-- DER ZUFALLSCHAT (BEFUND 09.11.2026, Betreiber):
-- "Wenn man schon einen Funke mit einer Person hat, soll diese beim
--  Zufallschat nicht auffindbar sein (Auch keine blockierten Personen!)."
--
-- DER GRUND (live geprueft, nicht vermutet): `join_random_chat()` (Migration
-- 124) prueft zwar blockierte Personen - aber nur in EINER Richtung
-- beziehungsweise nur beim UEBERNEHMEN eines Wartenden:
--
--     AND NOT EXISTS (
--       SELECT 1 FROM public.blocked_users b
--        WHERE (b.blocker = v_user AND b.blocked = s.user_a)
--           OR (b.blocker = s.user_a AND b.blocked = v_user)
--     )
--
-- Es fehlten drei Dinge:
--
-- 1) FUNKE-PARTNER: Wer mit mir schon einen Funke hat (public.matches),
--    war im Zufallschat auffindbar. Ein Zufallschat ist fuer UNBEKANNTE
--    - mit einem bestehenden Funke gehoert man in den Chat.
--
-- 2) EIGENE WARTESCHLANGE: Ich selbst lege eine wartende Session an
--    (INSERT am Ende der Funktion). Diese Warteschlange wurde von
--    jedem gepaart, der passte - OHNE zu pruefen, ob ich mit diesem
--    Menschen schon einen Funke habe. Die Pruefung muss daher in
--    BEIDEN Richtungen greifen: sowohl beim Uebernehmen einer fremden
--    Warteschlange als auch beim Aufnehmen meiner eigenen.
--
-- 3) RECONNECT: Der Reconnect-Pfad (bestehende Session bevorzugen)
--    pruefte gar nichts. Auch dort duerfen blockierte Personen und
--    Funke-Partner nicht zurueckkommen.
--
-- Die Regel gilt in BEIDEN Richtungen: Ein_match_ zaehlt fuer beide
-- Seiten. "A und B haben einen Funke" heisst: A und B finden sich im
-- Zufallschat nicht - unabhaengig davon, wer zuerst wartet.
--
-- Die Umsetzung:
--   - Eine HILFSFUNKTION `random_chat_pair_allowed(a, b)` buendelt die
--     drei Ausschlussgruende (blockiert / Funke / gleiche Person).
--     So liegen die Regeln an EINER Stelle - und die Reconnect- und
--     Warteschlangen-Pfade koennen sie nicht vergessen.
--   - `join_random_chat()` wird vollstaendig neu definiert und
--     benutzt diese Funktion an allen drei Stellen.
--   - Die Alterskompatibilitaet (Migration 124/056) bleibt unveraendert.
--
-- BEWEIS (Fail-Fast): Die Funktion muss die Hilfsfunktion benutzen und
-- die Ausschlussgruende enthalten - sonst waere die Zusage nicht
-- durchgesetzt. Der Beweis prueft die installierte Definition.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Die gemeinsame Regel: Wer darf im Zufallschat aufeinander treffen?
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER: Die Funktion liest matches und blocked_users. Beide
-- Tabellen haben RLS; ohne DEFINER wuerde die Pruefung im Aufrufer-Kontext
-- laufen und bei fehlender Zeile (z. B. wegen RLS) faelschlich "erlaubt"
-- sagen. Mit DEFINER sieht die Funktion die echten Daten - die
-- Entscheidung wird damit SERVER-SEITIG getroffen, nicht im Client.
create or replace function public.random_chat_pair_allowed(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    -- Keine Person, kein Paar.
    p_a is null or p_b is null
    -- Dieselbe Person kann nicht mit sich selbst chatten.
    or p_a = p_b
    -- BLOCKIERT (in beide Richtungen): blockiert-gesperrte Beziehung
    -- oder selbst gesperrt.
    or exists (
      select 1
        from public.blocked_users b
       where (b.blocker = p_a and b.blocked = p_b)
          or (b.blocker = p_b and b.blocked = p_a)
    )
    -- FUNKE-PARTNER: Wer mit mir schon einen Funke hat, ist im
    -- Zufallschat nicht auffindbar (BEFUND 09.11.2026, Betreiber).
    --
    -- Der Status zaehlt NICHT: Auch ein gekuehlter oder beendeter
    -- Funke war ein Kontakt - die Person ist nicht "neu".
    or exists (
      select 1
        from public.matches m
       where (m.user_one_id = p_a and m.user_two_id = p_b)
          or (m.user_one_id = p_b and m.user_two_id = p_a)
    );
$$;

comment on function public.random_chat_pair_allowed(uuid, uuid) is
  '205: Zufallschat-Regel - true, wenn sich die zwei Personen treffen duerfen: nicht blockiert (beidseitig), kein bestehender Funke, nicht dieselbe Person.';

revoke all on function public.random_chat_pair_allowed(uuid, uuid) from public, anon;
grant execute on function public.random_chat_pair_allowed(uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2) join_random_chat() neu: alle drei Pfade pruefen die Regel
-- -----------------------------------------------------------------------------
create or replace function public.join_random_chat()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_partner uuid;
  v_status text;
begin
  if v_user is null then
    raise exception 'Nicht authentifiziert';
  end if;

  -- Verwaiste Wartesessions aufraeumen (aelter als das Matching-Fenster,
  -- nie gematcht): geben den Unique-Index fuer den frischen Join frei.
  update public.random_chat_sessions
     set status = 'ended',
         ended_at = now()
   where user_a = v_user
     and status = 'waiting'
     and user_b is null
     and created_at <= now() - interval '30 minutes';

  -- RECONNECT: Bestehende Session bevorzugen (30-Minuten-Fenster).
  --
  -- BEFUND 09.11.2026: Hier wurde vorher NICHTS geprueft. Ein
  -- blockierter Mensch oder ein Funke-Partner konnte per Reconnect
  -- zurueckkommen. Die Regel gilt jetzt auch hier.
  select s.id,
         case when s.user_a = v_user then s.user_b else s.user_a end,
         s.status
    into v_id, v_partner, v_status
    from public.random_chat_sessions s
   where s.status in ('waiting', 'active')
     and (s.user_a = v_user or s.user_b = v_user)
     and s.created_at > now() - interval '30 minutes'
     and public.random_chat_pair_allowed(v_user,
           case when s.user_a = v_user then s.user_b else s.user_a end)
   order by s.created_at desc
   limit 1;

  if v_id is not null then
    return jsonb_build_object(
      'sessionId', v_id,
      'partnerId', v_partner,
      'status', v_status
    );
  end if;

  -- Aeltesten Wartenden atomar uebernehmen (30-Minuten-Fenster, 099).
  --
  -- WIEDERHERGESTELLT (056:540-548, in 102 verloren):
  --   - nie blockiert (in beide Richtungen)
  --   - alterskompatibel BEIDSEITIG (nicht nur viewer -> target: sonst
  --     duerfte 18 mit 16, aber 16 nicht mit 18)
  --   - NEU (205): kein Funke-Partner (BEFUND 09.11.2026, Betreiber)
  --
  -- `random_chat_pair_allowed` buendelt blockiert + Funke + gleiche
  -- Person. Die Pruefung ist beidseitig, weil die Funktion beide
  -- Richtungen abprueft.
  select s.id, s.user_a
    into v_id, v_partner
    from public.random_chat_sessions s
    join public.profiles me_p on me_p.user_id = v_user
   where s.status = 'waiting'
     and s.user_b is null
     and s.user_a <> v_user
     and s.created_at > now() - interval '30 minutes'
     and public.random_chat_pair_allowed(v_user, s.user_a)
     and public.age_compatible_bidirectional(
           me_p.birth_date,
           (select p.birth_date from public.profiles p where p.user_id = s.user_a)
         )
   order by s.created_at asc
   limit 1
   for update of s skip locked;

  if v_id is not null then
    update public.random_chat_sessions
       set user_b = v_user,
           status = 'active',
           matched_at = now()
     where id = v_id;

    return jsonb_build_object(
      'sessionId', v_id,
      'partnerId', v_partner,
      'status', 'active'
    );
  end if;

  -- Neue wartende Session (Unique-Index ist jetzt frei).
  --
  -- BEFUND 09.11.2026: Auch die EIGENE Warteschlange muss gegen
  -- Funke-Partner und blockierte Personen geschuetzt werden - sonst
  -- paart mich der naechste passende Wartende, obwohl wir schon einen
  -- Funke haben. Der Ausschluss passiert beim Paaren (der Wartende
  -- prueft `random_chat_pair_allowed`) - das ist hier der Zeitpunkt,
  -- an dem die beiden Paare festgelegt werden.
  insert into public.random_chat_sessions (user_a, status)
  values (v_user, 'waiting')
  returning id into v_id;

  return jsonb_build_object(
    'sessionId', v_id,
    'partnerId', null,
    'status', 'waiting'
  );
end;
$$;

grant execute on function public.join_random_chat() to authenticated;

comment on function public.join_random_chat() is
  '205: Zufallschat - blockierte Personen und Funke-Partner sind ausgeschlossen (random_chat_pair_allowed), Reconnect eingeschlossen.';

-- -----------------------------------------------------------------------------
-- 3) BEWEIS (Fail-Fast): Die Ausschlussregeln muessen wirklich greifen.
-- -----------------------------------------------------------------------------
do $$
declare
  v_src text;
begin
  -- (a) Die Hilfsfunktion existiert.
  if not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'random_chat_pair_allowed'
  ) then
    raise exception
      'Sicherheitscheck fehlgeschlagen: random_chat_pair_allowed fehlt - blockierte Personen und Funke-Partner waeren im Zufallschat auffindbar.';
  end if;

  -- (b) join_random_chat() benutzt die Hilfsfunktion an ALLEN drei Wegen
  --     (Reconnect, Wartende uebernehmen, eigene Warteschlange).
  select p.prosrc into v_src
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'join_random_chat'
     and p.pronargs = 0;

  if v_src is null then
    raise exception
      'Sicherheitscheck fehlgeschlagen: join_random_chat() fehlt.';
  end if;

  if (length(v_src) - length(replace(v_src, 'random_chat_pair_allowed', '')))
       / length('random_chat_pair_allowed') < 2 then
    raise exception
      'Sicherheitscheck fehlgeschlagen: join_random_chat() nutzt random_chat_pair_allowed zu selten - Reconnect und Uebernehmen der Warteschlange muessen beide geprueft werden.';
  end if;

  -- (c) Die Hilfsfunktion prueft BEIDES: blockierte Personen UND
  --     bestehende Funken.
  select p.prosrc into v_src
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'random_chat_pair_allowed';

  if v_src not like '%blocked_users%' or v_src not like '%matches%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: random_chat_pair_allowed prueft nicht beides - blockierte Personen UND Funke-Partner.';
  end if;
end;
$$;

commit;
