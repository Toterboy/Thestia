import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/guardian_status.dart';
import 'package:thestia/providers/guardian_provider.dart';
import 'package:thestia/widgets/guardian_section.dart';

/// Tests fuer den Zustand "die Freigabe ist beendet".
///
/// BEFUND 04.11.2026: Bis hierher sah dieser Fall in der App aus wie
/// "es gab nie eine Freigabe" - der Jugendliche wusste nicht, dass
/// seine Freigabe endete, und erst recht nicht, dass dabei die
/// E-Mail-Adresse des Elternteils geloescht wurde (Migration 179).
///
/// Der Test prueft den SICHTBAREN Zustand: Titel und Text. Ein Fehler
/// dort faellt nicht als Absturz auf, sondern als falsche Aussage an
/// der falschen Stelle.
class _TestNotifier extends GuardianNotifier {
  _TestNotifier(super.ref, this._status);

  final GuardianStatus _status;

  @override
  Future<void> load() async {
    state = _status;
  }
}

GuardianStatus _status({
  required String status,
  int? age,
  String? emailDeletedAt,
}) {
  return GuardianStatus.fromJson({
    'status': status,
    'age': age,
    'supervised': false,
    'emailDeletedAt': emailDeletedAt,
  });
}

Future<void> _pump(WidgetTester tester, GuardianStatus status) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        guardianProvider.overrideWith((ref) => _TestNotifier(ref, status)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: GuardianSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('GuardianSection: die Freigabe ist beendet', () {
    testWidgets('zeigt den Titel "Die Freigabe ist beendet"', (tester) async {
      await _pump(tester, _status(status: 'revoked', age: 17));

      expect(find.text('Die Freigabe ist beendet'), findsOneWidget);
      // Der alte Text ("keine Freigabe") darf hier NICHT stehen.
      expect(find.text('Keine Freigabe'), findsNothing);
    });

    testWidgets('sagt, dass die E-Mail des Elternteils geloescht wurde',
        (tester) async {
      await _pump(
        tester,
        _status(
          status: 'revoked',
          age: 17,
          emailDeletedAt: '2026-11-04T21:30:00Z',
        ),
      );

      expect(
        find.textContaining('E-Mail-Adresse des Elternteils wurde dabei'),
        findsOneWidget,
      );
      expect(find.textContaining('gelöscht'), findsOneWidget);
    });

    testWidgets('ein abgelaufener Status (expired) ist auch "beendet"',
        (tester) async {
      await _pump(tester, _status(status: 'expired', age: 18));

      expect(find.text('Die Freigabe ist beendet'), findsOneWidget);
    });

    testWidgets('ohne Loeschvermerk steht der vorsichtige Text',
        (tester) async {
      // Der Server weiss noch nicht, dass geloescht wurde (z. B. bei
      // einem alten Datensatz). Dann darf die App NICHT behaupten, es
      // sei geloescht worden.
      await _pump(tester, _status(status: 'revoked', age: 17));

      expect(
        find.textContaining('wird mit dem Ende der Freigabe gelöscht'),
        findsOneWidget,
      );
      expect(
        find.textContaining('E-Mail-Adresse des Elternteils wurde dabei'),
        findsNothing,
      );
    });

    testWidgets('ohne Freigabe ueberhaupt bleibt der alte Text',
        (tester) async {
      await _pump(tester, _status(status: 'none', age: 17));

      expect(find.text('Die Freigabe ist beendet'), findsNothing);
      expect(find.text('Keine Elternfreigabe'), findsOneWidget);
    });
  });

  group('GuardianStatus: der Zustand "beendet"', () {
    test('revoked und expired sind beendet, pending und active nicht', () {
      expect(_status(status: 'revoked').isEnded, isTrue);
      expect(_status(status: 'expired').isEnded, isTrue);
      expect(_status(status: 'pending').isEnded, isFalse);
      expect(_status(status: 'active').isEnded, isFalse);
      expect(_status(status: 'none').isEnded, isFalse);
    });

    test('emailDeletedAt kommt vom Server', () {
      final s = _status(
        status: 'revoked',
        emailDeletedAt: '2026-11-04T21:30:00Z',
      );
      expect(s.isGuardianEmailDeleted, isTrue);
      expect(s.emailDeletedAt, isNotNull);
    });

    test('ohne Loeschvermerk ist nichts geloescht', () {
      final s = _status(status: 'revoked');
      expect(s.isGuardianEmailDeleted, isFalse);
      expect(s.emailDeletedAt, isNull);
    });
  });
}
