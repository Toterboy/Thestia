-- 178: Der automatische Funke muss in der Match-Liste ankommen
--
-- BEFUND (04.11.2026): Das Sternchen "Automatisch" auf dem
-- Interessen-Screen waere nie erschienen.
--
-- Grund: Die RPC public.list_my_matches_with_state() baut ihre Zeilen
-- mit jsonb_build_object - und die Spalte auto_match (Migration 177)
-- war dort nicht enthalten. Das Dart-Modell las zwar 'autoMatch',
-- die RPC lieferte es aber nie. Der Hinweis waere stumm geblieben.
--
-- Das ist genau die Sorte Fehler, die beim reinen Lesen des Codes
-- nicht auffaellt: Die Spalte EXISTIERTE, das Feld im Modell EXISTIERTE,
-- nur die Liste lieferte es nicht.
--
-- LOESUNG: Die RPC wird um das Feld erweitert. Sie wird dabei
-- vollstaendig neu definiert (wie in Migration 117) - der Koerper
-- bleibt sonst unveraendert, es kommt genau ein Feld dazu.

BEGIN;

CREATE OR REPLACE FUNCTION public.list_my_matches_with_state()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
             'profile', row_to_json(p.*),
             'kind', coalesce(m.kind, 'spark'),
             -- NEU (Migration 178): der automatische Funke. Das Feld
             -- traegt die Kennzeichnung, damit der Interessen-Screen
             -- einmal nachfragen kann, ob die Person bleiben soll.
             --
             -- Der Name ist 'autoMatch' (camelCase wie die uebrigen
             -- Felder dieser RPC) - das Dart-Modell liest beide
             -- Schreibweisen.
             'autoMatch', coalesce(m.auto_match, false)
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
$function$;

COMMENT ON FUNCTION public.list_my_matches_with_state() IS
  'Die Match-Liste mit Quiz-Stand. Liefert seit Migration 178 auch '
  'autoMatch - die Kennzeichnung des automatischen Funkes.';

COMMIT;
