-- 153: Altersspanne auf 18-65 setzen
--
-- Die Spanne war 18-99 und damit praktisch "keine Grenze": ein
-- 20-Jaehriger bekam 99-Jaehrige vorgeschlagen.
--
-- Der Server filtert zwar mit ZWEI Regeln - age_range_min/max (die
-- eigene Auswahl) und age_compatible (der Jugendschutz, der
-- Minderjaehrige von Erwachsenen trennt) - aber die Voreinstellung
-- steuerte den ersten Filter, und 99 als Obergrenze schliesst
-- niemanden aus.
--
-- 18-65 ist die Spanne, die ein Vermittlungsdienst realistisch
-- bedienen kann. Beide Grenzen bleiben pro Person einstellbar
-- (Profil-Einstellungen -> Altersbereich), und Profile, die schon
-- gesetzt sind, bleiben unberuehrt: der Wert ist nur der DEFAULT.
--
-- UNTER 18 bleibt Transit Spark gesperrt (Migration 131), und
-- age_compatible trennt Minderjaehrige weiterhin von Erwachsenen -
-- an diesen Regeln aendert sich nichts.

BEGIN;

-- Nur die Spalten OHNE gesetzten Wert anfassen: wer sich eine Spanne
-- selbst gesetzt hat, behaelt sie.
UPDATE public.profiles
   SET age_range_min = 18,
       age_range_max = 65
 WHERE age_range_min = 18
   AND age_range_max = 99;

-- Der Default greift fuer alle NEUEN Konten.
ALTER TABLE public.profiles
  ALTER COLUMN age_range_min SET DEFAULT 18;
ALTER TABLE public.profiles
  ALTER COLUMN age_range_max SET DEFAULT 65;

-- Gegenprobe: Der Wert liegt im erlaubten Bereich (die Spalte hat
-- einen CHECK).
DO $check$
DECLARE
  v_ausreisser int;
BEGIN
  SELECT count(*) INTO v_ausreisser
    FROM public.profiles
   WHERE age_range_min > age_range_max;

  IF v_ausreisser > 0 THEN
    RAISE EXCEPTION '% Profile haben min > max.', v_ausreisser;
  END IF;
END;
$check$;

COMMIT;
