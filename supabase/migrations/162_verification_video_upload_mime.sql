-- =============================================================================
-- 162_verification_video_upload_mime.sql
-- =============================================================================
-- Das Verifikationsvideo erreicht den Adminbereich nicht.
--
-- BEFUND (01.11.2026): "Die Videoverifizierung kommt im Admin Bereich
-- irgendwie nicht an."
--
-- ZWEI URSACHEN, beide im Storage:
--
-- 1) DIE MIME-WHITELIST (der eigentliche Grund)
--
--    Migration 052 legt den Bucket 'verification-videos' mit
--    allowed_mime_types = array['video/mp4'] an. Seit v0.10.0
--    (Migration 151) liegt das Video aber VERSCHLUESSELT im Bucket -
--    der Client laedt es als 'application/octet-stream' hoch
--    (supabase_storage_service.dart). Der Inhalt ist Chiffrat, kein
--    abspielbares Video.
--
--    Die Storage-API prueft die Whitelist gegen den Content-Type des
--    Uploads. 'application/octet-stream' steht nicht auf der Liste ->
--    der Upload wird mit HTTP 400 abgelehnt.
--
--    DIESER FEHLER IST NICHT NEU - er ist entstanden, als das Video
--    verschluesselt wurde (Migration 151, 22.10.2026). Und er ist
--    genau derselbe Fehler, der im September 2026 die Intro-Audio-
--    Uploads zum Schweigen gebracht hat: der avatars-Bucket erlaubte
--    nur Bild-MIME-Typen, der Upload wurde still verworfen. Migration
--    088 hat ihn fuer 'avatars' behoben - fuer
--    'verification-videos' wurde er nie behoben.
--
--    Warum es unentdeckt blieb: der Client faengt den Fehler und
--    meldet "lokal pending" (verification_service.dart). Die App sagt
--    "Video eingereicht!" - aber im Bucket liegt nichts, in
--    verification_video_keys steht kein Schluessel, und der Fall
--    erscheint nie in admin_list_pending_verifications.
--
--    'video/mp4' bleibt auf der Liste: ein Altbestand aus der Zeit
--    vor der Verschluesselung kann noch unverschluesselt liegen und
--    muss weiterhin lesbar sein.
--
-- 2) DIE FEHLENDE UPDATE-POLICY
--
--    Der Upload laeuft mit upsert: true, damit die Einreichung nach
--    einer Ablehnung wiederholbar ist. Migration 052 legt aber
--    bewusst NUR INSERT, SELECT und DELETE fest ("Keine UPDATE-Policy",
--    Zeile 76). Jeder ZWEITE Upload desselben Nutzers scheitert
--    deshalb an der Berechtigung - der Kommentar im Client
--    ("Upsert macht die Einreichung wiederholbar") stimmt also
--    nicht.
--
--    Die Policy ist eng gefasst: nur der eigene Ordner
--    (erste Pfadkomponente = User-ID), nur dieser Bucket.
--
-- HINWEIS: KEIN "COMMENT ON storage.buckets ..." - die Tabelle
-- gehoert dem Storage-Admin; COMMENT verlangt Eigentuemerschaft und
-- bricht die Migration mit 42501 ab. Siehe Migration 088, Zeile 29-32.
-- =============================================================================

BEGIN;

-- ===========================================================================
-- 1) Der Bucket akzeptiert das Chiffrat
-- ===========================================================================
UPDATE storage.buckets
   SET allowed_mime_types = ARRAY[
         'video/mp4',              -- Altbestand vor der Verschluesselung
         'application/octet-stream' -- Chiffrat (v0.10.0, Migration 151)
       ]
 WHERE id = 'verification-videos';

-- ===========================================================================
-- 2) UPDATE-Policy: die erneute Einreichung ist moeglich
-- ===========================================================================
drop policy if exists "verification update own" on storage.objects;
create policy "verification update own"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'verification-videos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'verification-videos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ===========================================================================
-- 3) Selbsttest: die Whitelist muss das Chiffrat zulassen
-- ===========================================================================
DO $$
DECLARE
  v_typen text[];
BEGIN
  SELECT allowed_mime_types INTO v_typen
    FROM storage.buckets WHERE id = 'verification-videos';

  IF v_typen IS NULL THEN
    RAISE EXCEPTION
      'Bucket verification-videos fehlt - der Video-Upload kann nicht '
      'funktionieren.';
  END IF;

  IF NOT ('application/octet-stream' = ANY(v_typen)) THEN
    RAISE EXCEPTION
      'Bucket verification-videos erlaubt application/octet-stream '
      'nicht - jeder verschluesselte Video-Upload wird abgelehnt. '
      'Gefunden: %', array_to_string(v_typen, ',');
  END IF;

  RAISE NOTICE
    'verification-videos erlaubt jetzt: % (Selbsttest ok)',
    array_to_string(v_typen, ',');
END;
$$;

COMMIT;
