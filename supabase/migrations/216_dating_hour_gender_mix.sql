-- =============================================================================
-- 216_dating_hour_gender_mix.sql
-- =============================================================================
-- DER BETREIBER (14.11.2026): "Bei Dating Hour irgendwie umsetzen, dass von
-- beiden Geschlechtern welche in dem Event sind, wenn alle Hetero."
--
-- DER BEFUND IST AUCH EIN FEHLER: Die Paarung der Dating Hour hat die
-- Geschlechtspraeterenz NIE beachtet - weder Migration 058 noch 124 noch 161
-- noch 177 noch 190 filtert nach Geschlecht. Ein Nutzer, der im Profil
-- ausdruecklich nur Frauen sucht, konnte mit einem Mann gepaart werden (und
-- umgekehrt). Das widerspricht der Datenschutzerklaerung ("Die
-- Match-Berechnung nutzt deine Angaben, um dir passende Menschen zu zeigen",
-- Abschnitt 2b) und dem Versprechen der App.
--
-- DIE LOESUNG (dieser Block): Die Paarung sucht nur noch Partner, die zur
-- eigenen Wahl passen - und beidseitig (wie beim Alter schon lange):
--
--   * Wer ausdruecklich NUR das eigene Geschlecht waehlt (z. B. ein
--     schwuler Mann, der nur Maenner waehlt), wird nur mit Menschen
--     desselben Geschlechts gepaart. Seine Wahl wird nicht uebergangen.
--   * Wer ausdruecklich NUR das andere Geschlecht waehlt (hetero), wird
--     nur mit Menschen des anderen Geschlechts gepaart. Sind alle im
--     Event hetero, besteht das Event damit aus Maennern UND Frauen -
--     genau das, was der Betreiber wollte.
--   * Wer NICHTS ausgewaehlt hat (der Vorgabe-Stand der Spalte
--     `gender_preferences` ist ein leeres Array), wird ebenfalls mit dem
--     anderen Geschlecht gepaart: das Event ist ein hetero Event, und
--     niemand soll dort jemanden des eigenen Geschlechts gegenueber
--     sitzen, den er nicht gesucht hat.
--   * Wer ausdruecklich "Alle" gewaehlt hat (alle Werte in der Liste),
--     ist offen: er bekommt zuerst jemanden des anderen Geschlechts,
--     sonst jemanden ueberhaupt.
--
-- FINDET SICH NIEMAND PASSENDES, WIRD NICHT GEPAART: Lieber warten als
-- jemanden gegen den eigenen Wunsch bekommen. Die App sagt dem Nutzer,
-- worauf er wartet (siehe lib/screens/dating_hour/).
--
-- "GLEICHGESCHLECHTLICH" heisst hier: die Gruppen 'm' und 'w'. Trans-
-- Nutzerinnen und -Nutzer gehoeren zu ihrer Gruppe (ein trans Mann ist ein
-- Mann), 'divers' und 'eigenes' bilden die eigene Gruppe 'd'.
--
-- UNVERAENDERT BLEIBEN (aus der Bestandsfunktion uebernommen): der
-- Bot-Schutz, die Blockierten-Pruefung, die beidseitige Alterspruefung,
-- die Altersgrenzen der Praeferenz, die Nutzungszeit der Eltern und die
-- Mindestteilnehmerzahl.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Die Geschlechtsgruppe
-- -----------------------------------------------------------------------------

create or replace function public.dh_gender_group(p_gender text)
 returns text
 language sql
 immutable
 set search_path to ''
as $$
  select case p_gender
    when 'male' then 'm'
    when 'male_trans' then 'm'
    when 'female' then 'w'
    when 'female_trans' then 'w'
    when 'diverse' then 'd'
    when 'other' then 'd'
    else null
  end;
$$;

comment on function public.dh_gender_group(text) is
  'v0.10.2: Die Geschlechtsgruppe eines Nutzers (m/w/d). Trans-Nutzer gehoeren zu ihrer Gruppe. Unbekanntes Geschlecht -> null (keine Einschraenkung).';

revoke all on function public.dh_gender_group(text) from public, anon, authenticated;
grant execute on function public.dh_gender_group(text) to service_role;

-- -----------------------------------------------------------------------------
-- 2) Die Gruppen, die ein Nutzer sucht
-- -----------------------------------------------------------------------------

create or replace function public.dh_wanted_groups(p_prefs text[])
 returns text[]
 language plpgsql
 immutable
 set search_path to ''
as $$
declare
  v_groups text[] := array[]::text[];
  v_pref text;
  v_group text;
begin
  if p_prefs is not null then
    foreach v_pref in array p_prefs loop
      v_group := public.dh_gender_group(v_pref);
      if v_group is not null and not (v_group = any(v_groups)) then
        v_groups := array_append(v_groups, v_group);
      end if;
    end loop;
  end if;

  -- Leere Liste: der Nutzer hat nichts gewaehlt. Das ist der
  -- Vorgabe-Stand und wird an der Aufrufstelle als "hetero" behandelt
  -- (das Event ist ein hetero Event). Deshalb gibt diese Funktion hier
  -- eine LEERE Liste zurueck - "leer" bedeutet "nichts gewaehlt".
  return v_groups;
end;
$$;

comment on function public.dh_wanted_groups(text[]) is
  'v0.10.2: Die Geschlechtsgruppen, die ein Nutzer ausdruecklich gewaehlt hat. Eine leere Liste bedeutet: er hat nichts gewaehlt (Vorgabe).';

revoke all on function public.dh_wanted_groups(text[]) from public, anon, authenticated;
grant execute on function public.dh_wanted_groups(text[]) to service_role;

-- -----------------------------------------------------------------------------
-- 3) Passen zwei Menschen zusammen?
-- -----------------------------------------------------------------------------

create or replace function public.dh_gender_compatible(
  a_gender text,
  a_prefs text[],
  b_gender text,
  b_prefs text[]
)
 returns boolean
 language plpgsql
 immutable
 set search_path to ''
as $$
declare
  v_a_group text;
  v_b_group text;
  v_a_groups text[];
  v_b_groups text[];
begin
  v_a_group := public.dh_gender_group(a_gender);
  v_b_group := public.dh_gender_group(b_gender);

  -- Unbekanntes Geschlecht: keine Einschraenkung. Lieber einen
  -- Partner finden als niemanden.
  if v_a_group is null or v_b_group is null then
    return true;
  end if;

  v_a_groups := public.dh_wanted_groups(a_prefs);
  v_b_groups := public.dh_wanted_groups(b_prefs);

  -- AUSDRUECKLICH NUR DAS EIGENE GESCHLECHT: nur damit.
  if array_length(v_a_groups, 1) = 1 and v_a_groups[1] = v_a_group then
    return v_b_group = v_a_group;
  end if;

  -- AUSDRUECKLICH NUR DAS ANDERE GESCHLECHT (hetero): nur damit.
  if array_length(v_a_groups, 1) = 1 then
    return v_b_group <> v_a_group;
  end if;

  -- "ALLE" GEWAEHLT: offen. Die Reihenfolge (das andere Geschlecht
  -- zuerst) entscheidet die Aufrufstelle, nicht die Bedingung.
  if array_length(v_a_groups, 1) > 1 then
    -- Auch die Wahl des anderen muss passen.
    if not (v_b_group = any(v_a_groups)) then
      return false;
    end if;
    if not (v_a_group = any(v_b_groups)) then
      return false;
    end if;
    return true;
  end if;

  -- NICHTS GEWAEHLT (Vorgabe): das Event ist hetero - es wird nur
  -- jemand des anderen Geschlechts gesucht.
  return v_b_group <> v_a_group;
end;
$$;

comment on function public.dh_gender_compatible(text, text[], text, text[]) is
  'v0.10.2: Passen zwei Nutzer fuer die Dating Hour zusammen? Beidseitig (wie beim Alter). Ausdrueckliche Wahl hat Vorrang; nichts gewaehlt bedeutet: hetero Event.';

revoke all on function public.dh_gender_compatible(text, text[], text, text[]) from public, anon, authenticated;
grant execute on function public.dh_gender_compatible(text, text[], text, text[]) to service_role;

-- -----------------------------------------------------------------------------
-- 4) Die Paarungsrunde mit der neuen Regel
-- -----------------------------------------------------------------------------

create or replace function public.match_dating_hour_round(p_event_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $$
declare
  v_event public.dating_hour_event%rowtype;
  v_user record;
  v_pair record;
  v_user_birth date;
  v_user_gender text;
  v_user_prefs text[];
begin
  select * into v_event from public.dating_hour_event where id = p_event_id;
  if not found or v_event.status != 'active' then
    return;
  end if;

  -- Verifikationspflicht (v0.10.0, Migration 161) - NUR fuer den
  -- Aufrufer, der selbst handelt.
  --
  -- BEFUND 04.11.2026: Vorher stand hier ohne Einschraenkung
  --     IF NOT public.verification_granted(auth.uid()) THEN RAISE ...
  -- Der Cron ruft diese Funktion OHNE JWT auf - auth.uid() ist NULL,
  -- verification_granted(NULL) ist false - also hat der Cron bei der
  -- ERSTEN aktiven Veranstaltung 'verification_required' geworfen und
  -- die ganze Runde abgebrochen. Die Dating Hour hat damit seit dem
  -- 03.11.2026 nicht mehr gepaart.
  if auth.uid() is not null
     and not public.verification_granted(auth.uid()) then
    raise exception 'verification_required';
  end if;

  for v_user in
    select p.user_id, p.preferences
    from public.dating_hour_participant p
    where p.event_id = p_event_id
      and p.left_at is null
      and not exists (
        select 1 from public.dating_hour_session s
        where s.event_id = p_event_id
          and s.ended_at is null
          and (s.user_a = p.user_id or s.user_b = p.user_id)
      )
      and public.guardian_usage_time_allows(p.user_id)
    order by random()
  loop
    if not public.verification_granted(v_user.user_id) then
      continue;
    end if;

    select birth_date into v_user_birth
      from public.profiles where user_id = v_user.user_id;

    select gender, gender_preferences
      into v_user_gender, v_user_prefs
      from public.profiles where user_id = v_user.user_id;

    select q.user_id into v_pair
    from public.dating_hour_participant q
    left join public.profiles qp on qp.user_id = q.user_id
    where q.event_id = p_event_id
      and q.left_at is null
      and q.user_id <> v_user.user_id
      and not exists (
        select 1 from public.dating_hour_session s
        where s.event_id = p_event_id
          and s.ended_at is null
          and (s.user_a = q.user_id or s.user_b = q.user_id)
      )
      and not exists (
        select 1 from public.blocked_users b
        where (b.blocker = v_user.user_id and b.blocked = q.user_id)
           or (b.blocker = q.user_id and b.blocked = v_user.user_id)
      )
      and public.age_compatible_bidirectional(v_user_birth, qp.birth_date)
      and (
        v_user.preferences->>'ageMin' is null
        or public.profile_age(qp.birth_date) >= (v_user.preferences->>'ageMin')::int
      )
      and (
        v_user.preferences->>'ageMax' is null
        or public.profile_age(qp.birth_date) <= (v_user.preferences->>'ageMax')::int
      )
      and public.guardian_usage_time_allows(q.user_id)
      -- DIE NEUE REGEL (14.11.2026): die Geschlechtswaehle wird
      -- beachtet - beidseitig. Wer nur das eigene Geschlecht waehlt,
      -- wird nur damit gepaart; wer hetero ist, nur mit dem anderen.
      and public.dh_gender_compatible(
            v_user_gender, v_user_prefs, qp.gender, qp.gender_preferences)
      -- "ALLE" GEWAEHLT: offen - dann bekommt er zuerst jemanden des
      -- anderen Geschlechts (das Event soll gemischt sein).
      order by
        case
          when array_length(public.dh_wanted_groups(v_user_prefs), 1) > 1
            then case
              when public.dh_gender_group(qp.gender)
                   = case public.dh_gender_group(v_user_gender)
                       when 'm' then 'w'
                       when 'w' then 'm'
                       else null
                     end
                then 0
              else 1
            end
          else 0
        end,
        random()
    limit 1;

    if v_pair.user_id is not null then
      insert into public.dating_hour_session(
        event_id, user_a, user_b, expires_at, auto_match_at
      ) values (
        p_event_id,
        least(v_user.user_id, v_pair.user_id),
        greatest(v_user.user_id, v_pair.user_id),
        -- 5 Minuten: bis hierher entscheidet man sich.
        now() + interval '5 minutes',
        -- 10 Minuten: ab hier gibt es den automatischen Funke, wenn
        -- niemand vorher entschieden oder beendet hat.
        now() + interval '10 minutes'
      )
      on conflict (event_id, user_a, user_b) where (ended_at is null) do nothing;
    end if;
  end loop;
end;
$$;

comment on function public.match_dating_hour_round(uuid) is
  'v0.10.2: Die Paarungsrunde der Dating Hour. Beachtet seit heute die Geschlechtswaehle (beidseitig) - ein hetero Event besteht damit aus Maennern UND Frauen.';

revoke all on function public.match_dating_hour_round(uuid) from public, anon;
grant execute on function public.match_dating_hour_round(uuid) to authenticated, service_role;

commit;
