-- =============================================================================
-- 137_location_write_guard.sql
-- =============================================================================
-- BEFUND (v0.9.3, Review des expand-Schritts):
--
--   Migration 135 hat profile_locations angelegt und die RLS auf "nur der
--   Eigentuemer" gesetzt. Die RLS beantwortet aber nur die Frage "WEM
--   gehoeren die Zeilen" - NICHT "in welcher Genauigkeit darf der
--   Eigentuemer schreiben".
--
--   In profile_locations gibt es KEINEN Trigger, der die Koordinaten
--   rastert. Der einzige Aufruf von snap_location_to_grid() in 135 war der
--   Backfill aus profiles.
--
--   Damit haengt die zugesagte Aufloesung ("5-km-Raster") allein am
--   Client. Das ist fuer eine Privatsphaere-Zusage zu duenn: ein
--   manipulierter Client, ein Debug-Build mit gesetztem Breakpoint oder
--   ein Aufruf von PostgREST per Hand koennte ungerundete Koordinaten in
--   die Tabelle schreiben - und die Tabelle ist genau der Ort, an dem die
--   exakten Werte liegen sollen.
--
--   Der Aufrufer ist hier ausgerechnet der Nutzer selbst. Die RLS gibt
--   ihm genau diese eine Zeile frei, also auch das Schreibrecht fuer
--   ungerundete Werte.
--
-- LOESUNG: BEFORE INSERT OR UPDATE auf profile_locations ueberschreibt
-- lat/lng mit dem Ergebnis von snap_location_to_grid(). Ein Trigger
-- laeuft fuer JEDE Rolle, auch fuer service_role - die Rasterung ist
-- damit nicht mehr die Sache des Clients, sondern eine Eigenschaft der
-- Tabelle.
--
--   Der Client snappt trotzdem schon vor dem Senden (LocationPrivacy).
--   Das ist kein Widerspruch: snap_location_to_grid() ist nach der
--   Korrektur in 136 idempotent, ein zweiter Lauf aendert also nichts.
--   Der Client snappt fuer die Sofort-Anzeige, der Server ist die
--   Zusage.
--
--   Der Guard laesst sich nicht durch "RLS ist an" umgehen - deshalb
--   bewusst Trigger statt einer SECURITY DEFINER-RPC: die Tabelle ist
--   auch weiterhin direkt beschreibbar, nur eben immer gerastert.
--
-- REIHENFOLGE: Der contract-Schritt (profiles.city/location_lat/location_lng
-- droppen, public_profiles und die RPCs auf profile_locations umstellen)
-- bleibt aufgeschoben und ist als 138 vorgesehen. profiles wird weiterhin
-- befuellt, weil der Client alte Spalten noch mit altem Inhalt liefert;
-- dort schreibt weiterhin der Guard auf profiles (Migration 059/125).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Guard-Funktion
--
-- SECURITY INVOKER (Default): sie braucht keine Rechte, sie rechnet nur.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_profile_location_snap()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_snapped public.snap_location_to_grid%ROWTYPE;
BEGIN
  -- Aus ungueltigen Werten darf keine Zeile entstehen. Ohne diese
  -- Pruefung wuerde snap_location_to_grid() auf NULL rechnen und die
  -- Zeile waere danach an den NOT NULL-Constraints gescheitert - mit
  -- einer Fehlermeldung, die nichts ueber die Ursache sagt.
  IF NEW.lat IS NULL OR NEW.lng IS NULL THEN
    RAISE EXCEPTION 'Standort ohne Koordinaten ist nicht erlaubt.'
      USING ERRCODE = '22004';
  END IF;

  IF NEW.lat < -90 OR NEW.lat > 90
     OR NEW.lng < -180 OR NEW.lng > 180 THEN
    RAISE EXCEPTION 'Koordinaten ausserhalb des gueltigen Bereichs: lat=%, lng=%',
      NEW.lat, NEW.lng USING ERRCODE = '22023';
  END IF;

  SELECT s.lat, s.lng INTO v_snapped
  FROM public.snap_location_to_grid(NEW.lat, NEW.lng) AS s;

  NEW.lat := v_snapped.lat;
  NEW.lng := v_snapped.lng;

  -- updated_at nicht nur per Default setzen: bei einem UPDATE soll man
  -- sehen, wann zuletzt gespeichert wurde, auch wenn der Client die
  -- Spalte nicht mitschickt.
  IF TG_OP = 'UPDATE' THEN
    NEW.updated_at := now();
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_profile_location_snap() IS
  'v0.9.3: Setzt lat/lng auf das 5-km-Raster, bevor die Zeile gespeichert '
  'wird. Macht die Aufloesungszusage unabhaengig vom Client.';

-- -----------------------------------------------------------------------------
-- 2) Trigger anlegen (idempotent)
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_profile_location_snap
  ON public.profile_locations;

CREATE TRIGGER trg_profile_location_snap
  BEFORE INSERT OR UPDATE ON public.profile_locations
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_profile_location_snap();

COMMENT ON TRIGGER trg_profile_location_snap ON public.profile_locations IS
  'v0.9.3: Erzwingt das 5-km-Raster fuer jeden Schreibzugriff.';

-- -----------------------------------------------------------------------------
-- 3) Der Backfill aus 135 ist bereits gerastert - die neuen Zeilen der
--    Migration 136 ebenfalls. Ein erneuter Lauf ist unschaedlich, weil
--    snap_location_to_grid() nach 136 idempotent ist. Deshalb wird hier
--    bewusst KEIN Backfill gemacht: die Formel hat sich zwischen 135 und
--    136 geaendert, und 136 hat die Bestandsdaten bereits neu gerastert.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 4) Selbsttest - die Migration schlaegt fehl, wenn die Zusage nicht gilt
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_trigger_count integer;
  v_fn_count integer;
  v_first record;
  v_second record;
BEGIN
  -- a) Genau EIN Snap-Trigger auf der Tabelle.
  SELECT count(*) INTO v_trigger_count
  FROM pg_trigger
  WHERE tgrelid = 'public.profile_locations'::regclass
    AND NOT tgisinternal;

  IF v_trigger_count <> 1 THEN
    RAISE EXCEPTION
      'profile_locations hat % Trigger, erwartet genau 1.', v_trigger_count;
  END IF;

  -- b) Genau EINE Guard-Funktion, und sie nutzt das geschuetzte
  --    search_path-Muster der anderen Funktionen aus 133.
  SELECT count(*) INTO v_fn_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'guard_profile_location_snap'
    AND p.proconfig @> ARRAY['search_path='];

  IF v_fn_count <> 1 THEN
    RAISE EXCEPTION
      'guard_profile_location_snap() fehlt oder hat kein search_path=';
  END IF;

  -- c) Die Rasterung ist idempotent. Ohne diese Eigenschaft wuerde der
  --    Guard bei jedem Speichern den Punkt verschieben (Befund aus 136).
  SELECT * INTO v_first FROM public.snap_location_to_grid(52.52, 13.405);
  SELECT * INTO v_second
  FROM public.snap_location_to_grid(v_first.lat, v_first.lng);

  IF v_first.lat <> v_second.lat OR v_first.lng <> v_second.lng THEN
    RAISE EXCEPTION
      'snap_location_to_grid() ist nicht idempotent: % / % vs % / %',
      v_first.lat, v_first.lng, v_second.lat, v_second.lng;
  END IF;

  RAISE NOTICE
    'Sicherheitscheck bestanden: profile_locations rastet jeden Schreibzugriff.';
END;
$$;

-- -----------------------------------------------------------------------------
-- 5) Was bewusst NOCH nicht passiert
--
--    * profiles.city wird noch nicht geleert oder gedroppt.
--    * profiles.location_lat/location_lng existieren noch und sind ueber
--      PostgREST fuer jeden angemeldeten Nutzer lesbar (RLS auf profiles
--      ist mit qual: true sehr weit). Das ist die LETZTE und die
--      eigentliche Luecke - sie schliesst erst 138 (contract), und erst
--      wenn kein Client mehr in diese Spalten schreibt.
--
--    Rollback dieses Schrittes:
--      DROP TRIGGER trg_profile_location_snap ON public.profile_locations;
--      DROP FUNCTION public.guard_profile_location_snap();
--    Es gehen keine Nutzerdaten verloren.
-- =============================================================================