-- 148: Merkmale mit Kategorien, Suche und eigenen Attributen
--
-- BISHER: 15 flache Slugs in einem Array, das in SIEBEN Migrationen
-- als Volltextkopie stand (082, 084, 091, 104, 110, 131). Jede
-- Aenderung brauchte eine achte Kopie - die RPC-Datei waere auf
-- >1000 Zeilen angewachsen.
--
-- JETZT: eine Lookup-Tabelle. Die RPC liest die erlaubten Werte aus
-- ihr, statt sie hart zu codieren. Damit ist die Wertemenge nicht mehr
-- durch die Groesse eines Arrays begrenzt - die whitelisted
-- Kleidungsfarben allein waeren bei 6 Kategorien x 8 Werten x 12
-- Farben schon ueber 600 Eintraege, plus eigene Haar- und Augenfarben.
--
-- KATEGORIEN (die Anforderung):
--   top        Oberteil   - Hemd, Bluse, T-Shirt, Hoodie, Pullover, Jacke, Weste
--   bottom     Unterteil  - Hose, Jeans, Rock, Shorts, Leggings
--   head       Kopf       - Cap, Muetze, Helm, Kopfbedeckung
--   shoes      Schuhe     - Sneaker, Stiefel, Sandalen, Halbschuhe
--   accessory  Accessoires- Brille, Kopfhoerer, Schal, Rucksack, Tasche, Ausweis
--   hair       Haar       - Farbe + Laenge
--   eyes       Augen      - Farbe
--
-- HAAR- UND AUGENFARBEN haben eine EIGENE Palette. "schwarz" bei der
-- Kleidung und "schwarz" beim Haar sind verschiedene Angaben - mit
-- derselben Farb-Whitelist wuerde ein schwarzes Hemd mit schwarzem
-- Haar verwechselt. Die Werte tragen deshalb ihr eigenes Praefix in
-- der Farbangabe: 'hair:black' statt 'black'.
--
-- Das Wire-Format der Merkmale bleibt FLACH: ein Slug je Element,
-- Farbe als 'slug:farbe'. Grund: das Matching vergleicht Slugs
-- (Migration 131:234-238). Ein 'kategorie:wert'-Format wuerde alle
-- Bestandswerte neu kodieren muessen und den Vergleich kategorie-
-- abhaengig machen. Die Kategorie bleibt Client-Metadatum; die
-- serverseitige Tabelle liefert sie fuer Anzeige und Filter mit.
--
-- Bestandsdaten: transit_signals ist ephemer (Cron loescht aelter als
-- 24 h). Die Legacy-Slugs 'black_hoodie' und 'colorful_top' werden
-- deshalb auf die neuen Werte normalisiert.

BEGIN;

-- ===========================================================================
-- 1) Lookup-Tabelle
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.transit_tag_catalog (
  slug text PRIMARY KEY,
  category text NOT NULL,
  colorizable boolean NOT NULL DEFAULT false,
  -- Eigene Farbpalette je Kategorie. Leer = keine Farbwahl.
  allowed_colors text[] NOT NULL DEFAULT '{}'::text[],
  -- Reihenfolge in der Anzeige.
  sort_order int NOT NULL DEFAULT 0,
  -- Fuer die Suche: zusaetzliche Schreibweisen (z. B. 't-shirt' fuer
  -- 'tshirt'). Kleinbuchstaben, ohne Umlaute, Leerzeichen als '-'.
  search_aliases text[] NOT NULL DEFAULT '{}'::text[]
);

COMMENT ON TABLE public.transit_tag_catalog IS
  'Katalog der Transit-Spark-Merkmale mit Kategorien (v0.10.0, Migration 148). '
  'Ersetzt die hart codierte Whitelist in match_proximity_spark: die '
  'RPC liest die erlaubten Werte aus dieser Tabelle. Die Kategorie ist '
  'Client-Metadatum fuer Anzeige und Filter, das Wire-Format bleibt '
  'flach (ein Slug je Element, Farbe als slug:farbe).';

CREATE INDEX IF NOT EXISTS idx_transit_tag_catalog_category
  ON public.transit_tag_catalog (category, sort_order);

-- RLS: die Tabelle ist eine reine Stammdatentabelle, die jeder
-- angemeldete Nutzer lesen darf. Schreiben kann nur der Server.
ALTER TABLE public.transit_tag_catalog ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "transit_tag_catalog_read" ON public.transit_tag_catalog;
CREATE POLICY "transit_tag_catalog_read"
  ON public.transit_tag_catalog
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "transit_tag_catalog_no_write" ON public.transit_tag_catalog;
CREATE POLICY "transit_tag_catalog_no_write"
  ON public.transit_tag_catalog
  FOR ALL
  TO authenticated
  WITH CHECK (false);

-- GRANT (Migration 147 hat die Default-Privileges abgeschaltet: ohne
-- dieses GRANT ist die Tabelle fuer den Client unsichtbar).
GRANT SELECT ON public.transit_tag_catalog TO authenticated;
GRANT ALL ON public.transit_tag_catalog TO service_role;

-- ===========================================================================
-- 2) Werte
-- ===========================================================================
-- Kleidung mit der bestehenden Kleidungspalette.
TRUNCATE public.transit_tag_catalog;

INSERT INTO public.transit_tag_catalog
  (slug, category, colorizable, allowed_colors, sort_order, search_aliases) VALUES
-- Oberteil
  ('hemd',      'top', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 10, ARRAY['shirt','hemden','oberhemd']),
  ('bluse',     'top', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 20, ARRAY['blouse']),
  ('tshirt',    'top', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 30, ARRAY['t-shirt','shirt','tee']),
  ('hoodie',    'top', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 40, ARRAY['kapuzenpulli','kapuzenpullover']),
  ('pullover',  'top', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 50, ARRAY['pulli','strickpullover','sweater']),
  ('jacke',     'top', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 60, ARRAY['jacken','mantel']),
  ('weste',     'top', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 70, ARRAY['weste','gilet','vest']),
-- Unterteil
  ('hose',      'bottom', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 110, ARRAY['hosen','pants']),
  ('jeans',     'bottom', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 120, ARRAY['denim']),
  ('rock',      'bottom', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 130, ARRAY['rocke','kleid']),
  ('shorts',    'bottom', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 140, ARRAY['kurze hose','kurzhosen']),
  ('leggings',  'bottom', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 150, ARRAY['leggins']),
-- Kopf
  ('cap',       'head', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 210, ARRAY['muetze','kappe']),
  ('muetze',    'head', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 220, ARRAY['beanie','stirnband']),
  ('helm',      'head', false, '{}'::text[], 230, ARRAY[]::text[]),
-- Schuhe
  ('sneaker',   'shoes', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 310, ARRAY['schuhe','turnschuhe','sneakers']),
  ('stiefel',   'shoes', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 320, ARRAY['stiefel','boots']),
  ('sandalen',  'shoes', false, '{}'::text[], 330, ARRAY[]::text[]),
  ('halbschuhe','shoes', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 340, ARRAY['schuhe','loafer']),
-- Accessoires
  ('brille',    'accessory', false, '{}'::text[], 410, ARRAY['glasses','sonnenbrille']),
  ('kopfhoerer','accessory', false, '{}'::text[], 420, ARRAY['headphones','ohrhoerer']),
  ('schal',     'accessory', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 430, ARRAY['stola','tuch']),
  ('rucksack',  'accessory', false, '{}'::text[], 440, ARRAY['backpack','rucksack']),
  ('tasche',    'accessory', true, ARRAY['black','white','grey','blue','green','red','yellow','orange','pink','brown','purple','teal'], 450, ARRAY['shoppingbag','tote bag','umhaengetasche']),
  ('ausweis',   'accessory', false, '{}'::text[], 460, ARRAY['lanyard','badge','ausweis']),
  ('sportlich', 'accessory', false, '{}'::text[], 470, ARRAY['sportkleidung','sporty']),
-- Haar: EIGENE Palette
  ('hair_color', 'hair', true, ARRAY['black','blonde','brown','red','auburn','grey','white','bald'], 510, ARRAY['haarfarbe','hair colour']),
  ('hair_length','hair', false, '{}'::text[], 520, ARRAY['haarlaenge','hair length']),
  ('hair_style', 'hair', false, '{}'::text[], 530, ARRAY['frisur','haartyp']),
-- Augen: EIGENE Palette
  ('eyes_color','eyes', true, ARRAY['brown','blue','green','grey','hazel','bluegrey','amber'], 610, ARRAY['augenfarbe','eye colour']);

-- ===========================================================================
-- 3) Bestandswerte normalisieren
-- ===========================================================================
-- Die Legacy-Slugs wurden vom Client nie angeboten, sind aber noch
-- gespeichert. Ohne Normalisierung wuerde ein Match mit ihnen nicht
-- mehr zustande kommen (die neuen Werte heissen anders).
--
-- 'colorful_top' wird zu 'sportlich' (der naechste passende Wert),
-- 'black_hoodie' zu 'hoodie' (die Farbe steckt im Slug, die
-- Hoodie-Farbauswahl uebernimmt sie).
UPDATE public.transit_signals
   SET tags = array(
         SELECT CASE t
                  WHEN 'black_hoodie' THEN 'hoodie'
                  WHEN 'colorful_top' THEN 'sportlich'
                  ELSE t
                END
           FROM unnest(tags) AS t)
 WHERE tags && ARRAY['black_hoodie', 'colorful_top'];

UPDATE public.transit_signals
   SET self_tags = array(
         SELECT CASE t
                  WHEN 'black_hoodie' THEN 'hoodie'
                  WHEN 'colorful_top' THEN 'sportlich'
                  ELSE t
                END
           FROM unnest(self_tags) AS t)
 WHERE self_tags && ARRAY['black_hoodie', 'colorful_top'];

-- ===========================================================================
-- 4) Grenzen an die neuen Kategorien anpassen
-- ===========================================================================
--
-- BISHER: 2-5 Merkmale (Fremd-Beschreibung), max. 5 (Selbstbeschreibung).
-- MIT KATEGORIEN: wer Hemd, Hose, Schuhe, Cap UND Haarfarbe waehlt, ist
-- mit 5 schnell am Limit - und "Haarfarbe" plus "Haarlaenge" sind
-- getrennte Werte.
--
-- Deshalb: max. 1 Wert je Kategorie, und hoechstens 3 Kategorien fuer
-- die Fremd-Beschreibung (die dient dem Matching) bzw. 5 fuer die
-- Selbstbeschreibung (die dient der Vorstellung).
--
-- Die Grenze wird in der RPC durchgesetzt, der Client muss sie
-- spiegeln (lib/models/transit_models.dart, lib/screens/swipe/
-- transit_radar_screen.dart).
CREATE OR REPLACE FUNCTION public.transit_tag_limits()
RETURNS TABLE (
  max_gesamt integer,
  min_gesamt integer,
  max_je_kategorie integer
)
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT 8, 2, 1;
$$;

COMMENT ON FUNCTION public.transit_tag_limits() IS
  'Grenzen fuer die Merkmalsauswahl (v0.10.0, Migration 148). '
  'max_gesamt: insgesamt gewaehlte Merkmale. min_gesamt: Mindestzahl '
  'fuer die Fremd-Beschreibung. max_je_kategorie: hoechstens ein Wert '
  'je Kategorie - sonst waeren "Hemd" und "Bluse" gleichzeitig moeglich '
  'und die Angabe unsinnig.';

COMMIT;
