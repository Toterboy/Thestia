"""Sicherheits-Regressionswächter (Code + Migrationen).

Prüft die Fixes aus dem Audit vom 2026-09-26 und bricht mit Exit-Code 1 ab,
wenn jemand eines davon zurücksetzt. Bewusst als Tool im Repo, damit die
Prüfung Teil jedes Reviews sein kann:

    python tool/check_migration_safety.py
    python tool/check_security_invariants.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FN = ROOT / 'supabase' / 'functions'
LIB = ROOT / 'lib'
MIG = ROOT / 'supabase' / 'migrations'

results: list[tuple[bool, str]] = []


def read(p: pathlib.Path) -> str:
    return p.read_text(encoding='utf-8', errors='replace')


def check(ok: bool, label: str, detail: str = '') -> None:
    results.append((bool(ok), f'{label}{(" - " + detail) if detail else ""}'))


def has(rel: str, *needles: str) -> bool:
    f = ROOT / rel
    if not f.exists():
        return False
    c = read(f)
    return all(n in c for n in needles)


# =====================================================================
# 1) Datenbank
# =====================================================================
all_sql = '\n'.join(read(f) for f in sorted(MIG.glob('*.sql')))

check('REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;' in all_sql,
      'DB: ALTER DEFAULT PRIVILEGES schliesst den PUBLIC-Default')

QUIZ_HELPERS = ('quiz_shuffle_for_match', 'quiz_pick_personalized',
                'quiz_personal_distractors', 'quiz_stopwords',
                'quiz_interest_catalog')

# Migration 123 loest die Rechte DYNAMISCH ueber pg_proc/string_to_array
# auf. Grund: `REVOKE ... FROM anon` greift nicht (Rechte werden ueber die
# Pseudo-Rolle PUBLIC vererbt), und `quiz_pick_personalized` hat zwei
# Overloads, die eine Signatur-Liste verfehlt hat. Beide Fehler sind beim
# ersten Push aufgetreten - die statische Form ist deshalb verboten.
check("p.proname::text <> ALL" not in all_sql and
      "NOT (p.proname::text = ANY (v_ok))" in all_sql,
      'DB: anon verliert alles ausserhalb einer Allowlist (statisch geprueft)')
check("REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated" in all_sql,
      'DB: Entzug nennt PUBLIC - ein Rollen-Revoke allein wuerde nicht greifen')
check("GRANT EXECUTE ON FUNCTION %s TO authenticated" in all_sql,
      'DB: Allowlist bekommt ein EXPLIZITES Grant an authenticated')
check('GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;' in all_sql,
      'DB: service_role behaelt alles (Studio/Edge/Admin)')
check('p.oid::regprocedure::text' in all_sql,
      'DB: Signaturen werden aus pg_proc gelesen, nicht getippt')
for fn in QUIZ_HELPERS:
    check(fn in all_sql, f'DB: {fn} in der Entzugsliste')
check(all_sql.count('has_function_privilege') >= 3,
      'DB: Fail-Fast prueft anon UND authenticated (Rollen, nicht Liste)')
check("has_function_privilege('anon'" in all_sql and
      "NOT has_function_privilege('authenticated'" in all_sql,
      'DB: Fail-Fast verifiziert auch, dass authenticated nichts verloren hat')

check('trg_enforce_random_chat_safety' in all_sql,
      'DB: Tabellentrigger Zufallschat (nicht per CREATE OR REPLACE umgehbar)')
check('trg_enforce_dating_hour_safety' in all_sql,
      'DB: Tabellentrigger Dating Hour')
check('trg_quiz_attempt_cooldown' in all_sql,
      'DB: Quiz-Cooldown greift bei JEDEM Versuch')
check('trg_bucket_list_immutable' in all_sql,
      'DB: match_bucket_list match_id/created_by unveraenderlich')
check('trg_guard_match_status_change' in all_sql,
      'DB: Match-Statuswechsel gedrosselt (auch ohne RPC)')
check('uniq_active_dh_pair' in all_sql,
      'DB: Race-Condition Dating Hour (Unique je Paar)')
check('profile_discovery_visible' in all_sql,
      'DB: zentrale Discovery-Sichtbarkeitsregel')
check('session_meets_auth_requirements' in all_sql,
      'DB: AAL2/E-Mail-Pruefpunkt existiert')
check('email_verified_at' in all_sql and
      'trg_sync_email_verified_at' in all_sql,
      'DB: E-Mail-Bestaetigung wird gespiegelt (RLS kann auth.users nicht lesen)')
check("v_bad IS NOT NULL THEN" in all_sql or 'RAISE EXCEPTION' in all_sql,
      'DB: Fail-Fast-Guards vorhanden')

# =====================================================================
# 2) Edge Functions
# =====================================================================
for name in ('verify-account', 'cancel-registration'):
    c = read(FN / name / 'index.ts')
    fail_closed = re.search(
        r'consume_rate_limit (?:error|exception)[^;]*;?\s*return true;', c, re.S)
    check(bool(fail_closed), f'EDGE: {name} Rate-Limit fail-closed')

c = read(FN / 'delete-account' / 'index.ts')
check('listFactors !== "function") return false;' in c,
      'EDGE: delete-account MFA-Pruefung fail-closed')
check('MFA-Faktor-Prüfung fehlgeschlagen (fail-closed)' in c,
      'EDGE: delete-account MFA-catch fail-closed')

for name in ('request-unban', 'send-bug-report', 'prekeys'):
    c = read(FN / name / 'index.ts')
    check('function clientIp' in c and 'split(",")[0]' in c,
          f'EDGE: {name} IP korrekt geparst (kein Header-Rotations-Bypass)')
    raw = re.search(r'const ip = req\.headers\.get\("x-forwarded-for"\)', c)
    check(not raw, f'EDGE: {name} nutzt den Helfer statt rohem XFF')

c = read(FN / 'prekeys/index.ts')
check('SECURITY (2026-09-26): Beziehungspruefung' in c,
      'EDGE: prekeys prueft die Beziehung (kein Bundle-Harvesting)')
check('Kein Bundle verfügbar.' in c,
      'EDGE: prekeys 404 ohne Existenz-Auskunft')

c = read(FN / 'report-image/index.ts')
check('isPersistentRateLimited' in c and 'report_image:' in c,
      'EDGE: report-image persistentes Rate-Limit (Cold-Start-resistent)')

c = read(FN / 'match-media/index.ts')
check('match_media:' in c and 'consume_rate_limit' in c,
      'EDGE: match-media gedrosselt')

# =====================================================================
# 3) App-Code
# =====================================================================
pubspec = read(ROOT / 'pubspec.yaml')
assets_block = pubspec[pubspec.find('assets:'):pubspec.find('assets:') + 900]
check(not re.search(r'^\s*-\s*\.env\s*$', assets_block, re.M),
      'APP: .env ist KEIN App-Asset (nicht im APK extrahierbar)')
m = re.search(r'^\s*image:\s*\^?(\d+)\.(\d+)\.', pubspec, re.M)
check(bool(m) and (int(m.group(1)), int(m.group(2))) >= (4, 10),
      'APP: image-Paket >= 4.10 (Decoder-Hardening)',
      m.group(0).strip() if m else 'nicht gefunden')

check(has('lib/utils/exif_stripper.dart', 'kMaxScrubBytes',
          'kMaxScrubPixels', 'startDecode'),
      'APP: Exif-Scrubbing prueft Budget VOR dem Decode')

check(has('lib/services/secure_storage_namespaces.dart',
          'migrateLegacyNamespaces', 'storageNamespace'),
      'APP: Keystore-Namespaces + idempotente Migration')
check(has('lib/main.dart', 'await migrateLegacyNamespaces('),
      'APP: Namespace-Migration laeuft beim Start UND wird awaited')
# Ein unawaited-Lauf war der Bug: der Supabase-Client startet gleich danach
# und laeuft bei `resetOnError: true` (Default) sonst in einen Dekrypt-
# Fehlschlag, der die Werte aller anderen Namespaces mitloescht.
check('unawaited(migrateLegacyNamespaces' not in read(ROOT / 'lib/main.dart'),
      'APP: Namespace-Migration ist NICHT unawaited (Race mit Supabase-Init)')
check(has('lib/main.dart', '_supabaseSessionKey()'),
      'APP: Supabase-Session-Key wird fuer die Migration berechnet')
for f, ns in (('lib/services/secure_storage.dart', 'SecureNamespaces.tokens'),
              ('lib/services/secure_hive.dart', 'SecureNamespaces.signals'),
              ('lib/services/secure_supabase_session_storage.dart',
               'SecureNamespaces.session'),
              ('lib/services/secure_location_storage.dart',
               'SecureNamespaces.location')):
    check(has(f, ns), f'APP: eigener Namespace in {f}')

check(has('lib/main.dart', 'IOClient(CertPinning.pinnedHttpClient('),
      'APP: Supabase nutzt den STRICTEN Pin-Client (Callback laeuft immer)')
check(has('lib/utils/cert_pinning.dart', 'withTrustedRoots: false'),
      'APP: strikter Pin-Client vorhanden')

check(has('lib/providers/transit_provider.dart', 'SecurePreferencesStorage()'),
      'APP: Transit-Encounters im Keystore (kein Begehnachweis im Klartext)')
check(has('lib/providers/auth_provider.dart', 'TransitEncounterService('),
      'APP: Transit-Cache in der Loeschkette (Art. 17)')

check(has('lib/services/encryption_service.dart', 'assertPeerUsable',
          'requiresPeerVerification'),
      'APP: Safety-Number-Verifikation wird erzwungen')
check(has('lib/services/encryption_service.dart',
          'assertPeerUsable(recipientId);'),
      'APP: Pruefung haengt am Nachrichtenpfad, nicht nur in der UI')
check(has('lib/screens/chat/chat_detail_screen.dart',
          'chat.requireVerifiedTitle', 'setRequiresPeerVerification'),
      'APP: Schalter fuer erzwungene Verifikation vorhanden')

check('NSPhotoLibraryUsageDescription' in read(ROOT / 'ios/Runner/Info.plist'),
      'APP: iOS-Fotomediathek-Beschreibung (sonst Absturz beim Auswahl-Dialog)')

check(has('lib/utils/constants.dart',
          "defaultValue: 'turnstile'"),
      'APP: CAPTCHA ist per Default aktiv (kein stiller Bot-Schutz-Aus)')
check(has('tool/build_release.ps1', 'CAPTCHA_SITEKEY fehlt',
          'ConfigDefines'),
      'BUILD: Release bricht ohne Konfiguration/CAPTCHA ab')

# =====================================================================
# Ausgabe
# =====================================================================
print('SICHERHEITS-INVARIANTEN\n' + '=' * 78)
ok = 0
for passed, label in results:
    print(f'  {"OK  " if passed else "FEHLT"}  {label}')
    ok += passed

print('=' * 78)
print(f'{ok}/{len(results)} Invarianten erfuellt')
sys.exit(0 if ok == len(results) else 1)
