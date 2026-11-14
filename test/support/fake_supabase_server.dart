// Ein winziger Ersatz fuer den Supabase-Server - fuer die Tests.
//
// WOFUER: Zwei Bildschirme schreiben ueber PostgREST und lesen zur
// Kontrolle wieder zurueck: der Profil-Editor ("Lokal gespeichert.
// Server-Sync fehlgeschlagen") und der Admin-Bereich (die Listen
// kommen aus SECURITY DEFINER-RPCs). Ohne Server laeuft der
// Schreibvorgang ins Leere - der Test koennte dann nur noch pruefen
// "nichts ist passiert".
//
// Mit diesem Fake kann ein Test beide Faelle stellen:
//   * der Server antwortet (200) - die App meldet Erfolg,
//   * der Server schweigt (500)     - die App meldet den Fehlschlag.
//
// DER FAKE HAELT DEN ZUSTAND: Ein Schreibvorgang wird gemerkt und bei
// der naechsten Lese-Anfrage zurueckgespiegelt. Genau so arbeitet der
// echte Server mit seiner Verifikation ("per Zuruecklesen bestaetigen")
// - sonst wuerde jede Verifikation scheitern und die App wuerde
// grundlos einen Sync-Fehler melden.
//
// KEIN NETZ, KEINE ZEIT: Alles laeuft im RAM, es gibt keine Wartezeit
// und keine offenen Timer.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Der Fake-Server.
///
/// Er wird dem Supabase-Client bei [supabase.Supabase.initialize] als
/// `httpClient` uebergeben - danach laeuft JEDE Anfrage der App hier
/// hinein, statt ins Netz.
class FakeSupabaseServer extends http.BaseClient {
  FakeSupabaseServer({this.userId = 'test-user'});

  /// Die ID des Kontos, das angemeldet ist.
  final String userId;

  /// Wenn true, antwortet der Server mit einem Fehler (500).
  ///
  /// Damit laesst sich der Fall "der Server schweigt" stellen.
  bool antwortetMitFehler = false;

  /// Die Antworten der RPCs: Name der Funktion -> Antwort.
  ///
  /// Ohne Eintrag antwortet eine RPC mit `null`.
  final Map<String, Object?> rpcAntworten = <String, Object?>{};

  /// Die geschriebenen Zeilen je Tabelle.
  final Map<String, Map<String, dynamic>> zeilen =
      <String, Map<String, dynamic>>{};

  /// Die Schreibvorgaenge in der Reihenfolge - zum Nachpruefen.
  final List<Map<String, dynamic>> schreibvorgaenge = <Map<String, dynamic>>[];

  /// Wie viele Anfragen sind angekommen?
  int anfragen = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    anfragen++;
    final url = request.url;
    final pfad = url.path;

    if (antwortetMitFehler) {
      return _antwort(
        request,
        500,
        jsonEncode(<String, dynamic>{'message': 'Serverfehler'}),
      );
    }

    // Das eingeloggte Konto ("wer bin ich").
    if (pfad.endsWith('/auth/v1/user')) {
      return _antwort(request, 200, jsonEncode(_benutzer()));
    }

    // RPCs (PostgREST): die Admin-Listen und der Admin-Check.
    if (pfad.contains('/rest/v1/rpc/')) {
      const marker = '/rest/v1/rpc/';
      final name = pfad.substring(pfad.indexOf(marker) + marker.length);
      return _antwort(request, 200, jsonEncode(rpcAntworten[name]));
    }

    // Tabellen: lesen und schreiben.
    if (pfad.contains('/rest/v1/')) {
      const marker = '/rest/v1/';
      final tabelle = pfad.substring(pfad.indexOf(marker) + marker.length);
      if (request.method == 'GET') {
        return _antwort(request, 200, jsonEncode(_gelesen(tabelle, url)));
      }
      final body = await _leseBody(request);
      schreibvorgaenge.add(<String, dynamic>{'tabelle': tabelle, ...body});
      zeilen[tabelle] = <String, dynamic>{...?zeilen[tabelle], ...body};
      return _antwort(request, 200, '');
    }

    // Edge Functions (Sperren, Verifizierung, ...).
    if (pfad.contains('/functions/v1/')) {
      return _antwort(request, 200, jsonEncode(<String, dynamic>{}));
    }

    return _antwort(request, 200, '');
  }

  /// Die Antwort auf eine Lese-Anfrage.
  ///
  /// Gefragt wird nach bestimmten Spalten (`select=...`) - der Fake
  /// gibt genau die zurueck, die geschrieben wurden. Das entspricht
  /// dem echten Server und ist wichtig: die App prueft ihren Schreibvorgang
  /// per Zuruecklesen.
  ///
  /// WICHTIG (14.11.2026, gefunden von einem Test): PostgREST liefert
  /// bei einer Tabellen-Abfrage **immer ein Array** - auch bei genau
  /// einem Treffer. Der Fake gab vorher ein einzelnes Objekt zurueck;
  /// die Verifikation des Profils ("per Zuruecklesen bestaetigen")
  /// scheiterte daran und das Speichern brach ab, bevor der Name
  /// uebernommen wurde.
  dynamic _gelesen(String tabelle, Uri url) {
    final zeile = zeilen[tabelle] ?? <String, dynamic>{};
    final select = url.queryParameters['select'];
    if (select == null || select.isEmpty) {
      return <dynamic>[zeile];
    }
    final gewaehlt = <String, dynamic>{};
    for (final spalte in select.split(',')) {
      final name = spalte.trim();
      if (zeile.containsKey(name)) gewaehlt[name] = zeile[name];
    }
    return <dynamic>[gewaehlt];
  }

  /// Der JSON-Body einer Anfrage.
  Future<Map<String, dynamic>> _leseBody(http.BaseRequest request) async {
    if (request is! http.Request) return <String, dynamic>{};
    if (request.body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(request.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Kein JSON-Body - der Fake versteht nur Objekte.
    }
    return <String, dynamic>{};
  }

  /// Das Konto, das der Server kennt.
  Map<String, dynamic> _benutzer() {
    return <String, dynamic>{
      'id': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': '$userId@example.com',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'email_confirmed_at': '2026-01-01T00:00:00Z',
      'phone': '',
      'confirmed_at': '2026-01-01T00:00:00Z',
      'last_sign_in_at': '2026-01-01T00:00:00Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'identities': <dynamic>[],
      'is_anonymous': false,
    };
  }

  http.StreamedResponse _antwort(
    http.BaseRequest request,
    int status,
    String body,
  ) {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
      request: request,
    );
  }
}

/// Meldet ein Konto an - ohne echten Server.
///
/// Der Client akzeptiert ein selbstgebautes JWT (die Signatur wird
/// lokal nicht geprueft) und fragt danach beim Server, wer angemeldet
/// ist. Genau diese Frage beantwortet der [FakeSupabaseServer].
Future<void> alsNutzerAnmelden(
  supabase.SupabaseClient client,
  String userId,
) async {
  await client.auth.setSession(
    'refresh-token-im-test',
    accessToken: _jwt(userId),
  );
}

/// Ein JWT, das der Client lokal akzeptiert.
///
/// Die Signatur wird NICHT geprueft (es gibt keinen Server, der sie
/// pruefen koennte) - wichtig ist nur, dass der Payload ein gueltiges
/// Ablaufdatum hat.
String _jwt(String userId) {
  final jetzt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final kopf = _base64(
    jsonEncode(<String, dynamic>{'alg': 'HS256', 'typ': 'JWT'}),
  );
  final nutzlast = _base64(
    jsonEncode(<String, dynamic>{
      'sub': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'iat': jetzt,
      'exp': jetzt + 3600,
    }),
  );
  final signatur = _base64('test');
  return '$kopf.$nutzlast.$signatur';
}

/// Base64 ohne Fuellzeichen (so wie es JWTs tun).
String _base64(String text) {
  return base64Url.encode(utf8.encode(text)).replaceAll('=', '');
}
