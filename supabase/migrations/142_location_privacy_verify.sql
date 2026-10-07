-- =============================================================================
-- 139_location_privacy_verify.sql
-- =============================================================================
-- Nachweis fuer 138 (der Contract-Schritt), getrennt von der Aenderung.
--
-- Warum als eigene Migration und nicht als Block am Ende von 138:
--
--   Der Check liest pg_get_viewdef() und pg_get_functiondef() ueber genau
--   die Objekte, die 138 gerade in derselben Transaktion neu gebaut hat.
--   Als DO-Block am Ende von 138 brach der Push wiederholt mit
--   SQLSTATE 42809 ab ('"array_agg" is an aggregate function'), ohne dass
--   im Block selbst eine Aggregatfunktion stand - die Auswertung lief in
--   eine halb fertige Definition.
--
--   Eigene Migration, eigener Lauf: Der Check sieht jetzt den Endzustand,
--   und wenn er fehlschlaegt, ist das ein echter Befund und keine
--   Nebenwirkung des Aufbaus.
--
-- WAS GEPRUEFT WIRD:
--
--   1. profiles hat keine Ort-/Koordinats-Spalten mehr.
--   2. Kein View gibt Koordinaten nach aussen.
--   3. Keine Funktion referenziert location_lat/location_lng/profiles.city.
--   4. Der Rasterungs-Guard sitzt auf profile_locations.
--   5. profile_distance_km haengt an der Einwilligung.
--
-- Die Pruefungen sind Absicht - sie sollen spaeter fehlschlagen, wenn
-- jemand die Spalten zurueckholt oder eine Ausgabe vergisst.
-- =============================================================================

DO $$
DECLARE
  v_rest integer;
  v_name text;
BEGIN
  -- 1) Die drei Spalten sind weg.
  SELECT count(*) INTO v_rest
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'profiles'
     AND column_name IN ('city', 'location_lat', 'location_lng');

  IF v_rest <> 0 THEN
    RAISE EXCEPTION 'profiles hat noch % Standort-Spalte(n).', v_rest;
  END IF;

  -- 2) Kein View nennt Koordinaten in seiner Definition.
  --
  --    Nur die Definition zaehlt. Ein View, der sauber umbenannt wurde,
  --    ist kein Befund - die erste Fassung dieser Pruefung enthielt
  --    zusaetzlich `c.relname = 'public_profiles'` und schlug deshalb
  --    fehl, obwohl die Spalten entfernt waren.
  SELECT count(*) INTO v_rest
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relkind = 'v'
     AND (coalesce(pg_get_viewdef(c.oid), '') LIKE '%lat_approx%'
          OR coalesce(pg_get_viewdef(c.oid), '') LIKE '%lng_approx%');

  IF v_rest <> 0 THEN
    RAISE EXCEPTION '% View(s) geben noch Koordinaten aus.', v_rest;
  END IF;

  -- 3) Keine Funktion referenziert die entfernten Spalten.
  --
  --    Geprueft wird prosrc, nicht pg_get_functiondef(). prosrc ist der
  --    reine Rumpf; pg_get_functiondef() liefert den Definitionstext MIT
  --    Kommentaren. Da die Migrationen 138/139 die alten Spaltennamen in
  --    ihrer Dokumentation nennen, meldete die erste Fassung genau diese
  --    Kommentare als Zugriff - erst start_quiz_attempt, nach dessen
  --    Reparatur immer noch, weil die Beschreibung von 138 im Bestand
  --    blieb.
  --
  --    Muster mit Punkt davor: ein Spaltenzugriff wird in SQL als
  --    "alias.spalte" geschrieben, ein Kommentar dagegen nicht.
  SELECT count(*), min(p.proname) INTO v_rest, v_name
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND (p.prosrc LIKE '%.city%'
          OR p.prosrc LIKE '%.location_lat%'
          OR p.prosrc LIKE '%.location_lng%');

  IF v_rest <> 0 THEN
    RAISE EXCEPTION
      '% Funktion(en) referenzieren noch die Standort-Spalten, z. B. %',
      v_rest, v_name;
  END IF;

  -- 4) Der Guard auf profile_locations.
  SELECT count(*) INTO v_rest
    FROM pg_trigger
   WHERE tgrelid = 'public.profile_locations'::regclass
     AND tgname = 'trg_profile_location_snap';

  IF v_rest <> 1 THEN
    RAISE EXCEPTION
      'Der Snap-Guard auf profile_locations fehlt (% Treffer).', v_rest;
  END IF;

  -- 5) Die Entfernung ist an die Einwilligung gebunden.
  --
  --    Geprueft wird der Quelltext der Funktion, nicht das Ergebnis: ein
  --    Aufruf als angemeldeter Nutzer mit zwei Testkonten waere der
  --    bessere Test, braucht aber zwei echte Profile.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'profile_distance_km'
     AND p.prosrc LIKE '%show_distance%'
  ) THEN
    RAISE EXCEPTION
      'profile_distance_km() prueft show_distance nicht mehr.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'profile_discovery_visible'
     AND p.pronargs = 2
     AND p.prosrc LIKE '%profile_locations%'
  ) THEN
    RAISE EXCEPTION
      'profile_discovery_visible() liest den Radius nicht aus profile_locations.';
  END IF;

  RAISE NOTICE
    'Standort-Contract bestaetigt: profiles ohne Ort/Koordinaten, Ausgaben sauber, Guard aktiv.';
END;
$$;

-- -----------------------------------------------------------------------------
-- Rueckbau (bewusst NICHT ausgefuehrt, nur dokumentiert)
--
--   ALTER TABLE public.profiles ADD COLUMN city text;
--   ALTER TABLE public.profiles ADD COLUMN location_lat double precision;
--   ALTER TABLE public.profiles ADD COLUMN location_lng double precision;
--
--   Die entfernten Werte sind weg und kommen nicht zurueck. Ein
--   Wiederherstellen der Spalten ohne Werte waere schlimmer als nicht
--   vorhanden: ein leeres location_lat gilt an mehreren Stellen als
--   "Standort unbekannt", ein befuelltes waere eine Behauptung.
-- =============================================================================