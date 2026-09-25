import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/services/verification_service.dart';

/// Regressionstest für den Root-Cause-Fix "Einreichen schlägt fehl":
/// VerificationVideo hat KEINEN Hive-TypeAdapter und wird deshalb als
/// JSON-STRING in der verschlüsselten Box gespeichert (box.put() mit dem
/// reinen Objekt warf "HiveError: unknown type" und brach das Einreichen
/// VOR dem Upload ab). Diese Tests sichern den Speichervertrag:
/// toJson MUSS ein reines JSON-Map liefern, fromJson MUSS es exakt
/// zurückgeben - sonst ist der Einreichungspfad kaputt und der Test wird
/// ROT.
void main() {
  group('VerificationVideo JSON-Speichervertrag', () {
    test('Roundtrip erhält alle Felder (inkl. Challenge und Status)', () {
      final original = VerificationVideo(
        filePath: '/tmp/verification_123.mp4',
        recordedAt: DateTime.utc(2026, 9, 18, 12, 0, 0),
        durationSeconds: 15,
        challengeText: '4832',
      );
      final encoded = jsonEncode(original.toJson());
      final decoded = VerificationVideo.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(decoded.filePath, original.filePath);
      expect(decoded.recordedAt.toIso8601String(),
          original.recordedAt.toIso8601String());
      expect(decoded.durationSeconds, 15);
      expect(decoded.challengeText, '4832');
      expect(decoded.challengeGesture, isNull);
      expect(decoded.isVerified, isFalse);
    });

    test('copyWith(isVerified: true) ändert nur den Status', () {
      final original = VerificationVideo(
        filePath: '/tmp/verification_123.mp4',
        recordedAt: DateTime.utc(2026, 9, 18, 12, 0, 0),
        durationSeconds: 15,
      );
      final verified = original.copyWith(isVerified: true);
      expect(verified.isVerified, isTrue);
      expect(verified.filePath, original.filePath);
      expect(jsonDecode(jsonEncode(verified.toJson()))['isVerified'], isTrue);
    });

    test('fromJson toleriert fehlende optionale Felder', () {
      final decoded = VerificationVideo.fromJson({
        'filePath': '/tmp/verification_1.mp4',
        'recordedAt': DateTime.utc(2026, 9, 18).toIso8601String(),
        'durationSeconds': 15,
      });
      expect(decoded.challengeText, isNull);
      expect(decoded.isVerified, isFalse);
    });
  });

  group('Hive-No-Adapter-Beweis (der eigentliche Bug)', () {
    late Directory tempDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = await Directory.systemTemp.createTemp('verify_box_test');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test(
        'Box<VerificationVideo> OHNE Adapter wirft beim put (das war der '
        'Einreichungs-Abbruch)', () async {
      final box = await Hive.openBox<VerificationVideo>('verify_typed');
      final video = VerificationVideo(
        filePath: '/tmp/verification_x.mp4',
        recordedAt: DateTime.utc(2026, 9, 18),
        durationSeconds: 15,
      );
      // Der alte Code tat genau das -> HiveError "unknown type".
      // Wäre dieser Fehler weg, wäre der Fix nie nötig gewesen.
      await expectLater(
        box.put('k', video),
        throwsA(isA<HiveError>()),
      );
    });

    test('Box<String> mit JSON funktioniert (der Fix)', () async {
      final box = await Hive.openBox<String>('verify_json');
      final video = VerificationVideo(
        filePath: '/tmp/verification_x.mp4',
        recordedAt: DateTime.utc(2026, 9, 18),
        durationSeconds: 15,
      );
      await box.put('k', jsonEncode(video.toJson()));
      final back = VerificationVideo.fromJson(
        jsonDecode(box.get('k')!) as Map<String, dynamic>,
      );
      expect(back.filePath, video.filePath);
    });
  });
}
