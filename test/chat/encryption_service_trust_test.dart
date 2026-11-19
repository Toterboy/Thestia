// Das Vertrauens-Gedaechtnis des Verschluesselungsdienstes.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/encryption_service.dart 99 offene Zeilen - genau
// die Trust-Funktionen, mit denen die App auf einen kompromittierten
// Server reagiert.
//
// DER WEG: Der Audit vom 26.09.2026 hat die "erzwungene
// Safety-Number-Pruefung" eingefuehrt: [setRequiresPeerVerification]
// schaltet sie fuer einen Kontakt ein, und [encryptMessage] verweigert
// dann die Nachricht, solange die Identitaet nicht bestaetigt ist.
// Genau diese Kette war ungetestet - ein Fehler darin waere still:
// der Schalter waere reine Dekoration und der Nutzer haette den
// Schutz nicht, den die Oberflaeche verspricht.
//
// WAS HIER GEPRUEFT WIRD:
//   * ein unbekannter Kontakt gilt als nicht bestaetigt und hat keine
//     Safety-Nummer,
//   * die Bestaetigung wird gemerkt und wieder genommen,
//   * der Hinweis auf die Sicherheitsnummer wird je Kontakt gemerkt,
//   * das Merken des Hinweises LOESCHT die anderen Flags nicht
//     (das ist die eigentliche Falle: der Eintrag wird als JSON neu
//     geschrieben),
//   * die erzwungene Verifikation sperrt das Verschluesseln - und
//     nach der Bestaetigung geht es wieder,
//   * die Schalter an einem unbekannten Kontakt tun nichts.
//
// ANMERKUNG: Diese Tests laufen als NORMALE Tests (nicht als
// Widget-Tests) - Hive braucht echte Datei-Arbeit.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/services/chat/encryption_service.dart';

import '../support/plugin_mocks.dart';

void main() {
  late Directory temp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER KEYSTORE: die Boxen sind AES-256-verschluesselt.
    mockKeystore();
    // DIE ADAPTER: die Boxen halten Signal-Objekte.
    Hive.registerAdapter(SignalIdentityKeyPairAdapterAdapter());
    Hive.registerAdapter(SignalPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSignedPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSessionRecordAdapterAdapter());
    Hive.registerAdapter(SignalSenderKeyRecordAdapterAdapter());
    Hive.registerAdapter(EncryptedMessageAdapterAdapter());
    Hive.registerAdapter(SignalIdentityKeyStoreAdapterAdapter());
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('thesia_trust');
    Hive.init(temp.path);
  });

  tearDown(() async {
    await Hive.close();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  /// Baut einen fertigen Dienst.
  Future<EncryptionService> dienst(String? userId) async {
    final service = EncryptionService();
    service.localUserId = userId;
    await service.initialize();
    return service;
  }

  /// Baut eine Session (die Gegenseite wird durch ein Bundle aus
  /// demselben Dienst angedeutet - geprueft wird der Trust, nicht
  /// der Austausch zwischen zwei Geraeten).
  Future<void> baueSession(
    EncryptionService service,
    Map<String, dynamic> bundle,
    String peerId,
  ) async {
    await service.buildSession(
      peerId,
      bundle['identityKeyPublic'] as String,
      bundle['preKeyPublic'] as String,
      bundle['preKeyId'] as int,
      bundle['signedPreKeyPublic'] as String,
      bundle['signedPreKeyId'] as int,
      bundle['signedPreKeySignature'] as String,
      bundle['registrationId'] as int,
    );
  }

  group('Das Vertrauens-Gedaechtnis', () {
    test('ein unbekannter Kontakt gilt nicht als bestaetigt', () async {
      final service = await dienst('ich');

      expect(service.isPeerIdentityVerified('fremd'), isFalse);
      expect(service.safetyHintShown('fremd'), isFalse);
      expect(service.requiresPeerVerification('fremd'), isFalse);
      expect(
        service.safetyNumberFor('fremd'),
        isNull,
        reason:
            'Ohne bekannte Identity gibt es keine Safety-Nummer - '
            'sonst wuerde der Nutzer eine Zahl vergleichen, die zu '
            'niemandem gehoert.',
      );
    });

    test(
      'nach dem Session-Aufbau ist der Kontakt bekannt, aber ungeprueft',
      () async {
        final service = await dienst('ich');
        final bundle = await service.exportPreKeyBundle();
        await baueSession(service, bundle, 'partner-1');

        expect(service.isPeerIdentityVerified('partner-1'), isFalse);
        expect(
          service.safetyNumberFor('partner-1'),
          isNotNull,
          reason:
              'Nach dem Session-Aufbau muss der Nutzer die Safety-Number '
              'mit dem Partner vergleichen koennen.',
        );
        // Die Safety-Nummer ist stabil und besteht aus Ziffern.
        final nummer = service.safetyNumberFor('partner-1')!;
        expect(nummer.replaceAll(' ', ''), matches(RegExp(r'^\d+$')));
        expect(
          nummer,
          service.fingerprintSafetyNumber(
            'partner-1',
            bundle['identityKeyPublic'] as String,
          ),
        );
      },
    );

    test('die Bestaetigung wird gemerkt und wieder genommen', () async {
      final service = await dienst('ich');
      final bundle = await service.exportPreKeyBundle();
      await baueSession(service, bundle, 'partner-1');

      await service.setPeerIdentityVerified('partner-1', true);
      expect(service.isPeerIdentityVerified('partner-1'), isTrue);

      await service.setPeerIdentityVerified('partner-1', false);
      expect(service.isPeerIdentityVerified('partner-1'), isFalse);
    });

    test(
      'der Hinweis auf die Sicherheitsnummer wird je Kontakt gemerkt',
      () async {
        final service = await dienst('ich');
        final bundle = await service.exportPreKeyBundle();
        await baueSession(service, bundle, 'partner-1');

        expect(service.safetyHintShown('partner-1'), isFalse);

        await service.markSafetyHintShown('partner-1');

        expect(
          service.safetyHintShown('partner-1'),
          isTrue,
          reason:
              'Der Hinweis soll genau einmal kommen - sonst genervt er '
              'den Nutzer, und der Kontakt waere nie geschuetzt.',
        );
      },
    );

    test('das Merken des Hinweises loescht die anderen Flags nicht', () async {
      final service = await dienst('ich');
      final bundle = await service.exportPreKeyBundle();
      await baueSession(service, bundle, 'partner-1');

      await service.setPeerIdentityVerified('partner-1', true);
      await service.setRequiresPeerVerification('partner-1', true);

      await service.markSafetyHintShown('partner-1');

      // DER FALL: Der Eintrag wird als JSON neu geschrieben. Wer dabei
      // ein Flag vergisst, nimmt dem Nutzer den Schutz wieder weg -
      // und er merkt es nicht.
      expect(
        service.isPeerIdentityVerified('partner-1'),
        isTrue,
        reason:
            'Das Merken des Hinweises darf die Bestaetigung nicht loeschen.',
      );
      expect(
        service.requiresPeerVerification('partner-1'),
        isTrue,
        reason:
            'Das Merken des Hinweises darf die erzwungene Pruefung nicht '
            'abschalten - das waere ein stiller Verlust der Sicherheit.',
      );
      // Und der Identity-Key muss erhalten bleiben - ohne ihn gibt es
      // keine Safety-Nummer mehr.
      expect(service.safetyNumberFor('partner-1'), isNotNull);
    });

    test('die Schalter an einem unbekannten Kontakt tun nichts', () async {
      final service = await dienst('ich');

      // DER GRUND: Die Oberflaeche kann den Schalter auch an einem
      // Kontakt ohne Eintrag anbieten. Das darf keinen Absturz geben
      // und vor allem keinen halben Eintrag anlegen.
      await service.setPeerIdentityVerified('fremd', true);
      await service.setRequiresPeerVerification('fremd', true);
      await service.markSafetyHintShown('fremd');

      expect(service.isPeerIdentityVerified('fremd'), isFalse);
      expect(service.requiresPeerVerification('fremd'), isFalse);
      expect(service.safetyHintShown('fremd'), isFalse);
      expect(Hive.box<String>('signal_peer_trust').get('fremd'), isNull);
    });
  });

  group('Die erzwungene Safety-Number-Pruefung', () {
    test(
      'sie sperrt das Verschluesseln, solange die Identitaet offen ist',
      () async {
        final service = await dienst('ich');
        final bundle = await service.exportPreKeyBundle();
        await baueSession(service, bundle, 'partner-1');

        await service.setRequiresPeerVerification('partner-1', true);
        expect(service.requiresPeerVerification('partner-1'), isTrue);

        // DER GRUND: Der Audit hat das Flag vorher nirgends ausgewertet -
        // es war reine Dekoration. Genau das darf sich nicht wiederholen.
        expect(
          () => service.assertPeerUsable('partner-1'),
          throwsStateError,
          reason:
              'Bei erzwungener Pruefung und offener Identitaet muss die '
              'App den Versand verweigern.',
        );
        await expectLater(
          service.encryptMessage('partner-1', 'Hallo'),
          throwsStateError,
          reason:
              'Ohne bestaetigte Identitaet darf keine Nachricht raus - '
              'sonst koennte ein kompromittierter Server alles mitlesen.',
        );
      },
    );

    test('nach der Bestaetigung geht das Verschluesseln wieder', () async {
      final service = await dienst('ich');
      final bundle = await service.exportPreKeyBundle();
      await baueSession(service, bundle, 'partner-1');

      await service.setRequiresPeerVerification('partner-1', true);
      await service.setPeerIdentityVerified('partner-1', true);

      expect(() => service.assertPeerUsable('partner-1'), returnsNormally);

      final nachricht = await service.encryptMessage('partner-1', 'Hallo');
      expect(nachricht, isNotNull);
    });

    test('die erzwungene Pruefung bleibt beim Bestaetigen erhalten', () async {
      final service = await dienst('ich');
      final bundle = await service.exportPreKeyBundle();
      await baueSession(service, bundle, 'partner-1');

      await service.setRequiresPeerVerification('partner-1', true);
      await service.setPeerIdentityVerified('partner-1', true);

      // DER GRUND: Wer den Kontakt einmal bestaetigt hat, soll die
      // Pruefung nicht wieder verlieren - sonst kaeme der Schutz
      // ueber den Umweg wieder weg.
      expect(service.requiresPeerVerification('partner-1'), isTrue);
    });

    test('ohne erzwungene Pruefung bleibt das Verschluesseln frei', () async {
      final service = await dienst('ich');
      final bundle = await service.exportPreKeyBundle();
      await baueSession(service, bundle, 'partner-1');

      // DER GRUND: Die Erzwingung ist ein Schalter des Nutzers. Ohne
      // ihn darf der Normalfall nicht kaputt sein (sonst waere die
      // App nach dem Update unbenutzbar).
      expect(() => service.assertPeerUsable('partner-1'), returnsNormally);
      final nachricht = await service.encryptMessage('partner-1', 'Hallo');
      expect(nachricht, isNotNull);
    });

    test(
      'das Zuruecksetzen des Vertrauens nimmt auch die Erzwingung',
      () async {
        final service = await dienst('ich');
        final bundle = await service.exportPreKeyBundle();
        await baueSession(service, bundle, 'partner-1');

        await service.setRequiresPeerVerification('partner-1', true);
        await service.setPeerIdentityVerified('partner-1', true);

        await service.resetPeerTrust('partner-1');

        expect(service.requiresPeerVerification('partner-1'), isFalse);
        expect(service.isPeerIdentityVerified('partner-1'), isFalse);
        expect(
          service.safetyNumberFor('partner-1'),
          isNull,
          reason:
              'Nach dem Zuruecksetzen gibt es keinen Identity-Key mehr - '
              'die Safety-Nummer waere sonst eine Zahl ohne Gegenstueck.',
        );
      },
    );
  });
}
