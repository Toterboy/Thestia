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
    final view = tester.view;
    final bildschirm = view.physicalSize.height / view.devicePixelRatio;
    final groesse = tester.getSize(find.byType(ChatBackgroundPicker));
    expect(
      groesse.height,
      lessThanOrEqualTo(bildschirm * 0.6 + 1),
      reason:
          'der Picker waechst unbegrenzt - in einem scrollbaren Dialog '
          'genau das, was Flutter nicht mag',
    );
  });

  testWidgets('alle Muster sind ohne Scrollen sichtbar', (tester) async {
    // BEFUND (07.11.2026, Betreiber): "Das mit Chat Hintergrund, dass
    // man da scrollen muss ist nur so mittel gut bei den Einstellungen."
    //
    // Vorher stand im Picker ein festes SizedBox(height: 280). Bei
    // sieben Mustern (ohne + fuenf Vorgaenge + eigenes) sind das drei
    // Reihen - und 280 Pixel zeigten nur zwei. Man musste also
    // scrollen, um den letzten Hintergrund zu sehen.
    //
    // Der Test prueft: der Picker ist mindestens so hoch wie sein Raster.
    // Ein Grid, das hoeher ist als sein Platz, wuerde abgeschnitten
    // (oder scrollen) - und genau das war der Befund.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(hause());
    await tester.pumpAndSettle();

    // Kein Overflow, kein Absturz.
    expect(tester.takeException(), isNull);

    final raster = find.byType(GridView);
    expect(raster, findsOneWidget);

    final rasterHoehe = tester.getSize(raster).height;
    final picker = find.byType(ChatBackgroundPicker);
    final pickerHoehe = tester.getSize(picker).height;

    expect(
      pickerHoehe + 0.5,
      greaterThanOrEqualTo(rasterHoehe),
      reason:
          'der Picker ist kleiner als sein Raster - die letzten Muster '
          'wuerden abgeschnitten und man muesste scrollen '
          '($pickerHoehe < $rasterHoehe)',
    );

    // Und: der Picker hat kein eigenes Scrollen - das Raster waechst
    // mit, statt in einem Scrollbereich zu liegen.
    expect(
      find.byType(SingleChildScrollView),
      findsNothing,
      reason: 'der Picker scrollt selbst - dann muss der Dialog scrollen',
    );
  });
}
