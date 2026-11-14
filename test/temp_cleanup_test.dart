// Unit-Tests fuer das Aufräumen der temporären Dateien.
//
// WAS HIER GEPRUEFT WIRD:
//   * die entschlüsselten Voice-Notes werden aus dem Temp-Verzeichnis
//     gelöscht (Audit M-17: sie waren sonst ein Ruhezustand-Rest),
//   * fremde Dateien bleiben unangetastet,
//   * Verzeichnisse werden nicht angerührt.
//
// WARUM DAS EIGENTLICH WICHTIG IST:
//   Das E2E-Versprechen der App lautet "Inhalte existieren nur im
//   Speicher". Eine entschlüsselte Sprachnachricht, die im
//   System-Temp-Verzeichnis liegen bleibt, bricht dieses Versprechen -
//   sie ist danach von jedem Programm auf dem Geraet lesbar. Der
//   Aufraeum-Lauf ist deshalb das letzte Sicherheitsnetz, und er muss
//   TREFFER GENAU sein: Er darf nur die eigenen Reste loeschen und
//   keine fremde Datei (Cache, Log, Bild) wegraeumen.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/utils/temp_cleanup.dart';

/// Der Kanal, ueber den path_provider den Temp-Ordner nennt.
const MethodChannel _pfadKanal = MethodChannel(
  'plugins.flutter.io/path_provider',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thestia_temp_cleanup');
    // Das Temp-Verzeichnis wird normalerweise von path_provider geliefert.
    // Im Test gibt es kein Geraet - der Kanal liefert deshalb unseren
    // eigenen Ordner. So prueft der Test genau das, was auch in der App
    // passiert: Dateien im gemeldeten Temp-Verzeichnis.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pfadKanal, (anfrage) async {
          if (anfrage.method == 'getTemporaryDirectory') return tempDir.path;
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pfadKanal, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Legt eine Datei im Temp-Verzeichnis an.
  Future<File> datei(String name, [String inhalt = 'x']) async {
    final f = File('${tempDir.path}${Platform.pathSeparator}$name');
    await f.writeAsString(inhalt);
    return f;
  }

  test('die entschluesselte Voice-Note wird geloescht', () async {
    final reste = await datei(
      'thestia_incoming_123.m4a',
      'geheimer Audio-Inhalt',
    );

    await cleanupDecryptedTempFiles();

    expect(
      reste.existsSync(),
      isFalse,
      reason:
          'Die entschluesselte Sprachnachricht liegt noch im Temp-Ordner - '
          'das E2E-Versprechen waere gebrochen.',
    );
  });

  test('der historische Dateiname (wisp_) wird auch geloescht', () async {
    // DER GRUND: Aeltere App-Versionen schrieben mit "wisp_" - die Reste
    // liegen auf den Geraeten von Nutzern, die schon gewechselt sind.
    final reste = await datei('wisp_incoming_77.m4a');

    await cleanupDecryptedTempFiles();

    expect(reste.existsSync(), isFalse);
  });

  test('fremde Dateien bleiben liegen', () async {
    // DER GRUND FUER DIESE PRUEFUNG: Der Aufraeum-Lauf darf NICHT das
    // ganze Temp-Verzeichnis leeren. Sonst wuerde er neben den eigenen
    // Resten auch Dateien fremder Module (Cache, Log, Bild-Vorschau)
    // wegraeumen.
    final fremd = await datei('sonstige_datei.txt', 'gehoert jemand anderem');
    final eigenesBild = await datei('thestia_incoming_1.png');

    await cleanupDecryptedTempFiles();

    expect(
      fremd.existsSync(),
      isTrue,
      reason: 'Der Aufraeum-Lauf hat eine fremde Datei geloescht.',
    );
    expect(
      eigenesBild.existsSync(),
      isTrue,
      reason:
          'Nur entschluesselte Audio-Dateien (.m4a) sind Rueckstaende - '
          'ein Bild mit aehnlichem Namen nicht.',
    );
  });

  test('Verzeichnisse werden nicht geloescht', () async {
    // DER GRUND: Der Code prueft "ist es eine Datei?" - ein Ordner mit
    // demselben Namen darf nicht mitgeloescht werden (sonst waere ein
    // Nutzerordner im Temp-Verzeichnis weg).
    final ordner = Directory(
      '${tempDir.path}${Platform.pathSeparator}thestia_incoming_ordner',
    );
    await ordner.create();

    await cleanupDecryptedTempFiles();

    expect(
      ordner.existsSync(),
      isTrue,
      reason: 'Der Aufraeum-Lauf hat ein Verzeichnis geloescht.',
    );
  });

  test('mehrere Reste werden alle geloescht', () async {
    final a = await datei('thestia_incoming_1.m4a');
    final b = await datei('thestia_incoming_2.m4a');
    final c = await datei('wisp_incoming_3.m4a');

    await cleanupDecryptedTempFiles();

    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isFalse);
    expect(c.existsSync(), isFalse);
  });

  test('ein leeres Temp-Verzeichnis ist kein Fehler', () async {
    // DER GRUND: Der Aufraeum-Lauf laeuft beim App-Start. Wenn das
    // Verzeichnis leer ist (frische Installation), darf nichts passieren.
    await expectLater(cleanupDecryptedTempFiles(), completes);
  });
}
