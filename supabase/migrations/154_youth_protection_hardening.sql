-- 154: Jugendschutz - Luecken schliessen
--
-- Der Audit vom 21.10.2026 hat echte Luecken im Jugendschutz
-- gefunden. Die Discovery filterte zwar ueber age_compatible, aber:
--
-- 1) Die Discovery nutzte das EINSEITIGE age_compatible, nicht das
--    beidseitige age_compatible_bidirectional. Migration 124 hat die
--    Asymmetrie selbst als Defekt dokumentiert ("age_compatible(18,16)
--    = true, aber age_compatible(16,18) = false") und sie NUR in den
--    Paarungswegen behoben. In der Discovery blieb sie stehen: ein
--    18-Jaehriger sah 16- und 17-Jaehrige einseitig, diese sahen ihn
--    nie. Das ist genau die Konstellation, die die 124 schliessen
--    wollte.
--
--    FIX: Die Discovery nutzt jetzt die beidseitige Variante. Damit
--    sehen sich 16- und 17-Jaehrige NUR untereinander, und ein
--    18-Jaehriger sieht niemals einen Minderjaehrigen.
--
-- 2) profile_age war als IMMUTABLE deklariert, benutzt aber
--    current_date. IMMUTABLE erlaubt dem Planer, konstante Argumente
--    zur Planzeit zu falten - bei einer Altersfunktion mit
--    current_date ist das falsch und wuerde das Alter ueber einen
--    Mitternachtswechsel einfrieren. Korrekt ist STABLE.
--
-- 3) Die CHECK-Constraints auf birth_date und age_range waren
--    NOT VALID und wurden nie validiert. Bestehende Zeilen wurden
--    also nie geprueft; ein Legacy-Account mit einem Alter ueber 100
--    gaelte dem Filter als "erwachsen" und waere fuer Erwachsene
--    sichtbar. Beide Constraints werden jetzt validiert - die
--    Gegenprobe laeuft vorher, damit die Migration nicht an
--    Altbestand scheitert.
--
-- 4) Die Altersspanne war nach unten bis 16 einstellbar, obwohl der
--    Server fuer volljuehrige ohnehin nie unter 18 freigibt. Der
--    Filter war also tot, ohne dass die UI das erklaert. Jetzt wird
--    die Untergrenze serverseitig auf das Alter des Nutzers minus
--    MAX_ALTERSDIFFERENZ UNTER (10 Jahre) begrenzt - mindestens 18,
--    sobald der Nutzer volljuehrig ist. Die Obergrenze bleibt frei
--    (bis 99).
--
-- WICHTIG: Diese Migration aENDERT die Sichtbarkeit. Ein 18-Jaehriger
-- verliert die 16- und 17-Jaehrigen aus seiner Liste. Das ist der
-- gewollte Jugendschutz.

BEGIN;

-- ===========================================================================
-- 1) profile_age: IMMUTABLE -> STABLE
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.profile_age(v_birth_date date)
RETURNS int
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT date_part('year', age(coalesce(v_birth_date, '2000-01-01'::date)))::int;
$$;

COMMENT ON FUNCTION public.profile_age(date) IS
  'Alter in Jahren. STABLE, nicht IMMUTABLE: die Berechnung nutzt '
  'current_date, und bei IMMUTABLE darf der Planer konstante Argumente '
  'zur Planzeit falten - das Alter wuerde dann ueber einen '
  'Mitternachtswechsel eingefroren.';

-- ===========================================================================
-- 2) Untergrenze der Altersspanne
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.max_age_range_min(v_viewer_age int)
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT greatest(
    -- 10 Jahre nach unten, wie gewuenscht.
    v_viewer_age - 10,
    -- Nie unter 18, sobald der Nutzer volljuehrig ist. Fuer
    -- Minderjaehrige bleibt 16 moeglich - untereinander ja.
    CASE WHEN v_viewer_age < 18 THEN 16 ELSE 18 END
  );
$$;

COMMENT ON FUNCTION public.max_age_range_min(int) IS
  'Untergrenze der Altersspanne, die der Server fuer ein Nutzeralter '
  'zulaesst: hoechstens 10 Jahre unter dem eigenen Alter, und nie '
  'unter 18, sobald der Nutzer volljuehrig ist. Damit ist der Filter '
  'nicht mehr tot - die App kann nichts einstellen, was der Server '
  'ohnehin nicht liefert.';

-- ===========================================================================
-- 3) Gegenprobe vor dem Validieren der Constraints
-- ===========================================================================
DO $check$
DECLARE
  v_ausreisser int;
BEGIN
  SELECT count(*) INTO v_ausreisser
    FROM public.profiles
   WHERE birth_date > current_date - INTERVAL '16 years'
      OR birth_date < current_date - INTERVAL '100 years';

  IF v_ausreisser > 0 THEN
    RAISE EXCEPTION
      '% Profile haben ein Geburtsdatum ausserhalb 16..100 Jahre. '
      'Die CHECK-Constraints koennen nicht validiert werden.', v_ausreisser;
  END IF;
END;
$check$;

-- ===========================================================================
-- 4) Constraints validieren
-- ===========================================================================
ALTER TABLE public.profiles
  VALIDATE CONSTRAINT chk_profiles_birth_date_age;

ALTER TABLE public.profiles
  VALIDATE CONSTRAINT chk_profiles_age_range;

-- ===========================================================================
-- 5) Discovery: beidseitige Alterspruefung
-- ===========================================================================
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
        -- LATERAL statt EXISTS-Unterabfrage: die Entfernung braucht die
        -- Koordinaten im SELBEN Ausdruck. Ein "NOT EXISTS (...) OR
        -- haversine(vl.lat, tl.lat)" funktioniert nicht - vl/tl waeren
        -- nur innerhalb ihrer eigenen Unterabfrage sichtbar. Genau das
        -- hat den ersten Push dieser Migration mit "missing FROM-clause
        -- entry for table tl" abbrechen lassen.
        LEFT JOIN LATERAL (
          SELECT lat, lng FROM public.profile_locations WHERE user_id = v.user_id
        ) vl ON true
        LEFT JOIN LATERAL (
          SELECT lat, lng FROM public.profile_locations WHERE user_id = t.user_id
        ) tl ON true
       WHERE v.user_id = p_viewer
         -- BEIDSEITIG (v0.10.0, Migration 154).
         --
         -- Vorher stand hier das EINSEITIGE age_compatible. Migration 124
         -- hat die Asymmetrie selbst als Defekt dokumentiert
         -- ("age_compatible(18,16) = true, aber age_compatible(16,18) =
         -- false") und sie NUR in den Paarungswegen behoben. In der
         -- Discovery blieb sie stehen: ein 18-Jaehriger sah 16- und
         -- 17-Jaehrige einseitig, diese sahen ihn nie.
         --
         -- Die beidseitige Variante schliesst das: 16- und 17-Jaehrige
         -- sehen NUR einander, nie einen Erwachsenen - und ein
         -- Erwachsener sie nie.
         AND public.age_compatible_bidirectional(v.birth_date, t.birth_date)
         AND NOT EXISTS (
               SELECT 1 FROM public.blocked_users b
                WHERE (b.blocker = p_viewer AND b.blocked = p_target)
                   OR (b.blocker = p_target AND b.blocked = p_viewer)
             )
         AND coalesce(t.paused, false) = false
         -- Die eigene Altersspanne ...
         AND date_part('year', age(coalesce(t.birth_date, '2000-01-01'::date)))::int
               BETWEEN v.age_range_min AND v.age_range_max
         -- ... darf aber nicht beliebig weit nach unten gehen.
         --
         -- Der Server lieferte fuer Volljaehrige ohnehin nie unter 18.
         -- Einstellbar war 16 trotzdem - der Filter war also tot, ohne
         -- dass die UI das erklaert haette. Jetzt ist die Untergrenze
         -- das eigene Alter minus 10 Jahre (und nie unter 18, sobald
         -- der Nutzer volljuehrig ist).
         AND date_part('year', age(coalesce(t.birth_date, '2000-01-01'::date)))::int
               >= public.max_age_range_min(
                     public.profile_age(v.birth_date))
         AND (
           coalesce(v.distance_filter_mode, 'distance_km') <> 'distance_km'
           -- fehlender Standort heisst "kein Filter", nicht "unsichtbar"
           OR vl.lat IS NULL OR tl.lat IS NULL
           OR 2 * 6371 * asin(sqrt(
                power(sin(radians(tl.lat - vl.lat) / 2), 2)
              + cos(radians(vl.lat)) * cos(radians(tl.lat))
              * power(sin(radians(tl.lng - vl.lng) / 2), 2)
            )) <= v.max_distance_km
         )
    );
$$;

-- Die Volltextvariante (mit Geschlechtspraeferenz) ruft die
-- Grundfunktion auf und erbt damit die beidseitige Alterspruefung.
-- Der Body ist aus Migration 126 uebernommen (Migration 138 hat die
-- Funktion nicht neu definiert).
CREATE OR REPLACE FUNCTION public.profile_discovery_visible_full(
  p_viewer uuid, p_target uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_wants text[];
  v_target_gender text;
BEGIN
  IF NOT public.profile_discovery_visible(p_viewer, p_target) THEN
    RETURN false;
  END IF;

  SELECT coalesce(t.gender, 'unknown') INTO v_target_gender
    FROM public.profiles t WHERE t.user_id = p_target;

  SELECT v.gender_preferences INTO v_wants
    FROM public.profiles v WHERE v.user_id = p_viewer;

  -- 025: `gender_preferences` ist TEXT[] mit allen sechs Werten als
  -- "alle"-Kurzform. Enthaelt es alle sechs, ist keine Filterung gewollt.
  IF v_wants IS NULL
     OR coalesce(array_length(v_wants, 1), 0) = 0
     OR array_length(v_wants, 1) >= 6 THEN
    RETURN true;
  END IF;

  RETURN v_target_gender = ANY (v_wants);
END;
$$;

COMMIT;
