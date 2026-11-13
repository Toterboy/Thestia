// Gemeinsame Helfer fuer die Live-Nachweise.
//
// WOFUER: Zwei Tests sprechen mit dem echten Server (echte Konten,
// echte Schluessel, echte Krypto). Beide brauchen dieselben vier
// Dinge: die .env lesen, eine Sitzung fuer ein Konto, einen
// RPC-Aufruf und das PreKey-Bundle des Partners.
//
// DIE REGEL: Die Live-Tests sind die EINZIGEN Tests, die das
// Produktivsystem anruehren. Deshalb steht hier auch die Regel, wie
// sie ihre Testdaten wieder loswerden:
//
//     tool/cleanup_transit_testdata.sql
//
// Die Tests raeumen selbst ab, was sie ablegen koennen (die
// Relay-Zeile ueber relay_ack). Die Likes und der Match bleiben
// stehen, weil die App keine Funktion hat, sie zu loeschen - das
// Skript nimmt sie danach weg.
//
// WICHTIG: Der PreKey-Endpunkt gibt das Bundle eines Partners nur
// heraus, wenn zwischen beiden eine BEZIEHUNG besteht (Match oder
// Transit-Signal). Ohne sie antwortet er mit 404 "nicht verfuegbar".
// Die Tests bauen die Beziehung deshalb vorher auf.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Die zwei Testkonten (echte Konten auf dem Projekt).
///
/// WICHTIG: Das sind die Konten des Betreibers. Der Live-Test legt
/// dort Likes und einen Match an und raeumt sie danach ueber
/// tool/cleanup_transit_testdata.sql wieder weg. Die Konten selbst
/// werden NICHT veraendert.
const String kontoA = '46f3f558-b134-4d25-946b-4e052a8ab3b5';
const String kontoB = 'd177d5f9-f2d0-420e-981b-4d6ef5b77056';

/// Liest die .env im Projektverzeichnis.
Map<String, String> envLesen() {
  final datei = File('.env');
  if (!datei.existsSync()) return {};
  final werte = <String, String>{};
  for (final zeile in datei.readAsLinesSync()) {
    if (zeile.contains('=') && !zeile.trimLeft().startsWith('#')) {
      final teile = zeile.split('=');
      werte[teile.first.trim()] = teile.sublist(1).join('=').trim();
    }
  }
  return werte;
}

/// Sind alle Schluessel da? Ohne sie ueberspringen die Live-Tests
/// (der CI hat keine Schluessel).
///
/// **ACHTUNG, LEERER WERT:** Ein Schluessel, der in der .env zwar
/// NOTIERT, aber leer ist, gilt als **nicht vorhanden** (BEFUND
/// 13.11.2026: die .env hatte nach der Wiederherstellung die Zeile
/// `SUPABASE_SECRET_KEY_NEW =` - leer. Die Live-Tests liefen trotzdem
/// und scheiterten mit 401, statt sich ueberzuppringen).
bool hatSchluessel(Map<String, String> env) {
  bool hat(String schluessel) => (env[schluessel] ?? '').trim().isNotEmpty;
  return hat('SUPABASE_URL') &&
      hat('SUPABASE_PUBLISHABLE_KEY') &&
      (hat('SUPABASE_SECRET_KEY_NEW') ||
          hat('SUPABASE_SECRET_KEY') ||
          hat('SUPABASE_SERVICE_ROLE_KEY'));
}

/// Duerfen die Live-Tests ueberhaupt laufen?
///
/// ZWEI Bedingungen:
///   1. Die .env muss die Schluessel enthalten (die CI hat keine).
///   2. `THESTIA_SKIP_LIVE_TESTS=1` schaltet sie ab.
///
/// **WARUM (13.11.2026):** Der lokale CI-Spiegel
/// (tool/check_local_ci.ps1) hat frueher die .env des Entwicklers
/// durch die .env.example ersetzt - damit die Live-Tests nicht gegen
/// das Produktivsystem laufen - und sie danach **nicht** zurueckgespielt.
/// Die echten Werte waren damit weg (sie mussten aus dem Release-Build
/// und der Supabase-API wiederhergestellt werden).
///
/// Jetzt wird nichts mehr ueberschrieben: der Spiegel setzt nur diese
/// Umgebungsvariable, und die Live-Tests springen sich selbst ueber.
/// Die .env des Entwicklers bleibt unangetastet.
bool liveTestsLaufen(Map<String, String> env) =>
    hatSchluessel(env) &&
    Platform.environment['THESTIA_SKIP_LIVE_TESTS'] != '1';

/// Der Schluessel, mit dem die App den Server anspricht.
String? publishableKey(Map<String, String> env) =>
    env['SUPABASE_PUBLISHABLE_KEY'];

/// Der Schluessel fuer die Admin-Operationen (Session-Erzeugung).
String? adminKey(Map<String, String> env) =>
    env['SUPABASE_SECRET_KEY_NEW'] ??
    env['SUPABASE_SECRET_KEY'] ??
    env['SUPABASE_SERVICE_ROLE_KEY'];

/// Eine echte Sitzung fuer ein Konto (ueber den Admin-Magic-Link).
///
/// WARUM DER WIEDERHOLUNSLAUF: `flutter test` startet die Testdateien
/// parallel. Jede Live-Test-Datei erzeugt fuer DIESELBEN beiden Konten
/// einen Magic-Link - und ein zweiter Link fuer dieselbe Adresse
/// entwertet den ersten. Ohne Wiederholung schlug deshalb ab und zu
/// einer der beiden Live-Tests mit "Keine Sitzung fuer A/B" fehl
/// (gemessen am 08.11.2026). Der Link wird deshalb bei einem
/// fehlgeschlagenen verify neu erzeugt.
Future<String?> sitzung(
  Map<String, String> env,
  String kontoId,
  http.Client client,
) async {
  final url = env['SUPABASE_URL']!;
  final publicKey = publishableKey(env)!;
  final secret = adminKey(env)!;
  final kopf = {'apikey': secret, 'Authorization': 'Bearer $secret'};

  final liste = await client.get(
    Uri.parse('$url/auth/v1/admin/users?per_page=50'),
    headers: kopf,
  );
  if (liste.statusCode != 200) return null;
  final roh = jsonDecode(liste.body);
  final alle = roh is List
      ? roh.cast<Map<String, dynamic>>()
      : ((roh as Map)['users'] as List).cast<Map<String, dynamic>>();
  final nutzer = alle.firstWhere(
    (u) => u['id'] == kontoId,
    orElse: () => <String, dynamic>{},
  );
  final email = nutzer['email'] as String?;
  if (email == null) return null;

  for (var versuch = 0; versuch < 3; versuch++) {
    final link = await client.post(
      Uri.parse('$url/auth/v1/admin/generate_link'),
      headers: kopf,
      body: jsonEncode({'type': 'magiclink', 'email': email}),
    );
    if (link.statusCode != 200) continue;
    final hash = (jsonDecode(link.body) as Map)['hashed_token'] as String?;
    if (hash == null) continue;

    final verify = await client.post(
      Uri.parse('$url/auth/v1/verify'),
      headers: {'apikey': publicKey},
      body: jsonEncode({'type': 'magiclink', 'token_hash': hash}),
    );
    if (verify.statusCode != 200) continue;
    final token = (jsonDecode(verify.body) as Map)['access_token'] as String?;
    if (token != null) return token;
  }
  return null;
}

/// Ein Aufruf einer Datenbank-Funktion (so wie die App sie ruft).
Future<http.Response> rpc(
  Map<String, String> env,
  http.Client client,
  String name,
  Map<String, dynamic> params,
  String token,
) {
  return client.post(
    Uri.parse('${env['SUPABASE_URL']!}/rest/v1/rpc/$name'),
    headers: {
      'apikey': publishableKey(env)!,
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode(params),
  );
}

/// Das PreKey-Bundle des Partners (so wie die App es holt).
Future<Map<String, dynamic>?> bundleHolen(
  Map<String, String> env,
  String peerId,
  String token,
  http.Client client,
) async {
  final antwort = await client.get(
    Uri.parse('${env['SUPABASE_URL']!}/functions/v1/prekeys/$peerId'),
    headers: {'apikey': publishableKey(env)!, 'Authorization': 'Bearer $token'},
  );
  if (antwort.statusCode != 200) return null;
  return jsonDecode(antwort.body) as Map<String, dynamic>;
}

/// Sorgt fuer die Beziehung zwischen den beiden Testkonten.
///
/// WARUM: Der PreKey-Endpunkt gibt das Bundle nur heraus, wenn eine
/// Beziehung besteht. Ohne sie waere der Live-Nachweis nicht
/// moeglich - und genau deshalb ist das auch ein Test: die Kette
/// "Like -> Match -> Bundle -> Nachricht" muss von Anfang bis Ende
/// funktionieren.
///
/// DER RUECKGABE-WERT: true, wenn der zweite Like einen Match erzeugt
/// hat (der beidseitige Like), false, wenn nur der erste Like steht.
Future<bool> beziehungAufbauen(
  Map<String, String> env,
  http.Client client,
  String tokenA,
  String tokenB,
) async {
  final likeA = await rpc(env, client, 'create_match_if_mutual', {
    'p_liked_user_id': kontoB,
  }, tokenA);
  if (likeA.statusCode != 200) {
    throw StateError('Der erste Like scheiterte: ${likeA.body}');
  }

  final likeB = await rpc(env, client, 'create_match_if_mutual', {
    'p_liked_user_id': kontoA,
  }, tokenB);
  if (likeB.statusCode != 200) {
    throw StateError('Der zweite Like scheiterte: ${likeB.body}');
  }
  return (jsonDecode(likeB.body) as Map)['is_match'] == true;
}
