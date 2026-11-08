// Live-Nachweis: das PreKey-Bundle des Partners laesst sich verwenden.
//
// BEFUND (07.11.2026, Betreiber): "Nachrichten kommen noch immer nicht
// an."
//
// WARUM DIESER TEST: Beim Verschluesseln prueft die Bibliothek die
// Signatur des Signed PreKeys des Partners:
//
//     if (!Curve.verifySignature(
//           preKey.getIdentityKey().publicKey,
//           preKey.getSignedPreKey()!.serialize(),
//           preKey.getSignedPreKeySignature())) {
//       throw InvalidKeyException('Invalid signature on device key!');
//     }
//
// Passen die drei Teile nicht zusammen, kann die App KEINE Sitzung
// aufbauen - und damit KEINE Nachricht verschluesseln. Die Folge:
// Die Nachricht wird nie zugestellt, ohne dass irgendwo ein Fehler
// sichtbar wird.
//
// Dieser Test holt das ECHTE Bundle eines echten Kontos vom Server
// und baut genau daraus die Sitzung - so wie die App es macht. Wenn die
// App ihr Bundle falsch signiert, scheitert es HIER.
//
// Der Test laeuft nur mit .env (der CI hat keine Schluessel).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'support/live_test_support.dart';

void main() {
  final env = envLesen();

  test(
    'das PreKey-Bundle des Partners laesst sich zu einer Sitzung '
    'verwenden',
    () async {
      final client = http.Client();
      addTearDown(client.close);

      final tokenA = await sitzung(env, kontoA, client);
      final tokenB = await sitzung(env, kontoB, client);
      expect(tokenA, isNotNull, reason: 'Keine Sitzung fuer A.');
      expect(tokenB, isNotNull, reason: 'Keine Sitzung fuer B.');

      // Die Beziehung muss stehen, sonst gibt der Endpunkt das Bundle
      // nicht heraus (404 "nicht verfuegbar"). Das ist Absicht: ohne
      // Beziehung bekommt niemand die Schluessel eines Fremden.
      final match = await beziehungAufbauen(env, client, tokenA!, tokenB!);
      expect(
        match,
        isTrue,
        reason:
            'Der beidseitige Like muss sofort einen Match ergeben - '
            'vorher blieb der Like liegen.',
      );

      // Das echte Bundle holen - genau so wie die App es macht.
      final antwort = await client.get(
        Uri.parse('${env['SUPABASE_URL']!}/functions/v1/prekeys/$kontoB'),
        headers: {
          'apikey': publishableKey(env)!,
          'Authorization': 'Bearer $tokenA',
        },
      );
      expect(
        antwort.statusCode,
        200,
        reason: 'Das PreKey-Bundle liess sich nicht holen: ${antwort.body}',
      );
      final b = jsonDecode(antwort.body) as Map<String, dynamic>;

      // Der Signed Pre Key muss zur Identity-Key-Signatur passen.
      final identityKey = IdentityKey.fromBytes(
        base64Decode(b['identityKeyPublic'] as String),
        0,
      );
      final signedPreKey = Curve.decodePoint(
        base64Decode(b['signedPreKeyPublic'] as String),
        0,
      );
      final signatur = base64Decode(b['signedPreKeySignature'] as String);

      expect(
        Curve.verifySignature(
          identityKey.publicKey,
          signedPreKey.serialize(),
          signatur,
        ),
        isTrue,
        reason:
            'Die Signatur des Signed Pre Keys passt NICHT zur Identity-Key. '
            'Damit kann die App keine Sitzung aufbauen und KEINE Nachricht '
            'verschluesseln.',
      );

      // Und die Sitzung baut wirklich auf.
      final store = InMemorySignalProtocolStore(
        IdentityKeyPair(
          IdentityKey(Curve.generateKeyPair().publicKey),
          Curve.generateKeyPair().privateKey,
        ),
        31337,
      );
      final builder = SessionBuilder.fromSignalStore(
        store,
        const SignalProtocolAddress(kontoB, 1),
      );
      await builder.processPreKeyBundle(
        PreKeyBundle(
          b['registrationId'] as int,
          1,
          b['preKeyId'] as int,
          Curve.decodePoint(base64Decode(b['preKeyPublic'] as String), 0),
          b['signedPreKeyId'] as int,
          signedPreKey,
          signatur,
          identityKey,
        ),
      );
    },
    skip: hatSchluessel(env)
        ? null
        : 'Ohne .env gibt es keinen Server und keine Schluessel.',
  );
}
