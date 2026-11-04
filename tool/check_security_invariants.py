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


def _neueste_definition(sql: str, fn_name: str,
                       _gesehen: frozenset = frozenset()) -> str:
    """Der Funktionskoerper der LETZTEN Definition von fn_name.

    PostgreSQL nimmt bei CREATE OR REPLACE die letzte Definition. Ein
    aelterer, sicherer Koerper wuerde sonst den Check bestehen, obwohl
    die aktive Funktion ungeschuetzt ist.

    ZWEI AUFLOESUNGEN (beide noetig, seit Migration 176):

    1) RENAME: Eine Funktion kann per
       "ALTER FUNCTION ... RENAME TO ..." umbenannt worden sein. Ihr
       Koerper steht dann in der SQL weiterhin unter dem ALTEN Namen.

    2) DELEGATION: Eine Funktion kann eine duenne Huelle sein, die an
       eine andere weiterreicht. Die Sicherheitspruefungen stehen dann
       in der anderen.
    """
    # Endlosschleifen verhindern (Huelle -> Original -> Huelle).
    if fn_name.lower() in _gesehen:
        return ''
    _gesehen = _gesehen | {fn_name.lower()}

    # (1) Wurde die Funktion umbenannt? Dann steht ihr Koerper unter
    #     dem urspruenglichen Namen - und zwar in dem Teil der SQL,
    #     der VOR dem RENAME liegt (danach gibt es nur noch die
    #     duenne Huelle unter dem neuen Namen).
    ziel = fn_name
    suchtext = sql
    umbenannt = re.search(
        r'ALTER\s+FUNCTION\s+(?:public\.)?"?([a-z0-9_]+)"?\s*\([^)]*\)\s*'
        r'RENAME\s+TO\s+"?([a-z0-9_]+)"?',
        sql, re.I)
    if umbenannt and umbenannt.group(2).lower() == fn_name.lower():
        ziel = umbenannt.group(1)
        suchtext = sql[:umbenannt.start()]

    # Alle Definitionen finden und die letzte nehmen.
    treffer = list(re.finditer(
        r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+'
        r'(?:public\.)?' + re.escape(ziel) + r'\s*\(',
        suchtext, re.I))
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
    rest = suchtext[start:]
    dollar = re.search(r'\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$', rest)
    if not dollar:
        return rest[:2000]
    delim = dollar.group(0)
    body = rest[dollar.end():]
    ende = body.find(delim)
    koerper = body[:ende] if ende >= 0 else body[:4000]

    # Migration 176 (04.11.2026): Mehrere Funktionen wurden umbenannt
    # (ALTER FUNCTION ... RENAME TO ..._ohne_nutzungszeit) und davor
    # eine duenne Huelle gesetzt, die das Gate erzwingt. Die
    # Sicherheitspruefungen stehen im umbenannten Original.
    #
    # Ohne diese Aufloesung wuerde der Check nur die Huelle sehen und
    # eine Luecke melden, die es nicht gibt. Dass die Huelle das Gate
    # wirklich aufruft, ist getrennt abgesichert (Invariante
    # "match_dating_hour_round prueft den Aufrufer NUR, wenn er selbst
    # handelt").
    delegiert = re.search(r'PERFORM\s+public\.([a-z0-9_]+)\s*\(', koerper, re.I)
    if delegiert and delegiert.group(1).lower() != fn_name.lower():
        innen = _neueste_definition(sql, delegiert.group(1), _gesehen)
        if innen:
            koerper = koerper + '\n' + innen
    return koerper


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

    # ZUSAETZLICH: Bei den Dating-Hour-Funktionen muss die
    # TEILNEHMERPRUEFUNG dastehen - nicht nur die des Aufrufers.
    #
    # WARUM (04.11.2026): Ein Aufrufer-Check allein genuegt nicht.
    # Die Paarung laeuft ueber den Cron, wo es gar keinen Aufrufer
    # gibt (auth.uid() ist NULL) - dort wurde die ganze Runde
    # abgebrochen. Und die eigentliche Gefahr ist ein Match
    # zwischen einer verifizierten und einer unverifizierten Person:
    # da muss die Verifikation beider TEILNEHMER geprueft werden.
    if fn_name == 'match_dating_hour_round':
        # Die Paarung: beide TEILNEHMER muessen verifiziert sein. Ein
        # Aufrufer-Check allein genuegt nicht - die Paarung laeuft
        # ueber den Cron, wo es gar keinen Aufrufer gibt.
        check('verification_granted(v_user.user_id)' in koerper
              or 'verification_granted(q.user_id)' in koerper,
              'DB: Die Paarung prueft die Verifikation der TEILNEHMER '
              '(nicht nur die des Aufrufers - der Cron hat keinen '
              'Aufrufer)',
              f'letzte Definition von {fn_name} ohne Teilnehmerpruefung')
    elif fn_name == 'join_dating_hour':
        # Das Beitreten: hier ist der Aufrufer die betroffene Person.
        # Wichtig ist, dass die Pruefung NICHT wegfaellt - deshalb wird
        # sie hier ausdruecklich verlangt.
        check('verification_granted' in koerper,
              'DB: Das Beitreten prueft die Verifikation der Person, '
              'die beitritt',
              f'letzte Definition von {fn_name} ohne Verifikationspruefung')

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

# Der Modus "Bundesland" hat bis Migration 169 gar nichts gefiltert:
# "Bundesland" und "Ganz Deutschland" waren dieselbe Bedingung (kein
# Radius). Die drei Modi muessen jetzt alle drei ausgewertet werden.
for _modus in ('distance_km', 'state', 'germany'):
    check(f"= '{_modus}'" in _sichtbarkeit,
          f'DB: profile_discovery_visible wertet den Suchmodus "{_modus}" aus',
          'der Modus muss das tun, was er verspricht - sonst ist die '
          'Einstellung eine Anzeige ohne Wirkung')

# =====================================================================
# 1f) Die elterliche Aufsicht haengt an der Datenbank, nicht an der App
# =====================================================================
#
# BETREIBER-ENTSCHEIDUNG (03.11.2026): Elternfreigabe fuer 16- und
# 17-Jaehrige, mit PIN-geschuetzter Nutzungszeit und gebuendelten
# Benachrichtigungen.
#
# Die Regeln muessen serverseitig gelten: eine Einstellung im Client
# kann mit einem gepatchten Client gesetzt werden.

_anfrage = _neueste_definition(all_sql, 'request_guardian_consent')

check('guardian_eligible_age' in _anfrage,
      'DB: request_guardian_consent prueft das Alter (ueber das '
      'VERIFIZIERTE Alter)',
      'sonst koennte ein 14-Jaehriger eine Elternfreigabe anlegen')

check('same_email' in _anfrage,
      'DB: request_guardian_consent schliesst die eigene Kontoadresse aus',
      'sonst wuerde sich der Jugendliche selbst als Elternteil eintragen')

check('sha256' in _anfrage,
      'DB: request_guardian_consent hasht den Token',
      'der Token darf nicht im Klartext gespeichert werden - er ist die '
      'Berechtigung des Elternteils')

check('consume_rate_limit' in _anfrage,
      'DB: request_guardian_consent hat eine Sperre',
      'ohne Sperre koennte der Token erneuert und die Mail mit einem '
      'neuen Token geflutet werden')

_pin = _neueste_definition(all_sql, 'verify_guardian_pin')
check('crypt' in _pin,
      'DB: verify_guardian_pin vergleicht serverseitig (bcrypt)',
      'ein lokaler Vergleich waere mit einem gepatchten Client zu '
      'umgehen')
check('consume_rate_limit' in _pin,
      'DB: verify_guardian_pin hat eine Sperre',
      'eine vierstellige PIN hat nur 10 000 Moeglichkeiten - ohne '
      'Sperre waere sie in Sekunden durch')

_mit_pin = _neueste_definition(all_sql, 'set_guardian_settings_with_pin')
check('crypt' in _mit_pin,
      'DB: set_guardian_settings_with_pin prueft die PIN serverseitig',
      'sonst koennte der Jugendliche die Nutzungszeit selbst verschieben')
check('consume_rate_limit' in _mit_pin,
      'DB: set_guardian_settings_with_pin teilt die Sperre der PIN',
      'zwei getrennte Zaehler wuerden die Sperre aushebeln')

# Der Funken-Trigger: ein Funke erzeugt das Eltern-Ereignis, ein Like
# nicht ("nicht nur like auf einer Seite").
check('trg_matches_guardian_notify' in all_sql,
      'DB: Der Trigger fuer Eltern-Ereignisse haengt an matches',
      'ohne ihn erfahren die Eltern nie von einem Funken')
check('guardian_notification_events' in all_sql,
      'DB: Die Eltern-Ereignisse werden gespeichert',
      'ohne Zwischenspeicherung gibt es nichts zu buendeln')

# Die Freigabe- und Ereignis-Tabellen duerfen fuer Clients nicht
# direkt lesbar sein.
for _tabelle in ('guardian_consents', 'guardian_consent_audit',
                  'guardian_notification_events'):
    check(
        f'ALTER TABLE public.{_tabelle} ENABLE ROW LEVEL SECURITY' in all_sql,
        f'DB: {_tabelle} hat Row-Level-Security aktiv',
        'sonst koennte ein Client die Tabelle direkt lesen')

# =====================================================================
# 1g) Der Posteingang ist NUR LESBAR
# =====================================================================
#
# BETREIBER-ENTSCHEIDUNG (03.11.2026): "Koennen im Adminbereich fuer mich
# die Emails auch angezeigt werden? Kein Antworten nur anzeigen."
#
# "Kein Antworten" ist eine technische Vorgabe, keine Formulierung: eine
# Antwortfunktion braeuchte SMTP-Zugang und eine zweite Absender-
# identitaet. Im Kinderschutz waere die Gefahr real, aus dem falschen
# Konto zu schreiben.

check('ALTER TABLE public.mail_messages ENABLE ROW LEVEL SECURITY' in all_sql,
      'DB: mail_messages hat Row-Level-Security aktiv',
      'ohne RLS koennte ein Client die Tabelle direkt lesen')

_mails = _neueste_definition(all_sql, 'admin_list_mail_messages')
check('is_current_user_admin' in _mails,
      'DB: admin_list_mail_messages prueft den Admin-Status',
      'die Mails enthalten personenbezogene Daten Dritter - sie gehoeren '
      'nur in die Hand des Betreibers')

for _verb in ('INSERT INTO public.mail_messages',
              'UPDATE public.mail_messages',
              'DELETE FROM public.mail_messages'):
    check(_verb not in _mails,
          f'DB: admin_list_mail_messages schreibt nicht ({_verb})',
          'der Posteingang darf nur gelesen werden')

# Und es darf gar keine Schreibfunktion fuer die Mails geben.
for _name in ('send_mail', 'reply_mail', 'insert_mail_message',
              'delete_mail_message', 'update_mail_message'):
    check(f'FUNCTION public.{_name}' not in all_sql,
          f'DB: Es gibt keine Funktion {_name}()',
          'aus der App heraus wird nicht geantwortet')

# =====================================================================
# 1h) Die selektive Datenloeschung loescht NUR die eigenen Daten
# =====================================================================
#
# BETREIBER-ENTSCHEIDUNG (03.11.2026): "Biete ich Nutzern die
# Moeglichkeit das Entfernen einiger oder aller ihrer Daten anzufordern,
# ohne dass dabei das Konto geloescht werden muss?"
#
# Die Edge Function loescht mit der Service-Rolle - das ist der einzige
# Weg, die Daten wirklich zu entfernen (RLS und der normale Client
# duerfen das nicht). Damit ist die Function die kritische Stelle: sie
# muss die Identitaet des Aufrufers BEWEISEN, bevor sie loescht.

_loesch_funktion = 'supabase/functions/delete-user-data/index.ts'

check(has(_loesch_funktion, 'auth.getUser(token)'),
      'APP/SERVER: delete-user-data prueft das JWT des Aufrufers',
      'ohne Identitaetsnachweis wuerde die Funktion mit der '
      'Service-Rolle fuer jeden loeschen koennen')

check(has(_loesch_funktion, 'if (!token) return json({ error: "Unauthorized" })')
      or has(_loesch_funktion, 'if (!token)'),
      'SERVER: delete-user-data lehnt Anrufe ohne Token ab',
      'die Funktion schreibt mit der Service-Rolle - ohne Token waere das '
      'eine offene Loeschschnittstelle')

check(has(_loesch_funktion, '.eq("user_id", uid)'),
      'SERVER: delete-user-data filtert auf die eigene user_id',
      'die Loeschung muss sich auf das Konto des Aufrufers beschraenken')

# Und die Loeschung darf nicht ins Konto selbst eingreifen - das
# loescht die separate delete-account-Funktion (mit MFA-Step-up).
check('delete-user-data' not in all_sql
      or 'auth.users' not in _neueste_definition(all_sql, 'delete_user_data'),
      'SERVER: Die selektive Loeschung loescht kein Konto',
      'das Konto zu loeschen ist ein eigener Vorgang mit MFA-Bestaetigung')

# =====================================================================
# 1i) Keine Session-Fixierung ueber einen Deep-Link
# =====================================================================
#
# SICHERHEIT (03.11.2026): "thestia://" ist ein EXPORTIERTES Custom
# Scheme. Jede App auf dem Geraet kann die Thestia-App mit einer URI
# starten. Uebernimmt die App eine URI mit access_token oder
# token_hash, legt sie eine Session fuer genau dieses Konto an - ohne
# jeden Nachweis, dass der Nutzer den Link in seiner E-Mail geoeffnet
# hat. Eine boesartige App koennte so den Passwort-Reset-Screen mit
# dem Konto des Angreifers oeffnen; alles, was der Nutzer danach
# hochlaedt, landet im Konto des Angreifers.
#
# Beide von uns genutzten Flows sind PKCE-basiert (resetPasswordForEmail
# und signUp senden einen code_challenge) - der Link enthaelt deshalb
# einen ?code=..., der nur mit dem geräteeigenen code_verifier
# eingeloest werden kann. Die Formen access_token und token_hash sind
# ungenutzte Freiheitsgrade und genau die Angriffsflaeche.
check("has('access_token') || has('token_hash')" in
      read(ROOT / 'lib' / 'main.dart') and
      "return false;" in read(ROOT / 'lib' / 'main.dart'),
      'APP: Der Deep-Link-Filter lehnt access_token und token_hash ab',
      'sonst kann eine fremde App die Thestia-App in eine fremde Session '
      'zwingen (Session-Fixierung)')

# =====================================================================
# 1j) Heruntergeladen wird nur von eigenen Hosts
# =====================================================================
check('_istErlaubterHost' in
      read(ROOT / 'lib' / 'services' / 'supabase_storage_service.dart'),
      'APP: Download-URLs werden gegen eine Host-Liste geprueft',
      'eine URL aus dem Backend darf die App nicht auf einen beliebigen '
      'Host schicken')

check("uri.scheme != 'https'" in
      read(ROOT / 'lib' / 'services' / 'unified_push_service.dart'),
      'APP: Der UnifiedPush-Endpunkt muss HTTPS sein',
      'sonst wuerden die Push-Metadaten im Klartext uebertragen')

# =====================================================================
# 1k) Das BLE-Funk-Radio schweigt im Hintergrund
# =====================================================================
check('TransitBleService.instance.suspend()' in
      read(ROOT / 'lib' / 'providers' / 'transit_provider.dart'),
      'APP: Das BLE-Advertising wird im Hintergrund abgeschaltet',
      'das Advertising lief sonst bis zu 45 Minuten im 100-ms-Takt weiter - '
      'das ist Akku- und Datenschutzproblem in einem')

# =====================================================================
# 1l) Die Neugeraete-Warnung entscheidet der SERVER, nicht die App
# =====================================================================
#
# SICHERHEIT (03.11.2026): Die App meldet ihr Geraet nach dem Login.
# Ob es ein NEUES Geraet ist, entscheidet die Edge Function - nicht der
# Client. Andernfalls koennte ein Angreifer mit gestohlenem Passwort den
# Alarm unterdruecken, indem er selbst festlegt "bekanntes Geraet".
_check = 'supabase/functions/notify-new-login/index.ts'
# NACH DEM BEFUND VOM 03.11.2026 ("Ich habe keine Mail bekommen, als ich
# die App Daten geloescht und mich neu angemeldet habe") wurde der Weg
# umgebaut:
#
# VORHER: Die App rief die Edge Function auf, die Funktion legte die
# Geraete-Zeile an und schickte die Mail. Faellt der Aufruf aus, geht
# die Mail NIE raus - das war der gemeldete Fall. Und die Bremse
# zaehlte die Geraete-Zeilen statt der Mails, also war sie nach
# fuenf Neuinstallationen dicht.
#
# JETZT: Der Trigger auf auth_devices (Migration 170) loest die Mail
# aus. Er feuert bei JEDEM INSERT - unabhaengig davon, wer geschrieben
# hat. Die Entscheidung faellt damit die Datenbank, nicht der Client.

check('trg_auth_devices_new_login' in all_sql,
      'DB: Der Trigger fuer die Neugeraete-Meldung sitzt auf auth_devices',
      'ohne Trigger haengt die Warnung am Aufruf der App - und faellt der '
      'aus, geht keine Mail raus')

check('consume_rate_limit' in
      _neueste_definition(all_sql, 'notify_new_login_device'),
      'DB: Die Bremse der Neugeraete-Meldung zaehlt die MAILS',
      'zaehlt sie die Geraete-Zeilen, unterdrueckt eine haeufig neu '
      'registrierende App jeden Alarm')

check("'new_login_mail:'" in
      _neueste_definition(all_sql, 'notify_new_login_device'),
      'DB: Die Bremse nutzt einen eigenen Schluessel',
      'sonst teilt sie sich die Sperre mit anderen Funktionen')

check('x-thestia-internal' in read(ROOT / _check),
      'SERVER: notify-new-login akzeptiert nur das interne Secret',
      'die Funktion wird aus dem Trigger gerufen - ein offener '
      'Mail-Aufruf waere eine Spam-Schleuse')

check('notify-new-login' in
      _neueste_definition(all_sql, 'notify_new_login_device'),
      'DB: Der Trigger ruft notify-new-login auf',
      'sonst wird die Mail gar nicht erst angestossen')

# =====================================================================
# 1m) Das Verifikationsvideo haengt an der FREIGABE, nicht am Upload
# =====================================================================
#
# BETREIBER-AUFTRAG (03.11.2026): "Sie sollen 30 Tage nach Verifizierung
# (nicht Upload sondern Genehmigung der Verifizierung) bleiben und nach
# 30 Tagen geloescht werden."
#
# Vorher lief die Frist ab dem Upload (Migration 160): ein Video, das
# Wochen auf die Sichtung wartete, wurde am Tag der Freigabe geloescht.

_video = _neueste_definition(all_sql, 'cleanup_verification_videos')
check('verification_approved_at' in _video,
      'DB: Die Video-Frist laeuft ab dem Zeitpunkt der Freigabe',
      'vorher lief sie ab dem Upload - ein Video, das Wochen auf die '
      'Sichtung wartete, wurde am Tag der Freigabe schon geloescht')

check('30 days' in _video,
      'DB: Die Video-Frist betraegt 30 Tage',
      'die Zusage der Datenschutzerklaerung muss im Code stehen')

check('90 days' in _video,
      'DB: Es gibt ein Sicherheitsnetz fuer Videos ohne Entscheidung',
      'ein Video, das ewig in der Pruefung liegt, braucht eine Grenze')

# Der Freigabe-Zeitpunkt muss beim Freigeben auch wirklich gesetzt
# werden - sonst laeuft die Frist nie an.
_verifizierung = (ROOT / 'supabase' / 'functions' / 'verify-account' /
                  'index.ts')
if _verifizierung.exists():
    check('verification_approved_at' in read(_verifizierung),
          'SERVER: verify-account setzt den Freigabe-Zeitpunkt',
          'ohne ihn startet die 30-Tage-Frist nie')

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
# BEFUND 04.11.2026: Der alte Aufruf war
# "listFactors !== \"function\") return false;" in EINER Zeile. Der
# neue Code prueft dieselbe Sache, aber mit einer eigenen Meldung
# davor - deshalb wird jetzt geprueft, dass der Block vorhanden ist
# UND danach "return false" folgt (fail-closed).
_mfa_block = re.search(
    r'typeof listFactors !== "function".{0,400}?return false;', c, re.S)
check(bool(_mfa_block),
      'EDGE: delete-account MFA-Pruefung fail-closed '
      '(fehlt die Admin-API, wird die Loeschung blockiert)')
check('MFA-Faktor-Pruefung fehlgeschlagen (fail-closed)' in c,
      'EDGE: delete-account MFA-catch fail-closed')

for name in ('request-unban', 'send-bug-report', 'prekeys'):
    c = read(FN / name / 'index.ts')
    # BEFUND 04.11.2026: Geprueft wird jetzt der LETZTE Eintrag aus
    # x-forwarded-for, nicht der erste.
    #
    # Cloudflare HAENGT die echte Client-IP an den Header an - der
    # erste Eintrag ist damit der vom Client frei waehlbare, der
    # letzte der von der Plattform gesetzte. Wer den ersten nimmt,
    # laesst sich mit "x-forwarded-for: 1.2.3.4" pro Anfrage ein
    # neues Limit-Key bauen.
    check('function clientIp' in c
          and 'split(",")' in c
          and 'split(",")[0]' not in c,
          f'EDGE: {name} IP korrekt geparst (kein Header-Rotations-Bypass)')
    check('cf-connecting-ip' in c,
          f'EDGE: {name} nimmt zuerst cf-connecting-ip '
          '(der Header, den Cloudflare bei jeder Anfrage neu setzt)')
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
# 8) Client und Server duerfen nicht auseinanderlaufen
# =====================================================================
#
# Am 04.11.2026 wurden zwei echte Abweichungen gefunden - beide waren
# "die App dachte etwas anderes als der Server":
#
#   a) Die Re-Authentifizierung fuer "E-Mail aendern" und "Passwort
#      aendern" rief signInWithPassword OHNE CAPTCHA-Token. GoTrue
#      prueft das CAPTCHA bei jedem Passwort-Grant - der Server lehnte
#      also jeden Versuch mit "Invalid login credentials" ab. Beide
#      Funktionen waren im Release komplett kaputt, und die Meldung
#      sah aus wie ein Tippfehler.
#
#   b) Die Untergrenze des Altersfilters stand in der App bei 16
#      (18-Jaehrige) bzw. 17 (19-Jaehrige), der Server liefert fuer
#      Erwachsene aber ausschliesslich Erwachsene (max_age_range_min
#      = greatest(alter - 10, 18)). Der Filter war damit TOT.
#
# Beide Abweichungen sind nur durch den ABGLEICH mit dem Server
# aufgefallen. Diese beiden Invarianten halten den Abgleich fest.

# (a) Jeder signInWithPassword-Aufruf im Client braucht einen Token.
#
# Gesucht wird nicht nach einem Aufruf an sich, sondern nach einem
# Aufruf OHNE "captchaToken" - das ist der Fehler.
re_auth_ohne_token = []
for dart in sorted(LIB.rglob('*.dart')):
    if 'generated' in dart.parts:
        continue
    inhalt = read(dart)
    pos = 0
    while True:
        treffer = inhalt.find('signInWithPassword(', pos)
        if treffer < 0:
            break
        # Bis zum schliessenden Aufrufzeichen schauen.
        ende = inhalt.find(');', treffer)
        block = inhalt[treffer:ende if ende > 0 else treffer + 400]
        if 'captchaToken' not in block:
            re_auth_ohne_token.append(
                '%s:%d' % (dart.relative_to(ROOT),
                           inhalt[:treffer].count(chr(10)) + 1))
        pos = treffer + 1

check(not re_auth_ohne_token,
      'APP: Jeder signInWithPassword-Aufruf gibt ein captchaToken mit '
      '(GoTrue prueft das CAPTCHA bei jedem Passwort-Grant)',
      ', '.join(re_auth_ohne_token))

# (b) Die Alters-Untergrenze der App muss der des Servers entsprechen.
#
# Server (Migration 154, max_age_range_min):
#   greatest(v_viewer_age - 10, CASE WHEN v_viewer_age < 18 THEN 16 ELSE 18 END)
#
# App (lib/utils/age_safety_rules.dart, minFilterAge):
#   Minderjaehrige: 16, ab 18: nie unter 18, sonst eigenes Alter - 10.
sql_alt = read(MIG / '154_youth_protection_hardening.sql')
check('CASE WHEN v_viewer_age < 18 THEN 16 ELSE 18 END' in sql_alt,
      'DB: max_age_range_min laesst fuer Erwachsene nie unter 18 zu')
check(has('lib/utils/age_safety_rules.dart',
          'if (viewerAge < 18) return 16;',
          'if (viewerAge <= 19) return 18;'),
      'APP: minFilterAge entspricht max_age_range_min (Minderjaehrige 16, '
      'ab 18 nie unter 18)')
check(has('lib/utils/age_safety_rules.dart',
          'final viewerMinderjaehrig = viewerAge < 18;'),
      'APP: canViewProfile nutzt die beidseitige Server-Regel '
      '(Minderjaehrige sehen nur Minderjaehrige)')

# =====================================================================
# 9) Edge Functions: Befunde aus dem Audit vom 04.11.2026
# =====================================================================
#
# Alle sechs folgenden Punkte sind am 04.11.2026 am Code verifiziert
# worden - die Kommentare in den Funktionen nennen den Grund. Jeder
# Punkt war eine echte Luecke, kein Fehlalarm.

# (1) Der MFA-Step-up bei der Account-Loeschung war TOT.
#
#     Der Aufruf war `client.auth.mfa.listFactors(userId)` - das ist
#     die NUTZER-API: sie nimmt kein Argument, braucht eine Session
#     des Clients (der Service-Key-Client hat keine) und liefert
#     { data: null }. Damit war die Faktorenliste immer leer und die
#     Pruefung immer "erfuellt" - ein Konto mit TOTP war mit einem
#     einfachen aal1-Token loeschbar.
#
#     Richtig ist die ADMIN-API: client.auth.admin.mfa.listFactors.
delete_account = read(FN / 'delete-account' / 'index.ts')
check('auth.admin' in delete_account
      and 'listFactors({ userId })' in delete_account,
      'EDGE: delete-account nutzt die Admin-MFA-API '
      '(client.auth.admin.mfa.listFactors) - sonst ist der MFA-Step-up tot')
# Der Kommentar im Code nennt den alten Aufruf auch - deshalb wird nur
# der CODE geprueft. "ohne //" reichte nicht: der alte Aufruf stand in
# einem Blockkommentar (Zeilen mit " * ").
def _ohne_kommentar(text):
    return '\n'.join(
        z for z in text.split('\n')
        if not z.strip().startswith(('//', '*', '/*')))


delete_account_code = _ohne_kommentar(delete_account)
check('listFactors(userId)' not in delete_account_code,
      'EDGE: delete-account ruft NICHT die Nutzer-MFA-API auf '
      '(liefert ohne Session immer eine leere Liste)')

# (2) delete-user-data loeschte auf einer Spalte, die es nicht gibt.
#
#     rate_limit_hits hat bucket_key, window_start und hit_count
#     (Migration 042) - aber KEINE Spalte "identifier". PostgREST
#     antwortete mit einem Spaltenfehler, die selektive Datenloeschung
#     meldete dauerhaft ok:false und die Zaehler blieben stehen.
delete_user_data = read(FN / 'delete-user-data' / 'index.ts')
# Die Kommentare nennen den alten Aufruf auch - deshalb wird nur der
# CODE geprueft (siehe _ohne_kommentar).
delete_user_data_code = _ohne_kommentar(delete_user_data)
check('.eq("identifier"' not in delete_user_data_code,
      'EDGE: delete-user-data loescht rate_limit_hits ueber bucket_key '
      '(die Spalte "identifier" gibt es nicht)')
check('"rate_limit_hits"' in delete_user_data
      and 'bucket_key' in delete_user_data,
      'EDGE: delete-user-data greift auf die Schluessel-Spalte zu')

# (3) Das Rate-Limit in request-unban war fail-OPEN.
#
#     `const { data: limited } = await ...` - der Fehler der RPC
#     wurde nicht ausgewertet. Bei einem RPC-Fehler war data === null,
#     und "null === false" ist false: die 3/h-Bremse fiel ersatzlos weg.
request_unban = read(FN / 'request-unban' / 'index.ts')
check('limitError' in request_unban,
      'EDGE: request-unban wertet den Fehler des Rate-Limits aus '
      '(fail-closed - sonst faellt die Bremse bei jedem Stoerfall weg)')

# (4) Die Client-IP kam aus einem Header, den der Client setzen kann.
#
#     "x-client-ip" ist KEIN Standard-Header von Supabase oder
#     Cloudflare (das ist eine Vercel/Netlify-Konvention). Edge
#     Functions reichen unbekannte Header unveraendert durch. Mit
#     "x-client-ip: 1.2.3.4" pro Anfrage war das IP-Limit zu umgehen.
ip_probleme = []
for ts in sorted(FN.rglob('index.ts')):
    inhalt = read(ts)
    if 'headers.get("x-client-ip")' in inhalt:
        ip_probleme.append('%s' % ts.relative_to(ROOT))
check(not ip_probleme,
      'EDGE: Keine Funktion liest die Client-IP aus "x-client-ip" '
      '(der Header ist vom Client frei waehlbar - die IP-Limits waren '
      'damit umgehbar)',
      ', '.join(ip_probleme))

# (5) E-Mail-Adressen wurden ungefiltert in ein LIKE-Muster gebaut.
#
#     In SQL ist "%" ein Platzhalter und "_" matcht ein beliebiges
#     Zeichen. Eine Adresse wie "%@beispiel.de" loeschte dadurch die
#     Rate-Limit-Buckets ALLER Adressen auf dieser Domain.
like_probleme = []
for ts in sorted(FN.rglob('index.ts')):
    inhalt = read(ts)
    # Die Kommentare nennen die alten Muster auch - nur der CODE zaehlt.
    code = _ohne_kommentar(inhalt)
    for treffer in re.finditer(r'\.like\("bucket_key",\s*([^)]*)\)', code):
        muster = treffer.group(1)
        # Wird direkt interpoliert, muss escapeLike da sein. Wird eine
        # Variable benutzt, muss die Datei escapeLike benutzen - die
        # Variable wird dann beim Bauen des Musters maskiert.
        if '${' in muster:
            if 'escapeLike' not in muster:
                like_probleme.append('%s' % ts.relative_to(ROOT))
        elif 'escapeLike' not in code:
            like_probleme.append('%s' % ts.relative_to(ROOT))
check(not like_probleme,
      'EDGE: Jedes LIKE-Muster auf bucket_key maskiert die Wildcards '
      '(escapeLike) - sonst loescht "%@domain.de" fremde Zaehler',
      ', '.join(sorted(set(like_probleme))))

# (6) check-location verglich sein internes Secret NICHT constant-time,
#     obwohl der Kommentar genau das behauptete. Die neun anderen
#     internen Funktionen nutzen timingSafeEqual.
check_location = read(FN / 'check-location' / 'index.ts')
check('timingSafeEqual' in check_location
      and '[...internalSecret].every' not in check_location,
      'EDGE: check-location vergleicht das interne Secret constant-time '
      '(timingSafeEqual)')

# (7) Die Nutzungszeit im Elternportal wurde ungeprueft gespeichert
#     und bei einem unvollstaendigen Request geloescht.
#
#     Migration 165 schrieb "usage_start_min = p_usage_start_min"
#     (ohne coalesce) - fehlte der Wert, war die elterliche
#     Beschraenkung weg, waehrend "usage_limit_enabled" weiter true
#     blieb. Migration 173 holt das nach.
# =====================================================================
# 11) Dating Hour: der automatische Funke nach 10 Minuten
# =====================================================================
#
# NUTZERWUNSCH 04.11.2026): Die 5 Minuten sind eine
# ENTSCHEIDUNGSphase, nicht das Ende des Gespraechs. Danach laeuft
# der Chat weiter, und nach 10 Minuten entsteht automatisch ein
# beidseitiger Funke - damit eine unterbrochene Verbindung nicht
# dazu fuehrt, dass zwei sich gut verstandene Menschen kein Match
# bekommen.
#
# Das wird vom CRON erzeugt, nicht vom Client: der Cron laeuft auch
# dann, wenn beide Apps geschlossen sind. Ein clientseitiger Funke
# waere genau die Sorte gruener Status, die nichts bedeutet.

sql_177 = read(MIG / '177_dating_hour_auto_match.sql')
sql_178 = read(MIG / '178_auto_match_in_match_list.sql')

check('ADD COLUMN IF NOT EXISTS auto_match_at timestamptz' in sql_177,
      'DB: dating_hour_session fuehrt die 10-Minuten-Marke (auto_match_at)')
check('ADD COLUMN IF NOT EXISTS auto_matched boolean' in sql_177,
      'DB: dating_hour_session merkt sich, dass der Funke automatisch war')
check('ADD COLUMN IF NOT EXISTS ended_by uuid' in sql_177,
      'DB: dating_hour_session merkt sich, wer das Gespraech beendet hat')
check('ADD COLUMN IF NOT EXISTS auto_match boolean' in sql_177,
      'DB: public.matches merkt sich den automatischen Funke')

# Der Cron erzeugt den automatischen Funke.
check('auto_match_at <= now()' in sql_177
      and 'auto_matched = true' in sql_177,
      'DB: Der Cron erzeugt den automatischen Funke nach 10 Minuten')
check('INSERT INTO public.matches(user_one_id, user_two_id, auto_match)'
      in sql_177,
      'DB: Der automatische Funke landet auch in der Match-Liste')

# Wer beendet, bekommt KEINEN automatischen Funke.
check('ended_by = v_user' in sql_177,
      'DB: Ein beendetes Gespraech merkt sich, wer es beendet hat')
check('CREATE OR REPLACE FUNCTION public.end_dating_hour_conversation'
      in sql_177,
      'DB: Eine Seite kann das Gespraech jederzeit beenden')
check("user_a_decision = CASE WHEN user_a = v_user THEN 'reject'"
      in sql_177,
      'DB: Das Beenden verwirft ein laufendes "Ja" - wer beendet, meint es')

# Die Rueckfrage: einmalig, behalten oder entfernen.
check('CREATE OR REPLACE FUNCTION public.resolve_dating_hour_auto_match'
      in sql_177,
      'DB: Die Rueckfrage zum automatischen Funke gibt es (einmalig)')
check('SET auto_match = false' in sql_177,
      'DB: "Behalten" entfernt nur den Hinweis, der Funke bleibt')
check('DELETE FROM public.matches' in sql_177,
      'DB: "Person entfernen" loescht den Funke')

# Die Liste muss das Feld auch LIEFERN - sonst bleibt das Sternchen
# stumm (BEFUND 04.11.2026).
check("'autoMatch', coalesce(m.auto_match, false)" in sql_178,
      'DB: Die Match-Liste liefert das Kennzeichen mit - sonst bleibt '
      'der Hinweis auf dem Interessen-Screen unsichtbar')

# Der Client: der Chat bleibt nach den 5 Minuten bedienbar.
check(has('lib/screens/dating_hour/dating_hour_chat_screen.dart',
          "'dh.chat.fiveMinutesDone'",
          'MessageType.notice',
          'endConversation'),
      'APP: Die Fuenf-Minuten-Marke steht mittig im Chat und das '
      'Gespraech laeuft weiter')
check(has('lib/services/dating_hour_service.dart',
          'end_dating_hour_conversation',
          'resolve_dating_hour_auto_match'),
      'APP: Der Client kann das Gespraech beenden und die Rueckfrage '
      'zum automatischen Funke beantworten')

# =====================================================================
# 10) Dating Hour: der Cron-Fund und die Nutzungszeit
# =====================================================================
#
# BEFUND 04.11.2026: Die Dating Hour hat seit dem 03.11.2026 nicht mehr
# gepaart, und niemand hat es gemerkt.
#
# Die Ursache: match_dating_hour_round pruefte den AUFRUFER
#     IF NOT public.verification_granted(auth.uid()) THEN RAISE ...
# Die Funktion wird aber ausschliesslich vom Cron aufgerufen (alle 30
# Sekunden) - ohne JWT. auth.uid() ist dort NULL,
# verification_granted(NULL) ist false, also hat der Cron bei der
# ERSTEN aktiven Veranstaltung geworfen und die ganze Runde
# abgebrochen. Es wurde also ueberhaupt nicht mehr gepaart.
#
# Die App ruft die Funktion NICHT selbst auf (nur join_dating_hour) -
# der Cron war der einzige Weg.

sql_176 = read(MIG / '176_email_timezone_usage_time.sql')
sql_161 = read(MIG / '161_verification_gates_server_side.sql')

# Der Aufrufer darf nur geprueft werden, wenn er selbst handelt.
check('auth.uid() IS NOT NULL' in sql_176
      and 'AND NOT public.verification_granted(auth.uid())' in sql_176,
      'DB: match_dating_hour_round prueft den Aufrufer NUR, wenn er selbst '
      'handelt - der Cron (ohne JWT) darf nicht die ganze Runde abbrechen')

# Und die Teilnehmer werden weiterhin geprueft.
check('public.verification_granted(v_user.user_id)' in sql_176,
      'DB: match_dating_hour_round prueft JEDEN Teilnehmer auf Verifikation')

# Die Nutzungszeit wird je Teilnehmer geprueft, nicht je Veranstaltung.
check(sql_176.count('public.guardian_usage_time_allows(') >= 3,
      'DB: Die elterliche Nutzungszeit wird je Teilnehmer der Dating Hour '
      'geprueft (nicht je Veranstaltung - sonst wuerde eine '
      'Beschraenkung die ganze Runde betreffen)')

# Die Gate-Funktion selbst.
check('CREATE OR REPLACE FUNCTION public.guardian_usage_time_allows' in sql_176,
      'DB: Die Gate-Funktion fuer die elterliche Nutzungszeit existiert')
check("AT TIME ZONE v_tz" in sql_176,
      'DB: Die Nutzungszeit wird in der LOKALEN Zeit des Geraets '
      'geprueft (jetzt at time zone, mit Sommerzeit)')
check('pg_timezone_names' in sql_176,
      'DB: Die Zeitzone wird gegen die PostgreSQL-Zeitzonendatenbank '
      'geprueft - ein unbekannter Name wuerde in "at time zone" einen '
      'Fehler ausloesen')

# Die Zeitzone kommt vom Geraet, nicht vom Server.
check('ADD COLUMN IF NOT EXISTS timezone text' in sql_176,
      'DB: profiles fuehrt die Zeitzone des Geraets (fuer die '
      'Nutzungszeit im lokalen Takt)')
check(has('lib/services/guardian_service.dart',
          'report_my_timezone', 'FlutterTimezone.getLocalTimezone()'),
      'APP: Der Client meldet seine Zeitzone an den Server - ohne sie '
      'kann der Server die Nutzungszeit nicht bewerten')

# profiles.email: damit admin-ban nicht die GoTrue-Nutzerliste
# abklopfen muss.
check('ADD COLUMN IF NOT EXISTS email text' in sql_176,
      'DB: profiles fuehrt die E-Mail-Adresse (fuer die Adminsuche)')
check('idx_profiles_email' in sql_176,
      'DB: Die E-Mail-Spalte ist indiziert (die Adminsuche ist eine '
      'Gleichheitsabfrage)')
check(has('supabase/functions/admin-ban/index.ts',
          '.from("profiles")', '.eq("email", email)'),
      'EDGE: admin-ban sucht die User-ID ueber profiles.email statt '
      'ueber einen Scan durch die GoTrue-Nutzerliste')

sql_173 = read(MIG / '173_guardian_settings_validation.sql')
check('usage_start_min     = coalesce(p_usage_start_min, usage_start_min)'
      in sql_173,
      'DB: Das Elternportal loescht die Nutzungszeit nicht, wenn der '
      'Request sie nicht mitschickt (coalesce)')
check('invalid_usage_time' in sql_173,
      'DB: Das Elternportal prueft den Bereich der Nutzungszeit '
      '(0..1439) - sonst wird "-5 Minuten seit Mitternacht" gespeichert')

# =====================================================================
# 12) Der Eltern-Link: 24 Stunden, und die E-Mail des Elternteils
#     verschwindet mit der Freigabe
# =====================================================================
#
# NUTZERWUNSCH 04.11.2026):
#
#   * "der Link statt 14 Tagen nur 24 Stunden gueltig sein" - nicht nur
#     im Text, sondern im Server. Ein Link, der zwei Wochen lebt, liegt
#     irgendwann in irgendeinem Postkasten und wird dann von einer
#     fremden Person benutzt.
#
#   * "die Emailadresse des Elternteils auch mit Beendigung der Freigabe
#     geloescht" - mit EINER Ausnahme: Wer "noch 1 Monat behalten"
#     waehlt, hat die Freigabe noch nicht beendet. Dann wird die Adresse
#     erst nach dem Monat geloescht, nicht sofort.
#
# Beides wird hier geprueft, damit es nicht wieder verschwindet.

sql_179 = read(MIG / '179_guardian_email_purge_and_24h_token.sql')

# --- Der Token gilt 24 Stunden ---------------------------------------
check(sql_179.count("now() + interval '24 hours'") >= 3,
      'DB: Der Freigabe-Link gilt 24 Stunden - an ALLEN Stellen '
      '(Anlegen, Erneuern, Bestand), nicht nur an einer')
check("token_expires_at = now() + interval '24 hours'," in sql_179,
      'DB: Auch der erneuerte Link gilt 24 Stunden')
check("interval '14 days'" not in sql_179,
      'DB: In der neuen Migration steht keine 14-Tage-Frist mehr')
check('least(token_expires_at, now() + interval \'24 hours\')' in sql_179,
      'DB: Der Bestand offener Links wird auf 24 Stunden gekuerzt '
      '(sonst waeren die alten Links weiterhin gueltig)')

# --- Die E-Mail des Elternteils wird geloescht ------------------------
check('ALTER COLUMN guardian_email DROP NOT NULL' in sql_179,
      'DB: Die Adresse des Elternteils ist optional - sonst koennte '
      'sie gar nicht geloescht werden')
check('ADD COLUMN IF NOT EXISTS email_deleted_at timestamptz' in sql_179,
      'DB: Der Loeschzeitpunkt wird vermerkt (der Nachweis, dass die '
      'Freigabe auch ihre Daten zurueckgibt)')
check('CREATE OR REPLACE FUNCTION public.purge_guardian_emails()'
      in sql_179,
      'DB: Es gibt eine Funktion, die die Adresse nach dem Ende loescht')
check("access_until <= now()" in sql_179,
      'DB: Die Nachfrist ("noch 1 Monat") beendet die Freigabe erst, '
      'wenn sie abgelaufen ist - die Adresse bleibt bis dahin')
check(sql_179.count('guardian_email  = NULL') >= 5,
      'DB: Alle drei Beendigungswege und die Aufraeumfunktion loeschen '
      'die Adresse des Elternteils')
check("'guardian-email-purge'" in sql_179,
      'DB: Der Cron raeumt die Adresse nach einer Nachfrist ab')
check('REVOKE ALL ON FUNCTION public.purge_guardian_emails()' in sql_179,
      'DB: Die Aufraeumfunktion laeuft nur fuer den service_role')

# --- Der Text sagt dasselbe -------------------------------------------
check(has('supabase/functions/guardian-consent/index.ts',
          'Der Link ist 24 Stunden g\u00fcltig.'),
      'EDGE: Die E-Mail an den Elternteil nennt 24 Stunden')
check('14 Tagen ungueltig' not in read(FN / 'guardian-consent' / 'index.ts'),
      'EDGE: In der Funktion steht keine 14-Tage-Frist mehr')

# Die Website: der Elternbereich und das Portal sagen dasselbe.
check(has('passkey-assets/eltern.html',
          'Der Link ist 24 Stunden g\u00fcltig',
          'w\u00f6chentlich'),
      'WEB: Der Elternbereich nennt 24 Stunden (und das kaputte '
      '"W\u00f6chentlich" ist repariert)')
check(has('passkey-assets/en/eltern.html',
          'The link is valid for 24 hours'),
      'WEB: Die englische Fassung nennt 24 hours')
check(has('passkey-assets/eltern-einstellungen.html',
          'Der Link ist 24 Stunden lang'),
      'WEB: Das Elternportal meldet einen abgelaufenen Link nach 24 Stunden')
check(has('passkey-assets/en/eltern/einstellungen.html',
          'The link is valid for 24 hours'),
      'WEB: Das englische Elternportal meldet 24 hours')

# Die Datenschutzerklaerung (Quelle und erzeugte Seiten).
check(has('docs/DATENSCHUTZ.md',
          'nach 24 Stunden ung\u00fcltig ist',
          'E-Mail-Adresse des Elternteils wird mit dem Ende der Freigabe'),
      'WEB: Die Datenschutzerklaerung nennt 24 Stunden und die '
      'Loeschung der Eltern-Adresse')
check(has('docs/DATENSCHUTZ_EN.md',
          'invalid after 24 hours',
          "parent's e-mail address is deleted when the approval ends"),
      'WEB: Die englische Datenschutzerklaerung nennt 24 hours und die '
      'Loeschung der Eltern-Adresse')

# --- Der Generator darf den Canonical nicht mehr verlieren ------------
# BEFUND 04.11.2026: Beim Neuerzeugen der Datenschutz-Seiten (etwa nach
# einer Textaenderung) verschwand die kanonische Adresse wieder. Die Seite
# war danach "nicht auffindbar" fuer die Suchmaschine - und der Fehler
# fiel nur auf, weil der Publish-Checker sie meldete.
check(has('tool/make_privacy_policy.py',
          "'canonical': 'https://thestia.de/datenschutz'",
          "'canonical': 'https://thestia.de/en/datenschutz'",
          '<link rel="canonical" href="%s">'),
      'TOOL: Der Generator der Datenschutz-Seiten schreibt die '
      'kanonische Adresse mit (sonst verschwindet sie beim Neuerzeugen)')

# =====================================================================
# 13) Die Website: gleiche Hoehe, mittiger Text, englische Fassungen
# =====================================================================
#
# NUTZERWUNSCH 04.11.2026): "Bei den Websites sind die Buttons fuer
# Sprache und Hell Dunkel Modus nicht auf der selben Hoehe! (Nur
# Elternbereich)" und "Das EN im Sprach button ist nicht mittig im
# Button."

# BEFUND 04.11.2026: Der Elternbereich hat eine seiten-eigene Formular-
# Regel "label { margin: 1rem 0 .35rem; }". Sie traf auch den
# Modus-Knopf - er ist ja ein <label> fuer den unsichtbaren Schalter.
# Dadurch sass er 5,6 px hoeher als der Sprachknopf daneben.
def css_block(text: str, sel: str) -> str:
    """Der Inhalt eines CSS-Blocks, z. B. '.modus-knopf { ... }'.

    Die Kommentare werden vorher entfernt: sonst bricht der erste
    '}' INNERHALB eines Kommentars den Block ab - und die Pruefung
    schlaegt dann an, obwohl das CSS korrekt ist.
    """
    ohne_kommentare = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    m = re.search(re.escape(sel) + r'\s*\{(.*?)\}', ohne_kommentare, re.S)
    return m.group(1) if m else ''


theme = read(ROOT / 'tool' / 'web_theme.py')
for _sel in ('.modus-knopf', '.sprach-knopf'):
    _block = css_block(theme, _sel)
    check('margin-top: 0;' in _block and 'margin-bottom: 0;' in _block,
          'WEB: %s beommt kein margin - eine seiten-eigene '
          'Formular-Regel darf die Kopfzeile nicht verschieben' % _sel)
    check('flex: 0 0 auto;' in _block,
          'WEB: %s wird nicht zusammengedrueckt (flex: 0 0 auto)' % _sel)
check('justify-content: center;' in css_block(theme, '.sprach-knopf'),
      'WEB: Der Sprachknopf zentriert sein Kuerzel (inline-flex)')

# Jede Seite hat eine englische Fassung und verlinkt auf sie. Das prueft
# tool/check_publish_folder.py (Abschnitt 9) - hier steht nur die
# Grundlage: die Bestaetigungsseite, die bis jetzt keine hatte.
check(has('passkey-assets/en/bestaetigt.html',
          '<html lang="en">',
          'E-Mail confirmed',
          'href="/bestaetigt"'),
      'WEB: Die Bestaetigungsseite hat eine englische Fassung')
check(has('passkey-assets/bestaetigt.html',
          'href="/en/bestaetigt"'),
      'WEB: Die Bestaetigungsseite verlinkt auf ihre englische Fassung')

# Die Tabellen: das pinke Element ist der Tabellenkopf. Ohne die
# abgerundete Huelle bleiben seine Ecken eckig.
def tabellen_ohne_huelle(rel: str) -> int:
    """Wie viele Tabellen haben KEINE abgerundete Huelle?

    Das pinke Element ist der Tabellenkopf (background:
    var(--accent-soft)). Ohne die Huelle mit ihrem Radius von 20 px
    bleiben seine Ecken eckig - das war der gemeldete Fehler.
    """
    inhalt = read(ROOT / rel)
    tabellen = len(re.findall(r'<table[ >]', inhalt))
    hüllen = len(re.findall(r'<div class="tabellen-huelle">', inhalt))
    return tabellen - hüllen


check(tabellen_ohne_huelle('passkey-assets/daten-loeschen.html') == 0,
      'WEB: JEDE Tabelle bei "Daten loeschen" sitzt in der abgerundeten '
      'Huelle - das pinke Element bekommt runde Ecken')
check(tabellen_ohne_huelle('passkey-assets/en/daten-loeschen.html') == 0,
      'WEB: Die englische Fassung hat dieselbe abgerundete Huelle')
check(tabellen_ohne_huelle('passkey-assets/eltern.html') == 0,
      'WEB: Auch die Tabelle im Elternbereich sitzt in der Huelle')
check(tabellen_ohne_huelle('passkey-assets/en/eltern.html') == 0,
      'WEB: Auch die englische Elternseite hat die Huelle')

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
