-- 101_respark_grace.sql
--
-- Fix "Re-Funke geht nicht": Die 72-Stunden-Auto-Kuehlung (Client,
-- Interessen-Tab) kuehlte einen frisch re-entfachten Funken beim
-- naechsten Listen-Laden SOFORT wieder ein - der Funke hatte keine
-- neuen Nachrichten, also war das Auto-Kuehl-Kriterium erneut erfuellt.
-- Der Re-Funke "griff" dadurch nie sichtbar.
--
-- Fix: respark_match protokolliert ab jetzt einen Zeitstempel
-- (resparked_at). Die clientseitige Auto-Kuehlung behandelt ihn wie die
-- letzte Aktivitaet: Ein re-entfachter Funke bleibt mindestens 72 h
-- aktiv, auch ohne neue Nachricht. Der Zeitstempel steht serverseitig
-- und gilt damit auf BEIDEN Geraeten (im Gegensatz zu rein lokalen
-- Merkern).
--
-- Zusätzlich (Betreiber-Anforderung "Chat wird beim Erschließen nicht
-- gelöscht"): gekühlte Funken bleiben mit Chat erhalten - dazu keine
-- Schema-Änderung nötig (status 'cooled' bleibt gelistet und öffnbar),
-- der Zeitstempel verhindert nur das verschnellte Wegkühlen.

ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS resparked_at timestamptz;

COMMENT ON COLUMN public.matches.resparked_at IS
  'Letzter Re-Funke (Grace-Zeitstempel: 72 h keine Auto-Kuehlung danach).';

CREATE OR REPLACE FUNCTION public.respark_match(p_match_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
begin
  update public.matches
     set status = 'active',
         resparked_at = now()
   where id = p_match_id
     and status = 'cooled'
     and (user_one_id = auth.uid() or user_two_id = auth.uid());
  if not found then
    raise exception 'Funke nicht gefunden oder nicht gekuehlt.'
      USING ERRCODE = 'P0002';
  end if;
end;
$$;

GRANT EXECUTE ON FUNCTION public.respark_match(bigint) TO authenticated;

-- Liste um den Re-Funke-Zeitstempel erweitern (Client-Auto-Kuehlung).
CREATE OR REPLACE FUNCTION public.list_my_matches_with_state()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
             'passedAt', s.passed_at,
             'lastAttemptAt', s.last_attempt_at,
             'distanceKm', public.profile_distance_km(
               case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end),
             'profile', row_to_json(p.*)
           ) order by
             (m.status = 'active') desc,          -- aktive zuerst
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

GRANT EXECUTE ON FUNCTION public.list_my_matches_with_state() TO authenticated;
