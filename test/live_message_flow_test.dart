// Live-Nachweis: eine Nachricht kommt wirklich an.
//
// BEFUND (07.11.2026, Betreiber): "Nachrichten kommen noch immer nicht
// an." - und "Wenn beide sich liken entsteht kein Funke."
//
// DIESER TEST macht den kompletten Weg NACH, mit allem, was dazugehoert:
//
//   1. Beide Konten liken sich gegenseitig -> es entsteht ein Funke
//      (beweist Befund 15).
//   2. A holt das PreKey-Bundle von B (so wie die App das macht) und
//      baut die Sitzung.
//   3. A verschluesselt eine Nachricht mit der echten Signal-Krypto.
//   4. A legt sie im Relay ab (beweist Migration 196 - vorher scheiterte
//      jeder Aufruf mit HTTP 400).
//   5. B holt sie ab -> sie ist da, verschluesselt und mit dem PreKey
//      (die Form, in der nur der Empfaenger sie lesen kann).
//
// DAS WAR DER LETZTE OFFENER PUNKT: Mein erster Live-Test hat eine
// FAKE Nutzlast abgelegt (base64 von "Hallo"). Damit war die Server-
// Kette belegt, aber NICHT die Verschluesselung. Dieser Test schliesst
// die Luecke.
//
// DAS ENTSCHLUESSELN passiert hier bewusst NICHT: es braucht den
// PRIVATEN PreKey des Empfaengers - und der liegt nur auf dem Geraet,
// das den PreKey erzeugt hat (der Server kennt nur den oeffentlichen
// Teil). Die Krypto ist stattdessen in test/signal_first_message_test.dart
// (erste Nachricht traegt den PreKey und ist ohne Sitzung lesbar) und
// in test/live_prekey_bundle_test.dart (das echte Bundle eines echten
// Kontos ergibt eine Sitzung) belegt.
//
// ER LAEUFT NUR MIT .env (der CI hat keine Schluessel) - deshalb ist er
// ueber skip() abgesichert. Die Testdaten (Likes und Match) werden am
// Ende per SQL entfernt; das Skript dafuer liegt bei:
//   tool/cleanup_transit_testdata.sql
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'support/live_test_support.dart';

/// Das Bundle des Partners in ein PreKeyBundle der Bibliothek.
PreKeyBundle bundleBauen(Map<String, dynamic> b) => PreKeyBundle(
  b['registrationId'] as int,
  1,
  b['preKeyId'] as int,
  Curve.decodePoint(base64Decode(b['preKeyPublic'] as String), 0),
  b['signedPreKeyId'] as int,
  Curve.decodePoint(base64Decode(b['signedPreKeyPublic'] as String), 0),
  base64Decode(b['signedPreKeySignature'] as String),
  IdentityKey.fromBytes(base64Decode(b['identityKeyPublic'] as String), 0),
);

void main() {
  final env = envLesen();

  group('Eine Nachricht kommt an (live, mit echter Verschluesselung)', () {
    test(
      'A legt sie ab, B holt sie',
      () async {
        final client = http.Client();
        addTearDown(client.close);

        final tokenA = await sitzung(env, kontoA, client);
        final tokenB = await sitzung(env, kontoB, client);
        expect(tokenA, isNotNull, reason: 'Keine Sitzung fuer A.');
        expect(tokenB, isNotNull, reason: 'Keine Sitzung fuer B.');

        // 1) Beide liken sich gegenseitig -> es entsteht ein Funke.
        final match = await beziehungAufbauen(env, client, tokenA!, tokenB!);
        expect(
          match,
          isTrue,
          reason:
              'Der beidseitige Like muss sofort einen Match ergeben - '
              'vorher blieb der Like liegen.',
        );

        // 2) A holt B's Bundle und baut die Sitzung.
        final bundleDaten = await bundleHolen(env, kontoB, tokenA, client);
        expect(bundleDaten, isNotNull, reason: 'Kein PreKey-Bundle.');

        final storeA = InMemorySignalProtocolStore(
          IdentityKeyPair(
            IdentityKey(Curve.generateKeyPair().publicKey),
            Curve.generateKeyPair().privateKey,
          ),
          31337,
        );
        const adresseB = SignalProtocolAddress(kontoB, 1);
        final builder = SessionBuilder.fromSignalStore(storeA, adresseB);
        await builder.processPreKeyBundle(bundleBauen(bundleDaten!));

        // 3) A verschluesselt.
        final cipher = SessionCipher.fromStore(storeA, adresseB);
        final nachricht = await cipher.encrypt(
          Uint8List.fromList(utf8.encode('Hallo, das ist ein Live-Test!')),
        );
        expect(
          nachricht.getType(),
          CiphertextMessage.prekeyType,
          reason:
              'Die Nachricht traegt den PreKey - nur so kann der '
              'Empfaenger die Sitzung aufbauen.',
        );

        // 4) A legt sie im Relay ab.
        final abgelegt = await rpc(env, client, 'relay_store', {
          'p_receiver': kontoB,
          'p_ciphertext': base64Encode(nachricht.serialize()),
          'p_msg_type': nachricht.getType(),
          'p_kind': 'text',
        }, tokenA);
        expect(
          abgelegt.statusCode,
          200,
          reason:
              'relay_store muss klappen - vorher scheiterte jeder '
              'Aufruf mit 400.',
        );

        // 5) B holt sie ab.
        final geholt = await rpc(
          env,
          client,
          'relay_fetch',
          <String, dynamic>{},
          tokenB,
        );
        expect(geholt.statusCode, 200);
        final zeilen = (jsonDecode(geholt.body) as List)
            .cast<Map<String, dynamic>>();
        final meine = zeilen.where((z) => z['sender'] == kontoA).toList();
        expect(
          meine,
          isNotEmpty,
          reason: 'Die Nachricht ist nicht im Relay angekommen.',
        );

        final empfaengerTyp = (meine.first['msgType'] as num).toInt();
        expect(
          empfaengerTyp,
          CiphertextMessage.prekeyType,
          reason:
              'Die Nachricht traegt den PreKey - nur so kann der '
              'Empfaenger die Sitzung aufbauen.',
        );
        final bytes = base64Decode(meine.first['ciphertext'] as String);
        expect(bytes, isNotEmpty);

        // Und die Nutzlast ist wirklich verschluesselt: im Klartext
        // taucht der Text nirgends auf.
        expect(
          utf8.decode(bytes, allowMalformed: true),
          isNot(contains('Live-Test')),
          reason: 'Die Nutzlast ist nicht verschluesselt.',
        );

        // Aufraeumen: die Relay-Zeile bestaetigen (sie wird geloescht).
        await rpc(env, client, 'relay_ack', {
          'p_ids': [meine.first['id']],
        }, tokenB);
      },
      skip: liveTestsLaufen(env)
          ? null
          : 'Ohne .env gibt es keinen Server und keine Schluessel.',
    );
  });
}
