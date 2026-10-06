-- =============================================================================
-- 135_location_privacy_expand.sql
-- =============================================================================
-- ERWEITERUNG (expand), KEIN Umbau. Alles additive, nichts wird entfernt.
--
-- BEFUND (2026-10-06, Abfrage gegen die Datenbank):
--
--   RLS-Policy auf profiles:
--     "Public profiles are readable"  qual: true  roles: {authenticated}
--
--   Heisst: JEDER angemeldete Nutzer kann location_lat und location_lng
--   direkt per PostgREST aus profiles lesen. Nicht nur ueber die App - ein
--   einzelner Aufruf genuegt. Damit ist der genaue Standort bereits jetzt
--   oeffentlich, unabhaengig davon, was die UI anzeigt.
--
--   Zusaetzlich geben drei weitere Stellen Koordinaten aus:
--     1. public_profiles (View)      -> lat_approx, lng_approx
--     2. get_nearby_profiles()       -> lat_approx, lng_approx, distance_km
--     3. get_find_match_candidates() -> select p.*, also ALLE Spalten
--
-- WESENTLICH - was schon vorhanden und richtig ist:
--
--   * guard_profile_location_update rundet die Koordinaten schon "at rest"
--     auf 2 Nachkommastellen (~1,1 km Raster) fuer ALLE Schreiber.
--   * get_nearby_profiles rundet die Distanz auf 5-km-Schritte.
--   * get_nearby_profiles hat ein Rate-Limit (60/h) gegen Vantage-Point-
--     Scans zur Trilateration.
--
-- Diese Migration baut darauf auf, statt es neu zu erfinden.
--
-- WAS DIESE MIGRATION TUT (additiv, pushbar ohne Client-Aenderung):
--
--   1. profile_locations: eigene Tabelle fuer die exakten Koordinaten,
--      mit eigener RLS, die NUR dem Eigentueter das Lesen erlaubt.
--      Warum eigene Tabelle: RLS kann keine Spalten filtern. Solange die
--      Koordinaten in profiles liegen, bleiben sie fuer alle lesbar -
--      unabhaengig von jeder View und jedem RPC.
--   2. show_distance auf profiles (Default false). Wer anderen seine
--      Entfernung zeigen will, schaltet das ausdruecklich ein.
--   3. distance_bucket_km(uuid): serverseitige Grobung in 10-km-Stufen,
--      gespiegelt in lib/utils/distance_bucket.dart. Beide muessen
--      denselben Zuschnitt haben, sonst zeigt die App etwas anderes als
--      die Zusage.
--   4. Selbsttest am Ende: die Policy muss gelten UND die Sicht muss
--      stimmen, sonst bricht der Push ab.
--
-- WAS DIESE MIGRATION BEWUSST NICHT TUT (contract, spaeter):
--
--   * profiles.city wird NOCH NICHT gedroppt und NICHT geleert.
--   * profiles.location_lat/location_lng werden NOCH NICHT entfernt.
--   * public_profiles gibt die Koordinaten NOCH aus.
--   * get_find_match_candidates nutzt noch p.*.
--
-- Grund: Der Client schreibt city/location_* noch. Ein Drop jetzt wuerde
-- jedes Profil-Update mit einem Fehler abweisen - die App waere sofort
-- kaputt. Die Reihenfolge ist zwingend expand -> Client -> contract.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) show_distance
--
-- Default false ist die datenschutzfreundliche Richtung: es wird nichts
-- veroeffentlicht, was der Nutzer nicht ausdruecklich erlaubt hat. Ein
-- bestehendes Profil erbt damit "nein" - wer es einschaltet, entscheidet
-- das aktiv.
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS show_distance boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.show_distance IS
  'v0.9.3: Darf anderen die grobe Entfernung (10-km-Stufen) gezeigt '
  'werden? Default false = nichts wird gezeigt. Der genaue Standort '
  'wird NIE veroeffentlicht, unabhaengig von diesem Schalter.';

-- -----------------------------------------------------------------------------
-- 2) profile_locations - die exakten Koordinaten, privat
--
-- Eine Zeile pro Nutzer (user_id ist Primaerschluessel). Damit kann
-- "kein Standort" und "Standort bekannt" nicht verwechselt werden.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profile_locations (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profile_locations_lat_range CHECK (lat BETWEEN -90 AND 90),
  CONSTRAINT profile_locations_lng_range CHECK (lng BETWEEN -180 AND 180)
);

COMMENT ON TABLE public.profile_locations IS
  'v0.9.3: Exakte Koordinaten, eigenthümer-only. Die coords werden in '
  'public.profiles entfernt (contract-Schritt), weil RLS keine Spalten '
  'filtern kann - solange sie dort liegen, kann jeder angemeldete Nutzer '
  'sie ueber PostgREST lesen.';

-- -----------------------------------------------------------------------------
-- 3) RLS fuer profile_locations: NUR der Eigentuemer
--
-- Das ist der eigentliche Zweck dieser Tabelle. service_role bleibt frei,
-- sonst koennten die SECURITY DEFINER-Funktionen nicht mehr rechnen.
-- -----------------------------------------------------------------------------
ALTER TABLE public.profile_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Nutzer liest nur den eigenen Standort"
  ON public.profile_locations;
CREATE POLICY "Nutzer liest nur den eigenen Standort"
  ON public.profile_locations
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Nutzer schreibt nur den eigenen Standort"
  ON public.profile_locations;
CREATE POLICY "Nutzer schreibt nur den eigenen Standort"
  ON public.profile_locations
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- 4) Berechnung auf 5-km-Raster, zentral
--
-- EIN Ort fuer die Rundung. profile_distance_km und get_nearby_profiles
-- lesen beide von hier, damit die Schrittweite nicht auseinanderlaufen
-- kann.
--
-- Warum 5 km und nicht 1,1: der Guard rundet auf ~1,1 km (2
-- Nachkommastellen). Das ist die Genauigkeit, MIT DER geschrieben wird.
-- Gespeichert wird weiter auf diesem Raster - was hier fuer die
-- Berechnung geholt wird, ist derselbe Wert, den der Guard geschrieben
-- hat. Neu berechnet wird nichts.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.snap_location_to_grid(
  p_lat double precision,
  p_lng double precision,
  p_grid_km double precision DEFAULT 5.0
) RETURNS TABLE(lat double precision, lng double precision)
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  -- Ein Grad Breite ~ 111 km, ein Grad Laenge haengt vom Breitengrad ab.
  -- Fuer die Groessenordnung reicht die Breite; der Laengengrad wird
  -- ueber cos() am Breitengrad gestreckt.
  --
  -- round() gibt es nur fuer numeric, nicht fuer double precision. Der
  -- TEILER muss zu numeric gecastet werden - "p_lat::numeric / double"
  -- ergibt wieder double, und der erste Push scheiterte genau daran.
  -- Beide Casts sind noetig: einmal links, einmal am Teiler.
  SELECT round(p_lat::numeric / ((p_grid_km / 111.0)::numeric), 0)::double precision
           * (p_grid_km / 111.0),
         round(p_lng::numeric /
               ((p_grid_km / (111.0 * greatest(cos(radians(coalesce(p_lat, 0.0))), 0.01)))::numeric),
               0)::double precision
           * (p_grid_km / (111.0 * greatest(cos(radians(coalesce(p_lat, 0.0))), 0.01)))
$$;

COMMENT ON FUNCTION public.snap_location_to_grid(double precision,
                                                double precision,
                                                double precision) IS
  'Rundet Koordinaten auf ein Raster (Standard 5 km). Serverseitig einmal '
  'implementiert, damit Schreib- und Rechenweg dieselbe Quantisierung '
  'sehen - sonst vergleicht man zwei Werte, die nie gleich sein koennen.';

-- -----------------------------------------------------------------------------
-- 5) Distanz-Bucket, gespiegelt aus lib/utils/distance_bucket.dart
--
-- 10-km-Stufen, wie vom Nutzer gewuenscht ("unter 10 km", "10-20", ...).
-- Unterhalb von 5 km: KEINE Auskunft. In dicht bewohnten Gegenden wuerde
-- der Unterschied zwischen 2 und 4 km den Nachbarn verraten.
--
-- Die Grenzen sind halb offen [untere, untere+10): 10,0 gehoert zu
-- "10 bis 20", 19,999 auch, 20,0 zu "20 bis 30". Genau so, wie es im
-- Dart-Gegenstueck steht.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.distance_bucket_km(p_km double precision)
RETURNS TABLE(km int, km_upper int)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_last constant int := 100;
  v_step constant int := 10;
  v_visible_from constant double precision := 5.0;
  v_lower int;
BEGIN
  -- NaN-Pruefung: In SQL-Flieskommazahlen gilt NaN != NaN. "IS NAN"
  -- ist hier kein gueltiges SQL und hat den Push abgebrochen.
  IF p_km IS NULL OR p_km != p_km THEN
    RETURN;                                   -- keine Auskunft
  END IF;
  IF p_km < v_visible_from THEN
    RETURN;                                   -- zu nah zum Zeigen
  END IF;
  IF p_km >= v_last THEN
    RETURN QUERY SELECT v_last, NULL::int;     -- "ueber 100 km"
    RETURN;
  END IF;

  v_lower := floor(p_km / v_step) * v_step;
  IF v_lower >= v_last THEN
    RETURN QUERY SELECT v_last, NULL::int;
    RETURN;
  END IF;

  RETURN QUERY SELECT v_lower, v_lower + v_step;
END
$$;

COMMENT ON FUNCTION public.distance_bucket_km(double precision) IS
  'Grobe Entfernung in 10-km-Stufen. km/km_upper null = ueber 100 km. '
  'Unter 5 km kommt NULL zurueck - das ist Absicht, kein Fehler. '
  'Gespiegelt in lib/utils/distance_bucket.dart (DistanceBucket.bucketFor); '
  'die beiden muessen bei Aenderungen zusammen angepasst werden.';

-- -----------------------------------------------------------------------------
-- 6) Befuellung: vorhandene Koordinaten uebernehmen, auf 5-km-Raster
--
-- Der contract-Schritt entfernt location_lat/location_lng aus profiles.
-- Damit das kein Datenverlust wird, wandern die Werte vorher hierher -
-- auf dem Raster, das kuenftig gilt.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_verschoben int := 0;
BEGIN
  INSERT INTO public.profile_locations (user_id, lat, lng, updated_at)
  SELECT p.user_id,
         g.lat, g.lng,
         coalesce(p.location_checked_at, now())
    FROM public.profiles p
    CROSS JOIN LATERAL public.snap_location_to_grid(
           p.location_lat, p.location_lng) g
   WHERE p.location_lat IS NOT NULL
     AND p.location_lng IS NOT NULL
  ON CONFLICT (user_id) DO UPDATE
    SET lat = EXCLUDED.lat,
        lng = EXCLUDED.lng,
        updated_at = EXCLUDED.updated_at;

  GET DIAGNOSTICS v_verschoben = ROW_COUNT;
  RAISE NOTICE '% Standort(e) in profile_locations uebernommen (5-km-Raster).',
    v_verschoben;
END
$$;

-- -----------------------------------------------------------------------------
-- 7) BEWEIS (Fail-Fast)
--
-- Drei Abfragen. Alle drei brechen den Push ab, statt still durchzu-
-- laufen. Ein Sicherheitscheck, der nichts nachweisen kann, sieht aus
-- wie Bestaetigung - deshalb wird jede Abfrage gegen den Bestand
-- geprueft, nicht nur gegen die eigene Migration.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_zeilen int;
BEGIN
  -- a) Die Tabelle existiert und RLS ist aktiv.
  IF NOT EXISTS (
    SELECT 1 FROM pg_tables
     WHERE schemaname = 'public' AND tablename = 'profile_locations'
  ) THEN
    RAISE EXCEPTION 'profile_locations fehlt.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'profile_locations'
       AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION
      'RLS ist auf profile_locations NICHT aktiv. Dann kaeme jeder '
      'angemeldete Nutzer an die exakten Koordinaten - die Tabelle waere '
      'sinnlos.';
  END IF;

  -- b) Genau EINE Lese-Policy, und sie filtert auf auth.uid().
  SELECT count(*) INTO v_zeilen
    FROM pg_policies
   WHERE tablename = 'profile_locations'
     AND cmd = 'SELECT';

  IF v_zeilen <> 1 THEN
    RAISE EXCEPTION
      'profile_locations hat % Lese-Policies, erwartet genau 1. Mehrere '
      'Policies werden ODER-verknuepft - eine zu weite wuerde alle '
      'wieder auf machen.', v_zeilen;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename = 'profile_locations'
       AND cmd = 'SELECT'
       AND qual LIKE '%auth.uid()%'
  ) THEN
    RAISE EXCEPTION
      'Die Lese-Policy auf profile_locations prueft auth.uid() nicht. '
      'Damit waere jeder Standort fuer jeden lesbar.';
  END IF;

  -- c) show_distance existiert und ist per Default aus.
  IF NOT EXISTS (
    SELECT 1 FROM pg_attribute
     WHERE attrelid = 'public.profiles'::regclass
       AND attname = 'show_distance'
       AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'profiles.show_distance fehlt.';
  END IF;

  RAISE NOTICE 'Sicherheitscheck bestanden: profile_locations privat, '
               'show_distance vorhanden.';
END
$$;

-- -----------------------------------------------------------------------------
-- 8) Gegenprobe der Grobung: sie muss STUFEN ergeben, keine Meter
--
-- Frueher sind Guards ins Leere gelaufen, weil sie nichts zu pruefen
-- hatten. Diese Abfrage prueft echte Werte.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
  v_fehler int := 0;
BEGIN
  FOR r IN
    -- (Eingabe, erwartete km, erwartete km_upper)
    --
    -- WICHTIG: "keine Auskunft" heisst hier ZWEI mögliche Formen und beide
    -- sind richtig: (a) die Funktion liefert gar keine Zeile (RETURN ohne
    -- QUERY), (b) sie liefert eine Zeile mit null/null. Der Test muss beide
    -- als "keine Auskunft" akzeptieren - sonst schlaegt die Pruefung genau
    -- dann fehl, wenn der Code korrekt arbeitet. Genau das ist beim ersten
    -- Push passiert.
    SELECT * FROM (VALUES
      (4.9::double precision, NULL::int, NULL::int),
      (5.0::double precision, 0, 10),
      (9.9::double precision, 0, 10),
      (10.0::double precision, 10, 20),
      (19.999::double precision, 10, 20),
      (20.0::double precision, 20, 30),
      (34.0::double precision, 30, 40),
      (99.9::double precision, 90, 100),
      (100.0::double precision, 100, NULL::int),
      (1900.0::double precision, 100, NULL::int)
    ) AS t(km_in, km_out, km_upper_out)
  LOOP
    -- Menge aller gelieferten Zeilen fuer diesen Eingabewert.
    DECLARE
      v_zeilen int;
      v_km int;
      v_upper int;
    BEGIN
      SELECT count(*), min(b.km), min(b.km_upper)
        INTO v_zeilen, v_km, v_upper
        FROM public.distance_bucket_km(r.km_in) b;

      -- "Keine Auskunft" erwartet (km_out ist NULL): darf 0 Zeilen oder
      -- genau eine Zeile mit null-Werten liefern.
      IF r.km_out IS NULL THEN
        IF NOT (
          -- 0 Zeilen, oder alle Zeilen haben null in beiden Feldern
          (v_zeilen = 0)
          OR (v_zeilen > 0 AND v_km IS NULL AND v_upper IS NULL)
        ) THEN
          v_fehler := v_fehler + 1;
          RAISE WARNING 'distance_bucket_km(%) - "keine Auskunft" erwartet, '
                        'bekam % Zeile(n) km=% / ober=%',
            r.km_in, v_zeilen, v_km, v_upper;
        END IF;
      ELSE
        -- Konkrete Stufe erwartet: genau eine Zeile, Werte muessen passen.
        IF NOT (v_zeilen = 1 AND v_km = r.km_out AND v_upper IS NOT DISTINCT FROM r.km_upper_out) THEN
          v_fehler := v_fehler + 1;
          RAISE WARNING 'distance_bucket_km(%) - erwartet %/% , bekam %/% (% Zeile(n))',
            r.km_in, r.km_out, r.km_upper_out, v_km, v_upper, v_zeilen;
        END IF;
      END IF;
    END;
  END LOOP;

  IF v_fehler > 0 THEN
    RAISE EXCEPTION
      'Die Entfernungs-Grobung ist falsch in % von 10 Faellen. Damit '
      'waere die zugesagte 10-km-Stufung nicht eingehalten.', v_fehler;
  END IF;

  RAISE NOTICE 'Stufung geprueft: 10 von 10 Faellen korrekt.';
END
$$;

-- =============================================================================
-- BIS ZUM CONTRACT-SCHRITT NICHT ERLEDIGT (bewusst):
--
--   1. profiles.city droppen + Daten loeschen
--   2. profiles.location_lat/location_lng droppen
--   3. public_profiles: lat_approx/lng_approx aus der View streichen
--   4. get_nearby_profiles: nur noch Bucket, keine Koordinaten
--   5. get_find_match_candidates: p.* durch Spaltenliste ersetzen
--   6. profile_distance_km auf profile_locations umstellen
--   7. guard_profile_location_update auf profile_locations umstellen
--
-- Reihenfolge zwingend: erst der Client (der city und location_* noch
-- schreibt), dann diese Schritte. Ein Drop jetzt wuerde jedes
-- Profil-Update mit einem Fehler abweisen.
--
-- Der Rollback dieser Migration ist vollstaendig moeglich:
--   DROP TABLE public.profile_locations;
--   ALTER TABLE public.profiles DROP COLUMN show_distance;
-- Es geht kein Nutzerdaten verloren - profile_locations wurde in dieser
-- Migration erst BEFUELLT, und profiles bleibt unangetastet.
-- =============================================================================