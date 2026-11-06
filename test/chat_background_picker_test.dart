import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/widgets/chat_background_picker.dart';

/// Test fuer den Chat-Hintergrund-Picker.
///
/// WARUM (06.11.2026): Der Picker stand in einem AlertDialog mit
/// `scrollable: true` und benutzte ein `GridView` mit `shrinkWrap: true`.
/// Flutter wirft dann "RenderShrinkWrappingViewport does not support
/// returning intrinsic dimensions" - live im Emulator gesehen: der
/// Dialog blieb leer und der Chat-Bildschirm war unbrauchbar.
///
/// DER TEST: Der Picker muss sich in einem scrollbaren AlertDialog
/// bauen lassen, ohne dass Flutter eine Ausnahme wirft.
class _FakeLocalStorage implements LocalStorage {
  final map = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async => map[key] = value;

  @override
  Future<String?> getString(String key) async => map[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      map[key] = value ? 'true' : 'false';

  @override
  Future<bool?> getBool(String key) async => map[key] == 'true';

  @override
  Future<void> saveInt(String key, int value) async => map[key] = '$value';

  @override
  Future<int?> getInt(String key) async =>
      map[key] == null ? null : int.tryParse(map[key]!);

  @override
  Future<void> remove(String key) async => map.remove(key);
}

void main() {
  Widget hause() => ProviderScope(
    overrides: [localStorageProvider.overrideWithValue(_FakeLocalStorage())],
    child: const MaterialApp(home: Scaffold(body: ChatBackgroundPicker())),
  );

  testWidgets('der Picker baut sich in einem scrollbaren Dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(_FakeLocalStorage()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (ctx) => const AlertDialog(
                        // Genau die Konstellation, die im Emulator
                        // abstuerzte: scrollbarer Dialog.
                        scrollable: true,
                        title: Text('Hintergrund'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Waehle ein Muster.'),
                            SizedBox(height: 16),
                            // Mit fester Breite: sonst fragt der
                            // AlertDialog die intrinsische Breite der
                            // Liste ab - und die kann Flutter nicht.
                            ChatBackgroundPicker(festeBreite: 260),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Text('oeffnen'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('oeffnen'));
    await tester.pumpAndSettle();

    // Keine Ausnahme und der Dialog ist da.
    expect(tester.takeException(), isNull);
    expect(find.byType(ChatBackgroundPicker), findsOneWidget);
  });

  testWidgets('der Picker hat eine begrenzte Hoehe (kein shrink-wrap)', (
    tester,
  ) async {
    await tester.pumpWidget(hause());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final groesse = tester.getSize(find.byType(ChatBackgroundPicker));
    expect(
      groesse.height,
      lessThanOrEqualTo(300),
      reason:
          'der Picker waechst unbegrenzt - in einem scrollbaren Dialog '
          'genau das, was Flutter nicht mag',
    );
  });
}
