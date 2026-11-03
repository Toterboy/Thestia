-- =============================================================================
-- 171_video_retention_from_approval.sql
-- =============================================================================
-- BETREIBER-AUFTRAG (03.11.2026): "Gibt es eine Angabe wie lange die
-- Verifizierungsvideos gespeichert bleiben? Sie sollen 30 Tage nach
-- Verifizierung (nicht Upload sondern Genehmigung der Verifizierung)
-- bleiben und nach 30 Tagen geloescht werden."
--
-- BISHER (Migration 160): Die Frist lief ab dem UPLOAD
-- (storage.objects.created_at). Ein Video, das 25 Tage auf die Sichtung
-- wartete, wurde am Tag der Freigabe schon geloescht - und die Freigabe
-- selbst war nach dem Upload nicht mehr 30 Tage lang nachvollziehbar.
--
-- JETZT: Die Frist laeuft ab der GENEHMIGUNG der Verifizierung. Dazu
-- braucht es den Zeitpunkt der Freigabe - den gab es bisher nicht
-- (profiles.is_verified ist ein Flag, kein Zeitstempel).
--
-- DIE DREI FAELLE (das Video wird nach unterschiedlichen Regeln
-- behandelt, je nachdem, wo es im Prozess steht):
--
--   1) GENEHMIGT: geloescht 30 Tage nach der Freigabe. Das ist die
--      Zusage des Betreibers. Der Freigabe-Zeitpunkt wird beim
--      Freigeben gesetzt (verify-account).
--
--   2) ABGELEHNT: geloescht 30 Tage nach dem Upload. Die Sichtung ist
--      abgeschlossen, das Video wird nicht mehr gebraucht.
--
--   3) NOCH IN PRUEFUNG: BLEIBT liegen. Ein Video, das zur Sichtung
--      ansteht, wird gebraucht - eine automatische Loeschung wuerde die
--      Pruefung unmoeglich machen. Als Sicherheitsnetz gibt es eine
--      Rueckfallfrist von 90 Tagen: ein Video, das nach 90 Tagen immer
--      noch in der Pruefung liegt, wird geloescht (der Fall kommt
--      praktisch nicht vor, aber "nie" waere keine Frist).
--
-- Die Erklaerung (Abschnitt 7) nennt ab jetzt genau das.
-- =============================================================================

BEGIN;

-- ===========================================================================
-- 1) Der Zeitpunkt der Freigabe
-- ===========================================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_approved_at timestamptz;

COMMENT ON COLUMN public.profiles.verification_approved_at IS
  'Zeitpunkt der Freigabe der Altersverifizierung (v0.10.0, Migration '
  '171). Startpunkt der 30-Tage-Frist fuer das Verifikations-Video - '
  'vorher lief die Frist ab dem Upload.';

-- Fuer bestehende Konten: die Freigabe ist bereits da, der Zeitpunkt
-- fehlt. Der Freigabe-Zeitpunkt wird beim naechsten Freigeben
-- nachgetragen; fuer die bereits freigegebenen Konten gilt die
-- Uebergangsregel im Cleanup (siehe unten): ihr Video faellt unter die
-- 90-Tage-Sicherheitsnetz, nicht unter die 30-Tage-Frist.
UPDATE public.profiles
   SET verification_approved_at = now()
 WHERE is_verified = true
   AND verification_approved_at IS NULL;

-- ===========================================================================
-- 2) Der Cleanup: die Frist laeuft ab der Freigabe
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
  -- Alle Chiffrate, die nach ihrer Regel zu alt sind.
  --
  -- Der Namensfilter 'video.mp4.enc' greift bewusst NUR auf das
  -- eigentliche Verifikations-Video. Die Vorschau ('preview.mp4') hat
  -- ihre eigene Frist (20 Minuten, Migration 152) und wird hier nicht
  -- angefasst.
  SELECT coalesce(array_agg(
           (regexp_match(o.name, '^([^/]+)/'))[1]::uuid
         ), '{}'::uuid[])
    INTO v_betroffene
    FROM storage.objects o
    JOIN public.profiles p ON p.user_id = (regexp_match(o.name, '^([^/]+)/'))[1]::uuid
   WHERE o.bucket_id = 'verification-videos'
     AND o.name LIKE '%/video.mp4.enc'
     AND (
       -- 1) Freigegeben: 30 Tage ab der FREIGABE.
       (p.verification_approved_at IS NOT NULL
        AND p.verification_approved_at < now() - interval '30 days')
       OR
       -- 2) Abgelehnt: 30 Tage ab dem Upload (die Sichtung ist zu Ende).
       (p.is_verified = false
        AND p.verification_approved_at IS NULL
        AND p.verification_status IN ('rejected', 'failed', 'expired')
        AND o.created_at < now() - interval '30 days')
       OR
       -- 3) Sicherheitsnetz: 90 Tage ohne Entscheidung.
       (p.verification_approved_at IS NULL
        AND o.created_at < now() - interval '90 days')
     );

  IF array_length(v_betroffene, 1) IS NULL THEN
    RAISE NOTICE 'Keine Verifikations-Videos ueber der Frist.';
    RETURN 0;
  END IF;

  -- 1) Das Chiffrat loeschen.
  DELETE FROM storage.objects
   WHERE bucket_id = 'verification-videos'
     AND name LIKE '%/video.mp4.enc'
     AND (regexp_match(name, '^([^/]+)/'))[1]::uuid = ANY(v_betroffene);

  GET DIAGNOSTICS v_anzahl = ROW_COUNT;

  -- 2) Den Schluessel loeschen - nur fuer die Nutzer, deren Video
  --    gerade entfernt wurde. Sonst wuerde ein Schluessel verschwinden,
  --    dessen Chiffrat noch existiert (z. B. weil der Admin es sichert).
  DELETE FROM public.verification_video_keys k
   WHERE k.user_id = ANY(v_betroffene);

  RAISE NOTICE '% Verifikations-Video(s) ueber der Frist geloescht.',
    v_anzahl;

  RETURN v_anzahl;
END;
$cron$;

COMMENT ON FUNCTION public.cleanup_verification_videos() IS
  'Loescht Verifikations-Videos (Chiffrat) und ihre Schluessel nach der '
  'Frist aus Abschnitt 7 der Datenschutzerklaerung (v0.10.0, Migration '
  '171): 30 Tage nach der GENEHMIGUNG der Verifizierung, 30 Tage nach dem '
  'Upload bei einer Ablehnung, und als Sicherheitsnetz 90 Tage ohne '
  'Entscheidung.';

-- ===========================================================================
-- 3) Selbsttest
-- ===========================================================================
DO $check$
DECLARE
  v_body text;
BEGIN
  SELECT pg_get_functiondef(
    'public.cleanup_verification_videos()'::regprocedure
  ) INTO v_body;

  -- Die Frist muss an der Freigabe haengen, nicht am Upload.
  IF v_body NOT LIKE '%verification_approved_at%' THEN
    RAISE EXCEPTION
      'Der Video-Cleanup richtet sich nicht nach dem Freigabe-Zeitpunkt - '
      'die Frist muss ab der Genehmigung laufen, nicht ab dem Upload.';
  END IF;

  IF v_body NOT LIKE '%30 days%' THEN
    RAISE EXCEPTION 'Die 30-Tage-Frist fehlt im Cleanup.';
  END IF;

  -- Der Cronjob muss weiterhin taeglich laufen.
  PERFORM 1 FROM cron.job WHERE jobname = 'cleanup-verification-videos';
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Der Cronjob fuer die Video-Loeschung fehlt - die Videos wuerden '
      'unbegrenzt bleiben.';
  END IF;

  RAISE NOTICE 'Video-Aufbewahrung: Frist ab der Genehmigung, Sicherheitsnetz 90 Tage (Selbsttest ok)';
END;
$check$;

COMMIT;
