// Die Hive-Adapter der Signal-Schlüssel.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte für
// lib/models/signal/signal_key_models.g.dart 113 offene Zeilen bei
// nur 22 % Deckung - der gesamte Speichervertrag der Ende-zu-Ende-
// Verschlüsselung war ungetestet.
//
// DER GRUND: In diesen Adaptern steckt die Schlüssel-Verwaltung der
// App. Schreibt ein Adapter ein Feld falsch (oder in der falschen
// Reihenfolge), kommt danach ein fremdes Schlüssel-Paar aus der Box -
// und die Nachrichten würden nicht mehr lesbar sein. Ein Fehler
// fällt hier niemandem auf: die App schweigt einfach.
//
// WAS HIER GEPRÜFT WIRD:
//   * jedes Objekt übersteht den Weg durch die Box (hin und zurück),
//   * alle Felder kommen unverändert an,
//   * die Typ-IDs sind eindeutig (zwei gleiche IDs würden die Box
//     zerstören),
//   * die Adapter sind gleich, wenn sie gleich sind.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/models/signal/signal_key_models.dart';

void main() {
  late Directory temp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DIE ADAPTER: Sie melden sich beim Hive an - ohne sie kennt die
    // Box die Typen nicht.
    Hive.registerAdapter(SignalIdentityKeyPairAdapterAdapter());
    Hive.registerAdapter(SignalPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSignedPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSessionRecordAdapterAdapter());
    Hive.registerAdapter(SignalSenderKeyRecordAdapterAdapter());
    Hive.registerAdapter(EncryptedMessageAdapterAdapter());
    Hive.registerAdapter(SignalIdentityKeyStoreAdapterAdapter());
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('thesia_adapter');
    Hive.init(temp.path);
  });

  tearDown(() async {
    await Hive.close();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  /// Schreibt ein Objekt in die Box und liest es zurück.
  ///
  /// DER WEG: Hive liefert ein gespeichertes Objekt aus dem Speicher
  /// zurück - der Adapter würde gar nicht benutzt. Erst nach dem
  /// Schließen und Wiederöffnen der Box wird wirklich von der Platte
  /// gelesen (und damit der `read` des Adapters ausgeführt).
  Future<T> hinUndZurueck<T>(String schluessel, T objekt) async {
    final box = await Hive.openBox<Object>('adapter_test');
    await box.put(schluessel, objekt as Object);
    await box.close();
    final neu = await Hive.openBox<Object>('adapter_test');
    final gelesen = neu.get(schluessel) as T;
    await neu.close();
    return gelesen;
  }

  group('Die Hive-Adapter der Signal-Schluessel', () {
    test('der Identity-Key kommt unveraendert zurueck', () async {
      final gelesen = await hinUndZurueck<SignalIdentityKeyPairAdapter>(
        'identity',
        SignalIdentityKeyPairAdapter(
          identityKeyPairJson: '{"privateKey":"abc","publicKey":"def"}',
        ),
      );

      expect(
        gelesen.identityKeyPairJson,
        '{"privateKey":"abc","publicKey":"def"}',
        reason:
            'Der Identity-Key muss unveraendert in der Box liegen - '
            'sonst ist die Ende-zu-Ende-Verschluesselung nach dem '
            'Neustart kaputt.',
      );
    });

    test('der PreKey kommt mit allen Feldern zurueck', () async {
      final gelesen = await hinUndZurueck<SignalPreKeyRecordAdapter>(
        'prekey',
        SignalPreKeyRecordAdapter(keyId: 42, keyPairJson: '{"preKey":"x"}'),
      );

      expect(gelesen.keyId, 42);
      expect(gelesen.keyPairJson, '{"preKey":"x"}');
    });

    test('der Signed-PreKey kommt mit allen Feldern zurueck', () async {
      final gelesen = await hinUndZurueck<SignalSignedPreKeyRecordAdapter>(
        'signed',
        SignalSignedPreKeyRecordAdapter(
          keyId: 7,
          keyPairJson: '{"signedPreKey":"s"}',
          signatureJson: '{"signature":"g"}',
          timestamp: 1763600000,
        ),
      );

      expect(gelesen.keyId, 7);
      expect(gelesen.keyPairJson, '{"signedPreKey":"s"}');
      expect(gelesen.signatureJson, '{"signature":"g"}');
      expect(gelesen.timestamp, 1763600000);
    });

    test('die Session kommt mit beiden Feldern zurueck', () async {
      final gelesen = await hinUndZurueck<SignalSessionRecordAdapter>(
        'session',
        SignalSessionRecordAdapter(
          sessionId: 'partner-1',
          recordJson: '{"session":"r"}',
        ),
      );

      expect(gelesen.sessionId, 'partner-1');
      expect(gelesen.recordJson, '{"session":"r"}');
    });

    test('der Sender-Key kommt mit beiden Feldern zurueck', () async {
      final gelesen = await hinUndZurueck<SignalSenderKeyRecordAdapter>(
        'senderkey',
        SignalSenderKeyRecordAdapter(
          senderKeyId: 'gruppe-1',
          recordJson: '{"senderKey":"sk"}',
        ),
      );

      expect(gelesen.senderKeyId, 'gruppe-1');
      expect(gelesen.recordJson, '{"senderKey":"sk"}');
    });

    test('die verschluesselte Nachricht kommt komplett zurueck', () async {
      final gelesen = await hinUndZurueck<EncryptedMessageAdapter>(
        'nachricht',
        EncryptedMessageAdapter(
          senderId: 'ich',
          recipientId: 'partner-1',
          ciphertext: 'AAAA',
          messageType: 3,
          timestamp: 1763600001,
        ),
      );

      expect(gelesen.senderId, 'ich');
      expect(gelesen.recipientId, 'partner-1');
      expect(gelesen.ciphertext, 'AAAA');
      expect(gelesen.messageType, 3);
      expect(gelesen.timestamp, 1763600001);
    });

    test(
      'der Identity-Key-Speicher kommt mit beiden Feldern zurueck',
      () async {
        final gelesen = await hinUndZurueck<SignalIdentityKeyStoreAdapter>(
          'store',
          SignalIdentityKeyStoreAdapter(
            trustedKeyJson: '{"trusted":true}',
            recipientId: 'partner-1',
          ),
        );

        expect(gelesen.trustedKeyJson, '{"trusted":true}');
        expect(gelesen.recipientId, 'partner-1');
      },
    );

    test('die Typ-IDs sind eindeutig', () async {
      // DER GRUND: Zwei Adapter mit derselben ID machen die Box
      // unbrauchbar - beim Lesen würde der falsche Adapter benutzt.
      final ids = <int>[
        SignalIdentityKeyPairAdapterAdapter().typeId,
        SignalPreKeyRecordAdapterAdapter().typeId,
        SignalSignedPreKeyRecordAdapterAdapter().typeId,
        SignalSessionRecordAdapterAdapter().typeId,
        SignalSenderKeyRecordAdapterAdapter().typeId,
        EncryptedMessageAdapterAdapter().typeId,
        SignalIdentityKeyStoreAdapterAdapter().typeId,
      ];

      expect(
        ids.toSet().length,
        ids.length,
        reason: 'Jeder Adapter braucht seine eigene Typ-ID.',
      );
      expect(ids, containsAll(<int>[0, 1, 2, 3, 4, 5, 6]));
    });

    test('zwei gleiche Adapter sind gleich', () async {
      // DER GRUND: Der Hive vergleicht die Adapter, um zu entscheiden,
      // ob ein Wert neu geschrieben werden muss.
      //
      // DER WEG: Für jeden Adapter gibt es zwei Wege - "identisch"
      // (dieselbe Instanz) und "gleich" (zwei Instanzen desselben
      // Typs). Beide müssen geprüft werden, sonst bleibt der zweite
      // Zweig des Vergleichs ungetestet.
      final baue = <TypeAdapter<dynamic> Function()>[
        SignalIdentityKeyPairAdapterAdapter.new,
        SignalPreKeyRecordAdapterAdapter.new,
        SignalSignedPreKeyRecordAdapterAdapter.new,
        SignalSessionRecordAdapterAdapter.new,
        SignalSenderKeyRecordAdapterAdapter.new,
        EncryptedMessageAdapterAdapter.new,
        SignalIdentityKeyStoreAdapterAdapter.new,
      ];

      for (var i = 0; i < baue.length; i++) {
        final erster = baue[i]();
        final zweiter = baue[i]();

        expect(
          erster == zweiter,
          isTrue,
          reason:
              'Zwei Instanzen desselben Adapters muessen gleich sein - '
              'sonst schreibt der Hive jedes Mal neu.',
        );
        // Der Hash folgt der Typ-ID.
        expect(
          erster.hashCode,
          erster.typeId.hashCode,
          reason: 'Der Hash muss aus der Typ-ID kommen.',
        );
        // Ein ANDERER Adapter-Typ ist nicht gleich.
        final anderer = baue[(i + 1) % baue.length]();
        expect(
          erster == anderer,
          isFalse,
          reason: 'Zwei verschiedene Adapter sind nicht gleich.',
        );
        // Ein Adapter ist auch nicht gleich wie etwas ganz anderes.
        expect((erster as Object) == 'irgendwas', isFalse);
      }
    });
  });
}
