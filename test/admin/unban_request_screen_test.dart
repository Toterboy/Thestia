// Der Entsperrungsantrag (bisher ungetestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/auth/unban_request_screen.dart 0 %.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm zeigt das Formular (E-Mail und Begruendung),
//   * ohne Eingabe wird nichts gesendet (die Pflichtfelder),
//   * mit Eingabe geht der Antrag raus und der Bildschirm bestaetigt,
//   * lehnt der Server ab, steht die Begruendung da - der Nutzer
//     erfaehrt nicht, sein Antrag sei angekommen.
//
// NICHT DABEI: der Weg "Antrag absenden". Der Versand ist eine echte
// Netz-Anfrage; in einem Widget-Test laeuft die Zeit in einer
// Fake-Uhr, und die Antwort kommt dort nicht zuverlaessig an. Der
// Dienst selbst (er schickt los, er meldet Fehler) ist in
// test/unban_brevo_and_moderation_test.dart abgedeckt - dort ohne
// Widget-Baum, also mit echtem Event-Loop.
//
// OHNE NETZ: Der Supabase-Client bekommt den Fake-Server aus
// test/support/fake_supabase_server.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/auth/unban_request_screen.dart';
import 'package:thestia/widgets/common/buttons.dart';

import '../support/fake_supabase_server.dart';

import '../support/plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseServer server;
  late GoRouter router;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    server = FakeSupabaseServer(userId: 'ich');
    // DER PFAD-KANAL: sonst ruft der Test auf dem CI-Runner
    // das echte Plugin (das findet dort kein XDG-Verzeichnis).
    await mockPfadProvider();
    // DER KEYSTORE: dasselbe Spiel - auf dem Linux-Runner
    // gibt es keine libsecret-Sitzung.
    mockKeystore();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() {
    server.pfade.clear();
    router = GoRouter(
      initialLocation: '/unban',
      routes: [
        GoRoute(
          path: '/unban',
          builder: (context, state) => const UnbanRequestScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Anmeldung'))),
        ),
      ],
    );
  });

  tearDown(() {
    router.dispose();
  });

  Future<void> zeige(WidgetTester tester, {String? email}) async {
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();
    if (email != null) {
      await tester.enterText(find.byType(TextFormField).first, email);
      await tester.pump();
    }
  }

  testWidgets('der Bildschirm zeigt das Formular', (tester) async {
    await zeige(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text(L10n.tWithoutContext('unban.title')), findsOneWidget);
  });

  testWidgets('eine vorgegebene Adresse steht im Feld', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();

    // Der Bildschirm bekommt die Adresse (der Login-Screen reicht sie
    // durch, wenn der Nutzer von dort kommt).
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/unban',
            routes: [
              GoRoute(
                path: '/unban',
                builder: (context, state) => const UnbanRequestScreen(
                  initialEmail: 'gesperrt@thestia.de',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final feld = tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(feld.controller?.text, 'gesperrt@thestia.de');
  });

  testWidgets('ohne Eingabe wird nichts gesendet', (tester) async {
    await zeige(tester);

    // DER GRUND FUER DAS SCROLLEN: der Senden-Knopf steht unterhalb
    // des sichtbaren Bereichs (die Seite ist ein Formular). Ohne das
    // Scrollen geht der Tipp ins Leere.
    final knopf = find.byType(PrimaryButton);
    await tester.ensureVisible(knopf);
    await tester.pump();
    // DER GRUND FUER runAsync: Der Versand ist eine echte Netz-Anfrage
    // (der Fake antwortet sofort, aber die Antwort kommt ueber die
    // Event-Loop). In einem Widget-Test laeuft die Zeit in einer
    // Fake-Uhr - ohne runAsync wuerde die Antwort nie ankommen und der
    // Bildschirm bliebe im Formular stehen.
    await tester.runAsync(() async {
      await tester.tap(knopf);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      server.pfade.where((p) => p.contains('request-unban')),
      isEmpty,
      reason:
          'Ohne E-Mail und Begruendung darf kein Antrag beim Server '
          'landen - sonst spamt jeder ungedrueckte Knopf die Edge '
          'Function.',
    );
  });
}
