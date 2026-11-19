-- ============================================================================
-- Invite-Codes fǬr die App verwalten
-- ============================================================================
-- SICHERHEIT: Alle unten stehenden Codes (BLIND-*) sind REINE BEISPIELE.
-- Falls einer dieser Werte bereits in der Datenbank angelegt wurde (z. B.
-- per Copy-Paste aus dieser Datei), gilt er als kompromittiert, weil die
-- Datei im Git-Repo liegt: Sofort in der DB sperren oder löschen:
--   UPDATE invite_codes SET used = true, max_uses = 0 WHERE code IN
--     ('BLIND-SUPER-2026','BLIND-TEST-2026','BLIND-ONCE-2026','BLIND-ADMIN-2026');
-- Neue, echte Codes IMMER direkt im SQL Editor anlegen, nie in diese Datei.
--
-- Tabelle: invite_codes
--
-- Erwartete Spalten:
--   code         TEXT PRIMARY KEY       -- z. B. 'BLIND-ABC123'
--   created_at   TIMESTAMPTZ            -- Erstellungszeitpunkt
--   created_by   TEXT                   -- User-ID oder 'admin'
--   max_uses     INTEGER                -- Maximale Einlösungen
--   current_uses INTEGER DEFAULT 0      -- Bisherige Einlösungen
--   expires_at   TIMESTAMPTZ            -- Optional: Ablaufdatum
--   used         BOOLEAN DEFAULT FALSE  -- Vollständig verbraucht?
--   used_by      TEXT                   -- User-ID des Einlösers
--   used_at      TIMESTAMPTZ            -- Einlösungszeitpunkt
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Einfachen Einladungscode anlegen (beliebig oft einlösbar, kein Ablauf)
-- ---------------------------------------------------------------------------
INSERT INTO invite_codes (code, created_at, created_by, max_uses, current_uses, used)
VALUES (
  'BLIND-SUPER-2026',
  now(),
  'admin',
  50,    -- max_uses: kann 50 Mal eingelöst werden
  0,     -- current_uses: bisher 0 Mal eingelöst
  false  -- used: noch nicht verbraucht
)
ON CONFLICT (code) DO UPDATE
SET max_uses = EXCLUDED.max_uses,
    used     = EXCLUDED.used;

-- ---------------------------------------------------------------------------
-- 2) Einladungscode mit Ablaufdatum anlegen
-- ---------------------------------------------------------------------------
INSERT INTO invite_codes (code, created_at, created_by, max_uses, current_uses, expires_at, used)
VALUES (
  'BLIND-TEST-2026',
  now(),
  'admin',
  10,
  0,
  now() + INTERVAL '30 days',  -- Gültig für 30 Tage
  false
)
ON CONFLICT (code) DO UPDATE
SET max_uses  = EXCLUDED.max_uses,
    expires_at = EXCLUDED.expires_at,
    used       = EXCLUDED.used;

-- ---------------------------------------------------------------------------
-- 3) Einmaligen Code anlegen (nur 1 Einlösung)
-- ---------------------------------------------------------------------------
INSERT INTO invite_codes (code, created_at, created_by, max_uses, current_uses, used)
VALUES (
  'BLIND-ONCE-2026',
  now(),
  'admin',
  1,
  0,
  false
)
ON CONFLICT (code) DO UPDATE
SET max_uses = EXCLUDED.max_uses,
    used     = EXCLUDED.used;

-- ---------------------------------------------------------------------------
-- 4) Admin-Code anlegen (viele Nutzer, kein Ablauf)
-- ---------------------------------------------------------------------------
INSERT INTO invite_codes (code, created_at, created_by, max_uses, current_uses, used)
VALUES (
  'BLIND-ADMIN-2026',
  now(),
  'admin',
  200,
  0,
  false
)
ON CONFLICT (code) DO UPDATE
SET max_uses = EXCLUDED.max_uses,
    used     = EXCLUDED.used;

-- ---------------------------------------------------------------------------
-- 5) Alle vorhandenen Codes anzeigen
-- ---------------------------------------------------------------------------
SELECT
  code,
  created_at,
  created_by,
  max_uses,
  current_uses,
  expires_at,
  used,
  used_by,
  used_at
FROM invite_codes
ORDER BY created_at DESC;

-- ---------------------------------------------------------------------------
-- 6) Einen Code als verbraucht markieren (manuell, falls nötig)
-- ---------------------------------------------------------------------------
UPDATE invite_codes
SET used     = true,
    used_by  = 'user-id-des-nutzers',
    used_at  = now()
WHERE code = 'BLIND-SUPER-2026';

-- ---------------------------------------------------------------------------
-- 7) Einen Code löschen
-- ---------------------------------------------------------------------------
DELETE FROM invite_codes
WHERE code = 'BLIND-TEST-2026';

-- ============================================================================
-- Hinweise:
-- ============================================================================
-- - Führe diese Statements im Supabase SQL Editor aus (Supabase Dashboard ->
--   Project -> SQL Editor).
-- - Die App validiert Codes NUR noch über die Datenbank:
--     SELECT * FROM invite_codes WHERE code = ? AND used = false
-- - Hartkodierte Codes im Code wurden entfernt. Alle Codes leben jetzt in
--   der Tabelle invite_codes.
-- - RLS: Stelle sicher, dass die Tabelle entsprechende Policies hat, z.B.:
--
--   -- Öffentliches Lesen für die Validierung (read-only)
--   CREATE POLICY "Anyone can validate invite codes"
--     ON invite_codes FOR SELECT TO authenticated
--     USING (true);
--
--   -- Nur Admins/Server dürfen Codes anlegen/ändern/löschen.
--   -- Hier exemplarisch für den Dienst-Account oder eine Admin-Rolle.
--   CREATE POLICY "Only admins can insert invite codes"
--     ON invite_codes FOR INSERT TO authenticated
--     WITH CHECK (auth.uid() IN ('DEINE-ADMIN-USER-ID'));
--
--   CREATE POLICY "Only admins can update invite codes"
--     ON invite_codes FOR UPDATE TO authenticated
--     USING (auth.uid() IN ('DEINE-ADMIN-USER-ID'));
--
--   CREATE POLICY "Only admins can delete invite codes"
--     ON invite_codes FOR DELETE TO authenticated
--     USING (auth.uid() IN ('DEINE-ADMIN-USER-ID'));
-- ============================================================================
