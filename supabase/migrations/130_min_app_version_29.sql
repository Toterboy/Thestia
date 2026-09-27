-- =============================================================================
-- 130_min_app_version_29.sql
-- =============================================================================
-- Sicherheit/Support (v0.9.2, 2026-09-27):
--
-- `app_config.min_app_version_build` steuert, welche Clients der Server noch
-- bedient. Migration 076 hat den Wert mit '9' eingefuegt; die RELEASE_NOTES
-- von v0.9.1 sagten woertlich, er SOLLTE auf 29 angehoben werden - das ist
-- aus dem Release offen geblieben. Die Doku war sich uneinig (SECURITY.md
-- 29, SUPPORT.md 28, Migration 9), der Serverwert wurde nie nachgezogen.
--
-- BETREIBERENTSCHEIDUNG (2026-09-27): Support ab v0.9.1, also Build 29.
-- Damit werden aeltere Clients (WispDating-Builds, 0.7.x, 0.8.x) zum
-- Update gezeigt, statt gegen eine nicht mehr gepflegte Serverlogik zu
-- laufen. 0.9.1 selbst bleibt unterstuetzt.
--
-- Schemahinweis: `app_config` hat ausschliesslich (key, value) - 034:52.
-- Es gibt KEINE `description`-Spalte, die Erklaerung gehoert hierher.
--
-- v0.9.2 (Build 30) ist NICHT im Gate: der Wert wird beim Release dieses
-- Builds auf 30 angehoben, sobald 0.9.2 der unterstuetzte Stand ist.
-- =============================================================================

INSERT INTO public.app_config (key, value)
VALUES ('min_app_version_build', '29')
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value;

-- BEWEIS (Fail-Fast): der Wert muss wirklich 29 sein. Sonst laeuft die
-- Migration durch, obwohl ein ALTER-Trigger oder ein Schreibfehler den
-- zurueckgesetzt haette.
DO $$
DECLARE
  v_val text;
BEGIN
  SELECT value INTO v_val FROM public.app_config WHERE key = 'min_app_version_build';
  IF v_val IS DISTINCT FROM '29' THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: min_app_version_build ist "%", erwartet "29".', v_val;
  END IF;
END;
$$;
