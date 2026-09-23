import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/models/report_models.dart';

void main() {
  group('Altersschutz-Meldegründe (v0.9.1)', () {
    test('alle ReportType-Werte haben eindeutige Label-Keys', () {
      final keys = ReportType.values.map((t) => t.labelKey).toList();
      expect(keys.toSet().length, keys.length);
      for (final key in keys) {
        expect(key.startsWith('report.type.'), isTrue);
      }
    });

    test('Meldegrund Falsches Alter existiert', () {
      expect(
        ReportType.values.map((t) => t.name),
        contains('wrongAge'),
      );
      expect(ReportType.wrongAge.labelKey, 'report.type.wrongAge');
      expect(ReportType.wrongAge.value, 'wrongAge');
    });
  });
}
