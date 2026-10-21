-- 151: Schluesseltabelle fuer das verschluesselte Verifikations-Video
--
-- BISHER lag das Video unverschluesselt im Bucket `verification-videos`.
-- Der Bucket ist privat, aber privat heisst nicht verschluesselt: wer
-- den Bucket lesen kann, hat die rohen MP4-Bytes - Gesicht und Stimme,
-- also biometrische Daten im Sinne Art. 9 DSGVO. Migration 149 hat
-- die Erwaehnung im Funktionsnamen, Migration 151 macht die
-- Verschluesselung wirklich.
--
-- JETZT:
--   * Das Geraet verschluesselt das Video mit AES-256-GCM und laedt
--     NUR den Chiffrat hoch (verification_service.dart,
--     VerificationCrypto).
--   * Der Schluessel geht getrennt an die Edge Function und landet
--     hier.
--   * Nur die Edge Function mit Admin-Status darf diese Tabelle
--     lesen. Fuer den Client ist sie vollstaendig unsichtbar - keine
--     Policy gibt anon oder authenticated etwas.
--
-- DESHALB KEINE CLIENT-POLICY
-- ----------------------------
-- In PostgreSQL gilt: ohne GRANT kein Zugriff, unabhaengig von RLS.
-- Es wird hier bewusst KEIN SELECT fuer authenticated angelegt - dann
-- sieht der Client die Tabelle nicht, auch nicht seine eigene Zeile.
-- Das ist strenger als "nur die eigene Zeile sichtbar" und genau
-- richtig: der Schluessel darf nicht durch den Client laufen.
--
-- Der Admin-Pfad laeuft ueber service_role in der Edge Function
-- `verification-media`, die den Admin-Status serverseitig prueft.

BEGIN;

CREATE TABLE IF NOT EXISTS public.verification_video_keys (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  -- Schluessel (32 Byte) und IV (12 Byte) als Base64.
  key_b64 text NOT NULL,
  iv_b64 text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.verification_video_keys IS
  'AES-256-GCM-Schluessel des Verifikations-Videos (v0.10.0, Migration 151). '
  'Der Chiffrat liegt im Bucket verification-videos, der Schluessel hier. '
  'Bewusst ohne Policy fuer anon/authenticated: der Client darf diese '
  'Tabelle nicht sehen. Nur service_role (Edge Function mit Admin-Check) '
  'liest sie. Beim Loeschen des Accounts faellt die Zeile ueber die '
  'Kaskade weg.';

ALTER TABLE public.verification_video_keys ENABLE ROW LEVEL SECURITY;

-- Keine Policies anlegen. Erklaerung im Kommentar oben.

-- GRANT (Migration 147 hat die Default-Privileges abgeschaltet: ohne
-- dieses GRANT ist die Tabelle auch fuer service_role nicht nutzbar).
GRANT ALL ON public.verification_video_keys TO service_role;

-- Der Cron, der alte Transit-Signale loescht, raeumt hier nichts
-- auf: die Schluessel gehoeren zur Einreichung und werden beim
-- Ablehnen (verify-account, action=review mit isVerified=false)
-- ausdruecklich geloescht. Hier steht nur die Absicherung, falls
-- das Ablehnen ausbleibt.

-- Gegenprobe: Der Client darf die Tabelle NICHT sehen.
DO $check$
DECLARE
  v_anon boolean;
  v_auth boolean;
BEGIN
  v_anon := has_table_privilege('anon', 'public.verification_video_keys'::regclass, 'SELECT');
  v_auth := has_table_privilege('authenticated', 'public.verification_video_keys'::regclass, 'SELECT');
  IF v_anon OR v_auth THEN
    RAISE EXCEPTION 'Die Schluesseltabelle ist fuer den Client sichtbar - '
      'das darf nicht sein (Migration 151).';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.verification_video_keys'::regclass, 'SELECT') THEN
    RAISE EXCEPTION 'service_role hat keinen Zugriff auf die Schluesseltabelle - '
      'die Sichtung durch den Admin waere nicht moeglich.';
  END IF;
END;
$check$;

COMMIT;
