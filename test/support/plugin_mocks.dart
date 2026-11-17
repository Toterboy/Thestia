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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// Das Plattform-Interface wird von just_audio exportiert, aber nicht
// weitergereicht - der Test setzt die Attrappe darueber.
// ignore: depend_on_referenced_packages
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

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

/// Laedt die echte Textschrift (Roboto) in den Test.
///
/// DER GRUND (18.11.2026): `flutter_test` benutzt ohne diese Schrift die
/// Test-Schrift, bei der JEDES Zeichen so breit ist wie die Schrift gross.
/// Damit laeuft in jedem Test eine Zeile ueber den Rand - der Test
/// meldet dann einen Fehler, den es in der App gar nicht gibt (und
/// umgekehrt bleibt ein echter Ueberlauf unentdeckt).
///
/// Mit der echten Schrift stimmen die Breiten wieder - der Test sieht
/// dieselbe Oberflaeche wie das Telefon.
///
/// Wird die Schrift nicht gefunden (kein Flutter-SDK im Test-Runner),
/// bleibt es bei der Test-Schrift - der Test laeuft dann wie bisher.
Future<void> ladeEchteSchrift() async {
  final datei = _sdkSchrift('material_fonts/roboto-regular.ttf');
  if (datei == null) return;
  try {
    final bytes = await datei.readAsBytes();
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  } catch (e) {
    // Ohne Schrift laeuft der Test mit der Test-Schrift weiter.
    debugPrint('[Schrift] Roboto konnte nicht geladen werden: $e');
  }
}

/// Findet eine Schriftdatei im Flutter-SDK.
///
/// Reihenfolge: `FLUTTER_ROOT` aus der Umgebung, danach der Weg zur
/// Dart-Executable (im Flutter-SDK liegt sie unter bin/cache/dart-sdk).
File? _sdkSchrift(String name) {
  final wurzel = Platform.environment['FLUTTER_ROOT'];
  if (wurzel != null && wurzel.isNotEmpty) {
    final datei = File('$wurzel/bin/cache/artifacts/$name');
    if (datei.existsSync()) return datei;
  }

  // .../flutter/bin/cache/dart-sdk/bin/dart.exe -> .../flutter
  var teile = Platform.resolvedExecutable.split(RegExp(r'[\\/]'));
  if (teile.length > 5) {
    teile = teile.sublist(0, teile.length - 5);
    final datei = File('${teile.join('/')}/bin/cache/artifacts/$name');
    if (datei.existsSync()) return datei;
  }
  return null;
}

/// Beantwortet die Aufrufe des Aufnahme-Plugins.///
/// [erlaubt]=false simuliert "keine Mikrofonberechtigung" - dann zeigt
/// der Editor den Hinweis statt aufzunehmen.
///
/// [dateiBeimStoppen] ist der Pfad, den das Plugin beim Stoppen
/// zurueckgibt. Standard: ein Name im Temp-Ordner (die Datei existiert
/// dann nicht - so verhaelt sich ein Geraet ohne echte Aufnahme).
/// Fuellt man eine echte Datei hinein, kann der Screen sie lesen.
void mockAufnahme({bool erlaubt = true, String? dateiBeimStoppen}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(aufnahmeKanal, (anfrage) async {
        switch (anfrage.method) {
          case 'hasPermission':
            return erlaubt;
          case 'create':
            // DER EREIGNIS-KANAL: Das Plugin meldet den Zustand der
            // Aufnahme ueber einen eigenen Kanal (pro Aufnahme eine ID).
            // Ohne Antwort kommt dort ein "MissingPluginException" an -
            // der Test wuerde an einer Stelle scheitern, an der der
            // Bildschirm gar nichts getan hat.
            _mockeAufnahmeEreignisse(anfrage.arguments);
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
            // Der Pfad der Aufnahme. Ohne Angabe: ein Name im
            // Temp-Ordner (die Datei existiert dann nicht - so
            // verhaelt sich ein Geraet ohne echte Aufnahme).
            return dateiBeimStoppen ??
                '${Directory.systemTemp.path}/thestia_test_aufnahme.m4a';
        }
        return null;
      });
}

/// Beantwortet den Ereignis-Kanal des Aufnahme-Plugins.
///
/// DER GRUND (16.11.2026): Der Zustand der Aufnahme (Start, Pause,
/// Stopp) kommt ueber einen EventChannel - einer je Aufnahme. Ohne
/// diesen Ersatz meldet das Plugin im Test einen fehlenden Kanal.
void _mockeAufnahmeEreignisse(Object? argumente) {
  if (argumente is! Map) return;
  final id = argumente['recorderId'];
  if (id is! String || id.isEmpty) return;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('com.llfbandit.record/events/$id', (
        nachricht,
      ) async {
        final aufruf = const StandardMethodCodec().decodeMethodCall(nachricht);
        if (aufruf.method == 'listen' || aufruf.method == 'cancel') {
          return const StandardMethodCodec().encodeSuccessEnvelope(null);
        }
        return null;
      });
}

/// Der Audio-Player im Test.
///
/// DER GRUND (16.11.2026): Beim Anlegen eines Players raeumt das
/// Plugin alle Spieler der Engine weg. Dieser Aufruf geht ohne "await"
/// an den Server - im Test landet er als ungefangener Fehler auf dem
/// Bildschirm ("MissingPluginException"), obwohl die App ihn abfängt.
///
/// Das Abspielen selbst ist im Test nicht moeglich (dafuer gibt es
/// eigene Tests) - das Blatt zum Anhoeren zeigt deshalb den Fehler
/// "nicht abspielbar" an, was genau das Verhalten ohne Player ist.
class _FakeAudioPlattform extends JustAudioPlatform {
  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async => DisposeAllPlayersResponse();
}

/// Beantwortet die Aufrufe des Audio-Players (just_audio).
void mockAudioPlayer() {
  JustAudioPlatform.instance = _FakeAudioPlattform();
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
