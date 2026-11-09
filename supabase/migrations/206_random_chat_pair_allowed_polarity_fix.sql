-- =============================================================================
-- 206_random_chat_pair_allowed_polarity_fix.sql
-- =============================================================================
-- SOFORT-KORREKTUR zu Migration 205 (BEFUND 09.11.2026, live geprueft):
--
-- Die Funktion `random_chat_pair_allowed` hatte die VERTAUSCHTE Logik:
-- Sie lieferte TRUE, wenn ein Ausschlussgrund zutraf (blockiert oder
-- Funke), und FALSE, wenn das Paar erlaubt war.
--
-- DER BEWEIS (live, mit den echten Testkonten):
--
--   select public.random_chat_pair_allowed(
--            '46f3f558-...'::uuid,   -- Testkonto A
--            'd177d5f9-...'::uuid);  -- Testkonto B (Funke mit A)
--
--   Ergebnis: TRUE   <- FALSCH. A und B haben einen Funken, das Paar
--                         darf sich im Zufallschat NICHT finden.
--
--   Und mit einer unbekannten Person:
--
--   Ergebnis: FALSE  <- ebenfalls FALSCH (dort IST es erlaubt).
--
-- Die Folge waere gravierend gewesen: `join_random_chat()` benutzt die
-- Funktion mit `and public.random_chat_pair_allowed(...)`. Bei der
-- vertauschten Logik haette der Zufallschat NUR blockierte oder bereits
-- gematchte Personen gepaart - und normale Wartende nie.
--
-- DIE KORREKTUR: Die Funktion liefert jetzt TRUE genau dann, wenn sich
-- die beiden Personen treffen duerfen:
--   - beide Personen bekannt,
--   - nicht dieselbe Person,
--   - in BEIDEN Richtungen nicht blockiert,
--   - kein bestehender Funke.
--
-- Zusaetzlich wird der Fail-Fast-Beweis verschaerft: Er prueft jetzt
-- die POLARITAET (die Ausschlussabfragen muessen mit "not exists"
-- stehen) - mit dem alten Beweis war die Verwechslung nicht zu
-- sehen.
-- =============================================================================

begin;

create or replace function public.random_chat_pair_allowed(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    -- Beide Personen muessen bekannt sein.
    p_a is not null
    and p_b is not null
    -- Nicht dieselbe Person.
    and p_a <> p_b
    -- BLOCKIERT (in beide Richtungen): blockiert-gesperrte Beziehung
    -- oder selbst gesperrt -> NICHT erlaubt.
    and not exists (
      select 1
        from public.blocked_users b
       where (b.blocker = p_a and b.blocked = p_b)
          or (b.blocker = p_b and b.blocked = p_a)
    )
    -- FUNKE-PARTNER: Wer mit mir schon einen Funke hat, ist im
    -- Zufallschat nicht auffindbar (BEFUND 09.11.2026, Betreiber).
    -- Der Status zaehlt NICHT: Auch ein gekuehlter oder beendeter
    -- Funke war ein Kontakt - die Person ist nicht "neu".
    and not exists (
      select 1
        from public.matches m
       where (m.user_one_id = p_a and m.user_two_id = p_b)
          or (m.user_one_id = p_b and m.user_two_id = p_a)
    );
$$;

comment on function public.random_chat_pair_allowed(uuid, uuid) is
  '205+206: Zufallschat-Regel - TRUE heisst "darf sich treffen": nicht blockiert (beidseitig), kein bestehender Funke, nicht dieselbe Person. 206 hat die Polaritaet korrigiert.';

revoke all on function public.random_chat_pair_allowed(uuid, uuid) from public, anon;
grant execute on function public.random_chat_pair_allowed(uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast): Polaritaet und Anschlussstellen pruefen.
-- -----------------------------------------------------------------------------
do $$
declare
  v_src text;
  v_join text;
begin
  select p.prosrc into v_src
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'random_chat_pair_allowed';

  if v_src is null then
    raise exception
      'Sicherheitscheck fehlgeschlagen: random_chat_pair_allowed fehlt.';
  end if;

  -- (a) POLARITAET: Die Ausschlussabfragen muessen mit "not exists"
  --     stehen. Ohne das lieferte die Funktion die VERTAUSCHTE Antwort
  --     (Migration 205 - live geprueft).
  if v_src !~* 'not\s+exists\s*\(\s*select\s+1\s+from\s+public\.blocked_users'
     or v_src !~* 'not\s+exists\s*\(\s*select\s+1\s+from\s+public\.matches' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: random_chat_pair_allowed hat die vertauschte Polaritaet - die Ausschlussabfragen muessen mit "not exists" stehen.';
  end if;

  -- (b) Es darf kein positives "exists" mehr fuer die Ausschlussgruende
  --     geben (das war der Fehler aus 205).
  if v_src ~* 'or\s+exists\s*\(\s*select\s+1\s+from\s+public\.blocked_users'
     or v_src ~* 'or\s+exists\s*\(\s*select\s+1\s+from\s+public\.matches' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: random_chat_pair_allowed enthaelt noch ein positives "or exists" fuer die Ausschlussgruende.';
  end if;

  -- (c) join_random_chat() benutzt die Funktion an ALLEN drei Wegen
  --     (Reconnect, Wartende uebernehmen, eigene Warteschlange).
  select p.prosrc into v_join
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'join_random_chat'
     and p.pronargs = 0;

  if v_join is null then
    raise exception
      'Sicherheitscheck fehlgeschlagen: join_random_chat() fehlt.';
  end if;

  if (length(v_join) - length(replace(v_join, 'random_chat_pair_allowed', '')))
       / length('random_chat_pair_allowed') < 2 then
    raise exception
      'Sicherheitscheck fehlgeschlagen: join_random_chat() nutzt random_chat_pair_allowed zu selten - Reconnect und Uebernehmen der Warteschlange muessen beide geprueft werden.';
  end if;
end;
$$;

commit;
