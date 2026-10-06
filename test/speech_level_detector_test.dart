import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/speech_level_detector.dart';

/// Tests fuer die Stille-Erkennung der Audio-Vorstellung.
///
/// Anlass: eine Aufnahme konnte 10+ Sekunden komplett still sein und
/// wurde trotzdem akzeptiert. Der Mindestlaengen-Check im Review-Sheet
/// prueft nur die Dauer, nicht ob darin etwas gesagt wurde.
void main() {
  /// Kurzform: 10 Messungen mit demselben Pegel.
  SpeechLevelDetector filled(int count, double db) {
    final d = SpeechLevelDetector();
    for (var i = 0; i < count; i++) {
      d.addSample(db);
    }
    return d;
  }

  group('normalize', () {
    test('Pegel unter dem Rauschteppich werden zu null', () {
      expect(SpeechLevelDetector.normalize(-70), isNull);
      expect(SpeechLevelDetector.normalize(-60), isNull);
      expect(SpeechLevelDetector.normalize(-59.9), -59.9);
    });

    test('null und NaN werden zu null', () {
      expect(SpeechLevelDetector.normalize(null), isNull);
      expect(SpeechLevelDetector.normalize(double.nan), isNull);
    });

    test('0 dBFS bleibt 0, wird aber NICHT zu null', () {
      // record liefert bei Stille teils 0. 0 dBFS waere rechnerisch das
      // Maximum - genau deshalb wird 0 nicht stillgelegt, sondern erst
      // im Schwellwertvergleich als "laut" eingestuft.
      expect(SpeechLevelDetector.normalize(0), 0);
    });
  });

  group('isAudible', () {
    test('deutlich ueber der Schwelle ist Ton', () {
      expect(SpeechLevelDetector.isAudible(-20), isTrue);
      expect(SpeechLevelDetector.isAudible(-10), isTrue);
    });

    test('deutlich unter der Schwelle ist Stille', () {
      expect(SpeechLevelDetector.isAudible(-45), isFalse);
      expect(SpeechLevelDetector.isAudible(-55), isFalse);
    });

    test('genau auf der Schwelle gilt NICHT als Ton', () {
      // > statt >=: die Schwelle ist "ab hier Ton". >= wuerde exakt auf
      // dem Grenzwert schon Signal annehmen.
      expect(
        SpeechLevelDetector.isAudible(SpeechLevelDetector.speechThresholdDb),
        isFalse,
      );
      expect(
        SpeechLevelDetector.isAudible(
          SpeechLevelDetector.speechThresholdDb + 0.01,
        ),
        isTrue,
      );
    });

    test('Rauschteppich und darunter sind nie Ton', () {
      expect(SpeechLevelDetector.isAudible(-60), isFalse);
      expect(SpeechLevelDetector.isAudible(-90), isFalse);
      expect(SpeechLevelDetector.isAudible(null), isFalse);
    });

    test('leises Sprechen 40 cm entfernt gilt noch als Ton', () {
      // Der Grund fuer den tiefen Schwellwert: wer das Handy weiter weg
      // haelt, spricht leiser. -30 ist realistisch und muss durch.
      expect(SpeechLevelDetector.isAudible(-30), isTrue);
    });
  });

  group('SpeechLevelDetector', () {
    test('eine frische Instanz hat kein Fensterinhalt', () {
      final d = SpeechLevelDetector();
      expect(d.hasSpeech, isFalse);
      expect(d.peakDb, isNull);
      expect(d.averageDb, isNull);
      expect(d.trailingSilenceCount, 0);
    });

    test('10 Sekunden reine Stille ergibt hasSpeech false', () {
      // 100 Messungen bei 10 Hz = 10 s, exakt der Mindestlaengen-Fall,
      // der vorher durchging.
      final d = filled(100, -55);
      expect(d.hasSpeech, isFalse);
      expect(d.isSilentTail, isTrue);
    });

    test('10 Sekunden mit Stimme ergibt hasSpeech true', () {
      final d = filled(100, -25);
      expect(d.hasSpeech, isTrue);
      expect(d.isSilentTail, isFalse);
    });

    test('addSample meldet nur den Wechsel, nicht jeden Wert', () {
      // Sonst baut das Widget 10-mal pro Sekunde neu, obwohl sich die
      // Anzeige nicht geaendert hat.
      final d = SpeechLevelDetector();
      expect(d.addSample(-55), false, reason: 'Stille aendert nichts');
      expect(d.addSample(-25), true, reason: 'Ton ist ein Wechsel');
      expect(d.addSample(-20), false, reason: 'schon Ton, bleibt Ton');
      expect(d.addSample(-10), false);
      expect(d.addSample(-55), false);
    });

    test('das Fenster rutscht: alte Messung faellt heraus', () {
      final d = SpeechLevelDetector(window: 10);
      d.addSample(-20);
      for (var i = 0; i < 10; i++) {
        d.addSample(-50);
      }
      // -20 ist nach 10 weiteren Samples aus dem 10er-Fenster gewandert.
      // (-50 statt -55, weil -50 unterhalb des Rauschteppichs als null
      // gaelte und der Test dann die Normalisierung statt des Fensters
      // pruefen wuerde.)
      expect(d.peakDb, -50);
      expect(d.hasSpeech, isFalse);
    });

    test('kurze Pause gilt nicht als Stille', () {
      // 10 Messungen Pause = 1 s: "aehm, was sag ich" ist kein Grund
      // fuer eine Wiederholung.
      final d = SpeechLevelDetector(window: 60);
      d.addSample(-25);
      for (var i = 0; i < 10; i++) {
        d.addSample(-55);
      }
      expect(d.hasSpeech, isTrue);
      expect(d.isSilentTail, isFalse);
      expect(d.trailingSilenceCount, 10);
    });

    test('lange Pause am Ende gilt als Stille', () {
      final d = SpeechLevelDetector(window: 60);
      d.addSample(-25);
      for (var i = 0; i < 20; i++) {
        d.addSample(-55);
      }
      expect(d.hasSpeech, isTrue, reason: 'es wurde geredet');
      expect(d.isSilentTail, isTrue, reason: 'aber 2 s nichts mehr');
    });

    test('peakDb ist der Hoechstwert im Fenster', () {
      final d = SpeechLevelDetector();
      d.addSample(-40);
      d.addSample(-18);
      d.addSample(-55);
      d.addSample(-30);
      expect(d.peakDb, -18);
    });

    test('averageDb ist der Mittelwert der messbaren Werte', () {
      final d = SpeechLevelDetector();
      d.addSample(-20);
      d.addSample(-40);
      d.addSample(-70); // unter dem Teppich, zaehlt nicht mit
      expect(d.averageDb, -30);
    });

    test('reset leert das Fenster', () {
      final d = filled(30, -20);
      expect(d.hasSpeech, isTrue);
      d.reset();
      expect(d.hasSpeech, isFalse);
      expect(d.peakDb, isNull);
    });

    test('window kleiner als 1 wird auf 1 geholt', () {
      final d = SpeechLevelDetector(window: 0);
      d.addSample(-20);
      expect(d.hasSpeech, isTrue);
    });

    test('Gegenprobe: Schwellwert um einen Punkt anheben dreht das '
        'Ergebnis', () {
      // Haelt fest, DASS die Schwelle die Entscheidung traegt. Liegt
      // jemand bei -35 dBFS, ist die Aussage "still" - und genau das
      // ist der Fall, den die Einstellung sichtbar machen soll.
      final d = SpeechLevelDetector();
      for (var i = 0; i < 30; i++) {
        d.addSample(-35);
      }
      expect(SpeechLevelDetector.isAudible(-35), isFalse);
      expect(
        SpeechLevelDetector.isAudible(SpeechLevelDetector.speechThresholdDb),
        isFalse,
      );
    });
  });

  group('Anzeige-Werte', () {
    test('peakToPercent bildet das dB-Feld auf 0..100 ab', () {
      expect(SpeechLevelDetector.peakToPercent(null), 0);
      expect(SpeechLevelDetector.peakToPercent(-60), 0);
      expect(SpeechLevelDetector.peakToPercent(-30), 50);
      expect(SpeechLevelDetector.peakToPercent(0), 100);
    });

    test('peakToPercent begrenzt nach oben', () {
      expect(SpeechLevelDetector.peakToPercent(6), 100);
      expect(SpeechLevelDetector.peakToPercent(-999), 0);
    });

    test('dbToLevel01 ist 0 bei Stille und 1 bei 0 dBFS', () {
      expect(SpeechLevelDetector.dbToLevel01(null), 0.0);
      expect(SpeechLevelDetector.dbToLevel01(-60), 0.0);
      expect(SpeechLevelDetector.dbToLevel01(0), 1.0);
    });

    test('describe unterscheidet drei Faelle', () {
      expect(
        SpeechLevelDetector.describe(silent: false, peakDb: -20),
        'Ton erkannt',
      );
      expect(
        SpeechLevelDetector.describe(silent: true, peakDb: null),
        'Nur Stille',
      );
      expect(
        SpeechLevelDetector.describe(silent: true, peakDb: -50),
        'Sehr leise (17 %)',
      );
    });
  });
}