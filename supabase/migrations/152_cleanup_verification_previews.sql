-- 152: Klartext-Vorschauen des Verifikations-Videos aufraeumen
--
-- Die Edge Function `verification-media` legt bei der Sichtung durch den
-- Admin eine Klartext-Kopie ab (`<user_id>/preview.mp4`), weil der
-- Browser kein Chiffrat abspielen kann. Der Dauerzustand im Bucket
-- ist damit ausschliesslich Chiffrat - die Vorschau ist ein kurzlebiges
-- Arbeitsprodukt.
--
-- OHNE diesen Cron blieben die Klartextkopien liegen. Das waere genau
-- das Problem, das die Verschluesselung loesen soll: ein unabhaengiger
-- Zugriff auf den Bucket gaelte ein Video im Klartext.
--
-- Frist: 20 Minuten. Das reicht fuer den Blick des Admins, und die
-- signierte URL gilt nur 10 Minuten - die Vorschau ist also ohnehin
-- laenger nutzbar als der Link.
--
-- Der Ordnerpfad laesst sich nicht nach Alter filtern, weil
-- storage.objects die Zeit aus dem Objekt fuehrt. Die Vorschauen werden
-- deshalb ueber ihr Objektalter gesucht.

BEGIN;

DO $cron$
DECLARE
  v_alte uuid[];
  v_anzahl int;
BEGIN
  -- Alle Vorschauen, die aelter als 20 Minuten sind.
  SELECT coalesce(array_agg(id), '{}'::uuid[])
    INTO v_alte
    FROM storage.objects
   WHERE bucket_id = 'verification-videos'
     AND name LIKE '%/preview.mp4'
     AND created_at < now() - interval '20 minutes';

  IF array_length(v_alte, 1) IS NULL THEN
    RAISE NOTICE 'Keine alten Vorschauen zum Loeschen.';
    RETURN;
  END IF;

  DELETE FROM storage.objects
   WHERE bucket_id = 'verification-videos'
     AND id = ANY(v_alte);

  GET DIAGNOSTICS v_anzahl = ROW_COUNT;
  RAISE NOTICE '% Vorschau(en) geloescht.', v_anzahl;
END;
$cron$;

-- Der Job laeuft alle 5 Minuten.
DO $schedule$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    RAISE WARNING 'pg_cron fehlt - die Vorschauen werden nicht automatisch '
      'geloescht. Bitte manuell pruefen.';
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-verification-previews') THEN
    PERFORM cron.unschedule('cleanup-verification-previews');
  END IF;

  PERFORM cron.schedule(
    'cleanup-verification-previews',
    '*/5 * * * *',
    $job$
      DO $inner$
      DECLARE
        v_alte uuid[];
      BEGIN
        SELECT coalesce(array_agg(id), '{}'::uuid[])
          INTO v_alte
          FROM storage.objects
         WHERE bucket_id = 'verification-videos'
           AND name LIKE '%/preview.mp4'
           AND created_at < now() - interval '20 minutes';

        IF array_length(v_alte, 1) IS NOT NULL THEN
          DELETE FROM storage.objects
           WHERE bucket_id = 'verification-videos'
             AND id = ANY(v_alte);
        END IF;
      END;
      $inner$;
    $job$
  );
END;
$schedule$;

COMMIT;
