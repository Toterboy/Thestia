// Das Blockieren eines Nutzers im Chat.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/chat/parts/chatdialoge.dart 88 offene Zeilen - darunter
// der ganze Weg, einen Nutzer zu blockieren.
//
// DER GRUND: Das Blockieren ist der Bot-/Spam-Schutz der App.
// Serverseitig werden die Likes in beide Richtungen und der Match
// geloescht, und kuenftige Interaktionen werden verhindert. Das ist
// ein Eingriff, der nicht rueckgaengig zu machen ist - der Nutzer muss
// also BESTAETIGEN, bevor es passiert. Und er muss erfahren, wenn es
// nicht geklappt hat (sonst glaubt er, der Nutzer sei blockiert, und
// schreibt weiter - oder umgekehrt).
//
// WAS HIER GEPRUEFT WIRD:
//   * das Menue bietet das Blockieren an,
//   * der Dialog fragt nach (mit dem Namen des Nutzers),
//   * "Abbrechen" blockiert niemanden,
//   * das Bestaetigen blockiert den Nutzer (der Server wird gefragt).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import 'hilfen.dart';

void main() {
  // DER STIMMUNGS-DIENST: Der Chat zeigt die Stimmungskarte - ohne den
  // Client schlaegt der Aufbau fehl.
  moodClient = supabase.SupabaseClient(
    'https://example.supabase.co',
    'test-key',
  );
  tearDownAll(() async {
    await moodClient.dispose();
  });

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    mockAufnahme();
    mockAudioPlayer();
    mockZeitzone();
    server = FakeSupabaseServer(userId: 'ich');
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
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
    server.pfade.clear();
  });

  /// Oeffnet das Chat-Menue.
  Future<void> oeffneMenue(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Tippt den Eintrag "Blockieren" im Menue an.
  Future<void> tippeBlockieren(WidgetTester tester) async {
    final eintrag = find.text(L10n.tWithoutContext('chat.block'));
    await tester.ensureVisible(eintrag);
    await tester.pump();
    await tester.tap(eintrag);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Das Blockieren eines Nutzers', () {
    testWidgets('das Menue bietet das Blockieren an', (tester) async {
      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await oeffneMenue(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('chat.block')),
        findsOneWidget,
        reason:
            'Der Nutzer muss einen Nutzer blockieren koennen - das ist der '
            'Bot-Schutz der App.',
      );
    });

    testWidgets('der Dialog fragt nach und nennt den Nutzer', (tester) async {
      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await oeffneMenue(tester);
      await tippeBlockieren(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('chat.blockTitle')),
        findsOneWidget,
        reason: 'Der Dialog muss sagen, was passiert.',
      );
      expect(
        find.textContaining(chatDetailScreenPartner().name),
        findsWidgets,
        reason:
            'Der Dialog muss den Namen des Nutzers nennen - es geht um '
            'eine Person, nicht um eine Funktion.',
      );
      // Und beide Wege stehen da.
      expect(find.text(L10n.tWithoutContext('common.cancel')), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('chat.blockAction')),
        findsOneWidget,
      );
    });

    testWidgets('Abbrechen blockiert niemanden', (tester) async {
      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await oeffneMenue(tester);
      await tippeBlockieren(tester);

      await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        server.pfade.any((p) => p.contains('block')),
        isFalse,
        reason:
            'Nach dem Abbruch darf niemand blockiert werden - das Loeschen '
            'des Matches laesst sich nicht rueckgaengig machen.',
      );
    });

    testWidgets('das Bestaetigen blockiert den Nutzer', (tester) async {
      // DER PARTNER MIT UUID: Die Peer-IDs werden geprueft (Audit M1/M2).
      // Mit "partner-1" wuerde der Server die Blockierung ablehnen - der
      // Test wuerde dann den falschen Weg pruefen.
      final chat = chatMitNachricht(partnerMitUuid: true);
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await oeffneMenue(tester);
      await tippeBlockieren(tester);

      await tester.tap(find.text(L10n.tWithoutContext('chat.blockAction')));
      await tester.pump();
      // Der Server wird gefragt (echte Schleife).
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(
        server.pfade.any((p) => p.contains('block')),
        isTrue,
        reason:
            'Das Blockieren muss beim Server landen - sonst waere der '
            'Nutzer nicht wirklich blockiert (er koennte weiter schreiben).',
      );
    });
  });
}
