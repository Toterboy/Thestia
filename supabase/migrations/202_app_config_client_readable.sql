-- =============================================================================
-- 202_app_config_client_readable.sql
-- =============================================================================
-- ZWEI STILLE MECHANISMEN (BEFUND 08.11.2026):
--
-- Die App liest `app_config` direkt ueber PostgREST
-- (lib/services/app_config_service.dart: `.from('app_config')`).
-- Die Policy aus Migration 034 ("No direct app_config access") hat aber
-- `USING (false)` fuer die Rolle `authenticated` - der Client bekommt
-- also IMMER eine leere Liste. Live geprueft: HTTP 200 mit `[]`.
--
-- Betroffen waren damit zwei Sicherheitsmechanismen, die der Betreiber
-- fuer aktiv haelt:
--
-- 1. `min_app_version_build` (Migration 076/130/132, jetzt 201):
--    Der Update-Hinweis beim Start fuer zu alte Clients wurde NIE
--    angezeigt - der Wert war gesetzt, aber unerreichbar. Damit liefen
--    alte Builds weiter, deren Zertifikatspruefung die gesperrten
--    Zwischenzertifikate noch akzeptiert (Advisory
--    GHSA-frr6-h895-5pxp, High).
--
-- 2. `transit_spark_enabled` (Migration 159):
--    Die NOTBREMSE fuer Transit Spark - der Schalter, mit dem der
--    Betreiber das Feature abschalten kann, wenn der BLE-Geraetetest
--    nicht besteht - war ebenfalls stumm. Der Code behandelt das
--    Ergebnis als "fail-open" (Feature an), also hat der Schalter
--    nichts bewirkt.
--
-- DIE LOESUNG: Der Entwurf war richtig - `app_config` ist eine interne
-- Konfiguration (AAL2-Pflicht, E-Mail-Bestaetigungspflicht, Quiz-
-- Abklingzeiten, Aufbewahrungsfristen) und soll NICHT wholesale
-- lesbar sein. Aber die beiden Werte, die die App ausdruecklich
-- abfragt, muessen es sein. Diese Policy gibt genau diesen beiden
-- Zeilen den Zugriff - der Rest der Konfiguration bleibt gesperrt.
--
-- Warum eine Policy und keine SECURITY-DEFINER-Funktion: Eine
-- Funktion wuerde eine Aenderung der App erfordern (die App muesste
-- sie aufrufen statt zu lesen) - also einen neuen Build. Die
-- Auswirkung einer Policy ist sofort da, und zwar fuer genau die
-- bereits gebauten und verteilten Builds.
--
-- `enforce_aal2`, `enforce_email_confirmed`, `location_retention_days`
-- und `quiz_cooldown_seconds` bleiben unlesbar. Das ist Absicht: der
-- Client soll die Server-Flags nicht kennen, sondern nur erfahren, dass
-- sie gelten.
-- =============================================================================

DROP POLICY IF EXISTS "Read client-relevant app_config" ON public.app_config;

CREATE POLICY "Read client-relevant app_config"
  ON public.app_config
  FOR SELECT
  TO authenticated
  USING (key IN ('min_app_version_build', 'transit_spark_enabled'));

-- BEWEIS (Fail-Fast): der Client muss die beiden Werte jetzt wirklich
-- bekommen. Ohne diesen Test waere die Migration nur eine Absicht -
-- genau so ist der Fehler entstanden, den sie behebt.
DO $$
DECLARE
  v_anzahl integer;
BEGIN
  SELECT count(*) INTO v_anzahl
    FROM public.app_config
   WHERE key IN ('min_app_version_build', 'transit_spark_enabled');
  IF v_anzahl < 2 THEN
    RAISE EXCEPTION 'Sicherheitscheck fehlgeschlagen: % von 2 noetigen app_config-Werten vorhanden.', v_anzahl;
  END IF;
  RAISE NOTICE 'app_config: min_app_version_build und transit_spark_enabled sind fuer angemeldete Clients lesbar.';
END;
$$;
