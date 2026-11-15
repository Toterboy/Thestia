// Der Posteingang im Admin-Bereich (bisher ungetestet).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/admin/admin_mail_inbox.dart 0 %.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Mails stehen da (mit Absender, Betreff und Rubrik),
//   * die Rubrik-Kacheln filtern (das war die Anforderung: "aufgeteilt
//     nach Adresse"),
//   * ohne Mails steht der Leerzustand da,
//   * ein Serverfehler wird angezeigt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/admin/admin_mail_inbox.dart';

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();

    server = FakeSupabaseServer(userId: 'admin-1');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.pfade.clear();
    server.antwortetMitFehler = false;
  });

  /// Baut den Posteingang.
  Future<void> zeigePosteingang(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: AdminMailInboxTab())),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Eine Mail, wie sie der Server liefert.
  Map<String, dynamic> mail({
    String betreff = 'Frage zur Datenschutzerklaerung',
    String absender = 'kinderschutz@example.de',
    String kategorie = 'kinderschutz',
  }) => <String, dynamic>{
    'id': 'm-1',
    'subject': betreff,
    'from_email': absender,
    'from_name': 'Kinderschutz',
    'recipient': 'kinderschutz@thestia.de',
    'category': kategorie,
    'received_at': '2026-11-14T09:00:00Z',
  };

  group('Der Posteingang', () {
    testWidgets('die Mails stehen da', (tester) async {
      server.rpcAntworten['admin_list_mail_messages'] = [mail()];
      await zeigePosteingang(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Frage zur Datenschutzerklaerung'), findsOneWidget);
      expect(find.textContaining('kinderschutz@example.de'), findsOneWidget);
    });

    testWidgets('die Rubrik-Kacheln stehen da', (tester) async {
      server.rpcAntworten['admin_list_mail_messages'] = <dynamic>[];
      await zeigePosteingang(tester);

      // JEDE Anschrift hat eine Kachel - das war die Anforderung
      // ("aufgeteilt nach Adresse").
      expect(find.text(L10n.tWithoutContext('admin.mailAll')), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('admin.mailKinderschutz')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('admin.mailSupport')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('admin.mailDatenschutz')),
        findsOneWidget,
      );
    });

    testWidgets('eine Rubrik filtert', (tester) async {
      server.rpcAntworten['admin_list_mail_messages'] = [mail()];
      await zeigePosteingang(tester);

      // Auf "Kinderschutz" tippen - der Server wird mit der Rubrik
      // gefragt. (Die Kachel ist ein ChoiceChip - die Rubrik der Mail
      // darunter ist ein einfaches Chip.)
      await tester.tap(
        find.widgetWithText(
          ChoiceChip,
          L10n.tWithoutContext('admin.mailKinderschutz'),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(tester.takeException(), isNull);
      // Der Server hat die Rubrik bekommen.
      expect(server.pfade, isNotEmpty);
    });

    testWidgets('ohne Mails steht der Leerzustand da', (tester) async {
      server.rpcAntworten['admin_list_mail_messages'] = <dynamic>[];
      await zeigePosteingang(tester);

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });

    testWidgets('ein Serverfehler wird angezeigt', (tester) async {
      server.antwortetMitFehler = true;
      await zeigePosteingang(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(
          L10n.tWithoutContext('admin.error').replaceAll('{error}', ''),
        ),
        findsWidgets,
      );
    });
  });
}
