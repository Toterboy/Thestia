-- 188: Haarlaenge und Frisur brauchen eigene Kategorien
--
-- BEFUND (07.11.2026, Betreiber): "Ja kannst du auch mit aufnehmen,
-- also Hairstyle und so."
--
-- DER TEST HAT DEN FEHLER GEFUNDEN: Haarlaenge und Frisur lagen beide in
-- der Kategorie "hair". Die RPC erlaubt aber je Kategorie nur EIN Merkmal
-- (Migration 149: "Je Kategorie nur ein Merkmal waehlen" - damit
-- niemand "Hemd" UND "Bluse" waehlt, was keine Angabe mehr waere).
--
-- Haarlenge und Frisur sind aber KEINE Alternative, sondern zwei
-- Angaben: "lockig" UND "lang" ist eine vollstaendige Beschreibung.
-- In derselben Kategorie schliesst sich das gegenseitig aus - man
-- konnte also nur eine von beiden angeben. Das war beim Testen
-- aufgefallen: das Sheet liess nur eine Auswahl zu.
--
-- Die Loesung: eigene Kategorien. Damit gilt die Regel wieder
-- sinnvoll - je Kategorie ein Merkmal, und "Haarlenge" und "Frisur"
-- sind eben nicht dieselbe Kategorie.

BEGIN;

UPDATE public.transit_tag_catalog
   SET category = 'hair_length'
 WHERE slug = 'hair_length';

UPDATE public.transit_tag_catalog
   SET category = 'hair_style'
 WHERE slug = 'hair_style';

-- Die Kontrolle: die beiden Merkmale muessen jetzt getrennt sein, und
-- die bisherigen Kategorien muessen unangetastet bleiben.
DO $$
DECLARE
  v_haar text;
  v_laenge text;
  v_frisur text;
  v_kopf text;
BEGIN
  SELECT category INTO v_haar
    FROM public.transit_tag_catalog WHERE slug = 'hair_color';
  SELECT category INTO v_laenge
    FROM public.transit_tag_catalog WHERE slug = 'hair_length';
  SELECT category INTO v_frisur
    FROM public.transit_tag_catalog WHERE slug = 'hair_style';
  SELECT category INTO v_kopf
    FROM public.transit_tag_catalog WHERE slug = 'cap';

  IF v_laenge IS DISTINCT FROM 'hair_length' THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: hair_length hat die Kategorie %', v_laenge;
  END IF;
  IF v_frisur IS DISTINCT FROM 'hair_style' THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: hair_style hat die Kategorie %', v_frisur;
  END IF;
  IF v_haar IS DISTINCT FROM 'hair' THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: hair_color hat die Kategorie %', v_haar;
  END IF;
  IF v_kopf IS DISTINCT FROM 'head' THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: cap hat die Kategorie %', v_kopf;
  END IF;
END;
$$;

COMMIT;
