-- Migration 109: profile_distance_km fail-open (Fix "Funken ploetzlich alle weg")
--
-- ROOT CAUSE (Build 22, Beta-Test): profile_distance_km warf bei
-- Rate-Limit (5/h pro Paar) eine EXCEPTION. Weil die Funktion von
-- list_my_matches_with_state (Funken-Liste), get_find_match_candidates
-- und den Likes-Listen fuer JEDEN Eintrag aufgerufen wird und der
-- Home-Screen die Liste staendig refreshed, war das Limit in Sekunden
-- ausgereizt -> JEDER weitere Aufruf lief 400 -> die GESAMTE
-- Funken-/Likes-/Kandidaten-Liste blieb leer ("Funken ploetzlich alle
-- weg, nachdem man mit einer Person im Chat war" - Korrelation war
-- Zufall, das Limit war einfach verbraucht).
--
-- FIX:
--  1. Fail-open: Bei erschöpftem Limit NULL zurueckgeben (Distanz
--     fehlt nur in dieser Ausgabe - Liste laedt normal weiter). Der
--     Trilaterations-Schutz bleibt: keine Distanz-Ausgabe statt
--     Absturz des Screens.
--  2. Limit 5/h -> 60/h pro Paar: Ein echter Nutzer oeffnet seine
--     Funken-Liste/Homescreen oefter als 5x pro Stunde (Badge-Polling).
--     60/h verhindert Trilateration weiterhin (selbes Ziel laesst
--     sich damit pro Stunde nur 60x vermessen, bei 5km-Raster
--     weiterhin irrelevant).

create or replace function public.profile_distance_km(p_other uuid)
returns double precision
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_distance float8;
begin
  if auth.uid() is null or p_other is null or p_other = auth.uid() then
    return null;
  end if;

  -- Trilaterations-Schutz: wiederholte Distanz-Abfragen gegen dasselbe
  -- Opfer (bei eigenen Positionswechseln) werden gedrosselt.
  -- FAIL-OPEN-Fix: statt EXCEPTION (die frueher die ganze Liste
  -- verweigerte) nur NULL liefern - die Distanzanzeige entfaellt
  -- temporaer, der Rest der Liste funktioniert weiter.
  if not public.consume_rate_limit(
       'dist_pair:' || auth.uid()::text || ':' || p_other::text, 60, 3600) then
    return null;
  end if;

  select (round((6371 * acos(least(1.0,
             cos(radians(me.location_lat)) * cos(radians(o.location_lat))
             * cos(radians(o.location_lng) - radians(me.location_lng))
             + sin(radians(me.location_lat)) * sin(radians(o.location_lat))
           ))) / 5.0) * 5)::float8
    into v_distance
    from public.profiles me
    join public.profiles o on o.user_id = p_other
   where me.user_id = auth.uid()
     and me.location_lat is not null and me.location_lng is not null
     and o.location_lat is not null and o.location_lng is not null;

  return v_distance;
end;
$function$;

grant execute on function public.profile_distance_km(uuid) to authenticated;
