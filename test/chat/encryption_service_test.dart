// Der Verschluesselungs-Dienst (Signal-Protokoll) - bisher kaum getestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/encryption_service.dart 268 offene Zeilen bei 308 Zeilen
// gesamt - der Dienst, der die privaten Schluessel, die PreKeys und die
// Session-Ratchet-States haelt, war fast voellig ungetestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Dienst wird benutzbar (die Boxen sind offen, es gibt einen
//     Identity-Key),
//   * die Safety-Nummer ist auf beiden Seiten GLEICH (sonst stimmen die
//     Zahlen der beiden Geraete nicht ueber) und hat das erwartete Format,
//   * das PreKey-Bundle traegt alle Felder, die die Gegenseite braucht,
//   * die PreKeys werden nicht doppelt vergeben,
//   * ohne Session gibt es auch keine Safety-Nummer.
//
// OHNE SIGNAL-PARTNER: Der Dienst redet mit keinem echten Geraet - es
// geht um die eigene Seite (die Schluessel, die PreKeys, die Nummern).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/services/chat/encryption_service.dart';

import '../support/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER KEYSTORE: die Boxen sind AES-256-verschluesselt - der Schluessel
    // liegt im Keystore. Ohne den Ersatz sucht der Test auf dem
    // CI-Runner das echte Plugin (das findet dort keine libsecret-Sitzung).
    mockKeystore();
    // HIVE: die Boxen liegen auf der Platte - ohne initialisiertes Hive
    // schlaegt das Oeffnen fehl.
    final tempDir = await Directory.systemTemp.createTemp('thesia_crypto');
    Hive.init(tempDir.path);
    // DIE ADAPTER: Die Boxen halten Signal-Objekte (Identity-Key-Paare,
    // PreKeys, Sessions). Ohne die Adapter kann Hive sie nicht schreiben
    // ("unknown type"). In der App macht das main.dart - im Test muss es
    // der Test selbst tun.
    Hive.registerAdapter(SignalIdentityKeyPairAdapterAdapter());
    Hive.registerAdapter(SignalPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSignedPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSessionRecordAdapterAdapter());
    Hive.registerAdapter(SignalSenderKeyRecordAdapterAdapter());
    Hive.registerAdapter(EncryptedMessageAdapterAdapter());
    Hive.registerAdapter(SignalIdentityKeyStoreAdapterAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
  });

  /// Baut einen frischen Dienst und wartet, bis er bereit ist.
  Future<EncryptionService> dienst() async {
    final service = EncryptionService();
    await service.initialize();
    return service;
  }

  group('Der Verschluesselungs-Dienst', () {
    test('wird benutzbar und hat einen Identity-Key', () async {
      final service = await dienst();

      expect(service.bereit, isTrue);
      // Der oeffentliche Identity-Key ist die Basis fuer jede
      // Ende-zu-Ende-Verschluesselung - ohne ihn geht nichts.
      expect(service.identityKeyPublicBase64, isNotEmpty);
      // Und er ist gueltiges Base64 (33 Byte = ein Curve25519-Punkt).
      expect(
        base64Decode(service.identityKeyPublicBase64).length,
        33,
        reason: 'Der oeffentliche Identity-Key muss ein Curve25519-Punkt sein.',
      );
      // Der Dienst ist der einer Instanz - die Schluessel bleiben stabil.
      final nochmal = EncryptionService();
      await nochmal.initialize();
      expect(
        nochmal.identityKeyPublicBase64,
        service.identityKeyPublicBase64,
        reason:
            'Der Identity-Key liegt in der Box - er darf sich beim Neustart '
            'nicht aendern (sonst waere die alte Session unlesbar).',
      );
    });

    test(
      'eine zweite Instanz ohne Wartende laesst keinen Fehler laufen',
      () async {
        // DER FALL (BEFUND 24.11.2026): Ein Provider baut eine EIGENE
        // Instanz, waehrend die Boxen schon offen sind. Das Oeffnen
        // schlaegt dann fehl (die Box hat einen anderen Typ) - und der
        // Fehler hatte niemanden, der ihn abwartete. Dart meldet so einen
        // Fehler als "unhandled error" - der Test waere rot, obwohl die
        // App richtig arbeitet.
        // DIE BOXEN ZU: Sie werden mit einem ANDEREN Typ geoeffnet - das
        // Oeffnen der Instanz schlaegt dann fehl.
        await Hive.close();
        await Hive.openBox<String>('signal_identity');

        final zweiter = EncryptionService();

        // DER FEHLER: Er kommt an - der Aufrufer sieht ihn.
        await expectLater(
          zweiter.initialize(),
          throwsA(anything),
          reason: 'Der Aufrufer muss den Fehler sehen.',
        );

        // UND: Er laeuft nicht ungehandelt weiter (der Test wuerde sonst
        // mit einem "unhandled error" abbrechen).
        await Future<void>.delayed(const Duration(milliseconds: 50));

        await Hive.close();
      },
    );

    test('die Safety-Nummer ist auf beiden Seiten gleich', () async {
      // Zwei oeffentliche Keys (syntetisch - echte Schluessel braucht der
      // Test nicht).
      final a = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final b = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));

      final beiUns = EncryptionService.computeSafetyNumber(a, b);
      final beiIhnen = EncryptionService.computeSafetyNumber(b, a);

      expect(
        beiUns,
        beiIhnen,
        reason:
            'Beide Geraete muessen dieselbe Zahl zeigen - sonst haetten die '
            'Nutzer keine Chance, den Kanal zu pruefen.',
      );
      // Das Format: 30 Ziffern in 6 Bloecken zu 5.
      expect(beiUns.split(' ').length, 6);
      expect(
        beiUns.replaceAll(' ', '').length,
        30,
        reason: 'Die Safety-Nummer hat 30 Ziffern.',
      );
      expect(
        RegExp(r'^\d{5}( \d{5}){5}$').hasMatch(beiUns),
        isTrue,
        reason: 'Das Format muss "12345 67890 ..." sein.',
      );
    });

    test('die Safety-Nummer aendert sich mit dem Schluessel', () async {
      final a = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final b = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
      final c = Uint8List.fromList(List<int>.generate(32, (i) => 7 * i));

      expect(
        EncryptionService.computeSafetyNumber(a, b),
        isNot(EncryptionService.computeSafetyNumber(a, c)),
        reason: 'Ein anderer Schluessel muss eine andere Zahl ergeben.',
      );
    });

    test('das PreKey-Bundle traegt alle Felder', () async {
      final service = await dienst();

      final bundle = await service.exportPreKeyBundle();

      expect(bundle['identityKeyPublic'], isNotNull);
      expect(bundle['registrationId'], isNotNull);
      expect(bundle['preKeyId'], isNotNull);
      expect(bundle['preKeyPublic'], isNotNull);
      expect(bundle['signedPreKeyId'], isNotNull);
      expect(bundle['signedPreKeyPublic'], isNotNull);
      expect(bundle['signedPreKeySignature'], isNotNull);
      // Die Signatur des SignedPreKeys ist die Signatur des eigenen
      // Schluessels - ohne sie akzeptiert die Gegenseite das Bundle nicht.
      expect(
        base64Decode(bundle['signedPreKeySignature'] as String).length,
        64,
        reason: 'Die Signatur ist 64 Byte (Ed25519).',
      );
    });

    test('die PreKeys werden nicht doppelt vergeben', () async {
      final service = await dienst();

      final erster = await service.getUnusedPreKey();
      final zweiter = await service.getUnusedPreKey();

      expect(erster, isNotNull);
      expect(zweiter, isNotNull);
      expect(
        erster!.id,
        isNot(zweiter!.id),
        reason:
            'Ein PreKey darf nie zweimal vergeben werden - sonst koennte '
            'jemand mitgelesen werden.',
      );
    });

    test('ohne Partner gibt es keine Safety-Nummer', () async {
      final service = await dienst();

      expect(
        service.safetyNumberFor('unbekannter-partner'),
        isNull,
        reason:
            'Ohne bekannten Partner gibt es keine Nummer - eine erfundene '
            'waere schlimmer als keine.',
      );
      expect(await service.hasSession('unbekannter-partner'), isFalse);
    });

    test('nach dem Leeren gibt es einen neuen Schluessel', () async {
      final service = await dienst();
      final vorher = service.identityKeyPublicBase64;

      await service.clearAllData();

      // Der Dienst hat keinen Schluessel mehr - die Daten sind weg.
      // (Die App baut ihn nach dem Abmelden neu auf - siehe
      // "encryptionServiceProvider" im Auth-Notifier.)
      expect(() => service.identityKeyPublicBase64, throwsA(anything));

      // Und ein neuer Dienst legt einen neuen Schluessel an.
      final neu = await dienst();
      expect(
        neu.identityKeyPublicBase64,
        isNot(vorher),
        reason:
            'Nach dem Leeren gibt es einen neuen Schluessel - sonst koennte '
            'jemand mit dem alten Schluessel mitlesen.',
      );
    });
  });
}
