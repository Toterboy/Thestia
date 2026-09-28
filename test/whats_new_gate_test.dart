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

    test('cappt die Liste auf maxPoints Punkte', () {
      final keys = WhatsNewService.keysFor(currentBuild: 999, shownBuild: 0);
      expect(keys.length, lessThanOrEqualTo(WhatsNewService.maxPoints));
    });

    // Regression: keysFor nahm sublist(out.length - 6), also die LETZTEN
    // sechs. Build 30 hatte zehn Satzbausteine fuer vier Aussagen, das
    // Cap zerschnitt mitten im Satz - die Anzeige begann mit "fuer
    // Funken, Daumen und Nachrichten." und der Punkt "Vorstellungen
    // rotieren" fehlte vollstaendig.
    test('Cap zerstört keinen Punkt: gekürzt wird nur am Listenende', () {
      final keys = WhatsNewService.keysFor(currentBuild: 30, shownBuild: 29);
      expect(keys, isNotEmpty);
      // Erster Eintrag muss ein vollstaendiger Punkt aus contentByBuild
      // sein - kein Satzbaustein, kein deutscher Klartext.
      final known = WhatsNewService.contentByBuild[30]!;
      for (final k in keys) {
        expect(known, contains(k),
            reason: '$k steht nicht in contentByBuild[30]');
      }
      // Kein Klartext: jeder Eintrag ist ein l10n-Key.
      for (final k in keys) {
        expect(k, startsWith('whatsnew.'),
            reason: '$k ist kein l10n-Key - nicht uebersetzt');
      }
    });

    test('alle Punkte einer Version tauchen auf (kein Punkt geht verloren)', () {
      for (final build in [22, 30]) {
        final keys = WhatsNewService.keysFor(
            currentBuild: build, shownBuild: build - 1);
        expect(keys.length, WhatsNewService.contentByBuild[build]!.length,
            reason: 'Build $build verliert Punkte');
      }
    });

    // Regression: bei einem Sprung ueber mehrere Versionen verdraengte
    // die alte Logik den Inhalt der JUENGSTEN Version, weil sie die
    // letzten sechs einer aufsteigend gebauten Liste nahm.
    test('Sprung ueber mehrere Versionen zeigt zuerst die juengste', () {
      final keys = WhatsNewService.keysFor(currentBuild: 30, shownBuild: 21);
      expect(keys, isNotEmpty);
      final firstNewest = WhatsNewService.contentByBuild[30]!.first;
      expect(keys.first, firstNewest,
          reason: 'Juengste Version muss zuerst stehen');
    });

    test('jeder Eintrag ist ein vollstaendiger Punkt, kein Satzbaustein', () {
      // Satzbausteine erkennt man daran, dass sie mit einem
      // Kleinbuchstaben beginnen (Fortsetzung eines Satzes).
      for (final entry in WhatsNewService.contentByBuild.entries) {
        for (final k in entry.value) {
          expect(k, startsWith('whatsnew.'),
              reason: 'Build ${entry.key}: "$k" ist kein l10n-Key');
        }
      }
    });
  });

  group('WhatsNewService.hasNewInputs', () {
    test('Geburtstags-Stil wird ab Build 22 abgefragt', () {
      expect(WhatsNewService.hasNewInputs(21), isFalse);
      expect(WhatsNewService.hasNewInputs(22), isTrue);
    });
  });
}
