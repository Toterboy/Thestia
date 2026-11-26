// Die Anzeigen und Schalter im Chat.
//
// ANLASS (19.11.2026): `lib/screens/chat/parts/chatdetailaufbau.dart` war
// nur zu 63 % abgedeckt. Genau die Anzeigen, die dem Nutzer sagen
// "wie sicher ist dieser Chat" und "was kann ich abschalten", waren
// ungetestet.
//
// WAS HIER GEPRÜFT WIRD:
//   * die E2E-Anzeige steht da und zeigt "noch nicht verbunden",
//   * der Eisbrecher-Schalter im Menü schaltet die Einstellung um.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';

import 'hilfen.dart';

void main() {
  // DER STIMMUNGS-DIENST: Der Chat zeigt die Stimmungskarte - ohne den
  // Client schlägt der Aufbau fehl.
  moodClient = supabase.SupabaseClient(
    'https://example.supabase.co',
    'test-key',
  );
  tearDownAll(() async {
    await moodClient.dispose();
  });

  group('Die E2E-Anzeige in der Kopfzeile', () {
    testWidgets('sie steht da und zeigt "noch nicht verbunden"', (
      tester,
    ) async {
      // EINE ECHTE UNTERHALTUNG: Sonst zeigt der Bildschirm "Chat nicht
      // gefunden" - und die Kopfzeile gar nicht.
      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      expect(
        find.byIcon(Icons.lock_open),
        findsOneWidget,
        reason:
            'Ohne direkte Verbindung ist der Chat NICHT verschluesselt '
            'uebertragen - das Icon muss das zeigen.',
      );
      expect(find.text('E2E'), findsOneWidget);
    });
  });

  group('Das Chat-Menue', () {
    testWidgets('der Eisbrecher-Schalter schaltet die Einstellung um', (
      tester,
    ) async {
      final chat = chatMitNachricht();
      // Der Container, damit der Test den Stand der Einstellungen lesen
      // kann (der Bildschirm hat seinen eigenen).
      final container = ProviderContainer(
        overrides: chatDetailScreenOverrides(chat.notifier),
      );
      addTearDown(container.dispose);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: ChatDetailScreen(matchId: chat.match.id),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final vorher = container.read(settingsProvider).contextIcebreakerEnabled;

      // Das Menü öffnen.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Der Eintrag nennt die Wirkung (an oder aus).
      final eintrag = vorher
          ? L10n.tWithoutContext('chat.icebreakerOff')
          : L10n.tWithoutContext('chat.icebreakerOn');
      expect(
        find.text(eintrag),
        findsWidgets,
        reason:
            'Der Nutzer muss den Eisbrecher im Kontext abschalten koennen - '
            'der Eintrag gehoert ins Menue.',
      );

      await tester.tap(find.text(eintrag).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        container.read(settingsProvider).contextIcebreakerEnabled,
        !vorher,
        reason: 'Der Schalter muss die Einstellung umdrehen.',
      );
    });
  });
}
