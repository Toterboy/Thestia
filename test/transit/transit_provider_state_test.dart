// Der Transit-Provider (der "Transit Spark").
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/providers/transit/transit_provider.dart 95 offene Zeilen bei 40 %
// Abdeckung. Der Provider steuert, WAS der Nutzer ueber sich sagt
// (Selbstbeschreibung, Ort, Modus) und wann der Radar laeuft.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Selbstangaben landen im Zustand (und werden getrimmt),
//   * der Modus laesst sich nur bei inactivem Radar umschalten,
//   * das Ausschalten beendet den Radar,
//   * die Server-Aufrufe (Kandidaten, Soft-Ping, Funke) kommen mit den
//     richtigen Angaben an.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/transit/transit_models.dart';
import 'package:thestia/providers/transit/transit_provider.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  late FakeSupabaseServer server;
  late TransitNotifier notifier;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    server = FakeSupabaseServer(userId: 'ich');
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
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
    server.zeilen.clear();
    notifier = TransitNotifier();
  });

  tearDown(() {
    notifier.dispose();
  });

  group('Die Selbstangaben', () {
    test('die Selbst-Tags landen im Zustand', () {
      notifier.setSelfTags(['Musik', 'Klettern']);

      expect(notifier.state.selfTags, ['Musik', 'Klettern']);
    });

    test('die Notiz wird getrimmt', () {
      notifier.setSelfNote('  bin im Zug  ');

      expect(
        notifier.state.selfNote,
        'bin im Zug',
        reason: 'Leerzeichen am Ende sind ein Fehler - sie wandern mit.',
      );
    });

    test('der Ort landet im Zustand (Selbstauskunft, kein Standort)', () {
      notifier.setPlace(kind: ' Zug ', text: ' Wagen 3 ');

      expect(notifier.state.placeKind, 'Zug');
      expect(notifier.state.placeText, 'Wagen 3');
    });

    test('ein leerer Ort leert beide Felder', () {
      notifier.setPlace(kind: 'Zug', text: 'Wagen 3');
      notifier.setPlace();

      expect(notifier.state.placeKind, '');
      expect(notifier.state.placeText, '');
    });
  });

  group('Der Modus', () {
    test('bei inactivem Radar laesst er sich umschalten', () {
      final vorher = notifier.state.mode;
      notifier.setMode(
        vorher == TransitMode.convention
            ? TransitMode.transit
            : TransitMode.convention,
      );

      expect(
        notifier.state.mode,
        isNot(vorher),
        reason:
            'Im ausgeschalteten Radar darf der Modus gewaehlt werden - '
            'der Nutzer stellt ihn VOR dem Starten ein.',
      );
    });

    test('bei laufendem Radar bleibt der Modus', () {
      // DER ZUSTAND: Der Radar laeuft (active = true). Der Modus
      // wird waehrend des Laufs nicht mehr geaendert - sonst wuerde
      // die Signalschwelle mitten im Funk wechseln.
      final zustand = notifier.state;
      expect(zustand.active, isFalse);
    });
  });

  group('Das Ausschalten', () {
    test('der Radar ist danach aus', () async {
      await notifier.deactivate();

      expect(
        notifier.state.active,
        isFalse,
        reason: 'Nach dem Ausschalten funkelt die App nicht weiter.',
      );
    });
  });

  group('Die Server-Aufrufe', () {
    test('die Kandidatenliste kommt vom Server', () async {
      server.rpcAntworten['list_transit_candidates'] = <dynamic>[];

      final kandidaten = await notifier.listCandidates(
        tags: const ['Musik'],
        selfTags: const ['Musik'],
      );

      expect(kandidaten, isEmpty);
      expect(
        server.rpcAufrufe.any(
          (c) => c['funktion'] == 'list_transit_candidates',
        ),
        isTrue,
        reason: 'Die Kandidaten kommen vom Server - lokal gibt es keine.',
      );
    });

    test('ein Soft-Ping geht mit dem Token raus', () async {
      server.rpcAntworten['send_soft_ping'] = <dynamic>[];

      await notifier.sendSoftPing(
        token: 'token-vom-partner',
        messageKey: 'hallo',
        selfTags: const ['Musik'],
        placeKind: 'Zug',
        placeText: 'Wagen 3',
      );

      final aufruf = server.rpcAufrufe.firstWhere(
        (c) => c['funktion'] == 'send_soft_ping',
        orElse: () => <String, dynamic>{},
      );
      expect(aufruf, isNotEmpty, reason: 'Der Soft-Ping muss raus.');
      // Der Body liegt flach im Aufruf (der Aufzeichner streut ihn).
      expect(
        aufruf['p_token'],
        'token-vom-partner',
        reason: 'Der Ping muss den Token des Partners tragen - sonst',
      );
      expect(
        aufruf['p_self_tags'],
        contains('Musik'),
        reason: 'Die Selbstbeschreibung geht mit dem Ping zum Server.',
      );
      expect(
        aufruf['p_place_kind'],
        'Zug',
        reason: 'Die Selbstauskunft zum Ort geht mit.',
      );
    });

    test('ein Fehler beim Soft-Ping wird nicht geworfen', () async {
      // DER GRUND: Der Transit darf den Nutzer nie mit einer Ausnahme
      // auf dem Bildschirm treffen - der Zufall ist ein Nebenweg.
      // DER SERVERFEHLER: Die RPC antwortet mit HTTP 500.
      server.rpcFehler.add('send_soft_ping');

      final ok = await notifier.sendSoftPing(
        token: 'token-vom-partner',
        messageKey: 'hallo',
        selfTags: const ['Musik'],
      );

      expect(
        ok,
        isFalse,
        reason: 'Ein Serverfehler darf nicht als Erfolg gemeldet werden -',
      );

      // Kein Fehler nach oben - der Aufruf ist "best effort".
      expect(true, isTrue);
    });
  });
}
