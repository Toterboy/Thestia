// Die Plugin-Kanaele, die es auf dem Desktop (Linux/Windows) gibt, im
// Test aber nicht laufen.
//
// WARUM (14.11.2026): Die App laeuft auf dem Telefon - dort gibt es
// nur Android und iOS. Im Test laeuft aber die DESKTOP-Variante der
// Plugins: sie rufen das Plugin, das auf dem CI-Runner weder ein
// XDG-Verzeichnis noch eine libsecret-Sitzung hat. Dieselbe Testdatei
// ist damit auf dem Entwicklerrechner gruen und in der CI rot - ohne
// dass der Test selbst falsch waere.
//
// DER WEG: Die Kanaele werden hier beantwortet. Der Test ruft nie das
// Plugin - damit ist er auf jeder Plattform gleich.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Der Kanal von path_provider.
const MethodChannel pfadKanal = MethodChannel(
  'plugins.flutter.io/path_provider',
);

/// Der Kanal von flutter_secure_storage.
const MethodChannel keystoreKanal = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Der In-Memory-Keystore fuer die Tests.
final Map<String, String> keystoreInhalt = <String, String>{};

/// Beantwortet die Pfad-Aufrufe (mit einem Temp-Ordner).
///
/// DER GRUND: `Supabase.initialize` holt sich das Speicher-Verzeichnis
/// (fuer die Sitzung). Ohne diesen Ersatz ruft der Test auf dem
/// Linux-Runner das echte Plugin - und das findet dort kein
/// XDG-Verzeichnis.
Future<void> mockPfadProvider() async {
  final temp = await Directory.systemTemp.createTemp('thesia_test_pfad');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pfadKanal, (anfrage) async {
        switch (anfrage.method) {
          case 'getTemporaryDirectory':
          case 'getApplicationDocumentsDirectory':
          case 'getApplicationSupportDirectory':
            return temp.path;
        }
        return null;
      });
}

/// Beantwortet die Keystore-Aufrufe.
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

/// Nimmt die Kanaele wieder aus dem Spiel (am Ende des Tests).
void unmockPlugins() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pfadKanal, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(keystoreKanal, null);
}
