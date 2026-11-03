-- =============================================================================
-- 164_minor_discovery_radius_cap.sql
-- =============================================================================
-- Minderjaehrige (16 und 17 Jahre) bekommen einen begrenzten Suchradius.
--
-- BETREIBER-ENTSCHEIDUNG (03.11.2026): "Bei b) kann man ja einfach fuer 16
-- und 17 jaehrige entweder gleiches Bundesland oder max. 25 Km machen. Und
-- ab 18 alles frei auswaehlbar."
--
-- DER BISHERIGE ZUSTAND (und warum das nicht genuegte):
--
-- Der Suchradius hat drei Modi (Migration 085):
--
--   distance_km  - der km-Slider (1..100 km, Standard 50)
--   state        - "Bundesland"
--   germany      - "Ganz Deutschland"
--
-- Server-seitig wurde aber NUR der Modus distance_km ausgewertet
-- (Migration 155:209-217):
--
--   AND (coalesce(v.distance_filter_mode,'distance_km') <> 'distance_km'
--        OR ... Entfernung <= v.max_distance_km)
--
--Fuer 'state' und 'germany' FAELLT die Entfernungsbedingung also weg. Ein
--Bundesland-Vergleich gab es nirgends - weder server- noch client-seitig.
--"Bundesland" und "Ganz Deutschland" waren dieselbe eingeschraenkte
--Bedingung: kein Radius.
--
-- Deshalb reicht es nicht, im Client den Modus zu sperren. Ein gepatchter
--Client koennte distance_filter_mode auf 'germany' oder auf 100 km setzen
--und damit die Grenze aushebeln. Die Grenze sitzt in der Funktion, die die
--Sichtbarkeit entscheidet.
--
-- DIE REGEL (nur 16 und 17, ab 18 alles frei):
--
--   Modus distance_km  -> Entfernung <= 25 km (der WERT wird geklemmt,
--                          auch wenn profiles.max_distance_km groesser ist)
--   Modus state        -> nur Personen im SELBEN Bundesland
--   Modus germany      -> gesperrt. Server-seitig wird er wie distance_km
--                          behandelt (fail-closed): 25 km.
--
-- FEHLT DAS ALTER: fail-closed. Ein unbekanntes Alter (weder verifiziert
--noch deklariert) wird wie ein Minderjaehriger behandelt. Massstab ist
--public.profile_known_age() - das verifizierte Alter, sonst das
--deklarierte. (public.profile_effective_age() wuerde ein fehlendes
--Geburtsdatum auf den 01.01.2000 fallen lassen, also auf 26 Jahre - fuer
--eine Jugendschutzgrenze ist das die falsche Richtung.)
--
-- FEHLT DAS BUNDESLAND im Modus 'state': der Minderjaehrige faellt auf
--den 25-km-Radius zurueck, statt alles zu sehen. Auch das ist
--fail-closed - "kein Bundesland gesetzt" darf nicht heissen
--"kein Filter".
--
-- ERWACHSENE (18+): unveraendert. Der Modus entscheidet wie bisher.
--
-- RUECKWAERTSKOMPATIBEL: Fuer Erwachsene aendert sich NICHTS. Fuer
--Minderjaehrige wird der Radius enger - das ist der Punkt.
-- =============================================================================

BEGIN;

-- ===========================================================================
-- 1) Das Alter, das fuer die Grenze zaehlt - mit "unbekannt" als Ergebnis
-- ===========================================================================
-- public.profile_effective_age() (Migration 155) kennt kein "unbekannt":
-- es coalesct ein fehlendes Geburtsdatum auf den 01.01.2000. Fuer die
-- Sichtbarkeitslogik ist das harmlos, fuer eine Jugendschutzgrenze nicht:
-- 26 Jahre waeren "erwachsen", also unbegrenzt.
--
-- Diese Funktion liefert NULL, wenn das Alter nicht bekannt ist. NULL
-- wird von den Aufrufern als "behandele wie Minderjaehrig" ausgewertet.
CREATE OR REPLACE FUNCTION public.profile_known_age(
  v_birth_date date,
  v_verified_age int
)
RETURNS int
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN v_verified_age IS NOT NULL THEN v_verified_age
    WHEN v_birth_date IS NOT NULL THEN public.profile_age(v_birth_date)
    ELSE NULL
  END;
$$;

COMMENT ON FUNCTION public.profile_known_age(date, int) IS
  'Das Alter, das fuer Jugendschutz-Grenzen zaehlt: das verifizierte, '
  'sonst das deklarierte. NULL, wenn das Alter unbekannt ist - im '
  'Gegensatz zu profile_effective_age(), das dann auf den 01.01.2000 '
  'faellt (26 Jahre). Aufrufer werten NULL als "behandle wie '
  'Minderjaehrig" (v0.10.0, Migration 164).';

REVOKE ALL ON FUNCTION public.profile_known_age(date, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.profile_known_age(date, int) TO authenticated;

-- ===========================================================================
-- 2) Der Radius fuer Minderjaehrige
-- ===========================================================================
-- Der Grenzwert steht als Literal (25) im Body - er wird an EINER Stelle
-- des Codes definiert und in der App an derselben (age_safety_rules.dart).
-- Ein zweiter, abweichender Wert in der Datenbank waere die klassische
-- Stelle, an der eine Grenze auseinanderlaeuft.
CREATE OR REPLACE FUNCTION public.profile_discovery_visible(
  p_viewer uuid, p_target uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    p_viewer IS NOT NULL
    AND p_target IS NOT NULL
    AND p_target <> p_viewer
    AND EXISTS (
      SELECT 1
        FROM public.profiles v
        JOIN public.profiles t ON t.user_id = p_target
        LEFT JOIN LATERAL (
          SELECT lat, lng FROM public.profile_locations WHERE user_id = v.user_id
        ) vl ON true
        LEFT JOIN LATERAL (
          SELECT lat, lng FROM public.profile_locations WHERE user_id = t.user_id
        ) tl ON true
        LEFT JOIN LATERAL (
          SELECT public.profile_known_age(v.birth_date, v.verified_age) AS v_age
        ) va ON true
       WHERE v.user_id = p_viewer
         AND public.age_compatible_bidirectional_ages(
               public.profile_effective_age(v.birth_date, v.verified_age),
               public.profile_effective_age(t.birth_date, t.verified_age))
         AND NOT EXISTS (
               SELECT 1 FROM public.blocked_users b
                WHERE (b.blocker = p_viewer AND b.blocked = p_target)
                   OR (b.blocker = p_target AND b.blocked = p_viewer)
             )
         AND coalesce(t.paused, false) = false
         AND public.profile_effective_age(t.birth_date, t.verified_age)
               BETWEEN v.age_range_min AND v.age_range_max
         AND public.profile_effective_age(t.birth_date, t.verified_age)
               >= public.max_age_range_min(
                     public.profile_effective_age(v.birth_date, v.verified_age))
         AND (
           -- ERWACHSENE (18+): unveraendert - der Modus entscheidet, wie
           -- bisher (Migration 155).
           va.v_age >= 18
           OR (
             -- MINDERJAEHRIGE (16-17) - und alle, deren Alter unbekannt
             -- ist (fail-closed).
             (
               -- Option 1: gleiches Bundesland.
               coalesce(v.distance_filter_mode, 'distance_km') = 'state'
               AND nullif(trim(coalesce(v.state, '')), '') IS NOT NULL
               AND nullif(trim(coalesce(t.state, '')), '')
                   = nullif(trim(coalesce(v.state, '')), '')
             )
             OR (
               -- Option 2: hoechstens 25 km. Greift fuer distance_km, fuer
               -- den gesperrten Modus germany und fuer 'state' ohne
               -- gesetztes Bundesland.
               (
                 coalesce(v.distance_filter_mode, 'distance_km') <> 'state'
                 OR nullif(trim(coalesce(v.state, '')), '') IS NULL
               )
               AND (
                 -- fehlender Standort heisst "kein Filter" (Migration 138)
                 vl.lat IS NULL OR tl.lat IS NULL
                 OR 2 * 6371 * asin(sqrt(
                      power(sin(radians(tl.lat - vl.lat) / 2), 2)
                    + cos(radians(vl.lat)) * cos(radians(tl.lat))
                    * power(sin(radians(tl.lng - vl.lng) / 2), 2)
                  )) <= 25
               )
             )
           )
         )
    );
$$;

COMMENT ON FUNCTION public.profile_discovery_visible(uuid, uuid) IS
  'Sichtbarkeit eines Profils in der Begegnungsliste. v0.10.0 (Migration '
  '164): fuer 16- und 17-Jaehrige gilt ein begrenzter Suchradius - '
  'maximal 25 km ODER nur das gleiche Bundesland. "Ganz Deutschland" ist '
  'gesperrt und wird serverseitig wie 25 km behandelt (fail-closed). '
  'Massstab ist das verifizierte Alter (profile_known_age); ein '
  'unbekanntes Alter wird wie ein Minderjaehriger behandelt. Ab 18 ist '
  'alles frei wie bisher.';

REVOKE ALL ON FUNCTION public.profile_discovery_visible(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.profile_discovery_visible(uuid, uuid) TO authenticated;

-- ===========================================================================
-- 3) Selbsttest: die Grenze sitzt
-- ===========================================================================
DO $check$
DECLARE
  v_body text;
BEGIN
  SELECT pg_get_functiondef('public.profile_discovery_visible(uuid,uuid)'::regprocedure)
    INTO v_body;

  IF v_body IS NULL THEN
    RAISE EXCEPTION 'profile_discovery_visible fehlt.';
  END IF;

  -- Das Alter muss geprueft werden - sonst waere jeder Radius frei.
  IF v_body NOT LIKE '%profile_known_age%' THEN
    RAISE EXCEPTION
      'profile_discovery_visible prueft das Alter nicht - die 25-km-Grenze '
      'waere fuer jeden wirksam.';
  END IF;

  -- Die Grenze selbst.
  IF v_body NOT LIKE '%<= 25%' THEN
    RAISE EXCEPTION
      'profile_discovery_visible kennt keine 25-km-Grenze.';
  END IF;

  -- Der gesperrte Modus muss behandelt werden.
  IF v_body NOT LIKE '%distance_filter_mode%' THEN
    RAISE EXCEPTION
      'profile_discovery_visible ignoriert den Suchradius-Modus.';
  END IF;

  -- Und das Bundesland muss verglichen werden.
  IF v_body NOT LIKE '%v.state%' OR v_body NOT LIKE '%t.state%' THEN
    RAISE EXCEPTION
      'profile_discovery_visible vergleicht das Bundesland nicht.';
  END IF;

  RAISE NOTICE 'profile_discovery_visible: 25-km-Grenze fuer Minderjaehrige vorhanden (Selbsttest ok)';
END;
$check$;

COMMIT;
