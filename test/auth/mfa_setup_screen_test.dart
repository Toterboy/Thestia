// Die 2FA-Einrichtung (TOTP) - bisher voellig ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/auth/mfa_setup_screen.dart 205 offene Zeilen bei 206 Zeilen
// gesamt - der Bildschirm, auf dem die Person die zweite factors
// einrichtet, war komplett ungetestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (der Intro-Schritt steht da),
//   * ist 2FA schon aktiv, steht die aktive Ansicht statt des Flows,
//   * die Einrichtung zeigt den Schluessel (der manuelle Weg, wenn der
//     QR-Scan nicht klappt),
//   * der Schluessel laesst sich kopieren,
//   * ohne Code geht es nicht weiter (die Eingabe wird geprueft),
//   * ein falscher Code wird abgewiesen - der Nutzer erfaehrt es.
//
// DER MFA-DIENST: Die echte Anmeldung braucht die Supabase-MFA-API.
// Im Test spricht ein Ersatz dafuer - der echte Weg waere der ganze
// Auth-Stack.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/auth/mfa_setup_screen.dart';
import 'package:thestia/services/auth/mfa_service.dart';

/// Der MFA-Dienst als Ersatz (ohne echten Auth-Server).
class _FakeMfaService extends MfaService {
  _FakeMfaService(super.client);

  /// Der Status (ist 2FA schon aktiv?).
  MfaStatus status = const MfaStatus.initial();

  /// Der Fehler beim Starten der Einrichtung.
  Object? enrollFehler;

  /// Der Fehler beim Bestaetigen des Codes.
  Object? verifyFehler;

  /// Der Code, der bestaetigt wurde.
  String? bestaetigterCode;

  /// Wurde die Einrichtung verworfen (der Screen wurde verlassen)?
  bool verworfen = false;

  @override
  Future<MfaStatus> loadStatus() async => status;

  @override
  Future<({String factorId, String qrUri, String secret})> startTotpEnroll({
    String friendlyName = 'Thestia',
  }) async {
    final fehler = enrollFehler;
    if (fehler != null) throw fehler;
    return (
      factorId: 'factor-1',
      qrUri: 'otpauth://totp/Thestia?secret=ABCDEFGHIJKLMNOP',
      secret: 'ABCDEFGHIJKLMNOP',
    );
  }

  @override
  Future<void> verifyTotpEnroll({
    required String factorId,
    required String code,
  }) async {
    bestaetigterCode = code;
    final fehler = verifyFehler;
    if (fehler != null) throw fehler;
  }

  @override
  Future<void> cancelEnroll(String factorId) async {
    verworfen = true;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER SPEICHER: Der Auth-Client des Supabase-Clients legt seinen
    // Token dort ab - ohne den Ersatz sucht der Test auf dem CI-Runner
    // das echte Plugin.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // DER CLIENT: Der MFA-Dienst braucht einen Client (der echte Dienst
    // spricht damit). Ohne Initialisierung wirft `Supabase.instance`
    // eine Assertion.
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });

  /// Baut den Screen mit dem Ersatz-Dienst.
  ///
  /// [status] wird VOR dem Aufbau gesetzt: der Screen fragt den Status
  /// schon in seinem initState.
  Future<_FakeMfaService> zeigeScreen(
    WidgetTester tester, {
    MfaStatus status = const MfaStatus.initial(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dienst = _FakeMfaService(supabase.Supabase.instance.client)
      ..status = status;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mfaServiceProvider.overrideWithValue(dienst)],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const MfaSetupScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return dienst;
  }

  group('Die 2FA-Einrichtung', () {
    testWidgets('der Bildschirm baut sich', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Der Intro-Schritt steht da: was 2FA ist und wie man es einrichtet.
      expect(find.text(L10n.tWithoutContext('mfa.introTitle')), findsOneWidget);
      // Der Einstieg (scannen) und der Weg "spaeter".
      expect(find.text(L10n.tWithoutContext('mfa.setupScan')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('mfa.setupLater')), findsOneWidget);
    });

    testWidgets('mit aktivem 2FA steht die aktive Ansicht', (tester) async {
      await zeigeScreen(
        tester,
        status: const MfaStatus(
          currentAal: 'aal2',
          hasVerifiedFactors: true,
          hasAnyFactor: true,
          loaded: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Nutzer sieht, dass 2FA schon laeuft (Befund: "steht nicht,
      // dass ich es eingerichtet habe").
      expect(
        find.text(L10n.tWithoutContext('mfa.activeTitle')),
        findsOneWidget,
      );
      // Und der Einrichtungs-Flow ist nicht zu sehen.
      expect(find.text(L10n.tWithoutContext('mfa.setupScan')), findsNothing);
    });

    testWidgets('die Einrichtung zeigt den Schluessel', (tester) async {
      await zeigeScreen(tester);

      // Die Einrichtung starten (der QR-Scan-Weg).
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('mfa.setupScan'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Schluessel steht da - damit kann der Nutzer die App auch
      // ohne Kamera einrichten.
      expect(find.text('ABCDEFGHIJKLMNOP'), findsWidgets);
    });

    testWidgets('der Schluessel laesst sich kopieren', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('mfa.setupScan'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Der Schluessel steht da - ein Tippen darauf kopiert ihn (der
      // Absender-Apps koennen ihn nicht abtippen).
      final schluessel = find.text('ABCDEFGHIJKLMNOP');
      expect(schluessel, findsWidgets);
      await tester.tap(schluessel.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Und die App sagt, dass der Schluessel kopiert wurde.
      expect(find.text(L10n.tWithoutContext('mfa.copied')), findsOneWidget);

      // Der Bildschirm wird abgebaut - der Timer, der das Secret nach
      // 30 Sekunden aus der Zwischenablage loescht, muss beendet werden.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('ohne Code geht es nicht weiter', (tester) async {
      final dienst = await zeigeScreen(tester);

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('mfa.setupScan'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Weiter zum Bestaetigungsschritt.
      final weiter = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('mfa.setupNext'),
      );
      await tester.ensureVisible(weiter);
      await tester.pump();
      await tester.tap(weiter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Bestaetigungsschritt steht da.
      expect(
        find.text(L10n.tWithoutContext('mfa.confirmStep')),
        findsOneWidget,
      );

      // Ohne Code wird nicht bestaetigt.
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('common.confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(dienst.bestaetigterCode, isNull);
    });

    testWidgets('ein falscher Code wird abgewiesen', (tester) async {
      final dienst = await zeigeScreen(tester);
      // Der Server lehnt den Code ab.
      dienst.verifyFehler = StateError('Falscher Code');

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('mfa.setupScan'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final weiter = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('mfa.setupNext'),
      );
      await tester.ensureVisible(weiter);
      await tester.pump();
      await tester.tap(weiter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Den Code eintippen und bestaetigen.
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('common.confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Code ist angekommen - aber nicht angenommen.
      expect(dienst.bestaetigterCode, '123456');
      // Der Nutzer sieht, dass es nicht geklappt hat.
      expect(find.textContaining('Code'), findsWidgets);
    });
  });
}
