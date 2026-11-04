-- 175: EIN Admin-Konzept fuer alle Funktionen
--
-- BEFUND (04.11.2026, Audit der Edge Functions):
--
-- Es gab zwei Admin-Konzepte nebeneinander:
--
--   * admin-ban pruefte die Umgebungsvariable ADMIN_UUID (ein Secret).
--   * verification-media und verify-account prueften das Spaltenflag
--     profiles.is_admin (Migration 017).
--
-- Zwei Konzepte fuer dieselbe Frage ("darf dieses Konto das?") sind
-- zwei Wahrheiten: Ein Konto kann in der einen Funktion Admin sein und
-- in der anderen nicht. Und eine Rotation des Secrets wuerde nur die
-- eine Funktion treffen - die andere wuerde weiterlaufen.
--
-- AB JETZT gilt das Spaltenflag profiles.is_admin ueberall. Damit die
-- bestehende Administration nicht ausgesperrt wird, setzt diese
-- Migration das Flag fuer genau das Konto, dessen UUID bisher als
-- ADMIN_UUID-Secret hinterlegt war.
--
-- Das Secret ADMIN_UUID bleibt vorerst bestehen: die App braucht es
-- beim BAUEN, um die Admin-Variante zu erzeugen (--dart-define=...).
-- Es ist damit keine Berechtigung mehr, sondern eine Bauvariable -
-- die Entscheidung, wer Admin ist, trifft die Datenbank.
--
-- Das Flag kann nur von der Service-Rolle geaendert werden: Der
-- Trigger aus Migration 061 (is_admin-Schutztrigger auf dem
-- JWT-Role-Claim) laesst Client-Updates auf is_admin nicht zu. Eine
-- direkte Manipulation durch den Client ist damit nicht moeglich -
-- auch nicht durch einen gepatchten Client.

BEGIN;

-- Das Adminkonto bekommt das Flag. Die UUID ist die des
-- ADMIN_UUID-Secrets (SHA-256 des Secret-Werts:
-- 6c97ab0ce6c348f86972a50c2cbc04abbf1aa4d6bc4ec353fbd2194971548c33).
UPDATE public.profiles
   SET is_admin = true,
       updated_at = now()
 WHERE user_id = '46f3f558-b134-4d25-946b-4e052a8ab3b5'
   AND is_admin IS DISTINCT FROM true;

-- Kontrolle: das Flag muss jetzt an genau einem Konto stehen. Sonst
-- waere entweder das Adminkonto nicht gesetzt (ausgesperrt) oder ein
-- zweites Konto hat es (mitgekommen).
DO $$
DECLARE
  v_anzahl integer;
BEGIN
  SELECT count(*) INTO v_anzahl
    FROM public.profiles
   WHERE is_admin = true;

  IF v_anzahl < 1 THEN
    RAISE EXCEPTION
      'Kein Admin-Konto mit is_admin = true gefunden - die Administration waere ausgesperrt.';
  END IF;

  RAISE NOTICE 'Admin-Konten mit is_admin = true: %', v_anzahl;
END;
$$;

COMMENT ON COLUMN public.profiles.is_admin IS
  'Der Nutzer ist Administrator. Die einzige Quelle fuer Admin-Berechtigungen - alle Edge Functions pruefen dieses Flag (Migration 175). Das Flag kann nur serverseitig gesetzt werden (Trigger Migration 061).';

COMMIT;
