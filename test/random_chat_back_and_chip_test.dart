// Regressionstests fuer die zwei Fehler vom 13.11.2026.
//
// 1) DER ZUFALLSCHAT FRAGT BEIM ZURUECK-WISCHEN (Befund des Betreibers:
//    "Wenn man zurueck wischt bei Zufallschat, wird man nicht nochmal
//    gefragt, ob man ihn beenden moechte.")
//
// 2) EIN AUSGEWAEHLTES CHIP SPRINGT NICHT IN DIE NAECHSTE ZEILE
//    (Befund des Betreibers: "Wenn man Buttons auswaehlt, z. B. in den
//    Profileinstellungen, sollen sie sich nicht in die naechste Zeile
//    durch auswaehlen verschieben").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/screens/swipe/random_chat_screen.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/widgets/stable_chip.dart';

/// In-Memory-Implementierung von [LocalStorage] fuer Tests.
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> saveString(String key, String value) async => _data[key] = value;

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _data[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _data[key] == null ? null : _data[key] == 'true';

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _data[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _data[key] == null ? null : int.tryParse(_data[key]!);
}

/// Ein Chat-Zustand fuer den Test (der Screen braucht die Chatliste).
ChatNotifier _chatNotifier() {
  final service = ChatService();
  service.createMatch(
    UserProfile(
      id: 'partner',
      name: 'Mira',
      birthDate: DateTime.now().subtract(const Duration(days: 24 * 365)),
      bio: '',
    ),
  );
  return ChatNotifier(service);
}

/// Die Overrides fuer den Zufallschat-Screen.
List<Override> _overrides() => [
  localStorageProvider.overrideWithValue(_FakeLocalStorage()),
  chatProvider.overrideWith((ref) => _chatNotifier()),
];

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Der Zufallschat fragt beim Zurueck', () {
    testWidgets('das System-Zurueck (Wischen) fragt nach dem Beenden', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RandomChatScreen(),
                    ),
                  ),
                  child: const Text('oeffnen'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Den Zufallschat oeffnen (er muss auf einer Route liegen, die
      // sich zurueckpoppen laesst - die Startseite laesst das nicht).
      await tester.tap(find.text('oeffnen'));
      await tester.pumpAndSettle();

      // Das System-Zurueck - so ruft es der Randwisch (und der
      // Zurueck-Knopf des Systems) auf. `maybePop()` ist der Weg, der
      // den PopScope beachtet; ein direktes `pop()` wuerde daran
      // vorbeikommen (und wuerde genau den Befund wiederholen).
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pumpAndSettle();

      // Die Rueckfrage steht da.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Zufallschat beenden?'), findsOneWidget);
    });

    testWidgets('der Knopf oben links fragt genauso', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RandomChatScreen(),
                    ),
                  ),
                  child: const Text('oeffnen'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('oeffnen'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Zufallschat beenden?'), findsOneWidget);
    });
  });

  group('Ein ausgewaehltes Chip bleibt an seinem Platz', () {
    testWidgets('im Wrap springt es nicht in die naechste Zeile', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var ausgewaehlt = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final text in ['Alpha', 'Beta', 'Gamma', 'Delta'])
                    StableChip.filter(
                      label: Text(text),
                      selected: ausgewaehlt.contains(text),
                      onSelected: (_) => setState(() {
                        if (ausgewaehlt.contains(text)) {
                          ausgewaehlt.remove(text);
                        } else {
                          ausgewaehlt.add(text);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final vorher = tester.getTopLeft(find.text('Gamma'));

      await tester.tap(find.text('Gamma'));
      await tester.pumpAndSettle();

      final nachher = tester.getTopLeft(find.text('Gamma'));
      expect(
        nachher,
        vorher,
        reason:
            'Das ausgewaehlte Chip darf nicht springen - der Nutzer hat '
            'auf die Stelle getippt, an der es jetzt ist.',
      );
      // Und die Auswahl ist sichtbar (Zustand).
      expect(ausgewaehlt, contains('Gamma'));
    });

    testWidgets('der alte Chip-Typ waere gesprungen (Gegenprobe)', (
      tester,
    ) async {
      // Die Gegenprobe: mit dem normalen FilterChip springt das Chip,
      // weil Material das Haekchen einblendet und der Wrap neu packt.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var ausgewaehlt = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final text in ['Alpha', 'Beta', 'Gamma', 'Delta'])
                    FilterChip(
                      label: Text(text),
                      selected: ausgewaehlt && text == 'Gamma',
                      onSelected: (_) => setState(() => ausgewaehlt = true),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final vorher = tester.getTopLeft(find.text('Gamma'));
      await tester.tap(find.text('Gamma'));
      await tester.pumpAndSettle();
      final nachher = tester.getTopLeft(find.text('Gamma'));

      expect(
        nachher,
        isNot(vorher),
        reason:
            'Ohne StableChip springt das Chip (das Haekchen macht es '
            'breiter). Dieser Test haelt fest, warum es StableChip gibt.',
      );
    });
  });
}
