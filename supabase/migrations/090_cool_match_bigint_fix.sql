-- 090_cool_match_bigint_fix.sql
--
-- v0.9.1-Feedback: "Funke kann nicht gekühlt werden."
--
-- Ursache: public.matches.id ist BIGINT (007_likes_and_matches.sql), aber
-- 074 definierte cool_match/respark_match/end_match/hide_match mit
-- p_match_id UUID. Der Client sendet INTs (find_your_match_service,
-- interessen_screen, chat_detail) -> PostgREST fand cool_match(bigint)
-- nie ("function does not exist"), Kühlen/Re-Funke/Beenden/Ausblenden
-- schlugen IMMER fehl. Keine spätere Migration korrigierte das.
--
-- Fix: UUID-Varianten droppen, BIGINT-Varianten mit identischer Logik
-- anlegen (Teilnehmer-Check + Status-Übergänge unverändert).

DROP FUNCTION IF EXISTS public.cool_match(uuid);
DROP FUNCTION IF EXISTS public.respark_match(uuid);
DROP FUNCTION IF EXISTS public.end_match(uuid);
DROP FUNCTION IF EXISTS public.hide_match(uuid);

-- Funke "ruhig enden lassen": active -> cooled.
create or replace function public.cool_match(p_match_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.matches
     set status = 'cooled'
   where id = p_match_id
     and status = 'active'
     and (user_one_id = auth.uid() or user_two_id = auth.uid());
  if not found then
    raise exception 'Funke nicht gefunden oder bereits gekuehlt/endet.'
      USING ERRCODE = 'P0002';
  end if;
end;
$$;

-- Re-Funke ohne Druck: cooled -> active.
create or replace function public.respark_match(p_match_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.matches
     set status = 'active'
   where id = p_match_id
     and status = 'cooled'
     and (user_one_id = auth.uid() or user_two_id = auth.uid());
  if not found then
    raise exception 'Funke nicht gefunden oder nicht gekuehlt.'
      USING ERRCODE = 'P0002';
  end if;
end;
$$;

-- Endgueltig beenden (beide Seiten): active/cooled -> ended.
create or replace function public.end_match(p_match_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.matches
     set status = 'ended'
   where id = p_match_id
     and (user_one_id = auth.uid() or user_two_id = auth.uid());
  if not found then
    raise exception 'Funke nicht gefunden.' USING ERRCODE = 'P0002';
  end if;
end;
$$;

-- "Chats verwalten": Chat nur fuer mich aus der Liste nehmen.
create or replace function public.hide_match(p_match_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.matches
     set hidden_by = array_append(hidden_by, auth.uid())
   where id = p_match_id
     and (user_one_id = auth.uid() or user_two_id = auth.uid())
     and not (auth.uid() = any(hidden_by));
  if not found then
    raise exception 'Funke nicht gefunden.' USING ERRCODE = 'P0002';
  end if;
end;
$$;

grant execute on function public.cool_match(bigint) to authenticated;
grant execute on function public.respark_match(bigint) to authenticated;
grant execute on function public.end_match(bigint) to authenticated;
grant execute on function public.hide_match(bigint) to authenticated;
