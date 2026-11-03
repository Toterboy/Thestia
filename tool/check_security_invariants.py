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
# 1b) Verifikationssperre muss serverseitig gelten
# =====================================================================
#
# BEFUND (Security-Audit 31.10.2026): Die Verifikationspflicht fuer
# Find your Spark, Dating Hour und Transit Spark wurde an GENAU EINER
# Stelle geprueft - im Client, im Modus-Auswahlbildschirm. Find your
# Spark ist serverseitig geschuetzt (Migration 156), Dating Hour und
# Transit Spark nicht: in deren RPCs kommt is_verified nirgends vor.
#
# Ein Client-Gate ist keine Zugriffskontrolle: die RPCs sind fuer jeden
# mit eigenem JWT aufrufbar. Die Regel hier verhindert, dass das
# erneut so gebaut wird.
#
# Geprueft wird deshalb: JEDE Migration, die eine der betroffenen
# Funktionen neu definiert, muss die Verifikation im Funktionskoerper
# pruefen. Das ist robust gegen eine spaetere, aeltere Fassung einer
# Funktion - die spaeteste Definition gewinnt in PostgreSQL.

VERIFIKATIONS_PFLICHT = [
    ('join_dating_hour', 'Dating Hour (Opt-in)'),
    ('match_dating_hour_round', 'Dating Hour (Pairing)'),
    ('transit_spark_adult', 'Transit Spark (Alter UND Verifikation)'),
]


def _neueste_definition(sql: str, fn_name: str) -> str:
    """Der Funktionskoerper der LETZTEN Definition von fn_name.

    PostgreSQL nimmt bei CREATE OR REPLACE die letzte Definition. Ein
    aelterer, sicherer Koerper wuerde sonst den Check bestehen, obwohl
    die aktive Funktion ungeschuetzt ist.
    """
    # Alle Definitionen finden und die letzte nehmen.
    treffer = list(re.finditer(
        r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+'
        r'(?:public\.)?' + re.escape(fn_name) + r'\s*\(',
        sql, re.I))
    if not treffer:
        return ''
    start = treffer[-1].start()
    # Bis zum Ende des Funktionskoerpers.
    #
    # ACHTUNG (02.11.2026): Es gibt zwei Schreibweisen fuer das
    # Dollar-Delimiter - $$ ... $$ und $name$ ... $name$ (z.B.
    # $function$ oder $BODY$). Der Helfer erkannte nur $$ und griff
    # deshalb bei einer Funktion mit $function$ das FALSCHE Stueck:
    # es landete im nachfolgenden DO-Block statt im Funktionskoerper.
    #
    # Das war kein theoretischer Fehler: die Pruefung "gibt
    # Minderjaehrigen keine Entfernung" schlug dadurch fehl, obwohl
    # die Migration die Bedingung enthaelt - und ein Check, der an
    # der falschen Stelle sucht, prueft gar nichts.
    rest = sql[start:]
    dollar = re.search(r'\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$', rest)
    if not dollar:
        return rest[:2000]
    delim = dollar.group(0)
    body = rest[dollar.end():]
    ende = body.find(delim)
    return body[:ende] if ende >= 0 else body[:4000]


for fn_name, beschreibung in VERIFIKATIONS_PFLICHT:
    koerper = _neueste_definition(all_sql, fn_name)
    if not koerper:
        check(False,
              f'DB: {beschreibung} - Definition von {fn_name} gefunden',
              'keine CREATE OR REPLACE-Funktion in den Migrationen')
        continue
    # Die Verifikation kann direkt geprueft werden (is_verified) oder
    # ueber eine Hilfsfunktion. Beides zaehlt - aber nur, wenn die
    # genannte Funktion die Verifikation auch WIRKLICH prueft.
    #
    # transit_spark_is_adult prueft NUR das Alter (Alter ohne
    # Verifikation - die Reihenfolge ist hier wichtig). Deshalb zaehlt
    # sie NICHT als Verifikationspruefung; sonst wuerde die Regel den
    # Ist-Zustand als erfuellt melden.
    #
    # verification_granted ist dagegen die Verifikationspruefung
    # selbst (Migration 161): sie liest is_verified aus dem Profil.
    prueft = ('is_verified' in koerper
               or 'verification_granted' in koerper)
    check(prueft,
          f'DB: {beschreibung} prueft die Verifikation serverseitig',
          f'letzte Definition von {fn_name} ohne is_verified')

# Die Geburtsdatum-Angabe darf nicht still auf 26-Jahre fallen:
# ohne birth_date muss das Alter UNBEKANNT sein, nicht erfunden.
#
# Erlaubt sind zwei Schreibweisen fuer "unbekannt":
#   * birth_date ist NULL (NULLIF / NULL direkt)
#   * birth_date wird gar nicht gesetzt (die Spalte fehlt im INSERT)
#
# Verboten ist der erfundene Stichtag 2000-01-01 (Alter 26).
handle_new_user = _neueste_definition(all_sql, 'handle_new_user')
if handle_new_user:
    # Nur der AUSFUEHRENDE Teil zaehlt. Die Kommentare beschreiben
    # den alten Wert (und die Bereinigung per UPDATE) - die muessen
    # erlaubt sein, sonst koennte man den Fix nicht erklaeren.
    ausfuehrend = re.sub(r'--[^\n]*', '', handle_new_user)
    erfindet = '2000-01-01' in ausfuehrend
    # 'birth_date' muss im INSERT vorhanden sein, sonst ist die Spalte
    # NULL per Default - das ist auch in Ordnung.
    check(not erfindet,
          'DB: handle_new_user erfindet kein Geburtsdatum (kein '
          '26-Jaehriger ohne Angabe)',
          'sonst passiert die 18+-Pruefung ohne Altersangabe')
else:
    check(False,
          'DB: handle_new_user gefunden',
          'keine CREATE OR REPLACE-Funktion in den Migrationen')

# =====================================================================
# 1d) Minderjaehrige geben KEINE Entfernung preis
# =====================================================================
#
# BETREIBER-ENTSCHEIDUNG (02.11.2026): "Die grobe Entfernung duerfen 16
# und 17 jaehrige auch nicht aktivieren koennen."
#
# BISHER: profile_distance_km lieferte die Entfernung, sobald
# profiles.show_distance des anderen gesetzt war - das durfte JEDER
# aktivieren, auch ein 16-Jaehriger.
#
# Die Sperre muss in der FUNKTION sitzen, die die Entfernung ausgibt -
# eine Einstellung, die ein gepatchter Client setzen kann, ist keine
# Sperre. Geprueft wird deshalb, dass die letzte Definition von
# profile_distance_km das Alter beruecksichtigt (verified_age) UND
# mindestens 18 verlangt.
#
# Das ist die Server-Haelfte. Die App-Haelte (der gesperrte Schalter)
# steht in AgeSafetyRules.isRoughDistanceForced und wird von
# test/age_safety_rules_test.dart geprueft.

_distanz_funktion = _neueste_definition(all_sql, 'profile_distance_km')
check('verified_age' in _distanz_funktion,
      'DB: profile_distance_km rechnet mit dem verifizierten Alter '
      '(verified_age)',
      'sonst wuerde die Entfernung nach der Altersangabe im Profil '
      'entschieden')
check('>= 18' in _distanz_funktion,
      'DB: profile_distance_km gibt Minderjaehrigen (16-17) keine '
      'Entfernung',
      'die grobe Entfernung darf fuer unter 18-Jaehrige nicht '
      'ausgegeben werden')

# =====================================================================
# 1e) Minderjaehrige bekommen einen begrenzten Suchradius
# =====================================================================
#
# BETREIBER-ENTSCHEIDUNG (03.11.2026): "fuer 16 und 17 jaehrige
# entweder gleiches Bundesland oder max. 25 Km. Und ab 18 alles frei
# auswaehlbar."
#
# BISHER: Der Radius wurde nur im Modus 'distance_km' ausgewertet. Fuer
# 'state' und 'germany' fiel die Entfernungsbedingung weg - "Ganz
# Deutschland" war also dasselbe wie "Bundesland" (nur ohne jeden
# Vergleich!). Ein Client, der den Modus auf 'germany' stellt, kam an
# jeder Radiusgrenze vorbei.
#
# Die Grenze muss deshalb in der FUNKTION sitzen, die die Sichtbarkeit
# entscheidet - und zwar erzwungen fuer Minderjaehrige, unabhaengig vom
# gespeicherten Modus.

_sichtbarkeit = _neueste_definition(all_sql, 'profile_discovery_visible')

check('profile_known_age' in _sichtbarkeit,
      'DB: profile_discovery_visible rechnet mit dem bekannten Alter '
      '(profile_known_age)',
      'sonst wuerde die Grenze nach der Altersangabe im Profil '
      'entschieden - und ein unbekanntes Alter faelle auf 26 Jahre')

check('<= 25' in _sichtbarkeit,
      'DB: profile_discovery_visible begrenzt den Radius fuer '
      'Minderjaehrige auf 25 km',
      'die grobe Entfernung darf fuer unter 18-Jaehrige nicht '
      'ueberschritten werden')

check('distance_filter_mode' in _sichtbarkeit,
      'DB: profile_discovery_visible wertet den Suchradius-Modus aus',
      'sonst kaeme ein Client mit dem Modus "Ganz Deutschland" an der '
      'Grenze vorbei')

check('v.state' in _sichtbarkeit and 't.state' in _sichtbarkeit,
      'DB: profile_discovery_visible vergleicht das Bundesland',
      'die Alternative "gleiches Bundesland" fuer 16- und 17-Jaehrige '
      'waere sonst wirkungslos')

# =====================================================================
# 1c) Das Verifikationsvideo wird IMMER verschluesselt abgelegt
# =====================================================================
#
# BEFUND (Security-Audit 31.10.2026): Nur der Submit-Pfad
# verschluesselte das Video. Der Auto-Pfad lagerte das ROHVIDEO ab -
# unter dem Dateinamen 'video.mp4.enc', der Verschluesselung
# suggeriert, aber ohne Chiffrat. Zwei Folgen: die Zusage der
# Datenschutzerklaerung ("der Bucket enthaelt ausschliesslich
# Chiffrat") stimmte nicht, und die Admin-Sichtung brach ab, weil
# der Schluessel fehlte.
#
# Geprueft wird deshalb: JEDER Video-Upload im Client laeuft durch
# VerificationCrypto.encrypt().

verifikation = read(LIB / 'services' / 'verification_service.dart')

# Die Uploads, die das Video in den Bucket schieben.
uploads = list(re.finditer(
    r'uploadVerificationVideo\(([^)]*)\)', verifikation))
check(len(uploads) >= 2,
      'APP: das Verifikationsvideo wird an mindestens zwei Stellen '
      'hochgeladen (submit und auto)',
      '%d Upload-Aufruf(e) gefunden' % len(uploads))

for m in uploads:
    argument = m.group(1).strip()
    verschluesselt = ('encrypted.cipher' in argument
                      or 'cipher' in argument)
    check(verschluesselt,
          'APP: Jeder Video-Upload nutzt das Chiffrat (encrypted.cipher)',
          'Upload mit %r - das waere das Rohvideo' % argument[:40])

# Und: der Schluessel muss mitgeschickt werden, sonst kann die
# Edge Function ihn nicht ablegen.
check(verifikation.count("'videoKey': encrypted.keyB64") >= 2,
      'APP: der Video-Schluessel wird in BEIDEN Pfaden mitgeschickt',
      'sonst kann die Admin-Sichtung das Video nicht entschluesseln')

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
