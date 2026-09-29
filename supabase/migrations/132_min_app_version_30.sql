-- =============================================================================
-- 132_min_app_version_30.sql
-- =============================================================================
-- Support-Fenster (v0.9.2, 2026-09-29):
--
-- Migration 130 hat `min_app_version_build = 29` gesetzt und im Kommentar
-- festgehalten: "v0.9.2 (Build 30) ist NICHT im Gate: der Wert wird beim
-- Release dieses Builds auf 30 angehoben, sobald 0.9.2 der unterstuetzte
-- Stand ist." Das ist jetzt der Fall.
--
-- WARUM 30 und nicht weiter 29 (NUTZERWUNSCH):
--   Der Support ab v0.9.2 ist hier keine Kosmetik, sondern Folge der
--   Alterssperre fuer Transit Spark (Migration 131). Aeltere Clients
--   enthalten diese Sperre nicht: Build 29 blendet Transit Spark fuer
--   Minderjaehrige lediglich per Hinweistext aus, statt es zu blockieren,
--   und der Server hat die RPCs ohne Alters-Gate ausgeliefert.
--
--   Solange Build 29 bedient wird, laeuft also mindestens ein Client im
--   Umlauf, ueber den sich die Sperre umgehen laesst - unabhaengig vom
--   Server, denn die alte App hat die Funktion gar nicht abgefragt. Der
--   einzig wirksame Weg ist, den alten Client zum Update zu schicken.
--
--   Damit gilt: Transit Spark ist ab Build 30 belastbar auf 18+ begrenzt.
--   Wer den Support frueher auf 0.9.1 setzt, muss die Sperre entweder
--   wieder aus dem Server nehmen (dann ist sie umgehbar) oder akzeptieren,
--   dass sie fuer installierte 0.9.1-Clients nicht gilt.
--
-- Gegenrichtung geprueft: Die 18+-Sperre in der Datenbank (131) gilt
-- unabhaengig von diesem Gate fuer JEDEN Aufruf der betroffenen RPCs.
-- Das Gate hier schliesst also keine bestehende Luecke, es verhindert nur,
-- dass die Funktion auf einem Client erreichbar bleibt, der sie gar nicht
-- erst abfragt. Beides wird gebraucht.
--
-- Schemahinweis: `app_config` hat ausschliesslich (key, value) - 034:52.
-- Es gibt KEINE `description`-Spalte, die Erklaerung gehoert hierher.
-- =============================================================================

INSERT INTO public.app_config (key, value)
VALUES ('min_app_version_build', '30')
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value;

-- BEWEIS (Fail-Fast): der Wert muss wirklich 30 sein. Sonst laeuft die
-- Migration durch, obwohl ein ALTER-Trigger oder ein Schreibfehler den
-- zurueckgesetzt haette - dann wuerden weiterhin 0.9.1-Clients bedient
-- und die Alterssperre waere fuer sie umgehbar.
DO $$
DECLARE
  v_val text;
BEGIN
  SELECT value INTO v_val FROM public.app_config WHERE key = 'min_app_version_build';
  IF v_val IS DISTINCT FROM '30' THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: min_app_version_build ist "%", erwartet "30".', v_val;
  END IF;
END;
$$;

-- Gegenprobe: die 18+-Sperre aus Migration 131 muss existieren, BEVOR
-- wir aeltere Builds aussperren. Fehlt sie, wuerde diese Migration den
-- Schutzzweck umkehren - wir sperrten dann die einzigen Clients, die
-- wenigstens eine Sperre hatten.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'transit_spark_adult'
  ) THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: public.transit_spark_adult() fehlt. '
      'Migration 131 (Transit Spark 18+) muss vor 132 laufen.';
  END IF;
END;
$$;
