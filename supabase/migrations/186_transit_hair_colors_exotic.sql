-- 186: noch mehr Haarfarben - ausgefallene Farben fuer Transit Spark
--
-- BEFUND (07.11.2026, Betreiber): "Zudem soll bei Haarfarben auch noch
-- sowas wie lila usw. sein."
--
-- Migration 184 hatte die Palette von 8 auf 14 Werte gebracht. Es fehlten
-- die ausgefallenen Farben - und "lila" ist genau die, die genannt
-- wurde.
--
-- WARUM EINE MIGRATION: Die Whitelist der erlaubten Merkmale steht im
-- Katalog public.transit_tag_catalog (Migration 148). Die RPC
-- match_proximity_spark baut ihre erlaubte Liste aus dieser Tabelle
-- (Migration 149) - ein Wert, den der Server nicht kennt, wird beim
-- Senden stillschweigend weggefiltert. Die App wuerde die neue Farbe
-- anbieten, der Server wuerde sie ablehnen.
--
-- DIE NEUEN WERTE: lila, rosa, blau, gruen.
--
-- Sie benutzen die vorhandenen Farb-Slugs ('purple', 'pink', 'blue',
-- 'green') - die Farbwerte sind damit dieselben wie in der
-- Kleidungspalette, und die Uebersetzungen existieren bereits
-- ('transit.color.purple' = "Lila"). Eigene Slugs waeren ein zweites
-- Wort fuer dieselbe Farbe - und die RPC vergleicht Slugs, nicht
-- Farben.
--
-- Die Reihenfolge ist die Anzeigereihenfolge. Sie wird hier bewusst
-- mitgeschrieben, damit Server und App dieselbe kennen (so auch in
-- Migration 184): die natuerlichen Farben zuerst, die ausgefallenen
-- am Ende.

BEGIN;

-- Die Haarfarben-Palette: 18 Werte statt 14.
--
-- Neu gegenueber Migration 184: lila, rosa, blau, gruen.
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
         'bald',
         'purple',
         'pink',
         'blue',
         'green'
       ]
 WHERE slug = 'hair_color';

-- Die Kontrolle: genau ein Katalogeintrag, genau 18 Farben, und die
-- neuen sind drin. Ohne diese Pruefung wuerde ein Tippfehler in der
-- Palette unbemerkt bleiben - und die App wuerde eine Farbe anbieten,
-- die der Server nicht kennt (der filtert sie dann still weg, und der
-- Nutzer wundert sich, warum sein Funke nie ankommt).
DO $$
DECLARE
  v_anzahl int;
  v_farben text[];
  farbe text;
BEGIN
  -- Erst die Anzahl pruefen, dann die Palette holen. Ein array_agg
  -- ueber allowed_colors wuerde ein Array von Arrays liefern (und
  -- array_length damit 1 statt 18).
  SELECT count(*)
    INTO v_anzahl
    FROM public.transit_tag_catalog
   WHERE slug = 'hair_color';

  IF v_anzahl <> 1 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: % Katalogeintraege fuer hair_color (erwartet: 1)', v_anzahl;
  END IF;

  SELECT allowed_colors
    INTO v_farben
    FROM public.transit_tag_catalog
   WHERE slug = 'hair_color';

  IF array_length(v_farben, 1) <> 18 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: hair_color hat % Farben (erwartet: 18)',
      array_length(v_farben, 1);
  END IF;

  FOREACH farbe IN ARRAY v_farben LOOP
    IF farbe NOT IN ('purple', 'pink', 'blue', 'green')
       AND farbe NOT IN ('black', 'brown', 'darkbrown', 'lightbrown',
                         'blonde', 'platinum', 'red', 'copper', 'auburn',
                         'grey', 'silver', 'saltpepper', 'white', 'bald') THEN
      RAISE EXCEPTION 'Kontrolle fehlgeschlagen: unbekannte Farbe "%" in der Haarfarben-Palette', farbe;
    END IF;
  END LOOP;

  IF NOT ('purple' = ANY (v_farben))
     OR NOT ('pink' = ANY (v_farben))
     OR NOT ('blue' = ANY (v_farben))
     OR NOT ('green' = ANY (v_farben)) THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: die neuen Farben fehlen in der Palette';
  END IF;
END;
$$;

COMMIT;
