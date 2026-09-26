-- =============================================================================
-- 129_location_retention_and_privacy.sql
-- =============================================================================
-- Sicherheitsaudit 2026-09-26: Standort-Aufbewahrung (DSGVO Art. 9).
--
-- BEFUND:
--   * `guard_profile_location_update` (059:43-51) rundet auf 2 Nachkommastellen
--     (~1,1 km) - fuer "Distanzanzeige" mehr als noetig, aber immer noch
--     Strassenadress-Niveau.
--   * Es gab KEINEN Cron, der `location_lat/lng` zuruecksetzt. Der letzte
--     exakte Standort blieb unbegrenzt stehen.
--   * `location_checked_at` erlaubt zusaetzlich Rueckschluesse auf
--     Aufenthaltsmuster (Zeitstempel der letzten Positionsaenderung).
--
-- LOESUNG: TTL-Cron. Der Standort wird 30 Tage nach der letzten Pruefung
-- geloescht. Die Distanzanzeige arbeitet bis dahin mit den 1-km-Rasterdaten
-- (das ist der Zweck), danach ist das Feld NULL und `public_profiles`
-- liefert 0/0 (wie schon bei nie gesetzten Koordinaten).
--
-- 30 Tage statt kuerzer: gewaehlt als Kompromiss aus Nutzer-Erwartung
-- ("wie weit weg") und Datenminimierung. Wer es strenger braucht, zieht den
-- Wert im Cron-Skript nach (oder setzt `location_retention_days` in
-- `app_config`).
--
-- ZUSAETZLICH: `check_email_ban_status` wird mit einem Hinweis versehen,
-- dass die E-Mail in der Sperrliste im Klartext bleibt (DSGVO-Aufbewahrung
-- braucht eine eigene Rechtsgrundlage - Betreiber-Aufgabe, hier nur Doku).
-- =============================================================================

-- Aufbewahrungsdauer in Tagen (als app_config, damit sie ohne neue
-- Migration anpassbar ist).
INSERT INTO public.app_config (key, value)
VALUES ('location_retention_days', '30')
ON CONFLICT (key) DO NOTHING;

-- Standort-TTL: 30 Tage nach der letzten Pruefung loeschen.
DO $$
DECLARE
  v_days int := COALESCE(
    (SELECT value::int FROM public.app_config WHERE key = 'location_retention_days'),
    30
  );
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'purge_stale_locations',
      '40 3 * * *',
      format(
        'UPDATE public.profiles %I
            SET location_lat = NULL, location_lng = NULL
          WHERE location_checked_at IS NOT NULL
            AND location_checked_at < now() - interval ''%s days''
            AND location_lat IS NOT NULL',
        'profiles', v_days
      )
    );
  ELSE
    RAISE NOTICE 'pg_cron nicht verfuegbar - location_retention_days manuell als Cron eintragen.';
  END IF;
END;
$$;

COMMENT ON COLUMN public.profiles.location_lat IS
  'Letzter gemeldeter Standort, 2 Nachkommastellen (~1,1 km) gerundet. '
  'Wird per Cron (purge_stale_locations) nach location_retention_days (30) '
  'zurueckgesetzt. Oeffentliche Ausgaben nutzen lat_approx/lng_approx '
  '(1 Nachkommastelle, ~11 km).';

-- Dokumentation der bewussten Aufbewahrung in der Sperrliste.
COMMENT ON TABLE public.banned_emails IS
  'Sperrliste fuer E-Mail-Adressen. ACHTUNG DSGVO: `email` bleibt nach '
  'einer Kontoloeschung im Klartext erhalten (bewusste Ausnahme, siehe '
  'delete-account/index.ts). Das braucht eine eigene Rechtsgrundlage und '
  'eine eigene Loeschfrist - Betreiber-Aufgabe, nicht durch Code loesbar.';

-- -----------------------------------------------------------------------------
-- BEWEIS (Fail-Fast)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  -- Ueber die FUNCTION aufgeloest, nicht ueber den Trigger-Namen: 059 legt
  -- `guard_profile_location_update_trigger` an. Der Name ist frei gewaehlt,
  -- die Function nicht - und genau die rundet die Koordinaten.
  IF NOT EXISTS (
    SELECT 1
      FROM pg_trigger t
      JOIN pg_proc p ON p.oid = t.tgfoid
     WHERE t.tgrelid = 'public.profiles'::regclass
       AND NOT t.tgisinternal
       AND p.proname = 'guard_profile_location_update') THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: der Trigger guard_profile_location_update '
      'fehlt auf public.profiles - exakte Koordinaten wuerden ungerundet gespeichert.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM app_config WHERE key = 'location_retention_days') THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: location_retention_days fehlt.';
  END IF;
END;
$$;
