-- =============================================================================
-- 160_verification_video_retention.sql
-- =============================================================================
-- Die Datenschutzerklaerung verspricht seit Version 8, dass das
-- Verifikations-Video "nach spaetestens 30 Tagen nach Einreichung"
-- geloescht wird. Eingeloest war das nie: es gab keinen Cronjob, der
-- das Chiffrat nach einer Frist entfernt.
--
-- BEFUND (Security-Audit 24.10.2026, bei der Durchsicht der
-- Speicherfristen):
--
--   * Die Zusage stand in Abschnitt 2 der Erklaerung ("sonst nach
--     spaetestens 30 Tagen nach Einreichung (Abschnitt 7)") - und in
--     Abschnitt 7 fehlte sie sogar, weil der Satz dort zerbrochen war.
--   * Die Suche nach allen Cronjobs ergab genau drei: Transit-Signale,
--     Soft-Pings und Verifikations-Vorschauen. KEINER davon fasst das
--     Chiffrat an.
--   * Das Chiffrat ist personenbezogen: ein Video von Gesicht und
--     Stimme einer identifizierbaren Person, dauerhaft gespeichert.
--
-- Das ist die unguenstigste Form von Verletzung: Die Erklaerung sagt
-- es zu, und niemand haelt das ein. Bei einer Nachfrage zur
-- Speicherdauer waere die Antwort "das loescht keiner" - und das
-- waere nicht vertretbar.
--
-- DESHALB wird die Frist hier eingeloest, nicht die Zusage gestrichen.
-- Eine kuerzere Frist waere strenger, wuerde aber die Stichproben
-- fuer die Qualitaetssicherung (siehe verify-account, action=auto)
-- unmoeglich machen. 30 Tage sind der Wert, der in der Erklaerung
-- steht - und jetzt auch der Wert, der im Code steht.
--
-- Was geloescht wird:
--   * der Chiffrat `video.mp4.enc` im Bucket `verification-videos`
--   * der zugehoerige Schluessel aus `verification_video_keys`
--
-- Der Schluessel wird MIT geloescht: ein Schluessel ohne Chiffrat (oder
-- umgekehrt) ist ein halbes Paar - und genau das war der Grund, warum
-- Migration 151 beide getrennt haelt. Ein liegengebliebener Schluessel
-- waere die wertvollere Haelfte.
--
-- Die entschluesselte Vorschau fuer die Admin-Sichtung hat ihre eigene,
-- kuerzere Frist (20 Minuten, Migration 152). Die wird hier nicht
-- angefasst.
-- =============================================================================

BEGIN;

-- ===========================================================================
-- 1) Die Loeschfunktion
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.cleanup_verification_videos()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $cron$
DECLARE
  v_betroffene uuid[];
  v_anzahl integer := 0;
BEGIN
  -- Alle Chiffrate, die aelter als 30 Tage sind.
  --
  -- Der Namensfilter 'video.mp4.enc' greift bewusst NUR auf das
  -- eigentliche Verifikations-Video. Die Vorschau ('preview.mp4') hat
  -- ihre eigene Frist (20 Minuten, Migration 152) und wird hier nicht
  -- angefasst - sonst wuerde dieser Job die Vorschau ebenfalls
  -- einsammeln, obwohl sie juenger ist.
  SELECT coalesce(array_agg(
           (regexp_match(o.name, '^([^/]+)/'))[1]::uuid
         ), '{}'::uuid[])
    INTO v_betroffene
    FROM storage.objects o
   WHERE o.bucket_id = 'verification-videos'
     AND o.name LIKE '%/video.mp4.enc'
     AND o.created_at < now() - interval '30 days';

  IF array_length(v_betroffene, 1) IS NULL THEN
    RAISE NOTICE 'Keine Verifikations-Videos aelter als 30 Tage.';
    RETURN 0;
  END IF;

  -- 1) Das Chiffrat loeschen.
  DELETE FROM storage.objects
   WHERE bucket_id = 'verification-videos'
     AND name LIKE '%/video.mp4.enc'
     AND created_at < now() - interval '30 days';

  GET DIAGNOSTICS v_anzahl = ROW_COUNT;

  -- 2) Den Schluessel loeschen - nur fuer die Nutzer, deren Video
  --    gerade entfernt wurde. Sonst wuerde ein Schluessel verschwinden,
  --    dessen Chiffrat noch existiert (z. B. weil der Admin es sichert).
  DELETE FROM public.verification_video_keys k
   WHERE k.user_id = ANY(v_betroffene);

  RAISE NOTICE '% Verifikations-Video(s) aelter als 30 Tage geloescht.',
    v_anzahl;

  RETURN v_anzahl;
END;
$cron$;

COMMENT ON FUNCTION public.cleanup_verification_videos() IS
  'Loescht Verifikations-Videos (Chiffrat) und ihre Schluessel, wenn sie '
  'aelter als 30 Tage sind. Loest die Zusage der Datenschutzerklaerung '
  'ein (v0.10.0, Migration 160).';

REVOKE EXECUTE ON FUNCTION public.cleanup_verification_videos()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_verification_videos()
  TO service_role;

-- ===========================================================================
-- 2) Der Cronjob
-- ===========================================================================
-- Täglich um 04:20 - die Nachtstunde, in der auch die anderen
-- Aufräumjobs laufen (Location-Retention 03:xx, Transit-Signale 04:xx).
DO $schedule$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    RAISE WARNING 'pg_cron fehlt - Verifikations-Videos werden NICHT '
      'automatisch geloescht. Bitte manuell pruefen.';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'cleanup-verification-videos'
  ) THEN
    PERFORM cron.unschedule('cleanup-verification-videos');
  END IF;

  PERFORM cron.schedule(
    'cleanup-verification-videos',
    '20 4 * * *',
    $job$ SELECT public.cleanup_verification_videos(); $job$
  );
END;
$schedule$;

-- ===========================================================================
-- 3) Gegenprobe: der Job muss existieren
-- ===========================================================================
DO $check$
DECLARE
  v_anzahl integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    -- Ohne pg_cron gibt es nichts zu pruefen. Das ist kein Fehler des
    -- Deploys, aber es MUSS sichtbar sein - sonst glaubt man, die
    -- Frist wuerde eingehalten.
    RAISE WARNING 'pg_cron fehlt: die 30-Tage-Frist fuer '
      'Verifikations-Videos wird nicht automatisch eingeloest.';
    RETURN;
  END IF;

  SELECT count(*) INTO v_anzahl
    FROM cron.job
   WHERE jobname = 'cleanup-verification-videos';

  IF v_anzahl <> 1 THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: der Cronjob '
      'cleanup-verification-videos existiert nicht (% Treffer). Die in der '
      'Datenschutzerklaerung zugesagte 30-Tage-Loeschung des '
      'Verifikations-Videos waere nicht eingeloest.', v_anzahl;
  END IF;

  RAISE NOTICE 'Selbsttest bestanden: der Loeschjob fuer '
    'Verifikations-Videos ist eingerichtet.';
END;
$check$;

COMMIT;
