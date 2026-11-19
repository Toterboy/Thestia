// Die Challenge und die Metadaten des Verifikationsvideos.
//
// ANLASS (19.11.2026): `lib/services/verification_service.dart` war nur
// zu 19 % abgedeckt. Der Speicher (Hive) braucht das echte Plugin -
// aber die Challenge (was der Nutzer tun soll) und die Metadaten des
// Videos sind reine Logik und gehören geprueft.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Metadaten ueberstehen den Weg in den Speicher und zurueck
//     (inkl. GPS-Position und Gesichtseinbettung),
//   * die Challenge nennt nur sprachneutrale Codes,
//   * die Anzeige der Challenge ist lokalisiert,
//   * die Videolaenge wird gegen die Server-Regel (5 bis 15 Sekunden)
//     geprueft.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/verification_service.dart';

/// Liefert einen BuildContext (Default-Locale Deutsch, wie ohne Scope).
Future<BuildContext> _ctx(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    ),
  );
  return ctx;
}

/// Eine Position wie das Plugin sie liefert (alle Felder befuellt).
Position _position(double breite, double laenge) => Position(
  latitude: breite,
  longitude: laenge,
  timestamp: DateTime(2026, 11, 18, 20, 30),
  accuracy: 5,
  altitude: 0,
  heading: 0,
  speed: 0,
  speedAccuracy: 0,
  headingAccuracy: 0,
  altitudeAccuracy: 0,
);

void main() {
  group('Die Metadaten des Videos', () {
    test('Ort und Einbettung ueberstehen den Speicherweg', () {
      final video = VerificationVideo(
        filePath: '/tmp/verification_1.mp4',
        recordedAt: DateTime(2026, 11, 18, 20, 30),
        durationSeconds: 9,
        challengeText: '4821',
        challengeGesture: 'tongue',
        location: _position(53.123456, 8.654321),
        isVerified: true,
        faceEmbedding: const [0.1, 0.25, 0.5],
      );

      final json = video.toJson();
      final zurueck = VerificationVideo.fromJson(json);

      expect(zurueck.filePath, video.filePath);
      expect(zurueck.recordedAt, video.recordedAt);
      expect(zurueck.durationSeconds, 9);
      expect(zurueck.challengeText, '4821');
      expect(zurueck.challengeGesture, 'tongue');
      expect(zurueck.isVerified, isTrue);
      expect(zurueck.faceEmbedding, const [0.1, 0.25, 0.5]);
      // Der Ort bleibt erhalten (Breite/Länge auf drei Stellen genau).
      expect(zurueck.location, isNotNull);
      expect(zurueck.location!.latitude, closeTo(53.123456, 0.000001));
      expect(zurueck.location!.longitude, closeTo(8.654321, 0.000001));
    });

    test('ohne Ort und ohne Einbettung bleiben die Felder leer', () {
      final video = VerificationVideo(
        filePath: '/tmp/verification_2.mp4',
        recordedAt: DateTime(2026, 11, 18, 20, 30),
        durationSeconds: 7,
      );
      final json = video.toJson();
      expect(json['location'], isNull);
      expect(json['faceEmbedding'], isNull);

      final zurueck = VerificationVideo.fromJson(json);
      expect(zurueck.location, isNull);
      expect(zurueck.faceEmbedding, isNull);
      expect(zurueck.isVerified, isFalse);
    });

    test('copyWith aendert nur das, was man ihm gibt', () {
      final video = VerificationVideo(
        filePath: '/tmp/a.mp4',
        recordedAt: DateTime(2026, 11, 18),
        durationSeconds: 8,
        challengeText: '1234',
        location: _position(1, 2),
      );
      final kopie = video.copyWith(isVerified: true);
      expect(kopie.isVerified, isTrue);
      expect(kopie.filePath, video.filePath);
      expect(kopie.challengeText, '1234');
      expect(kopie.location, isNotNull);
    });
  });

  group('Die Challenge', () {
    test('die erzeugten Daten passen zum Typ', () {
      final service = VerificationService();
      for (var i = 0; i < 40; i++) {
        final (typ, daten) = service.generateChallenge();
        switch (typ) {
          case VerificationChallengeType.speakNumber:
            // Vier Ziffern zwischen 1000 und 9999.
            expect(daten, matches(RegExp(r'^\d{4}$')));
            expect(int.parse(daten), inInclusiveRange(1000, 9999));
          case VerificationChallengeType.makeGesture:
            expect(
              daten,
              anyOf(equals('tongue'), equals('blink'), equals('brows')),
            );
          case VerificationChallengeType.turnHead:
            expect(daten, anyOf(equals('left_right'), equals('right_left')));
          case VerificationChallengeType.smile:
            expect(daten, 'smile');
        }
      }
    });

    testWidgets('die Zahl wird unveraendert angezeigt', (tester) async {
      final ctx = await _ctx(tester);
      expect(
        VerificationService.challengeDataLabel(
          ctx,
          VerificationChallengeType.speakNumber,
          '4821',
        ),
        '4821',
      );
    });

    testWidgets('Geste und Richtung kommen uebersetzt', (tester) async {
      final ctx = await _ctx(tester);
      // Die Labels sind lokalisiert - der Code selbst nicht.
      final geste = VerificationService.challengeDataLabel(
        ctx,
        VerificationChallengeType.makeGesture,
        'tongue',
      );
      expect(geste, isNot('tongue'));
      expect(geste, L10n.t(ctx, 'verify.challenge.gesture.tongue'));

      final richtung = VerificationService.challengeDataLabel(
        ctx,
        VerificationChallengeType.turnHead,
        'left_right',
      );
      expect(richtung, L10n.t(ctx, 'verify.challenge.direction.left_right'));

      final lachen = VerificationService.challengeDataLabel(
        ctx,
        VerificationChallengeType.smile,
        'smile',
      );
      expect(lachen, L10n.t(ctx, 'verify.challenge.action.smile'));
    });

    testWidgets('die Beschreibung nennt Aufgabe und Label', (tester) async {
      final ctx = await _ctx(tester);
      final service = VerificationService();
      final text = service.challengeDescription(
        ctx,
        VerificationChallengeType.speakNumber,
        '4821',
      );
      expect(text, contains('4821'));
      expect(text, contains(L10n.t(ctx, 'verify.challenge.task')));
      // Die Basiszeile (was der Nutzer tun soll) steht auch drin.
      expect(text, contains(L10n.t(ctx, 'verify.challenge.base.speakNumber')));
    });
  });

  group('Die Laengenregel des Videos', () {
    test('der Server erlaubt 5 bis 15 Sekunden', () {
      expect(VerificationService.minDurationSeconds, 5);
      expect(VerificationService.maxDurationSeconds, 15);
    });
  });
}
