import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/whats_new_service.dart';

/// Tests für das "Neu in dieser Version"-Gate (NUTZERWUNSCH: Popup bei
/// App-Update für bereits registrierte Nutzer + neue Angaben abfragen).
void main() {
  group('WhatsNewService.shouldShow', () {
    test('zeigt bei gestiegenem Build für eingerichtete Konten', () {
      expect(
        WhatsNewService.shouldShow(
          currentBuild: 30,
          shownBuild: 21,
          registered: true,
          onboardingDone: true,
        ),
        isTrue,
      );
    });

    test('zeigt NICHT, wenn bereits gezeigt (gleicher/neuer Build)', () {
      expect(
        WhatsNewService.shouldShow(
          currentBuild: 30,
          shownBuild: 30,
          registered: true,
          onboardingDone: true,
        ),
        isFalse,
      );
      expect(
        WhatsNewService.shouldShow(
          currentBuild: 31,
          shownBuild: 31,
          registered: true,
          onboardingDone: true,
        ),
        isFalse,
      );
    });

    test('zeigt NICHT bei ungültigem Build (0)', () {
      expect(
        WhatsNewService.shouldShow(
          currentBuild: 0,
          shownBuild: 0,
          registered: true,
          onboardingDone: true,
        ),
        isFalse,
      );
    });

    test('zeigt NICHT für nicht-registrierte / nicht-eingerichtete', () {
      expect(
        WhatsNewService.shouldShow(
          currentBuild: 30,
          shownBuild: 0,
          registered: false,
          onboardingDone: true,
        ),
        isFalse,
      );
      expect(
        WhatsNewService.shouldShow(
          currentBuild: 30,
          shownBuild: 0,
          registered: true,
          onboardingDone: false,
        ),
        isFalse,
      );
    });

    test('zeigt NICHT, wenn keine Inhalte in der Build-Range', () {
      expect(
        WhatsNewService.shouldShow(
          currentBuild: 22, // erste Inhalts-Version
          shownBuild: 21,
          registered: true,
          onboardingDone: true,
        ),
        isTrue,
      );
      // Build ohne eigenen Inhalt und Range endet vor Inhalt:
      expect(
        WhatsNewService.shouldShow(
          currentBuild: 20,
          shownBuild: 19,
          registered: true,
          onboardingDone: true,
        ),
        isFalse,
      );
    });
  });

  group('WhatsNewService.keysFor', () {
    test('liefert Bullets für neue Builds, leer für alte', () {
      expect(
        WhatsNewService.keysFor(currentBuild: 30, shownBuild: 0),
        isNotEmpty,
      );
      expect(
        WhatsNewService.keysFor(currentBuild: 30, shownBuild: 30),
        isEmpty,
      );
      expect(
        WhatsNewService.keysFor(currentBuild: 20, shownBuild: 19),
        isEmpty,
      );
    });

    test('cappt die Liste auf 6 Punkte', () {
      final keys = WhatsNewService.keysFor(currentBuild: 999, shownBuild: 0);
      expect(keys.length, lessThanOrEqualTo(6));
    });
  });

  group('WhatsNewService.hasNewInputs', () {
    test('Geburtstags-Stil wird ab Build 22 abgefragt', () {
      expect(WhatsNewService.hasNewInputs(21), isFalse);
      expect(WhatsNewService.hasNewInputs(22), isTrue);
    });
  });
}
