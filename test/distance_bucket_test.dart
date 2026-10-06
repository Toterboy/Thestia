import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/utils/distance_bucket.dart';

/// Tests fuer die Entfernungs-Grobung.
///
/// Grundsatz: andere sehen OB nah oder weit weg - keinen Ort, keinen
/// exakten Standort, keine Meter. Deshalb 10-km-Stufen und keine
/// Auskunft unterhalb von 5 km.
void main() {
  group('bucketFor', () {
    test('unterhalb der Sichtbarkeitsgrenze gibt es keine Stufe', () {
      // 2 km sind zwar nah, koennten in dicht bewohnten Gegenden aber
      // den Nachbarn verraten.
      expect(DistanceBucket.bucketFor(0), isNull);
      expect(DistanceBucket.bucketFor(2.4), isNull);
      expect(DistanceBucket.bucketFor(4.9), isNull);
      expect(DistanceBucket.bucketFor(5), isNotNull);
    });

    test('die erste Stufe sagt "unter 10 km"', () {
      expect(DistanceBucket.bucketFor(5), (km: 0, kmUpper: 10));
      expect(DistanceBucket.bucketFor(9.9), (km: 0, kmUpper: 10));
    });

    test('mitte landet in der passenden 10-km-Stufe', () {
      expect(DistanceBucket.bucketFor(10), (km: 10, kmUpper: 20));
      expect(DistanceBucket.bucketFor(15.7), (km: 10, kmUpper: 20));
      expect(DistanceBucket.bucketFor(19.9), (km: 10, kmUpper: 20));
      expect(DistanceBucket.bucketFor(34), (km: 30, kmUpper: 40));
      expect(DistanceBucket.bucketFor(87), (km: 80, kmUpper: 90));
    });

    test('genau auf einer Grenze rueckt eine Stufe nach oben', () {
      // Die Grenzen sind halb offen [untere, untere+10): 10,0 gehoert
      // zu "10 bis 20", 19,9 auch, 20,0 zu "20 bis 30". Jede Grenze
      // ist genau einmal besetzt.
      expect(DistanceBucket.bucketFor(10), (km: 10, kmUpper: 20));
      expect(DistanceBucket.bucketFor(19.999), (km: 10, kmUpper: 20));
      expect(DistanceBucket.bucketFor(20), (km: 20, kmUpper: 30));
    });

    test('jede Grenze wird genau einmal besetzt', () {
      // Jeder Wert kurz UNTER einer Grenze gehoert noch zur unteren
      // Stufe, die Grenze selbst zur oberen. Keine Luecke, keine
      // Ueberschneidung.
      for (var g = 10; g < DistanceBucket.lastThresholdKm;
          g += DistanceBucket.stepKm) {
        final below = DistanceBucket.bucketFor(g - 0.1)!;
        final at = DistanceBucket.bucketFor(g.toDouble())!;
        expect(below.kmUpper, g, reason: 'Stufe unter $g endet falsch');
        expect(at.km, g, reason: 'Stufe ab $g beginnt falsch');
      }
    });

    test('ab 100 km wird nicht mehr verraten', () {
      // 180 km und 1900 km bekommen denselben Text: die genaue Zahl
      // waere ein Standortdetail.
      final b180 = DistanceBucket.bucketFor(180);
      final b1900 = DistanceBucket.bucketFor(1900);
      expect(b180, (km: 100, kmUpper: null));
      expect(b1900, b180);
    });

    test('genau 100 km ist die letzte beschriftete Stufe', () {
      expect(DistanceBucket.bucketFor(100), (km: 100, kmUpper: null));
      expect(DistanceBucket.bucketFor(99.9), (km: 90, kmUpper: 100));
    });

    test('null und NaN ergeben keine Stufe', () {
      expect(DistanceBucket.bucketFor(null), isNull);
      expect(DistanceBucket.bucketFor(double.nan), isNull);
    });

    test('die Grenzen liegen dort, wo die Beschriftung sagt', () {
      // Jede beschriftete Stufe muss genau 10 km breit sein - sonst
      // waere die Anzeige nicht die zugesagte Grobung.
      for (var lower = 0; lower < DistanceBucket.lastThresholdKm;
          lower += DistanceBucket.stepKm) {
        final b = DistanceBucket.bucketFor(lower == 0 ? 5 : lower.toDouble());
        expect(b, isNotNull, reason: 'Stufe $lower fehlt');
        final lo = b!.km!;
        final hi = b.kmUpper;
        if (hi != null) {
          expect(
            hi - lo,
            DistanceBucket.stepKm,
            reason: 'Stufe $lo-$hi ist nicht 10 km breit',
          );
        }
      }
    });
  });

  group('label', () {
    /// Ersatz-L10n mit realistischen Textbausteinen. Fuer die Vergleiche
    /// unten MUSS er die Zahlen einsetzen: mit einem konstanten
    /// Rueckgabewert waeren alle Stufen derselbe String und die Tests
    /// waeren aussagelos.
    String t(String key) {
      switch (key) {
        case 'distance.bucketUnder':
          return 'unter {km} km';
        case 'distance.bucketRange':
          return '{from} bis {to} km';
        case 'distance.bucketOver':
          return 'ueber {km} km';
        case 'distance.bucketUnknown':
          return 'unbekannt';
        default:
          return key;
      }
    }

    test('erste Stufe nutzt den "unter"-Text', () {
      final b = DistanceBucket.bucketFor(7)!;
      expect(DistanceBucket.label(b, t), 'unter 10 km');
    });

    test('mittlere Stufe nutzt den Bereichs-Text mit beiden Zahlen', () {
      final b = DistanceBucket.bucketFor(34)!;
      expect(DistanceBucket.label(b, t), '30 bis 40 km');
    });

    test('ueber der letzten Stufe gibt es nur eine Zahl', () {
      final b = DistanceBucket.bucketFor(500)!;
      expect(DistanceBucket.label(b, t), 'ueber 100 km');
    });

    test('kein Platzhalter bleibt uebrig', () {
      for (final km in [3.0, 5.0, 9.9, 10.0, 34.0, 99.9, 100.0, 900.0]) {
        final b = DistanceBucket.bucketFor(km);
        if (b == null) continue;
        final label = DistanceBucket.label(b, t);
        expect(label.contains('{'), isFalse, reason: 'km=$km: $label');
      }
    });
  });

  group('labelForKm', () {
    test('liefert null unterhalb der Sichtbarkeitsgrenze', () {
      expect(DistanceBucket.labelForKm(2, (k) => k), isNull);
    });

    test('liefert den Text oberhalb', () {
      expect(DistanceBucket.labelForKm(15, (k) => k), isNotNull);
    });
  });

  group('Gegenproben zur Absicht', () {
    test('zwei Personen 8 km auseinander bekommen denselben Text', () {
      // Das ist der Zweck: 8 und 9 km sind fuer "koennen wir uns
      // treffen" dieselbe Aussage.
      final a = DistanceBucket.labelForKm(8, (k) => 'X');
      final b = DistanceBucket.labelForKm(9.5, (k) => 'X');
      expect(a, b);
    });

    test('der Text nennt niemals eine Zahl unter 10 km', () {
      // Gegenprobe zur Absicht der Sichtbarkeitsgrenze.
      final label = DistanceBucket.labelForKm(5, (k) => k)!;
      expect(label.contains('5'), isFalse);
    });

    test('sehr weit entfernte Personen sind nicht unterscheidbar', () {
      expect(
        DistanceBucket.labelForKm(300, (k) => 'X'),
        DistanceBucket.labelForKm(3000, (k) => 'X'),
      );
    });

    test('die Genauigkeit waechst mit der Naehe', () {
      // Wer nah wohnt, erfaehrt mehr - aber nur in ganzen Stufen.
      // Geprueft an den Stufen-Daten, nicht am Text: mit einem
      // konstanten Text-Mock waeren alle Stufen gleich.
      final nah = DistanceBucket.bucketFor(12)!;
      final weit = DistanceBucket.bucketFor(42)!;
      expect(nah.km, 10);
      expect(weit.km, 40);
      expect(nah.km, isNot(weit.km));
    });
  });
}