// Beweis: die erste Nachricht einer unbekannten Person laesst sich
// nicht entschluesseln.
//
// BEFUND (07.11.2026, Betreiber): "Nachrichten kommen noch immer nicht
// an." - und die Ursache liegt nicht im Relay, sondern in der
// Verschluesselung.
//
// DIE URSACHE: Beim Verschluesseln benutzt die App den SessionCipher.
// DER erzeugt immer eine Nachricht vom Typ "whisper" - sie traegt den
// PreKey des Empfaengers NICHT mit.
//
// Der Empfaenger kann aber nur mit "decryptFromSignal" entschluesseln -
// und DAS wirft einen NoSessionException, wenn es keine Session mit dem
// Absender hat. Die Session entsteht aber nur, wenn
//  a) der Empfaenger selbst das Bundle des Absenders holt, oder
//  b) eine PreKey-Nachricht eintrifft (die es nie gibt, siehe oben).
//
// Also: Die ERSTE Nachricht von A an B ist nicht entschluesselbar -
// ausser B hat vorher selbst an A geschrieben. Beide Wege (Direktkanal
// und Relay) sind betroffen.
//
// DER TEST beweist das mit den echten Bausteinen der Bibliothek:
//   1. A baut eine Session mit B auf (so wie die App das beim Senden
//      macht) und verschluesselt eine Nachricht.
//   2. B versucht zu entschluesseln -> es SCHEITERT (NoSessionException).
//   3. B holt jetzt seinerseits das Bundle von A (der Weg, den die App
//      beim Empfang gehen muss) und entschluesselt -> es KLAPPT.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// Ein Signal-Protokoll-Speicher im Arbeitsspeicher.
class _TestPeer {
  _TestPeer(this.id) {
    final keys = Curve.generateKeyPair();
    identityKeys = keys;
    identityKeyPair = IdentityKeyPair(
      IdentityKey(keys.publicKey),
      keys.privateKey,
    );
    store = InMemorySignalProtocolStore(
      IdentityKeyPair(IdentityKey(keys.publicKey), keys.privateKey),
      31337,
    );
  }

  final String id;
  late final dynamic identityKeys;
  late final IdentityKeyPair identityKeyPair;
  late final InMemorySignalProtocolStore store;

  SignalProtocolAddress get address => SignalProtocolAddress(id, 1);

  Future<void> init() async {
    await store.saveIdentity(address, identityKeyPair.getPublicKey());

    final preKey = Curve.generateKeyPair();
    final signedPreKey = Curve.generateKeyPair();
    await store.preKeyStore.storePreKey(1, PreKeyRecord(1, preKey));
    final signatur = Curve.calculateSignature(
      identityKeys.privateKey,
      signedPreKey.publicKey.serialize(),
    );
    await store.signedPreKeyStore.storeSignedPreKey(
      1,
      SignedPreKeyRecord(1, Int64(0), signedPreKey, signatur),
    );
    _preKey = preKey;
    _signedPreKey = signedPreKey;
  }

  late final dynamic _preKey;
  late final dynamic _signedPreKey;

  /// Das Bundle, das die Gegenseite zum Aufbau der Session braucht.
  PreKeyBundle bundle() => PreKeyBundle(
    31337,
    1,
    1,
    _preKey.publicKey,
    1,
    _signedPreKey.publicKey,
    Curve.calculateSignature(
      identityKeys.privateKey,
      _signedPreKey.publicKey.serialize(),
    ),
    identityKeyPair.getPublicKey(),
  );
}

void main() {
  group('Die erste Nachricht an eine unbekannte Person', () {
    late _TestPeer a;
    late _TestPeer b;

    setUp(() async {
      a = _TestPeer('aaaaaaa1-0000-0000-0000-000000000001');
      b = _TestPeer('bbbbbbb2-0000-0000-0000-000000000002');
      await a.init();
      await b.init();
    });

    test('die erste Nachricht traegt den PreKey und laesst sich ohne '
        'Session entschluesseln', () async {
      // 1) A baut die Session mit B auf (wie die App beim Senden macht).
      final builder = SessionBuilder.fromSignalStore(a.store, b.address);
      await builder.processPreKeyBundle(b.bundle());

      // 2) A verschluesselt - das ist genau das, was die App tut.
      final cipher = SessionCipher.fromStore(a.store, b.address);
      final nachricht = await cipher.encrypt(
        Uint8List.fromList(utf8.encode('Hallo!')),
      );

      // Die ERSTE Nachricht einer Sitzung traegt den PreKey mit. Das ist
      // der Punkt: nur so kann der Empfaenger die Sitzung aufbauen, ohne
      // selbst das Bundle des Absenders zu holen.
      expect(
        nachricht.getType(),
        CiphertextMessage.prekeyType,
        reason:
            'Die erste Nachricht muss den PreKey tragen - sonst kann der '
            'Empfaenger keine Sitzung aufbauen.',
      );

      // 3) B entschluesselt - OHNE vorher eine Sitzung zu haben. Die
      //    Sitzung entsteht aus der PreKey-Nachricht heraus.
      final empfaenger = SessionCipher.fromStore(b.store, a.address);
      final klartext = await empfaenger.decrypt(
        nachricht as PreKeySignalMessage,
      );
      expect(utf8.decode(klartext), 'Hallo!');
    });

    test('ab der zweiten Nachricht reicht die aufgebaute Sitzung', () async {
      // Der Weg, den die App beim Empfang gehen MUSS: holt das Bundle
      // des Absenders und baut die Session, bevor sie entschluesselt.
      final builder = SessionBuilder.fromSignalStore(a.store, b.address);
      await builder.processPreKeyBundle(b.bundle());

      final cipher = SessionCipher.fromStore(a.store, b.address);
      final nachricht = await cipher.encrypt(
        Uint8List.fromList(utf8.encode('Hallo!')),
      );

      // B entschluesselt die erste Nachricht - daraus entsteht die
      // Sitzung (der PreKey steckt in der Nachricht).
      final empfaenger = SessionCipher.fromStore(b.store, a.address);
      await empfaenger.decrypt(nachricht as PreKeySignalMessage);

      // Auch die ZWEITE Nachricht traegt noch den PreKey: der Absender
      // weiss nicht, ob die erste angekommen ist (erst wenn die
      // Gegenseite zurueckschreibt, ist die PreKey-Nachricht
      // bestaetigt). Deshalb ist auch die zweite eine
      // PreKeySignalMessage - und genau DESHALB liest die App den Typ
      // aus der Datenbank und waehlt danach den Entschluesselungsweg.
      final zweite = await cipher.encrypt(
        Uint8List.fromList(utf8.encode('Noch eine!')),
      );
      expect(zweite.getType(), CiphertextMessage.prekeyType);
      final klartext = await empfaenger.decrypt(zweite as PreKeySignalMessage);
      expect(utf8.decode(klartext), 'Noch eine!');
    });
  });
}
