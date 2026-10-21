-- 150: Umbenannte Merkmale in bestehenden Transit-Signalen nachziehen
--
-- Migration 148 hat den Merkmalskatalog umgestellt. Die Slugs wurden
-- dabei umbenannt, damit sie zur Kategorie passen:
--
--     sweater  -> pullover      pants    -> hose
--     glasses  -> brille        scarf    -> schal
--     sporty   -> sportlich     backpack -> rucksack
--     headphones -> kopfhoerer   tote_bag -> tasche
--     lanyard  -> ausweis
--
-- In transit_signals gespeicherte Zeilen behalten den alten Slug. Der
-- Vergleich im Matching (Migration 131) vergleicht Slugs direkt - ein
-- alter Slug trifft einen neuen nicht, und die Begegnung bleibt aus.
--
-- Die Tabelle ist zwar ephemer (Cron loescht aelter als 24 Stunden),
-- aber eine halbe Stunde mit falschen Werten ist trotzdem eine halbe
-- Stunde ohne Funken. Deshalb hier nachziehen.
--
-- Die Umbenennungen sind 1:1. Ein Wert, der keine Entsprechung mehr
-- hat, wird nicht geraten - er faellt aus der Whitelist und wird vom
-- RPC stillschweigend verworfen (das ist das bestehende Verhalten
-- fuer unbekannte Slugs).

BEGIN;

UPDATE public.transit_signals
   SET tags = array(
         SELECT CASE t
                  WHEN 'sweater'    THEN 'pullover'
                  WHEN 'pants'      THEN 'hose'
                  WHEN 'glasses'    THEN 'brille'
                  WHEN 'scarf'      THEN 'schal'
                  WHEN 'sporty'     THEN 'sportlich'
                  WHEN 'backpack'   THEN 'rucksack'
                  WHEN 'headphones' THEN 'kopfhoerer'
                  WHEN 'tote_bag'   THEN 'tasche'
                  WHEN 'lanyard'    THEN 'ausweis'
                  WHEN 'black_hoodie'  THEN 'hoodie'
                  WHEN 'colorful_top'  THEN 'sportlich'
                  ELSE t
                END
           FROM unnest(tags) AS t)
 WHERE tags && ARRAY[
   'sweater','pants','glasses','scarf','sporty','backpack',
   'headphones','tote_bag','lanyard','black_hoodie','colorful_top'];

UPDATE public.transit_signals
   SET self_tags = array(
         SELECT CASE t
                  WHEN 'sweater'    THEN 'pullover'
                  WHEN 'pants'      THEN 'hose'
                  WHEN 'glasses'    THEN 'brille'
                  WHEN 'scarf'      THEN 'schal'
                  WHEN 'sporty'     THEN 'sportlich'
                  WHEN 'backpack'   THEN 'rucksack'
                  WHEN 'headphones' THEN 'kopfhoerer'
                  WHEN 'tote_bag'   THEN 'tasche'
                  WHEN 'lanyard'    THEN 'ausweis'
                  WHEN 'black_hoodie'  THEN 'hoodie'
                  WHEN 'colorful_top'  THEN 'sportlich'
                  ELSE t
                END
           FROM unnest(self_tags) AS t)
 WHERE self_tags && ARRAY[
   'sweater','pants','glasses','scarf','sporty','backpack',
   'headphones','tote_bag','lanyard','black_hoodie','colorful_top'];

DO $check$
DECLARE
  v_rest int;
BEGIN
  SELECT count(*) INTO v_rest
    FROM public.transit_signals s
   WHERE s.tags || s.self_tags
         && ARRAY['sweater','pants','glasses','scarf','sporty','backpack',
                  'headphones','tote_bag','lanyard',
                  'black_hoodie','colorful_top'];

  IF v_rest > 0 THEN
    RAISE EXCEPTION 'Noch % Transit-Signale mit umbenanntem Slug - '
      'die Umbenennung ist unvollstaendig.', v_rest;
  END IF;
END;
$check$;

COMMIT;
