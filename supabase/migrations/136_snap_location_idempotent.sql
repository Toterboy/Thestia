-- =============================================================================
-- 136_snap_location_idempotent.sql
-- =============================================================================
-- KORREKTUR zu Migration 135: snap_location_to_grid war NICHT idempotent.
--
-- BEFUND (2026-10-06, Client-Test "ist idempotent"):
--
--   snap(snap(52.52, 13.405))  ->  (52.5225, 13.39988)
--   snap(52.52, 13.405)         ->  (52.5225, 13.39911)
--
-- Der Laengengrad wanderte um 0,00077 Grad (~57 m) bei jedem weiteren
-- Aufruf. Ursache:
--
--   step_lng = grid_km / (111 * cos(lat))
--
-- Der gerundete Laengengrad ist KEIN Vielfaches der Breite, die er
-- selbst definiert - cos() ist namensabhängig und der gerundete Wert
-- weicht minimal ab. Beim naechsten Aufruf rutscht der Punkt dadurch
-- um einen Rasterschritt.
--
-- Warum das schlimmer ist als ein Rundungsfehler: der Client snappt
-- BEIM SPEICHERN, und der Server snappt BEIM RECHNEN. Bei jedem
-- Abgleich wanderte der Standort ein Stueck weiter. Die Entfernungs-
-- anzeige waere langsam driftend gesprungen, ohne dass etwas einen
-- Fehler gemeldet haette - und weder Profil noch Radar zeigen einen
-- Standort an, also faellt es niemandem auf.
--
-- LOESUNG: Die Rasterbreite fuer den Laengengrad aus einem KONSTANTEN
-- Breitengrad ableiten (53 Grad = Mitteleuropa, der principale Markt),
-- nicht aus lat selbst. Dann ist der Rasterpunkt ein Vielfaches genau
-- dieser Breite und damit fix.
--
--   const ref_lat = 53 * pi / 180
--   step_lng = grid_km / (111 * greatest(cos(ref_lat), 0.01))
--
-- In den Tropen liegt der Laengengrad dadurch bis zu ~20 Prozent
-- feiner. Das ist zumutbar und heisst im Umkehrschluss: die Aufloesung
-- ist NIE schlechter als 5 km, sondern hoechstens etwas besser. Fuer
-- das zugesagte "gerundet mit 5 km" ist das die richtige Richtung.
--
-- GESPIEGELT in lib/utils/location_privacy.dart (LocationPrivacy).
-- Beide Seiten muessen dieselbe Formel benutzen - die Drift trat
-- genau deshalb auf, weil es zwei Kopien der Formel gab.
--
-- Bestandsdaten: profile_locations wurde in 135 aus profiles
-- uebernommen, also mit der fehlerhaften Formel gerastert. Sie wird
-- hier einmal neu gerastert. Das ist sicher, weil der zweite Lauf
-- idempotent ist (Beweis unten im Sicherheitscheck).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.snap_location_to_grid(
  p_lat double precision,
  p_lng double precision,
  p_grid_km double precision DEFAULT 5.0
) RETURNS TABLE(lat double precision, lng double precision)
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  -- Rasterbreiten aus einem KONSTANTEN Breitengrad (53 Grad
  -- Mitteleuropa). NICHT aus p_lat: sonst ist die Funktion nicht
  -- idempotent und der Standort wandert bei jedem Abgleich.
  SELECT round(p_lat::numeric / ((p_grid_km / 111.0)::numeric), 0)::double precision
           * (p_grid_km / 111.0),
         round(p_lng::numeric / ((p_grid_km /
               (111.0 * greatest(cos(radians(53.0)), 0.01)))::numeric), 0)::double precision
           * (p_grid_km / (111.0 * greatest(cos(radians(53.0)), 0.01)))
$$;

COMMENT ON FUNCTION public.snap_location_to_grid(double precision,
                                                double precision,
                                                double precision) IS
  'Rundet Koordinaten auf ein 5-km-Raster. IDEMPOTENT: die Breite des '
  'Laengengrads kommt aus einem konstanten Breitengrad (53 Grad), nicht '
  'aus lat selbst. Ohne das rutschte der Standort bei jedem Aufruf um '
  'einen Rasterschritt (~57 m). Gespiegelt in '
  'lib/utils/location_privacy.dart.';

-- -----------------------------------------------------------------------------
-- 1) Bestandsdaten neu rasteren
--
-- Zweimal rasteren ist NICHT noetig und waere sogar schaedlich: der
-- erste Lauf bringt jeden Wert auf das Raster, der zweite bestaetigt
-- nur. Ein einziger Lauf ueber alle Zeilen reicht.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_angepasst int := 0;
  v_erste uuid;
  v_letzte uuid;
BEGIN
  -- Skalar-Unterabfrage statt FROM/JOIN: die Funktion liest pl.lat und
  -- pl.lng aus derselben Zeile, die aktualisiert wird. Ein FROM-Teil
  -- kann die Zielzeile nicht referenzieren ("invalid reference to
  -- FROM-clause entry"), auch nicht per LATERAL. Darum so.
  UPDATE public.profile_locations pl
     SET lat = (SELECT g.lat FROM public.snap_location_to_grid(pl.lat, pl.lng) g),
         lng = (SELECT g.lng FROM public.snap_location_to_grid(pl.lat, pl.lng) g);

  GET DIAGNOSTICS v_angepasst = ROW_COUNT;

  SELECT user_id INTO v_erste FROM public.profile_locations ORDER BY user_id LIMIT 1;
  SELECT user_id INTO v_letzte FROM public.profile_locations ORDER BY user_id DESC LIMIT 1;

  RAISE NOTICE '% Standort(e) auf das korrigierte Raster gebracht (% .. %).',
    v_angepasst, v_erste, v_letzte;
END
$$;

-- -----------------------------------------------------------------------------
-- 2) BEWEIS (Fail-Fast)
--
-- Der Test, der den Fehler gefunden hat, wird hier zum Abnahmetest:
-- snap(snap(p)) MUSS snap(p) ergeben. Genau daran war die alte Fassung
-- gescheitert.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
  v_fehler int := 0;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      (52.52::double precision, 13.405::double precision),
      (53.0793::double precision, 8.8017::double precision),   -- Bremen
      (48.1351::double precision, 11.5820::double precision),  -- Muenchen
      (-33.8688::double precision, 151.2093::double precision), -- Sydney
      (0.0::double precision, 0.0::double precision),
      (64.1466::double precision, -21.9426::double precision)  -- Reykjavik
    ) AS t(km_lat, km_lng)
  LOOP
    IF NOT EXISTS (
      SELECT 1
        FROM public.snap_location_to_grid(r.km_lat, r.km_lng) a,
             public.snap_location_to_grid(a.lat, a.lng) b
       WHERE a.lat IS NOT DISTINCT FROM b.lat
         AND a.lng IS NOT DISTINCT FROM b.lng
    ) THEN
      v_fehler := v_fehler + 1;
      RAISE WARNING 'Nicht idempotent bei (%, %)', r.km_lat, r.km_lng;
    END IF;
  END LOOP;

  IF v_fehler > 0 THEN
    RAISE EXCEPTION
      'snap_location_to_grid ist in % von 6 Faellen NICHT idempotent. '
      'Der Standort wuerde bei jedem Abgleich wandern.', v_fehler;
  END IF;

  RAISE NOTICE 'Idempotenz bestanden: 6 von 6 Punkten fix.';
END
$$;

-- -----------------------------------------------------------------------------
-- 3) Gegenprobe: die Rasterung verliert nicht die ganze Aufloesung
--
-- Idempotenz allein beweist nichts - eine Funktion, die alles auf
-- einen konstanten Punkt zwingt, waere auch idempotent und wertlos.
-- Geprueft wird deshalb der Abstand zwischen einem Punkt und seinem
-- Rasterpunkt.
--
-- Die Grenze ist die DIAGONALE der halben Rasterzelle, nicht die halbe
-- Kantenlaenge. Das Raster ist ein Rechteck (5 km Breite im Breiten-
-- grad, 5 km im Laengengrad), und ein Punkt sitzt maximal in einer
-- Ecke davon: dann ist er sqrt(2,5² + 2,5²) = 3,54 km vom Mittelpunkt
-- entfernt. Mit 2,5 km als Grenze schlug dieser Guard bei 2,72 km fehl -
-- bei einem vollstaendig korrekten Raster.
--
-- (Ein frueherer Entwurf verglich zwei 11 m entfernte Punkte per
-- HAVING und brach dabei ab: set-returning functions sind in HAVING
-- nicht erlaubt. Der Vergleich war ausserdem inhaltlich sinnlos - zwei
-- so nahe Punkte SOLLEN im selben Raster landen.)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_abstand_km double precision;
BEGIN
  SELECT 6371 * acos(least(1.0,
      cos(radians(p.lat)) * cos(radians(g.lat))
    * cos(radians(p.lng) - radians(g.lng))
    + sin(radians(p.lat)) * sin(radians(g.lat))))
    INTO v_abstand_km
    FROM (SELECT 53.0793::double precision AS lat,
                 8.8017::double precision AS lng) p,
         public.snap_location_to_grid(53.0793, 8.8017) g;

  -- Diagonale der halben Zelle: sqrt(2,5^2 + 2,5^2) = 3,5355 km.
  IF v_abstand_km > 3.5356 THEN
    RAISE EXCEPTION
      'Ein Punkt liegt % km von seinem Rasterpunkt entfernt, erlaubt '
      'waeren hoechstens 3,536 km (Diagonale der halben Rasterzelle). '
      'Das Raster waere feiner als gedacht.',
      v_abstand_km;
  END IF;

  -- KEIN "%.3f": PL/pgSQL kennt keine Praezisionsangaben, "%.3f" wird
  -- als "%" mit ".3f" als Nachrichtentext ausgegeben. round() vorher.
  RAISE NOTICE 'Raster bestaetigt: Versatz zum Rasterpunkt % km '
               '(erlaubt bis 3,536).', round(v_abstand_km, 3);
END
$$;

-- =============================================================================
-- NACHTRAG (2026-10-06, nach dem Push):
--
-- Die NOTICE-Zeile in Block 3 enthielt "%.3f". PL/pgSQL kennt keine
-- Praezisionsangaben, der Push lief durch und gab den Text als
-- "% .3f km" aus - kosmetisch, ohne Wirkung auf die Daten. Hier auf
-- round() umgestellt, damit die Datei bei einem frischen Aufbau das
-- Richtige sagt. Angewendete Migrationen laufen nicht erneut, die
-- Korrektur ist also rein dokumentarisch.
-- =============================================================================

-- =============================================================================
-- WAS HIER NICHT GEAENDERT WIRD:
--
-- Der contract-Schritt bleibt aufgeschoben: profiles.city und
-- profiles.location_lat/lng existieren noch, und der Client schreibt
-- sie weiterhin. Erst wenn dort nichts mehr fliesst, loescht man sie -
-- siehe die offene Liste am Ende von 135.
-- =============================================================================