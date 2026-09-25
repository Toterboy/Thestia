-- ============================================================================
-- Plattform-Sperre (Ban) verwalten - Migration 045
--
-- Bannt eine E-Mail-Adresse: Der Nutzer kann sich weder neu registrieren
-- (serverseitig erzwungen via handle_new_user) noch einloggen (Client-Check).
-- Stattdessen sieht er nur noch den Entsperrungs-Flow (request-unban).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Account sperren (E-Mail in banned_emails eintragen)
--
-- WICHTIG: Bestehende Accounts zusätzlich löschen (DSGVO-konform und
-- verhindert halb-aktive Sessions), z. B. über die App selbst
-- (Settings -> Account löschen) oder die Edge Function delete-account.
-- ---------------------------------------------------------------------------
INSERT INTO public.banned_emails (email, reason, banned_by)
VALUES (
  'nutzer@beispiel.de',
  'Wiederholter Verstoß gegen die Community-Richtlinien',
  'admin'
)
ON CONFLICT (email) DO UPDATE
SET reason    = EXCLUDED.reason,
    banned_at = now(),
    banned_by = EXCLUDED.banned_by;

-- ---------------------------------------------------------------------------
-- 2) Alle gesperrten E-Mail-Adressen anzeigen
-- ---------------------------------------------------------------------------
SELECT email, reason, banned_at, banned_by
FROM public.banned_emails
ORDER BY banned_at DESC;

-- ---------------------------------------------------------------------------
-- 3) Sperre aufheben (Entsperrung nach Antrag)
-- ---------------------------------------------------------------------------
DELETE FROM public.banned_emails
WHERE email = 'nutzer@beispiel.de';

-- ============================================================================
-- Hinweise:
-- - Ausführen im Supabase SQL Editor (Dashboard -> Project -> SQL Editor).
-- - Die Tabelle ist per RLS vollständig abgeriegelt: nur postgres und
--   Service-Role (Edge Functions) haben Zugriff - weder anon noch
--   eingeloggte Nutzer.
-- - Entsperrungsanträge kommen per E-Mail über die Edge Function
--   request-unban (Brevo) an support@thestia.de.
-- ============================================================================