-- =============================================================================
-- 143_location_retention_cron.sql
-- =============================================================================
-- Nachbesserung an 138/142: der Standort-TTL laeuft nicht mehr.
--
-- BEFUND:
--
--   Migration 129 hat per pg_cron einen Job `purge_stale_locations`
--   angelegt (taeglich 03:40) mit genau diesem SQL:
--
--     UPDATE public.profiles
--        SET location_lat = NULL, location_lng = NULL
--      WHERE location_checked_at IS NOT NULL
--        AND location_checked_at < now() - interval '30 days'
--        AND location_lat IS NOT NULL
--
--   Migration 138 hat location_lat/location_lng aus profiles entfernt.
--   Der Job laeuft seitdem naechlich in einen Fehler ("column location_lat
--   does not exist") - genauer: der Lauf schlaegt fehl, es wird nichts
--   geloescht.
--
--   Zwei Folgen, und die zweite ist die schlimmere:
--
--     1. Der Job erzeugt jeden Tag einen Fehler im Cron-Log. Stoert,
--        aber sichtbar - man kann es uebersehen.
--     2. Die in der Datenschutzerklaerung zugesagte Loeschung nach
--        location_retention_days (30) findet nicht mehr statt. Die
--        Koordinaten in profile_locations bleiben unbegrenzt stehen.
--        Das ist eine echte Verschlechterung gegenueber dem Stand vor
--        138 und widerspricht einem zugesagten Text.
--
--   Warum 142 das nicht gefunden hat: die Pruefung 3 dort durchsucht
--   pg_proc nach Verweisen auf die Spalten. Ein per cron.schedule()
--   registrierter Auftrag ist eine Zeile in cron.job.command - kein
--   Funktionskoerper. Der Cron stand damit ausserhalb des Pruefrahmens.
--
-- LOESUNG:
--
--   Der alte Job wird abgemeldet und durch einen ersetzt, der auf
--   profile_locations wirkt. Massgebliche Zeit ist `updated_at` in
--   profile_locations - nicht location_checked_at aus profiles: die
--   Koordinaten-Tabelle wird bei jedem Standortschreiben aktualisiert
--   (der Guard aus 137 setzt updated_at auch beim UPDATE), damit ist
--   sie die Zeit, zu der der gespeicherte Standort tatsaechlich
--   gesetzt wurde. location_checked_at haengt am Edge Function-Pfad und
--   bleibt stehen, wenn dieser ausfaellt.
--
--   Geloescht wird die Zeile, nicht auf NULL gesetzt: es gibt in
--   profile_locations genau eine Zeile pro Nutzer (user_id ist
--   Primaerschluessel). NULL koennte man dort gar nicht ausdruecken,
--   ohne die Zeile zu loeschen - das waere der gleiche Unterschied wie
--   bei profiles.
--
--   Einmalige Bereinigung: profile_locations kann nach 138 Eintraege
--   enthalten, die nie unter die 30-Tage-Regel fielen. Die werden hier
--   mitgenommen, damit die Zusage ab sofort auch fuer Bestandsdaten
--   gilt. Wie viele es waren, steht als NOTICE im Log.
--
-- Rueckbau:
--   SELECT cron.unschedule('purge_stale_locations');
-- =============================================================================

DO $$
DECLARE
  v_jobid bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE
      'pg_cron nicht verfuegbar - Standort-TTL muss manuell als Cron eingetragen werden.';
    RETURN;
  END IF;

  -- Alten Job abmelden, falls vorhanden. cron.unschedule wirft bei
  -- unbekanntem Namen, deshalb vorher nachsehen.
  FOR v_jobid IN SELECT jobid FROM cron.job WHERE jobname = 'purge_stale_locations'
  LOOP
    PERFORM cron.unschedule(v_jobid);
  END LOOP;

  -- Einmalige Bereinigung der Bestandsdaten.
  WITH deleted AS (
    DELETE FROM public.profile_locations
     WHERE updated_at < now() - interval '30 days'
    RETURNING 1
  )
  SELECT count(*) INTO v_jobid FROM deleted;

  IF v_jobid > 0 THEN
    RAISE NOTICE
      '% Standort(e) aelter als 30 Tage entfernt (Einmalbereinigung).',
      v_jobid;
  ELSE
    RAISE NOTICE 'Keine Bestandsdaten aelter als 30 Tage.';
  END IF;

  -- Neuer Job, gleicher Name und gleiche Uhrzeit, damit ein Betrachter
  -- des Cron-Logs keine zweite Sorte Job sieht.
  PERFORM cron.schedule(
    'purge_stale_locations',
    '40 3 * * *',
    format(
      'DELETE FROM public.profile_locations %I
        WHERE updated_at < now() - interval ''%s days''',
      'profile_locations',
      COALESCE(
        (SELECT value FROM public.app_config WHERE key = 'location_retention_days'),
        '30'
      )
    )
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- Selbsttest: der Job darf nicht mehr auf die entfernten Spalten zeigen,
-- und er muss die neue Tabelle nennen.
--
-- Geprueft wird cron.job.command - der Auftrag ist ein String, dort gibt
-- es keinen Kommentar, der etwas verfaelschen koennte.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_cmd text;
  v_count integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'Selbsttest uebersprungen (kein pg_cron).';
    RETURN;
  END IF;

  SELECT count(*) INTO v_count
    FROM cron.job
   WHERE jobname = 'purge_stale_locations';

  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'Es gibt % Jobs mit dem Namen purge_stale_locations, erwartet genau 1.',
      v_count;
  END IF;

  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'purge_stale_locations';

  IF v_cmd LIKE '%location_lat%' OR v_cmd LIKE '%location_lng%' THEN
    RAISE EXCEPTION
      'Der Cron-Job greift noch auf die entfernten Spalten zu: %', v_cmd;
  END IF;

  IF v_cmd NOT LIKE '%profile_locations%' THEN
    RAISE EXCEPTION
      'Der Cron-Job loescht nicht aus profile_locations: %', v_cmd;
  END IF;

  IF v_cmd NOT LIKE '%location_retention_days%' THEN
    RAISE NOTICE
      'Hinweis: der Job nennt die Konfiguration nicht - er nutzt einen festen Wert.';
  END IF;

  RAISE NOTICE
    'Standort-TTL laeuft wieder (pg_cron, taeglich 03:40, % Tage).',
    COALESCE(
      (SELECT value FROM public.app_config WHERE key = 'location_retention_days'),
      '30'
    );
END;
$$;