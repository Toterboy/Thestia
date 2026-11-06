import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:thestia/models/signal_key_models.dart';
import 'package:thestia/services/hive_signal_store.dart';

/// Tests fuer die Einmal-Nutzung der PreKeys.
///
/// WARUM (06.11.2026, aus der P2P-Analyse): Ein PreKey ist ein
/// EINMAL-Schluessel. Wird er fuer eine Session verbraucht, nimmt
/// libsignal ihn aus dem Store. Die App persistiert die PreKeys aber
/// zusaetzlich in einer Hive-Box, und diese Box wurde beim naechsten
/// [_loadOrEnsurePreKeys] wieder gefuellt - samt der verbrauchten
/// Keys. Ein PreKey konnte so an zwei verschiedene Peers gehen.
///
/// Das bricht die Annahme von X3DH: dieselbe Sitzung, dasselbe
/// Schluesselpaar, zwei Partner - die Forward-Secrecy-Eigenschaft des
/// PreKeys geht verloren.
///
/// Der Test prueft die Kette: PreKey ablegen -> verbrauchen ->
/// er darf weder im Store noch in der persistenten Box auftauchen.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('prekey_einmal');
    Hive.init(tempDir.path);
    // Die Adapter registrieren (ohne sie kann Hive den Typ nicht
    // schreiben) - nur, wenn sie noch nicht registriert sind. Es sind
    // dieselben Adapter-Generatoren, die auch main.dart benutzt.
    if (!Hive.isAdapterRegistered(SignalPreKeyRecordAdapterAdapter().typeId)) {
      Hive.registerAdapter(SignalPreKeyRecordAdapterAdapter());
    }
    if (!Hive.isAdapterRegistered(SignalSessionRecordAdapterAdapter().typeId)) {
      Hive.registerAdapter(SignalSessionRecordAdapterAdapter());
    }
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('ein verbrauchter PreKey verschwindet auch aus der Box', () async {
    final preKeyBox = await Hive.openBox<SignalPreKeyRecordAdapter>('prekeys');
    final sessionBox = await Hive.openBox<SignalSessionRecordAdapter>(
      'sessions',
    );

    final store = await HiveSignalProtocolStore.open(
      identityKeyPair: generateIdentityKeyPair(),
      localRegistrationId: 42,
      sessionBox: sessionBox,
      preKeyBox: preKeyBox,
    );

    // Einen PreKey ablegen - so wie die App es tut.
    final preKey = generatePreKeys(7, 1).first;
    await store.storePreKey(7, preKey);
    await preKeyBox.put(
      '7',
      SignalPreKeyRecordAdapter(
        keyId: 7,
        keyPairJson: base64Encode(preKey.serialize()),
      ),
    );
    expect(
      preKeyBox.get('7'),
      isNotNull,
      reason:
          'der PreKey wurde nicht '
          'persistent abgelegt - der Test prueft das Falsche',
    );

    // Der Peer nutzt ihn: libsignal ruft removePreKey.
    await store.removePreKey(7);

    expect(
      preKeyBox.get('7'),
      isNull,
      reason:
          'der verbrauchte PreKey steht noch in der Box - er wuerde beim '
          'naechsten _loadOrEnsurePreKeys wiederbelebt und ein zweites Mal '
          'verwendet (gebrochene Einmal-Nutzung)',
    );
    expect(
      await store.containsPreKey(7),
      isFalse,
      reason: 'der PreKey ist noch im Store',
    );
  });
}
