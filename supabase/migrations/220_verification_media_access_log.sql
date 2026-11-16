-- 220_verification_media_access_log.sql
--
-- Sicherheits-Audit 16.11.2026 (P3): Das Verifikations-Video (ein
-- Ausweisdokument) wird serverseitig entschluesselt - der Schluessel
-- liegt in `verification_video_keys` (nur service_role). Das ist fuer
-- die Sichtung durch die Administration noetig (der Browser kann kein
-- Chiffrat abspielen), hat aber eine Luecke: BISHER war nicht
-- auffindbar, WER das Dokument entschluesselt hat.
--
-- Diese Migration schliesst die Luecke: Jede Entschluesselung wird
-- protokolliert. Damit ist nachvollziehbar, wer ein Ausweisdokument
-- angesehen hat - und ein Missbrauch faellt auf.
--
-- Die Tabelle ist keinclientsichtbar (keine Policies) - nur die
-- Administration liest sie (ueber service_role in der Edge Function
-- bzw. im Admin-Bereich).
--
-- Aufbewahrung: 90 Tage. Danach wird der Eintrag per Cron geloescht
-- (die Aussage "wer hat wann entschluesselt" ist danach nicht mehr
-- moeglich - das ist der Preis eines begrenzten Zeitfensters).

CREATE TABLE IF NOT EXISTS public.verification_media_access_log (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  admin_id    UUID NOT NULL,
  target_id   UUID NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Was wurde gemacht: 'decrypt' (Vorschau erzeugt).
  action      TEXT NOT NULL DEFAULT 'decrypt'
);

ALTER TABLE public.verification_media_access_log ENABLE ROW LEVEL SECURITY;

-- Bewusst KEINE Policies: der Client kann weder lesen noch schreiben.
-- Nur die Administration (service_role) greift zu.

COMMENT ON TABLE public.verification_media_access_log IS
  'Protokoll der Video-Entschluesselung durch die Administration '
  '(Audit 16.11.2026: ohne dieses Protokoll war nicht auffindbar, wer '
  'ein Ausweisdokument entschluesselt hat). Aufbewahrung 90 Tage.';

CREATE INDEX IF NOT EXISTS idx_verification_media_access_log_created
  ON public.verification_media_access_log (created_at);

-- ---------------------------------------------------------------------------
-- Aufraeumung: 90 Tage (Cron taeglich 05:30)
-- ---------------------------------------------------------------------------
DO $schedule$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    RAISE WARNING 'pg_cron fehlt - die Zugriffsprotokolle werden nicht '
      'automatisch geloescht. Bitte manuell pruefen.';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM cron.job
     WHERE jobname = 'cleanup-verification-media-access-log'
  ) THEN
    PERFORM cron.unschedule('cleanup-verification-media-access-log');
  END IF;

  PERFORM cron.schedule(
    'cleanup-verification-media-access-log',
    '30 5 * * *',
    $job$
      DO $inner$
      DECLARE
        v_anzahl integer;
      BEGIN
        DELETE FROM public.verification_media_access_log
         WHERE created_at < now() - interval '90 days';

        GET DIAGNOSTICS v_anzahl = ROW_COUNT;
        RAISE NOTICE '% Zugriffseintrag/-eintraege geloescht.', v_anzahl;
      END;
      $inner$;
    $job$
  );
END;
$schedule$;
