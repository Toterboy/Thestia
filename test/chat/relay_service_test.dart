// Der Relay-Weg (Nachrichten ueber den Server, wenn der Kanal nicht steht).
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/relay_service.dart nur 43 % Abdeckung.
//
// DER WEG: Der Server ist der [FakeSupabaseServer] (test/support/
// fake_supabase_server.dart), der Verschluesselungs-Dienst der echte
// (ohne Session kann er nichts entschluesseln - so stellt der Test den
// Fall "die Nachricht laesst sich nicht lesen" her).
//
// WAS HIER GEPRUEFT WIRD:
//   * eine Nachricht von einem ANDEREN Chat wird uebersprungen (und
//     nicht quittiert - sie gehoert dem anderen Chat),
//   * eine unlesbare Nachricht bleibt im Relay (sie wird beim naechsten
//     Poll erneut versucht),
//   * erst nach fuenf Fehlversuchen wird sie verworfen (sonst waechst
//     das Relay endlos),
//   * ohne "ack" wird nichts quittiert.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/chat/relay_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  late Directory temp;
  late FakeSupabaseServer server;
  late EncryptionService encryption;
  late RelayService dienst;
  late ProviderContainer container;

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

    // DIE ADAPTER: die Boxen des Verschluesselungs-Dienstes halten
    // Signal-Objekte.
    Hive.registerAdapter(SignalIdentityKeyPairAdapterAdapter());
    Hive.registerAdapter(SignalPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSignedPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSessionRecordAdapterAdapter());
    Hive.registerAdapter(SignalSenderKeyRecordAdapterAdapter());
    Hive.registerAdapter(EncryptedMessageAdapterAdapter());
    Hive.registerAdapter(SignalIdentityKeyStoreAdapterAdapter());
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('thesia_relay');
    Hive.init(temp.path);
    server.rpcAufrufe.clear();
    server.rpcAntworten.clear();
    encryption = EncryptionService();
    await encryption.initialize();
    container = ProviderContainer(
      overrides: <Override>[
        encryptionServiceProvider.overrideWithValue(encryption),
      ],
    );
    addTearDown(container.dispose);
    dienst = container.read(relayServiceProvider);
  });

  tearDown(() async {
    await encryption.dispose();
    await Hive.close();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  /// Die Name der quittierten RPC-Aufrufe.
  List<String> quittierungen() => server.rpcAufrufe
      .map((a) => a['funktion'] as String? ?? '')
      .where((f) => f == 'relay_ack')
      .toList();

  group('Das Relay', () {
    test('eine Nachricht von einem anderen Chat wird uebersprungen', () async {
      server.rpcAntworten['relay_fetch'] = <dynamic>[
        <String, dynamic>{
          'id': 1,
          'sender': 'partner-2',
          'ciphertext': 'aGVsbG8=',
          'msgType': 1,
          'createdAt': '2026-11-25T12:00:00Z',
        },
      ];

      final nachrichten = await dienst.fetchPending(from: 'ich');

      expect(
        nachrichten,
        isEmpty,
        reason: 'Die Nachricht gehoert dem anderen Chat.',
      );
      expect(
        quittierungen(),
        isEmpty,
        reason:
            'Sie darf auch nicht quittiert werden - sonst waere sie fuer '
            'den anderen Chat weg.',
      );
    });

    test('eine unlesbare Nachricht bleibt im Relay', () async {
      server.rpcAntworten['relay_fetch'] = <dynamic>[
        <String, dynamic>{
          'id': 2,
          'sender': 'ich',
          'ciphertext': '',
          'msgType': 1,
          'createdAt': '2026-11-25T12:00:00Z',
        },
      ];

      final nachrichten = await dienst.fetchPending();

      expect(nachrichten, isEmpty, reason: 'Die Nachricht ist nicht lesbar.');
      expect(
        quittierungen(),
        isEmpty,
        reason:
            'Sie muss im Relay bleiben - sonst geht die Nachricht verloren, '
            'wenn die Session nur kurz fehlt.',
      );
    });

    test('nach fuenf Versuchen wird die Nachricht verworfen', () async {
      server.rpcAntworten['relay_fetch'] = <dynamic>[
        <String, dynamic>{
          'id': 3,
          'sender': 'ich',
          'ciphertext': '',
          'msgType': 1,
          'createdAt': '2026-11-25T12:00:00Z',
        },
      ];

      for (var i = 0; i < 4; i++) {
        await dienst.fetchPending();
      }
      expect(
        quittierungen(),
        isEmpty,
        reason: 'Nach vier Versuchen bleibt die Nachricht noch liegen.',
      );

      await dienst.fetchPending();

      expect(
        quittierungen(),
        isNotEmpty,
        reason:
            'Nach fuenf Versuchen wird die Nachricht endgueltig verworfen - '
            'sonst waechst das Relay endlos.',
      );
    });

    test('ohne "ack" wird nichts quittiert', () async {
      server.rpcAntworten['relay_fetch'] = <dynamic>[
        <String, dynamic>{
          'id': 4,
          'sender': 'ich',
          'ciphertext': '',
          'msgType': 1,
          'createdAt': '2026-11-25T12:00:00Z',
        },
      ];

      await dienst.fetchPending(ack: false);

      expect(
        quittierungen(),
        isEmpty,
        reason:
            'Ohne "ack" wird nichts quittiert - das ist der Weg fuer die '
            'Bildschirme, die ihre Zeilen selbst holen.',
      );
    });

    test('ohne Zeilen wird nichts quittiert', () async {
      server.rpcAntworten['relay_fetch'] = <dynamic>[];

      final nachrichten = await dienst.fetchPending();

      expect(nachrichten, isEmpty);
      expect(quittierungen(), isEmpty);
    });
  });
}
