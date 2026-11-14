// DER KANAL VON flutter_secure_storage wird hier beantwortet.
//
// WARUM (14.11.2026): Der Keystore-Plugin hat auf Linux eine echte
// Implementierung (libsecret). Im Test laeuft sie auf - und auf dem
// CI-Runner gibt es weder libsecret noch eine DBus-Sitzung. Der
// Aufruf schlaegt dort fehl, waehrend er auf Windows (kein
// Plugin) einfach unbeantwortet bleibt. Dieselbe Testdatei ist also
// auf dem Entwicklerrechner gruen und in der CI rot - ohne dass der
// Test selbst falsch waere.
//
// DER WEG: Der Kanal wird hier beantwortet (wie in
// test/secure_location_storage_test.dart). Damit ruft der Test nie
// das Plugin - er ist damit auf jeder Plattform gleich.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Der Kanal von flutter_secure_storage.
const MethodChannel keystoreKanal = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Der In-Memory-Keystore fuer die Tests.
final Map<String, String> keystoreInhalt = <String, String>{};

/// Beantwortet die Keystore-Aufrufe (Aufraeumen am Ende).
///
/// [inhalt] setzt den Anfangsinhalt (z. B. "user_id" -> "ich").
void mockKeystore({Map<String, String> inhalt = const {}}) {
  keystoreInhalt
    ..clear()
    ..addAll(inhalt);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(keystoreKanal, (anfrage) async {
        final args =
            (anfrage.arguments as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        switch (anfrage.method) {
          case 'read':
            return keystoreInhalt[args['key'] as String?];
          case 'write':
            keystoreInhalt[args['key'] as String] = args['value'] as String;
            return null;
          case 'delete':
            keystoreInhalt.remove(args['key']);
            return null;
          case 'containsKey':
            return keystoreInhalt.containsKey(args['key']);
          case 'readAll':
            return Map<String, String>.from(keystoreInhalt);
          case 'deleteAll':
            keystoreInhalt.clear();
            return null;
        }
        return null;
      });
}

/// Nimmt den Keystore wieder aus dem Spiel (am Ende des Tests).
void unmockKeystore() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(keystoreKanal, null);
}
