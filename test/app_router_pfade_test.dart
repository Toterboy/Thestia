// Die Wege (Pfade) des Routers.
//
// ANLASS (19.11.2026): `lib/routing/app_router.dart` war nur zu 29 %
// abgedeckt. Ein Tippfehler in einem Pfad fuehrt nicht zu einem
// Absturz, sondern zu einer stillen Fehlernavigation - der Nutzer
// tippt auf "Quiz" und landet auf dem Ladebildschirm.
//
// WAS HIER GEPRUEFT WIRD:
//   * die gebauten Wege (mit den Parametern) passen zu den Routen,
//   * jeder Weg ist einmal da (keine zwei Routen mit demselben Pfad),
//   * jeder Weg beginnt mit einem Schraegstrich.
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/routing/app_router.dart';

void main() {
  group('Die gebauten Wege', () {
    test('das Quiz bekommt die Nummer der Partie', () {
      expect(AppRoutes.quizPath(42), '/quiz/42');
    });

    test('die Eisbrecher-Fragen bekommen die Nummer der Partie', () {
      expect(AppRoutes.spiceQuestionsPath(7), '/spice/7');
    });

    test('das fremde Profil bekommt die Nutzer-ID', () {
      expect(AppRoutes.profileDetailPath('nutzer-7'), '/profile/nutzer-7');
    });

    test('die gebauten Wege passen zu den Routen', () {
      // DER GRUND: Der gebaute Weg muss genau dem Muster der Route
      // entsprechen - sonst findet der Router die Route nicht.
      expect(
        AppRoutes.quizPath(1),
        matches(RegExp('^${AppRoutes.quiz}\$'.replaceAll(':matchId', r'\d+'))),
      );
      expect(
        AppRoutes.spiceQuestionsPath(1),
        matches(
          RegExp(
            '^${AppRoutes.spiceQuestions}\$'.replaceAll(':matchId', r'\d+'),
          ),
        ),
      );
      expect(
        AppRoutes.profileDetailPath('abc'),
        matches(
          RegExp(
            '^${AppRoutes.profileDetail}\$'.replaceAll(':userId', r'[^/]+'),
          ),
        ),
      );
    });
  });

  group('Die Routen selbst', () {
    test('jede Route hat ihren Platz', () {
      // DER GRUND: Ohne Pfad gibt es keinen Weg dorthin - der Nutzer
      // kann den Screen nicht erreichen.
      final pfade = <String>[
        AppRoutes.loading,
        AppRoutes.signupWelcome,
        AppRoutes.deleteData,
        AppRoutes.guardianConsent,
        AppRoutes.guardianTransition,
        AppRoutes.guardianSettings,
        AppRoutes.onboarding,
        AppRoutes.login,
        AppRoutes.forgotPassword,
        AppRoutes.resetPassword,
        AppRoutes.unbanRequest,
        AppRoutes.home,
        AppRoutes.findYourMatch,
        AppRoutes.findYourMatchCategory,
        AppRoutes.interessen,
        AppRoutes.quiz,
        AppRoutes.spiceQuestions,
        AppRoutes.chatDetail,
        AppRoutes.profile,
        AppRoutes.profileEdit,
        AppRoutes.profileDetail,
        AppRoutes.settings,
        AppRoutes.personalityTest,
        AppRoutes.settingsPrivacyOnce,
        AppRoutes.datingSafetyEducation,
        AppRoutes.swipeModeSelection,
        AppRoutes.randomChat,
        AppRoutes.transitRadar,
        AppRoutes.bugReport,
        AppRoutes.qrProfile,
        AppRoutes.qrScan,
        AppRoutes.qrContacts,
        AppRoutes.moodPicker,
        AppRoutes.whatsNew,
        AppRoutes.privacy,
        AppRoutes.privacyPolicy,
      ];
      for (final pfad in pfade) {
        expect(pfad, isNotEmpty, reason: 'Eine Route hat keinen Pfad.');
        expect(
          pfad.startsWith('/'),
          isTrue,
          reason: '"$pfad" muss mit einem Schraegstrich beginnen.',
        );
      }
    });

    test('keine Route hat denselben Pfad', () {
      final pfade = <String>[
        AppRoutes.loading,
        AppRoutes.signupWelcome,
        AppRoutes.deleteData,
        AppRoutes.guardianConsent,
        AppRoutes.guardianTransition,
        AppRoutes.guardianSettings,
        AppRoutes.onboarding,
        AppRoutes.login,
        AppRoutes.forgotPassword,
        AppRoutes.resetPassword,
        AppRoutes.unbanRequest,
        AppRoutes.home,
        AppRoutes.findYourMatch,
        AppRoutes.findYourMatchCategory,
        AppRoutes.interessen,
        AppRoutes.quiz,
        AppRoutes.spiceQuestions,
        AppRoutes.chatDetail,
        AppRoutes.profile,
        AppRoutes.profileEdit,
        AppRoutes.profileDetail,
        AppRoutes.settings,
        AppRoutes.personalityTest,
        AppRoutes.settingsPrivacyOnce,
        AppRoutes.datingSafetyEducation,
        AppRoutes.swipeModeSelection,
        AppRoutes.randomChat,
        AppRoutes.transitRadar,
        AppRoutes.bugReport,
        AppRoutes.qrProfile,
        AppRoutes.qrScan,
        AppRoutes.qrContacts,
        AppRoutes.moodPicker,
        AppRoutes.whatsNew,
        AppRoutes.privacy,
        AppRoutes.privacyPolicy,
      ];
      final doppelte = pfade
          .where((p) => pfade.where((q) => q == p).length > 1)
          .toSet();
      expect(
        doppelte,
        isEmpty,
        reason:
            'Zwei Routen mit demselben Pfad - der Router nimmt immer die '
            'erste, die zweite ist unerreichbar.',
      );
    });
  });
}
