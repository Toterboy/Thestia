// Die Plugin-Kanäle, die es auf dem Desktop (Linux/Windows) gibt, im
// Test aber nicht laufen.
//
// WARUM (14.11.2026): Die App läuft auf dem Telefon - dort gibt es
// nur Android und iOS. Im Test läuft aber die DESKTOP-Variante der
// Plugins: sie rufen das Plugin, das auf dem CI-Runner weder ein
// XDG-Verzeichnis noch eine libsecret-Sitzung hat. Dieselbe Testdatei
// ist damit auf dem Entwicklerrechner grün und in der CI rot - ohne
// dass der Test selbst falsch wäre.
//
// DER WEG: Die Kanäle werden hier beantwortet. Der Test ruft nie das
// Plugin - damit ist er auf jeder Plattform gleich.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// Das Plattform-Interface wird von just_audio exportiert, aber nicht
// weitergereicht - der Test setzt die Attrappe darüber.
// ignore: depend_on_referenced_packages
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// Der Kanal von path_provider.
const MethodChannel pfadKanal = MethodChannel(
  'plugins.flutter.io/path_provider',
);

/// Der Kanal von package_info_plus (die Versionsangaben der App).
///
/// DER GRUND (19.11.2026, gefunden vom Rauchtest): Die App fragt die
/// Versionsangaben ab (der "Was ist neu"-Bildschirm vergleicht den
/// Build mit dem gemerkten). Ohne den Ersatz wartet der Aufruf im
/// Test endlos - der Bildschirm bleibt beim Lade-Spinner.
const MethodChannel packageInfoKanal = MethodChannel(
  'dev.fluttercommunity.plus/package_info',
);

/// Beantwortet die Versionsangaben der App.
///
/// [build] ist die Build-Nummer - der Rauchtest braucht eine, damit
/// der "Was ist neu"-Bildschirm nicht dauerhaft auftaucht.
void mockPackageInfo({String version = '0.10.2', String build = '56'}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(packageInfoKanal, (anfrage) async {
        if (anfrage.method == 'getAll') {
          return <String, dynamic>{
            'appName': 'Thestia',
            'packageName': 'de.toterboy.thestia',
            'version': version,
            'buildNumber': build,
          };
        }
        return null;
      });
}

/// Der Kanal von flutter_secure_storage.
const MethodChannel keystoreKanal = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Der Kanal von flutter_timezone (die Zeitzone des Geräts).
const MethodChannel zeitzoneKanal = MethodChannel('flutter_timezone');

/// Der Kanal des Aufnahme-Plugins (`record`).
///
/// DER GRUND (15.11.2026): Der Vorstellungs-Editor (IntroEditor) nimmt
/// Audio auf. Das Plugin spricht die Plattform über einen
/// MethodChannel an - ohne Mock kommt im Test keine Antwort und der
/// Aufruf wartet endlos.
const MethodChannel aufnahmeKanal = MethodChannel(
  'com.llfbandit.record/messages',
);

/// Läuft die Aufnahme gerade? (der Zustand des Ersatzes)
///
/// DER GRUND: Das Aufnahme-Plugin fragt in festen Abständen den Pegel
/// ab - aber nur, wenn wirklich aufgenommen wird. Ohne diesen Zustand
/// bekommt die App nie einen Pegel und kann eine Aufnahme nicht von
/// Stille unterscheiden.
bool aufnahmeLaeuft = false;

/// Beantwortet die Aufrufe des Aufnahme-Plugins.///
/// [erlaubt]=false simuliert "keine Mikrofonberechtigung" - dann zeigt
/// der Editor den Hinweis statt aufzunehmen.
///
/// [dateiBeimStoppen] ist der Pfad, den das Plugin beim Stoppen
/// zurückgibt. Standard: ein Name im Temp-Ordner (die Datei existiert
/// dann nicht - so verhält sich ein Gerät ohne echte Aufnahme).
/// Füllt man eine echte Datei hinein, kann der Screen sie lesen.
///
/// [amplitude] ist der Pegel in dB, den das Plugin meldet. Der Wert
/// entscheidet darüber, ob die Aufnahme als "Sprache" oder als "Stille"
/// gilt - der Vorstellungs-Editor fragt eine stille Aufnahme nach.
void mockAufnahme({
  bool erlaubt = true,
  String? dateiBeimStoppen,
  double amplitude = -20,
}) {
  // DER ZUSTAND BEGINNT NEU: Ein Test, der eine Aufnahme laufen lässt,
  // darf den nächsten nicht beeinflussen.
  aufnahmeLaeuft = false;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(aufnahmeKanal, (anfrage) async {
        switch (anfrage.method) {
          case 'hasPermission':
            return erlaubt;
          case 'create':
            // DER EREIGNIS-KANAL: Das Plugin meldet den Zustand der
            // Aufnahme über einen eigenen Kanal (pro Aufnahme eine ID).
            // Ohne Antwort kommt dort ein "MissingPluginException" an -
            // der Test würde an einer Stelle scheitern, an der der
            // Bildschirm gar nichts getan hat.
            _mockeAufnahmeEreignisse(anfrage.arguments);
            return null;
          case 'isRecording':
            return aufnahmeLaeuft;
          case 'isPaused':
            return false;
          case 'isEncoderSupported':
            return true;
          case 'getAmplitude':
            return <String, dynamic>{'current': amplitude, 'max': -10.0};
          case 'start':
          case 'resume':
            // DIE AUFNAHME LÄUFT: Erst jetzt fragt das Plugin den Pegel
            // ab - so verhält sich das echte Plugin auch.
            aufnahmeLaeuft = true;
            return null;
          case 'pause':
            return null;
          case 'cancel':
          case 'dispose':
            aufnahmeLaeuft = false;
            return null;
          case 'stop':
            aufnahmeLaeuft = false;
            // Der Pfad der Aufnahme. Ohne Angabe: ein Name im
            // Temp-Ordner (die Datei existiert dann nicht - so
            // verhält sich ein Gerät ohne echte Aufnahme).
            return dateiBeimStoppen ??
                '${Directory.systemTemp.path}/thestia_test_aufnahme.m4a';
        }
        return null;
      });
}

/// Beantwortet den Ereignis-Kanal des Aufnahme-Plugins.
///
/// DER GRUND (16.11.2026): Der Zustand der Aufnahme (Start, Pause,
/// Stopp) kommt über einen EventChannel - einer je Aufnahme. Ohne
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
/// DER GRUND (16.11.2026): Beim Anlegen eines Players räumt das
/// Plugin alle Spieler der Engine weg. Dieser Aufruf geht ohne "await"
/// an den Server - im Test landet er als ungefangener Fehler auf dem
/// Bildschirm ("MissingPluginException"), obwohl die App ihn abfängt.
///
/// Das Abspielen selbst ist im Test nicht möglich (dafür gibt es
/// eigene Tests) - das Blatt zum Anhören zeigt deshalb den Fehler
/// "nicht abspielbar" an, was genau das Verhalten ohne Player ist.
class _FakeAudioPlattform extends JustAudioPlatform {
  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async => DisposeAllPlayersResponse();

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      _FakeAudioPlayerPlatform();
}

/// Der Player-Ersatz: leere Strom, kein Ton.
///
/// DER GRUND: Der Standard-Ersatz kann den Player nicht öffnen. Der
/// Player hängt dann mit einem offenen Datenstrom fest - und beim
/// Schließen wirft er ("cannot close the subject while items are being
/// added"). Das trifft jeden Test, der eine Aufnahme anhören will.
class _FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  _FakeAudioPlayerPlatform() : super('fake-player');

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      const Stream<PlaybackEventMessage>.empty();

  @override
  Future<LoadResponse> load(LoadRequest request) async =>
      LoadResponse(duration: const Duration(seconds: 1));

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
    SetSkipSilenceRequest request,
  ) async => SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();
}

/// Beantwortet die Aufrufe des Audio-Players (just_audio).
void mockAudioPlayer() {
  JustAudioPlatform.instance = _FakeAudioPlattform();
}

/// Liefert eine feste Zeitzone.
///
/// WARUM: Der Benachrichtigungs-Dienst braucht die Zeitzone des Geräts
/// (für die Zeitangabe in der Meldung). Das Plugin gibt es auf Linux
/// (dem CI-Runner), auf Windows nicht - dort bleibt die Antwort einfach
/// aus, hier schlägt der Aufruf fehl und der Dienst startet nicht.
void mockZeitzone([String zone = 'Europe/Berlin']) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(zeitzoneKanal, (anfrage) async => zone);
}

/// Der In-Memory-Keystore für die Tests.
final Map<String, String> keystoreInhalt = <String, String>{};

/// Beantwortet die Pfad-Aufrufe (mit einem Temp-Ordner).
///
/// DER GRUND: `Supabase.initialize` holt sich das Speicher-Verzeichnis
/// (für die Sitzung). Ohne diesen Ersatz ruft der Test auf dem
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
/// ihre Daten in verschlüsselten Hive-Boxen. Ohne initialisiertes
/// Hive wirft das Box-Öffnen ("You need to initialize Hive") - der
/// Fehler landet sonst als unbehandelter Testfehler auf dem Bildschirm.
Future<void> mockHive() async {
  final temp = await Directory.systemTemp.createTemp('thesia_test_hive');
  Hive.init(temp.path);
}

/// Nimmt die Kanäle wieder aus dem Spiel (am Ende des Tests).
void unmockPlugins() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pfadKanal, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(keystoreKanal, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(aufnahmeKanal, null);
}
