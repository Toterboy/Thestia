import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/guardian_status.dart';
import 'package:thestia/providers/guardian_provider.dart';
import 'package:thestia/services/encryption_service.dart';
import 'package:thestia/services/guardian_service.dart';
import 'package:thestia/widgets/guardian_section.dart';

/// Tests fuer den Elternbereich (BEFUND 06.11.2026).
///
/// BEFUND (Betreiber): "Der Elternbereich laedt ewig lang." Ursache:
/// Der Abruf schlug fehl (keine Sitzung, Netz, Server) - und der
/// Bildschirm zeigte fuer JEDEN Fehler einen endlosen Ladekreis. Der
/// Nutzer hatte keinen Weg aus dem Bereich heraus.
///
/// DIESE TESTS halten fest:
///   1) Ein Fehler ist von "laedt noch" unterscheidbar.
///   2) Der Bildschirm bietet einen Ausweg (erneut versuchen).
///   3) Der Provider versucht es selbst noch einmal.
class _FehlgeschlagenerService extends GuardianService {
  _FehlgeschlagenerService() : super(_NichtGenutzt());

  int aufrufe = 0;

  @override
  Future<GuardianStatus> fetchStatus() async {
    aufrufe++;
    throw const GuardianServiceException('network');
  }
}

/// Ein Client, den der Test nie benutzt (der Dienst wird ja ersetzt).
///
/// WICHTIG: `autoRefreshToken: false` - sonst startet der Client einen
/// Auto-Refresh-Timer, und der Widget-Test meldet am Ende "A Timer is
/// still pending even after the widget tree was disposed".
class _NichtGenutzt extends SupabaseClient {
  _NichtGenutzt()
    : super(
        'https://nicht.verwendet',
        'nicht-verwendet',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
}

/// Die Verschluesselung ohne Keystore.
///
/// Der Elternbereich hoert auf den Auth-Provider - und der Auth-Provider
/// braucht die Verschluesselung. Im Test gibt es keinen Keystore
/// (MissingPluginException), deshalb wird sie hier ersetzt.
class _OhneKeystore extends EncryptionService {
  @override
  Future<void> get initialized => Future<void>.value();
}

/// Die Provider-Overrides fuer alle Tests in dieser Datei.
List<Override> _overrides(_FehlgeschlagenerService service) => [
  guardianServiceProvider.overrideWithValue(service),
  encryptionServiceProvider.overrideWithValue(_OhneKeystore()),
];

void main() {
  group('Der Zustand', () {
    test('ein Fehler ist von "unbekannt" unterscheidbar', () {
      const fehler = GuardianStatus(loadError: 'network');
      expect(fehler.isError, isTrue);
      expect(
        fehler.isUnknown,
        isTrue,
        reason:
            'der Stand ist weiterhin unbekannt - ein Fehler heisst nicht '
            '"es gibt keine Aufsicht"',
      );

      const unbekannt = GuardianStatus.unknown;
      expect(unbekannt.isError, isFalse);
      expect(unbekannt.isUnknown, isTrue);
    });

    test('ein geladener Stand ist kein Fehler', () {
      final geladen = GuardianStatus.fromJson(const {'status': 'none'});
      expect(geladen.isError, isFalse);
      expect(geladen.isUnknown, isFalse);
    });
  });

  group('Der Provider', () {
    test('ein gescheiterter Abruf endet in einem Fehlerzustand', () async {
      final service = _FehlgeschlagenerService();
      final container = ProviderContainer(overrides: _overrides(service));
      addTearDown(container.dispose);

      await container.read(guardianProvider.notifier).load();

      final status = container.read(guardianProvider);
      expect(status.isError, isTrue);
      expect(status.loadError, 'network');
    });
  });

  group('Der Bildschirm', () {
    testWidgets('bei einem Fehler gibt es einen Ausweg', (tester) async {
      final service = _FehlgeschlagenerService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(service),
          child: const MaterialApp(home: Scaffold(body: GuardianSection())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Kein endloser Ladekreis: der Fehler steht da, und der Knopf
      // "Erneut versuchen" auch.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'der Bereich zeigte einen endlosen Ladekreis - der Nutzer '
            'kam nicht heraus',
      );
      expect(
        find.text(L10n.tWithoutContext('guardian.loadErrorTitle')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('guardian.retry')),
        findsOneWidget,
        reason: 'es muss einen Weg aus dem Fehler geben',
      );
    });

    testWidgets('der Knopf startet einen neuen Versuch', (tester) async {
      final service = _FehlgeschlagenerService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(service),
          child: const MaterialApp(home: Scaffold(body: GuardianSection())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final vorher = service.aufrufe;
      await tester.tap(find.text(L10n.tWithoutContext('guardian.retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        service.aufrufe,
        greaterThan(vorher),
        reason: 'der Knopf muss den Abruf wiederholen',
      );
    });
  });
}
