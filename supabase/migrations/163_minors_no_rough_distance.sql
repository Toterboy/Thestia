-- =============================================================================
-- 163_minors_no_rough_distance.sql
-- =============================================================================
-- Minderjaehrige (16 und 17 Jahre) geben KEINE Entfernung preis.
--
-- BETREIBER-ENTSCHEIDUNG (02.11.2026): "Die grobe Entfernung duerfen 16
-- und 17 jaehrige auch nicht aktivieren koennen."
--
-- BISHER (Migration 138):
--
--   profile_distance_km(p_other) liefert die Entfernung, wenn
--   profiles.show_distance des anderen gesetzt ist. Diese Einstellung
--   durfte JEDER aktivieren - auch ein 16- oder 17-Jaehriger. Damit
--   konnte ein Minderjaehriger ueber die App mitteilen, wie weit weg
--   jemand wohnt.
--
-- ZWEI GETRENNTE SPERREN:
--
-- 1) IN DER DATENBANK (die maechtige)
--
--    Das Alter wird ueber public.profile_effective_age() bestimmt -
--    das verifizierte, wenn es eins gibt, sonst das deklarierte
--    (Migration 155). Das ist derselbe Massstab, den Discovery,
--    Transit Spark und die beidseitige Alterspruefung benutzen.
--
--    Die Sperre sitzt in der Funktion, die die Entfernung ausgibt -
--    nicht in der Einstellung. Eine Einstellung, die man per
--    gepatchtem Client setzen kann, ist keine Sperre. Der Server
--    weist die Anfrage ab, unabhaengig davon, was in profiles steht.
--
--    FAIL-CLOSED: Ein unbekanntes Alter (kein verifiziertes Alter UND
--    kein Geburtsdatum) gibt KEINE Entfernung preis. Das ist die
--    strengere Variante - bei public.profile_age() waere ein fehlendes
--    Geburtsdatum auf den 01.01.2000 gefallen, also auf 26 Jahre.
--
-- 2) IN DER APP (die freundliche)
--
--    Der Schalter "Entfernung anzeigen" ist fuer Minderjaehrige
--    gesperrt und zeigt den Grund. Sonst koennte ein 16-Jaehriger
--    den Schalter einschalten, und die Entfernung bliebe trotzdem
--    aus - das sieht nach einem Fehler aus.
--
--    Die App kennt nur das DEKLARIERTE Alter (das verifizierte steht
--    nicht im Profil des Nutzers). Fuer die Anzeige reicht das: die
--    Verifikation prueft das Video gegen die Altersangabe und laesst
--    Abweichungen ueber zwei Jahre nicht mehr automatisch durch. Die
--    Datenbank entscheidet ohnehin nach dem verifizierten Alter.
--
-- RUECKWAERTSKOMPATIBEL: Fuer Erwachsene aendert sich nichts. Ein
-- 18-Jaehriger, der die Entfernung anzeigt, sieht sie weiterhin.
--
-- HINWEIS: Die Spalte profiles.show_distance bleibt bestehen. Sie
-- steuert weiterhin, OB ein Erwachsener seine Entfernung zeigt. Nur
-- die Ausgabe fuer Minderjaehrige ist damit ausgeschlossen.
-- =============================================================================

BEGIN;

-- ===========================================================================
-- 1) Die Entfernungs-Ausgabe: kein Minderjaehriger gibt sie preis
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.profile_distance_km(p_other uuid)
RETURNS double precision
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path to 'public', 'pg_temp'
AS $function$
DECLARE
  v_distance float8;
BEGIN
  IF auth.uid() IS NULL OR p_other IS NULL OR p_other = auth.uid() THEN
    RETURN NULL;
  END IF;

  -- Trilaterations-Schutz: wiederholte Abfragen gegen dasselbe Opfer.
  -- FAIL-OPEN (109): kein Exception, nur NULL - der Rest der Seite
  -- funktioniert weiter.
  IF NOT public.consume_rate_limit(
       'dist_pair:' || auth.uid()::text || ':' || p_other::text, 60, 3600) THEN
    RETURN NULL;
  END IF;

  -- Einwilligung der ANDEREN Person. Ohne sie: keine Auskunft.
  --
  -- ZUSAETZLICH (v0.10.0, Migration 163): ein Minderjaehriger gibt
  -- auch dann keine Entfernung preis, wenn er die Einstellung
  -- gesetzt hat. Das Alter wird ueber profile_effective_age()
  -- bestimmt - das verifizierte, wenn es eins gibt, sonst das
  -- deklarierte (Migration 155).
  --
  -- FAIL-CLOSED: Das Alter wird HIER direkt aus birth_date und
  -- verified_age gebildet und nicht ueber public.profile_age()
  -- (das coalesct ein fehlendes Geburtsdatum auf den 01.01.2000 und
  -- damit auf 26 Jahre). Ein unbekanntes Alter gibt deshalb keine
  -- Entfernung preis.
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles o
     WHERE o.user_id = p_other
       AND o.show_distance
       AND coalesce(
             o.verified_age,
             CASE WHEN o.birth_date IS NOT NULL
                  THEN public.profile_age(o.birth_date) END
           ) >= 18
  ) THEN
    RETURN NULL;
  END IF;

  SELECT (round((6371 * acos(least(1.0,
             cos(radians(me.lat)) * cos(radians(o.lat))
             * cos(radians(o.lng) - radians(me.lng))
             + sin(radians(me.lat)) * sin(radians(o.lat))
           ))) / 5.0) * 5)::float8
    INTO v_distance
    FROM public.profile_locations me
    JOIN public.profile_locations o ON o.user_id = p_other
   WHERE me.user_id = auth.uid();

  RETURN v_distance;
END;
$function$;

COMMENT ON FUNCTION public.profile_distance_km(uuid) IS
  'Die Entfernung zwischen dem Aufrufer und p_other, auf 5 km gerundet. '
  'Voraussetzung: die andere Person hat show_distance gesetzt UND ist '
  'erwachsen (v0.10.0, Migration 163) - Minderjaehrige geben keine '
  'Entfernung preis. Das Alter ist das verifizierte, sonst das '
  'deklarierte (Migration 155). Ohne bekanntes Alter: keine Auskunft.';

REVOKE ALL ON FUNCTION public.profile_distance_km(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.profile_distance_km(uuid) TO authenticated;

-- ===========================================================================
-- 2) Selbsttest: die Sperre sitzt
-- ===========================================================================
DO $$
DECLARE
  v_typen text;
BEGIN
  -- Die Funktion muss die Alterspruefung enthalten. Ein reines
  -- 'show_distance' waere wieder die alte Fassung.
  SELECT pg_get_functiondef('public.profile_distance_km(uuid)'::regprocedure)
    INTO v_typen;

  IF v_typen IS NULL THEN
    RAISE EXCEPTION 'profile_distance_km fehlt.';
  END IF;

  IF v_typen NOT LIKE '%verified_age%'
     OR v_typen NOT LIKE '%profile_effective_age%'
     AND v_typen NOT LIKE '%profile_age%' THEN
    RAISE EXCEPTION
      'profile_distance_km prueft das Alter nicht - ein Minderjaehriger '
      'koennte weiterhin seine Entfernung preisgeben.';
  END IF;

  RAISE NOTICE 'profile_distance_km: Alterspruefung vorhanden (Selbsttest ok)';
END;
$$;

COMMIT;
