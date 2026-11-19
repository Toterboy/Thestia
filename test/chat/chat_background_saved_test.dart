// Test: der gewaehlte Chat-Hintergrund wird gespeichert.
//
// BEFUND (07.11.2026, Betreiber): "Der Hintergrund, den man auswaehlt,
// wird nicht gespeichert."
//
// Der Test macht den kompletten Weg:
//   1. Der Picker wird getippt (ein Muster waehlen).
//   2. Der Zustand muss den Hintergrund tragen.
//   3. Er muss im Speicher (Keystore-Ersatz) stehen - sonst ist er
//      beim naechsten Start weg.
//
// SCHRITT 3 ist der wichtige: der Fehler im Feld war still - die
// Oberflaeche zeigte den neuen Hintergrund sofort an (optimistisch),
// aber das Schreiben schlug fehl und wurde nur protokolliert. Der
// Nutzer sah es erst beim naechsten Start.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/utils/chat_backgrounds.dart';
import 'package:thestia/widgets/chat_background_picker.dart';

/// Ein Speicher-Ersatz, der Fehler werfen kann - damit der stille
/// Fehlerfall nachstellbar wird.
class _FakeLocalStorage implements LocalStorage {
  _FakeLocalStorage({this.schlaegtFehl = false});

  final Map<String, String> map = <String, String>{};

  /// Wenn true: jeder Schreibvorgang scheitert (wie ein Keystore im
  /// Streit mit einem zweiten Zugriff).
  bool schlaegtFehl;

  @override
  Future<void> saveString(String key, String value) async {
    if (schlaegtFehl) {
      throw StateError('Keystore belegt');
    }
    map[key] = value;
  }

  @override
  Future<String?> getString(String key) async => map[key];

  @override
  Future<void> saveBool(String key, bool value) async => map[key] = '$value';

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

/// Der uebersetzte Text eines Musters ("Punkte", "Linien", ...).
///
/// Die Beschriftung kommt aus den App-Texten - im Test muss man also
/// den Text finden, den der Nutzer sieht, nicht den Schluessel.
String _text(String id) {
  const namen = {
    'none': 'Keiner',
    'dots': 'Punkte',
    'lines': 'Linien',
    'hearts': 'Herzen',
    'stars': 'Sterne',
    'waves': 'Wellen',
    'custom': 'Eigenes Bild',
  };
  return namen[id] ?? id;
}

void main() {
  testWidgets('ein gewaehltes Muster steht im Zustand und im Speicher', (
    tester,
  ) async {
    final speicher = _FakeLocalStorage();
    final container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(speicher)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChatBackgroundPicker())),
      ),
    );
    await tester.pumpAndSettle();

    // Das erste Muster waehlen.
    final muster = ChatBackgrounds.presets.first;
    await tester.tap(find.text(_text(muster)));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).chatBackground,
      muster,
      reason: 'Der Zustand muss den gewaehlten Hintergrund tragen.',
    );

    // Und im Speicher:
    expect(
      speicher.map.isNotEmpty,
      isTrue,
      reason: 'Es wurde nichts gespeichert.',
    );
    expect(
      speicher.map.values.join(),
      contains(muster),
      reason: 'Der gewaehlte Hintergrund steht nicht im Speicher.',
    );
  });

  testWidgets('schlaegt das Schreiben fehl, ist er beim naechsten Start weg', (
    tester,
  ) async {
    // DER BEFUND: Das Schreiben schlug still fehl. Die Oberflaeche zeigte
    // den Hintergrund trotzdem an (sie setzt den Zustand zuerst). Beim
    // naechsten Start war er weg - und niemand wusste warum.
    final speicher = _FakeLocalStorage(schlaegtFehl: true);
    final container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(speicher)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChatBackgroundPicker())),
      ),
    );
    await tester.pumpAndSettle();

    final muster = ChatBackgrounds.presets.first;
    await tester.tap(find.text(_text(muster)));
    await tester.pumpAndSettle();

    // Der Zustand zeigt den Hintergrund (optimistisch) ...
    expect(container.read(settingsProvider).chatBackground, muster);

    // ... aber im Speicher ist nichts. DAS ist der Fehler, den der
    // Betreiber gemeldet hat: sichtbar wird nichts, gespeichert
    // nichts.
    expect(
      speicher.map.isEmpty,
      isTrue,
      reason:
          'Der Hintergrund wurde nicht gespeichert - beim Neustart ist er weg.',
    );
  });
}
