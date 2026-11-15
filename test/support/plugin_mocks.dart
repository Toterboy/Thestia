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
import 'package:hive/hive.dart';

/// Der Kanal von path_provider.
const MethodChannel pfadKanal = MethodChannel(
  'plugins.flutter.io/path_provider',
);

/// Der Kanal von flutter_secure_storage.
const MethodChannel keystoreKanal = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Der Kanal von flutter_timezone (die Zeitzone des Geraets).
const MethodChannel zeitzoneKanal = MethodChannel('flutter_timezone');

/// Der Kanal des Aufnahme-Plugins (`record`).
///
/// DER GRUND (15.11.2026): Der Vorstellungs-Editor (IntroEditor) nimmt
/// Audio auf. Das Plugin spricht die Plattform ueber einen
/// MethodChannel an - ohne Mock kommt im Test keine Antwort und der
/// Aufruf wartet endlos.
const MethodChannel aufnahmeKanal = MethodChannel(
  'com.llfbandit.record/messages',
);

/// Beantwortet die Aufrufe des Aufnahme-Plugins.
///
/// [erlaubt]=false simuliert "keine Mikrofonberechtigung" - dann zeigt
/// der Editor den Hinweis statt aufzunehmen.
void mockAufnahme({bool erlaubt = true}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(aufnahmeKanal, (anfrage) async {
        switch (anfrage.method) {
          case 'hasPermission':
            return erlaubt;
          case 'create':
            return null;
          case 'isRecording':
          case 'isPaused':
            return false;
          case 'isEncoderSupported':
            return true;
          case 'getAmplitude':
            return <String, dynamic>{'current': -20.0, 'max': -10.0};
          case 'start':
          case 'resume':
          case 'pause':
          case 'cancel':
          case 'dispose':
            return null;
          case 'stop':
            // Der Pfad der Aufnahme - im Test gibt es keine Datei,
            // deshalb wird er nur als Zeichenkette geliefert.
            return '${Directory.systemTemp.path}/thestia_test_aufnahme.m4a';
        }
        return null;
      });
}

/// Liefert eine feste Zeitzone.
///
/// WARUM: Der Benachrichtigungs-Dienst braucht die Zeitzone des Geraets
/// (fuer die Zeitangabe in der Meldung). Das Plugin gibt es auf Linux
/// (dem CI-Runner), auf Windows nicht - dort bleibt die Antwort einfach
/// aus, hier schlaegt der Aufruf fehl und der Dienst startet nicht.
void mockZeitzone([String zone = 'Europe/Berlin']) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(zeitzoneKanal, (anfrage) async => zone);
}

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

/// Legt Hive in einem Temp-Ordner ab.
///
/// DER GRUND (15.11.2026): Der Chat- und der Signal-Dienst speichern
/// ihre Daten in verschluesselten Hive-Boxen. Ohne initialisiertes
/// Hive wirft das Box-Oeffnen ("You need to initialize Hive") - der
/// Fehler landet sonst als unbehandelter Testfehler auf dem Bildschirm.
Future<void> mockHive() async {
  final temp = await Directory.systemTemp.createTemp('thesia_test_hive');
  Hive.init(temp.path);
}

/// Nimmt die Kanaele wieder aus dem Spiel (am Ende des Tests).
void unmockPlugins() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pfadKanal, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(keystoreKanal, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(aufnahmeKanal, null);
}
