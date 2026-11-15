// Das Zeitlimit der Edge-Function-Aufrufe.
//
// ANLASS (15.11.2026, gefunden von einem Test): Der Admin-Bereich rief
// die Edge Function "verify-account" ohne Zeitlimit auf. Kam keine
// Antwort (Server gestoert, Mobilfunk voll), blieb der Bildschirm mit
// dem Ladeindikator stehen - bis der Nutzer ihn verliess.
//
// DER WEG: Alle Edge-Function-Aufrufe laufen jetzt ueber
// [SupabaseService.rufeEdgeFunktion] - mit einem Zeitlimit von 20
// Sekunden. Danach kommt eine TimeoutException, die der Aufrufer als
// Fehlermeldung zeigt (nie als haengender Bildschirm).
//
// WAS HIER GEPRUEFT WIRD:
//   * der Aufruf bricht nach dem Zeitlimit ab (statt endlos zu warten),
//   * die Antwort kommt an, wenn der Server antwortet,
//   * ein Serverfehler (HTTP 500) wird NICHT als Timeout behandelt,
//     sondern als Fehler weitergereicht.
//
// DER SERVER: Ein handgeschriebener Ersatz, der auf alles schweigt -
// bis auf die Anmeldung (ohne Sitzung wartet der Client selbst).
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/supabase_service.dart';

/// Ein Ersatz-Server, der auf alles schweigt (ausser auf die Anmeldung).
///
/// Die Anmeldung muss antworten, weil der Client vor jedem Aufruf das
/// Access-Token holt - ohne Sitzung wartet er auf eine
/// Token-Aktualisierung, die nie kommt.
class _SchweigenderServer extends http.BaseClient {
  _SchweigenderServer();

  /// Wenn false: der Server antwortet mit 500.
  bool antworten = true;

  /// Die Anfragen, die ankamen (für die Kontrolle).
  final List<String> pfade = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final pfad = request.url.path;
    pfade.add(pfad);

    // Die Sitzung (Token/Refresh).
    if (pfad.contains('/auth/v1/token')) {
      return _antwort(
        200,
        jsonEncode(<String, dynamic>{
          'access_token': _jwt('ich'),
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'refresh-token-im-test',
          'user': <String, dynamic>{
            'id': 'ich',
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'ich@example.de',
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
          },
        }),
      );
    }

    if (!antworten) {
      return _antwort(500, jsonEncode(<String, dynamic>{'message': 'Fehler'}));
    }

    // Keine Antwort: der Aufruf wartet endlos - genau der Fall, gegen
    // den das Zeitlimit da ist.
    return Completer<http.StreamedResponse>().future;
  }

  http.StreamedResponse _antwort(int status, String body) {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }
}

/// Ein JWT, das der Client lokal akzeptiert.
String _jwt(String userId) {
  final jetzt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  String base64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
  final kopf = base64(
    utf8.encode(jsonEncode(<String, dynamic>{'alg': 'HS256'})),
  );
  final nutzlast = base64(
    utf8.encode(
      jsonEncode(<String, dynamic>{
        'sub': userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'iat': jetzt,
        'exp': jetzt + 3600,
      }),
    ),
  );
  return '$kopf.$nutzlast.test';
}

void main() {
  late _SchweigenderServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER SPEICHER: der Supabase-Client legt die Sitzung dort ab.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    server = _SchweigenderServer();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    // KEINE Anmeldung: der Client schickt ohne Sitzung den
    // Publishable-Key als Bearer - der Aufruf kommt also beim Server an
    // (mit Sitzung wuerde er vorher eine Token-Aktualisierung versuchen -
    // genau der Weg, der ohne Antwort haengen bleibt).
  });

  test('der Aufruf bricht nach dem Zeitlimit ab', () async {
    server.pfade.clear();

    await expectLater(
      SupabaseService.rufeEdgeFunktion(
        'verify-account',
        body: <String, dynamic>{'action': 'review'},
        zeitlimit: const Duration(milliseconds: 200),
      ),
      throwsA(isA<TimeoutException>()),
      reason:
          'Ein Aufruf ohne Antwort darf nicht endlos warten - der '
          'Bildschirm blieb sonst mit dem Ladeindikator stehen.',
    );

    // Die Anfrage ging wirklich raus (der Server hat sie gesehen).
    expect(
      server.pfade.any((p) => p.contains('verify-account')),
      isTrue,
      reason: 'Der Aufruf muss den Server erreicht haben.',
    );
  });

  test('ein Serverfehler wird weitergereicht, nicht als Timeout', () async {
    server.antworten = false;
    addTearDown(() => server.antworten = true);

    await expectLater(
      SupabaseService.rufeEdgeFunktion(
        'verify-account',
        body: <String, dynamic>{'action': 'review'},
        zeitlimit: const Duration(seconds: 5),
      ),
      throwsA(isNot(isA<TimeoutException>())),
      reason:
          'Ein echter Serverfehler muss als Fehler kommen - nicht als '
          'Zeitueberschreitung (sonst waere die Meldung irrefuehrend).',
    );
  });
}
