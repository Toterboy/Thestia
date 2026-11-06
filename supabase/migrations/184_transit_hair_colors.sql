-- 184: mehr Haarfarben fuer Transit Spark
--
-- BEFUND (06.11.2026, Betreiber): "Es muss mehr Haarfarben zur Auswahl
-- geben." Die acht bisherigen Werte decken nur die grobsten
-- Unterscheidungen ab: "dunkelbraun" und "hellbraun" sind fuer viele
-- Menschen genau die Unterscheidung, die zaehlt, und "Kupferrot" sieht
-- anders aus als "Rot".
--
-- WARUM EINE MIGRATION: Die Whitelist der erlaubten Merkmale steht im
-- Katalog public.transit_tag_catalog (Migration 148). Die RPC
-- match_proximity_spark baut ihre erlaubte Liste aus dieser Tabelle
-- (Migration 149) - ein Wert, den der Server nicht kennt, wird beim
-- Senden stillschweigend weggefiltert. Die App wuerde die neue Farbe
-- anbieten, der Server wuerde sie ablehnen.
--
-- DESHALB: Hier wird die Palette des Eintrags 'hair_color' erweitert.
-- Die App (lib/models/transit_models.dart) fuehrt dieselben 14 Werte in
-- TransitTag.hairColors - in der Auswahl in der Reihenfolge der
-- Palette.
--
-- Die Reihenfolge im Array ist die Anzeigereihenfolge fuer die
-- Auswahl. Sie wird hier bewusst mitgeschrieben, damit Server und App
-- dieselbe Reihenfolge kennen.

BEGIN;

-- Die Haarfarben-Palette: 14 Werte statt 8.
--
-- Neu gegenueber Migration 148: dunkelbraun, hellbraun, Kupferrot,
-- Platinblond, Silbergrau, Salz und Pfeffer.
UPDATE public.transit_tag_catalog
   SET allowed_colors = ARRAY[
         'black',
         'brown',
         'darkbrown',
         'lightbrown',
         'blonde',
         'platinum',
         'red',
         'copper',
         'auburn',
         'grey',
         'silver',
         'saltpepper',
         'white',
         'bald'
       ]::text[]
 WHERE slug = 'hair_color';

-- Kontrolle: Der Eintrag muss genau eine Zeile sein und 14 Farben
-- haben. Sonst haette die App Farben im Angebot, die der Server nicht
-- kennt (oder umgekehrt) - das Matching wuerde dann stillschweigend
-- ins Leere laufen.
DO $$
DECLARE
  v_anzahl int;
  v_farben int;
BEGIN
  SELECT count(*), max(array_length(allowed_colors, 1))
    INTO v_anzahl, v_farben
    FROM public.transit_tag_catalog
   WHERE slug = 'hair_color';

  IF v_anzahl <> 1 THEN
    RAISE EXCEPTION 'Der Katalogeintrag hair_color fehlt oder ist doppelt (%)', v_anzahl;
  END IF;

  IF v_farben <> 14 THEN
    RAISE EXCEPTION 'hair_color hat % Farben, erwartet sind 14', v_farben;
  END IF;
END $$;

COMMIT;
