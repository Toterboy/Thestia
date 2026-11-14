// Der Anruf-Bildschirm (bisher ungetestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/chat/call_screen.dart 435 offene Zeilen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * der Name der Person steht da,
//   * ohne Verbindung erscheint der Mobilfunk-Hinweis (der Nutzer soll
//     wissen, dass es am Netz liegt und nicht an ihm).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/chat/call_screen.dart';

import 'support/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
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

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: CallScreen(partnerName: 'Mira', peerId: 'partner-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('der Bildschirm baut sich ohne Absturz', (tester) async {
    await zeigeScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(CallScreen), findsOneWidget);
  });

  testWidgets('der Name der Person steht da', (tester) async {
    await zeigeScreen(tester);

    expect(find.text('Mira'), findsWidgets);
  });

  testWidgets('ohne Verbindung erscheint der Mobilfunk-Hinweis', (
    tester,
  ) async {
    await zeigeScreen(tester);

    // Im Test gibt es keine Gegenstelle - der Aufbau schlaegt fehl, und
    // die App sagt das (statt zu schweigen).
    expect(
      find.textContaining(L10n.tWithoutContext('chat.callNetHint')),
      findsWidgets,
      reason:
          'Ohne Gegenstelle muss der Nutzer erfahren, dass es am Netz '
          'liegt - nicht an ihm.',
    );
  });
}
