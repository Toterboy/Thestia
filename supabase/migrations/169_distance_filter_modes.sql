-- =============================================================================
-- 169_distance_filter_modes.sql
-- =============================================================================
-- DER SUCHFILTER WIRD DREI MODI TATSÄCHLICH BEDIENEN.
--
-- BETREIBER-ENTSCHEIDUNG (03.11.2026): "Bitte das mit Bundesland und Ganz
-- Deutschland fixen!"
--
-- DER BEFUND (aus Migration 126:76-93 und 155:209-217):
--
-- Der Suchradius hat drei Modi (Migration 085):
--
--   distance_km  - der km-Slider
--   state        - "Bundesland"
--   germany      - "Ganz Deutschland"
--
-- Ausgewertet wurde aber NUR der Radius, und der nur im Modus
-- 'distance_km':
--
--   AND (coalesce(v.distance_filter_mode,'distance_km') <> 'distance_km'
--        OR ... Entfernung <= v.max_distance_km)
--
-- Fuer 'state' und 'germany' fiel die Bedingung also weg. Und einen
-- Bundesland-Vergleich gab es NIRGENDS - weder server- noch client-
-- seitig. "Bundesland" und "Ganz Deutschland" waren dieselbe Bedingung:
-- kein Radius.
--
-- Der Modus war also eine Anzeige, keine Einstellung. Wer "Bundesland"
-- waehlte, bekam ganz Deutschland - und bekam es nicht einmal gemerkt,
-- weil die Liste plausibel aussah.
--
-- DIE KORREKTUR:
--
--   distance_km  -> Entfernung <= max_distance_km (fuer Minderjaehrige
--                   zusaetzlich auf 25 km geklemmt, Migration 164)
--   state        -> nur Personen im SELBEN Bundesland
--   germany      -> keine geografische Beschraenkung
--
-- Fuer Minderjaehrige (16 und 17) bleibt es bei der Fassung aus
-- Migration 164: höchstens 25 km ODER gleiches Bundesland, und
-- 'germany' wird wie 'distance_km' behandelt (fail-closed).
--
-- FUER ERWACHSENE AENDERT SICH ETWAS - und zwar zum ersten Mal, dass der
-- Modus das tut, was er sagt. Wer bisher "Bundesland" gewaehlt hat,
-- sieht jetzt weniger Menschen. Das ist der Sinn der Einstellung.
--
-- LEERE BUNDESLAENDER: Fehlt das Bundesland beim Betrachter oder beim
-- Kandidaten, gilt keine Beschraenkung - genau wie bei fehlendem
-- Standort ("kein Filter", nicht "unsichtbar"). Sonst waeren alle
-- Accounts ohne Bundesland unsichtbar.
-- =============================================================================

BEGIN;

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
           -- ----------------------------------------------------------------
           -- MINDERJAEHRIGE (16 und 17): max. 25 km ODER gleiches
           -- Bundesland. 'germany' wird wie 'distance_km' behandelt
           -- (fail-closed, Migration 164).
           -- ----------------------------------------------------------------
           (
             va.v_age < 18
             AND coalesce(v.distance_filter_mode, 'distance_km') <> 'state'
             AND (
               vl.lat IS NULL OR tl.lat IS NULL
               OR 2 * 6371 * asin(sqrt(
                    power(sin(radians(tl.lat - vl.lat) / 2), 2)
                  + cos(radians(vl.lat)) * cos(radians(tl.lat))
                  * power(sin(radians(tl.lng - vl.lng) / 2), 2)
                )) <= 25
             )
           )
           OR (
             va.v_age < 18
             AND coalesce(v.distance_filter_mode, 'distance_km') = 'state'
             AND nullif(trim(coalesce(v.state, '')), '') IS NOT NULL
             AND nullif(trim(coalesce(t.state, '')), '')
                 = nullif(trim(coalesce(v.state, '')), '')
           )
           -- ----------------------------------------------------------------
           -- ERWACHSENE (18+): der Modus entscheidet - und jetzt auch
           -- wirklich.
           -- ----------------------------------------------------------------
           OR (
             va.v_age >= 18
             AND (
               -- 'distance_km': der gewaehlte Radius
               (
                 coalesce(v.distance_filter_mode, 'distance_km') = 'distance_km'
                 AND (
                   vl.lat IS NULL OR tl.lat IS NULL
                   OR 2 * 6371 * asin(sqrt(
                        power(sin(radians(tl.lat - vl.lat) / 2), 2)
                      + cos(radians(vl.lat)) * cos(radians(tl.lat))
                      * power(sin(radians(tl.lng - vl.lng) / 2), 2)
                    )) <= v.max_distance_km
                 )
               )
               OR
               -- 'state': nur das gleiche Bundesland
               (
                 coalesce(v.distance_filter_mode, 'distance_km') = 'state'
                 AND (
                   nullif(trim(coalesce(v.state, '')), '') IS NULL
                   OR nullif(trim(coalesce(t.state, '')), '') IS NULL
                   OR nullif(trim(coalesce(t.state, '')), '')
                      = nullif(trim(coalesce(v.state, '')), '')
                 )
               )
               OR
               -- 'germany': keine geografische Beschraenkung
               coalesce(v.distance_filter_mode, 'distance_km') = 'germany'
             )
           )
         )
    );
$$;

COMMENT ON FUNCTION public.profile_discovery_visible(uuid, uuid) IS
  'Sichtbarkeit eines Profils in der Begegnungsliste. v0.10.0 '
  '(Migration 169): der Suchradius hat drei Modi, die jetzt auch alle drei '
  'das tun, was sie sagen - Entfernung (km), gleiches Bundesland, ganz '
  'Deutschland. Fuer 16- und 17-Jaehrige gilt weiterhin: max. 25 km '
  'ODER gleiches Bundesland, "Ganz Deutschland" wird wie 25 km '
  'behandelt (fail-closed). Massstab ist das verifizierte Alter.';

REVOKE ALL ON FUNCTION public.profile_discovery_visible(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.profile_discovery_visible(uuid, uuid) TO authenticated;

-- ===========================================================================
-- Selbsttest
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

  -- Der Bundesland-Vergleich muss drin sein - er fehlte vorher
  -- vollstaendig, und genau deshalb war "Bundesland" wirkungslos.
  IF v_body NOT LIKE '%v.state%' OR v_body NOT LIKE '%t.state%' THEN
    RAISE EXCEPTION
      'profile_discovery_visible vergleicht das Bundesland nicht - der '
      'Modus "Bundesland" waere wieder wirkungslos.';
  END IF;

  -- Und alle drei Modi muessen vorkommen.
  IF v_body NOT LIKE '%= ''distance_km''%'
     OR v_body NOT LIKE '%= ''state''%'
     OR v_body NOT LIKE '%= ''germany''%' THEN
    RAISE EXCEPTION
      'profile_discovery_visible wertet nicht alle drei Suchmodi aus.';
  END IF;

  -- Die 25-km-Grenze fuer Minderjaehrige muss bleiben.
  IF v_body NOT LIKE '%<= 25%' THEN
    RAISE EXCEPTION
      'profile_discovery_visible kennt keine 25-km-Grenze mehr.';
  END IF;

  IF v_body NOT LIKE '%profile_known_age%' THEN
    RAISE EXCEPTION
      'profile_discovery_visible rechnet nicht mit dem bekannten Alter.';
  END IF;

  RAISE NOTICE 'Suchfilter: alle drei Modi bedient, 25-km-Grenze fuer Minderjaehrige erhalten (Selbsttest ok)';
END;
$check$;

COMMIT;
