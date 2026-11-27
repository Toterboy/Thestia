// Der Transit-Radar selbst (der Provider, nicht nur der Zustand).
//
// ANLASS (26.11.2026): Die Abdeckung zeigte für
// lib/providers/transit/transit_provider.dart 57 offene Zeilen. Der
// Zustand (Selbstbeschreibung, Modus) war getestet - der RADAR selbst
// nicht: das Starten des Funks, das Ausschalten, die Begegnungen und
// der Signal-Versand.
//
// DER WEG: Der Dienst hat eine Test-Naht (TransitPlattform), und im
// Test gibt es den Ersatz für das Bluetooth (test/support/ble_mocks.dart)
// - der zählt, wie oft das Advertising wirklich gestartet wurde.
//
// WAS HIER GEPRÜFT WIRD:
//   * das Radar startet den Funk wirklich (nicht nur die Anzeige),
//   * die Session hat ein Ende (45 Minuten),
//   * das Ausschalten beendet den Funk und lässt die Selbstbeschreibung
//     stehen (der "unsichtbar gewordene Knopf"-Fund),
//   * der Presence-Heartbeat geht zum Server,
//   * ohne Gerät in Reichweite sagt die App es selbst (kein stilles
//     "kein Match"),
//   * ohne den eigenen Token wird gar nicht erst gesendet,
//   * der Signal-Versand trägt den eigenen Token und die Begegnungen.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/providers/transit/transit_provider.dart';
import 'package:thestia/services/transit/transit_ble_service.dart';

import '../support/ble_mocks.dart';
import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Ersatz für die Plattform (Android 13).
class _FakePlattform extends TransitPlattform {
  @override
  bool get istWeb => false;

  @override
  bool get istAndroid => true;

  @override
  bool get istIOS => false;

  @override
  Future<int> androidSdkInt() async => 33;
}

void main() {
  late FakeSupabaseServer server;
  late TransitNotifier notifier;

  /// Ein gültiges Token (20 Hexzeichen).
  const fremdesToken = 'bbbbbbbbbbbbbbbbbbbb';

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

  /// Legt eine frische Begegnung in den Cache (der Keystore).
  void legeBegegnungAn() {
    keystoreInhalt['transit_encounters'] = jsonEncode(<Map<String, String>>[
      <String, String>{
        't': fremdesToken,
        'at': DateTime.now().toIso8601String(),
      },
    ]);
  }

  setUp(() {
    TransitPlattform.instance = _FakePlattform();
    mockBluetooth();
    resetAdvertisingZaehler();
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
    server.rpcFehler.clear();
    // DER CACHE: Der Begegnungs-Cache liegt im Keystore - ohne das
    // Leeren hätte der nächste Test die Begegnungen des vorherigen.
    keystoreInhalt.remove('transit_encounters');
    notifier = TransitNotifier();
  });

  tearDown(() async {
    await TransitBleService.instance.stop();
    notifier.dispose();
  });

  group('Das Starten', () {
    test('der Funk startet wirklich', () async {
      final ok = await notifier.activate();

      expect(ok, isTrue);
      expect(
        advertisingStarts,
        greaterThan(0),
        reason:
            'Das Advertising muss wirklich gestartet werden - sonst sagt '
            'nur die Anzeige "aktiv".',
      );
      expect(notifier.state.active, isTrue);
    });

    test('die Session hat ein Ende', () async {
      await notifier.activate();

      final ende = notifier.state.endsAt;
      expect(ende, isNotNull);
      expect(
        ende!.difference(DateTime.now()).inMinutes,
        inInclusiveRange(43, 45),
        reason: 'Die Session läuft 45 Minuten.',
      );
    });

    test('ein zweites Starten ändert nichts', () async {
      await notifier.activate();
      final starts = advertisingStarts;

      final ok = await notifier.activate();

      expect(ok, isTrue);
      expect(advertisingStarts, starts);
    });
  });

  group('Das Ausschalten', () {
    test('der Funk hört auf', () async {
      await notifier.activate();

      await notifier.deactivate();

      expect(notifier.state.active, isFalse);
      expect(TransitBleService.instance.isActive, isFalse);
    });

    test('die Selbstbeschreibung bleibt stehen', () async {
      notifier.setSelfTags(<String>['Musik']);
      notifier.setSelfNote('bin im Zug');
      notifier.setPlace(kind: 'Zug', text: 'Wagen 3');
      await notifier.activate();

      await notifier.deactivate();

      expect(
        notifier.state.selfTags,
        <String>['Musik'],
        reason:
            'Die Selbstbeschreibung darf beim Ausschalten nicht '
            'verschwinden - die Ergänzungskarte wäre weg.',
      );
      expect(notifier.state.selfNote, 'bin im Zug');
      expect(notifier.state.placeText, 'Wagen 3');
    });
  });

  group('Die Anwesenheit', () {
    test('der Heartbeat geht zum Server', () async {
      await notifier.activate();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final aufruf = server.rpcAufrufe.firstWhere(
        (z) => z['funktion'] == 'transit_presence_heartbeat',
        orElse: () => <String, dynamic>{},
      );
      expect(aufruf, isNotEmpty, reason: 'Der Server muss den Token kennen.');
      expect('${aufruf['p_token']}'.length, 20);
    });

    test('das Ausschalten meldet die Abwesenheit', () async {
      await notifier.activate();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      await notifier.deactivate();

      expect(
        server.rpcAufrufe.any((z) => z['funktion'] == 'transit_presence_leave'),
        isTrue,
        reason:
            'Radar aus = nicht mehr adressierbar - der Server muss das '
            'wissen.',
      );
    });
  });

  group('Die Begegnungen', () {
    test('sie stehen in der Liste', () async {
      legeBegegnungAn();
      final neuer = TransitNotifier();
      addTearDown(neuer.dispose);
      // Das Laden des Caches läuft im Hintergrund - kurz warten.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(neuer.hasSoftEncounters, isTrue);
      expect(neuer.softEncounters(), hasLength(1));
      expect(neuer.softUntil(), isNotNull);
    });

    test('ohne Begegnung ist die Liste leer', () {
      expect(notifier.hasSoftEncounters, isFalse);
      expect(notifier.softUntil(), isNull);
    });
  });

  group('Der Signal-Versand', () {
    test('ohne laufenden Radar wird nicht gesendet', () async {
      final ergebnis = await notifier.sendSpark(<String>['Musik']);

      expect(ergebnis, isNull);
      expect(
        server.rpcAufrufe.any((z) => z['funktion'] == 'match_proximity_spark'),
        isFalse,
      );
    });

    test('ohne Gerät in Reichweite sagt die App es selbst', () async {
      await notifier.activate();

      final ergebnis = await notifier.sendSpark(<String>['Musik']);

      expect(ergebnis, isNull);
      expect(
        notifier.state.lastError,
        'no_devices',
        reason:
            'Ohne Gerät in Reichweite ist das kein Fehler, sondern eine '
            'Lage - die App muss es sagen, statt still zu schweigen.',
      );
      expect(notifier.state.busy, isFalse);
    });

    test('ohne den eigenen Token wird gar nicht erst gesendet', () async {
      legeBegegnungAn();
      final neuer = TransitNotifier();
      addTearDown(neuer.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await neuer.activate();
      // Der Funk geht aus, der Provider hält den Radar aber aktiv.
      await TransitBleService.instance.stop();

      final ergebnis = await neuer.sendSpark(<String>['Musik']);

      expect(ergebnis, isNull);
      expect(neuer.state.lastError, 'own_token_missing');
    });

    test('der Versand trägt den eigenen Token und die Begegnungen', () async {
      legeBegegnungAn();
      final neuer = TransitNotifier();
      addTearDown(neuer.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await neuer.activate();
      server.rpcAntworten['match_proximity_spark'] = <String, dynamic>{
        'matched': true,
        'partner': 'sie',
      };

      final ergebnis = await neuer.sendSpark(<String>['Musik']);

      expect(ergebnis?.matched, isTrue);
      expect(ergebnis?.partnerId, 'sie');
      final aufruf = server.rpcAufrufe.firstWhere(
        (z) => z['funktion'] == 'match_proximity_spark',
        orElse: () => <String, dynamic>{},
      );
      expect(aufruf, isNotEmpty);
      expect(
        aufruf['p_self_token'],
        TransitBleService.instance.currentToken,
        reason:
            'Ohne den eigenen Token kann der Server die Frage "hat der '
            'andere mich gesehen?" nicht beantworten.',
      );
      expect(
        aufruf['p_tokens'],
        contains(fremdesToken),
        reason: 'Die gesehenen Geräte gehen mit dem Signal zum Server.',
      );
    });
  });
}
