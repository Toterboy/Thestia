// Die Nachricht überdenken (NUTZERWUNSCH 26.11.2026) - der Bildschirm.
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne Einstellung geht die Nachricht sofort raus (kein Dialog),
//   * bei "immer" fragt die App nach der Deutung - und die Nachricht
//     geht NICHT raus, solange der Nutzer nicht bestätigt hat,
//   * nach der Deutung geht sie raus,
//   * bei "ab Zeichen" fragt die App erst ab der Schwelle,
//   * die Ausnahme für den Kontakt schlägt den globalen Wert,
//   * das Drei-Punkte-Menü führt zu den Einstellungen,
//   * der Extra-Knopf prüft die Nachricht von Hand.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:thestia/models/verification/report_models.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/widgets/chat/nachricht_ueberdenken.dart';
import 'package:thestia/widgets/chat/secure_composer.dart';
import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

import 'hilfen.dart';

/// Tippt einen Text in das Eingabefeld (über die eigene Tastatur).
Future<void> tippeText(WidgetTester tester, String text) async {
  await tester.tap(find.byType(TextField));
  await tester.pumpAndSettle();
  for (final zeichen in text.split('')) {
    await tester.tap(find.text(zeichen).first);
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    Hive.registerAdapter(UserReportAdapter());
    mockAufnahme();
    mockZeitzone();
    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    moodClient = supabase.SupabaseClient(
      'https://example.supabase.co',
      'test-key',
    );
    mockAufnahme();
    mockAudioPlayer();
  });
  tearDown(() async {
    await moodClient.dispose();
  });

  group('Die Nachricht überdenken', () {
    testWidgets('ohne Einstellung geht die Nachricht sofort raus', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await tippeText(tester, 'hi');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // Kein Dialog - die Nachricht ist raus.
      expect(find.byType(NachrichtPruefDialog), findsNothing);
      expect(
        chat.notifier.messagesFor(chat.match.id).any((m) => m.text == 'hi'),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('bei "immer" fragt die App und sendet noch nicht', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        settings: <String, dynamic>{'nachrichtPruefModus': 'immer'},
      );

      await tippeText(tester, 'hi');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Der Dialog steht da - und die Nachricht ist NOCH NICHT raus.
      expect(find.byType(NachrichtPruefDialog), findsOneWidget);
      // Die Nachricht steht im Dialog (im Eingabefeld steht sie auch).
      expect(
        find.descendant(
          of: find.byType(NachrichtPruefDialog),
          matching: find.text('hi'),
        ),
        findsOneWidget,
      );
      expect(
        chat.notifier.messagesFor(chat.match.id).any((m) => m.text == 'hi'),
        isFalse,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('nach der Deutung geht die Nachricht raus', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        settings: <String, dynamic>{'nachrichtPruefModus': 'immer'},
      );

      await tippeText(tester, 'hi');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Ohne Deutung ist der Senden-Knopf im Dialog tot.
      final knopf = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'So senden'),
      );
      expect(knopf.onPressed, isNull);

      // Die Deutung eintippen - dann wird der Knopf aktiv.
      await tester.enterText(
        find.descendant(
          of: find.byType(NachrichtPruefDialog),
          matching: find.byType(TextField),
        ),
        'Ich will dich freundlich grüßen',
      );
      await tester.pump();

      await tester.tap(find.text('So senden'));
      await tester.pumpAndSettle();

      expect(find.byType(NachrichtPruefDialog), findsNothing);
      expect(
        chat.notifier.messagesFor(chat.match.id).any((m) => m.text == 'hi'),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('bei "ab Zeichen" fragt die App erst ab der Schwelle', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        settings: <String, dynamic>{
          'nachrichtPruefModus': 'abZeichen',
          'nachrichtPruefSchwelle': 5,
        },
      );

      // "hi" ist kürzer als die Schwelle - die Nachricht geht raus.
      await tippeText(tester, 'hi');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(find.byType(NachrichtPruefDialog), findsNothing);

      // "hallo" hat fünf Zeichen - jetzt wird gefragt.
      await tippeText(tester, 'hallo');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(find.byType(NachrichtPruefDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('die Ausnahme für den Kontakt schlägt den globalen Wert', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        settings: <String, dynamic>{
          'nachrichtPruefModus': 'immer',
          'nachrichtPruefAusnahmen': <String, String>{'partner-1': 'aus'},
        },
      );

      await tippeText(tester, 'hi');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Der Partner hat die Ausnahme "aus" - es wird nicht gefragt.
      expect(find.byType(NachrichtPruefDialog), findsNothing);
      expect(
        chat.notifier.messagesFor(chat.match.id).any((m) => m.text == 'hi'),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('das Drei-Punkte-Menü führt zu den Einstellungen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // Der Eintrag steht im Menü.
      expect(find.text('Nachricht überdenken'), findsWidgets);

      await tester.tap(find.text('Nachricht überdenken').last);
      await tester.pumpAndSettle();

      // Der Bogen ist offen: die Geltung und der Modus stehen da.
      expect(find.text('Für alle Kontakte'), findsOneWidget);
      expect(find.text('Nur für Mira'), findsOneWidget);
      expect(find.text('Bei jeder Nachricht'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('der Extra-Knopf prüft die Nachricht von Hand', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        settings: <String, dynamic>{'nachrichtPruefModus': 'manuell'},
      );

      // Der Extra-Knopf steht da (im Modus "manuell").
      expect(find.byIcon(Icons.psychology_alt_outlined), findsOneWidget);

      await tippeText(tester, 'hi');
      await tester.tap(find.byIcon(Icons.psychology_alt_outlined));
      await tester.pumpAndSettle();

      // Der Dialog fragt - und die Nachricht ist noch nicht raus.
      expect(find.byType(NachrichtPruefDialog), findsOneWidget);
      expect(
        chat.notifier.messagesFor(chat.match.id).any((m) => m.text == 'hi'),
        isFalse,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ohne Einstellung steht der Extra-Knopf nicht da', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      expect(find.byIcon(Icons.psychology_alt_outlined), findsNothing);
      // Die Eingabeleiste ist trotzdem da.
      expect(find.byType(SecureComposer), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
