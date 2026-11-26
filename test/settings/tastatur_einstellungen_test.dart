// Die Einstellungen der eigenen Tastatur (0.11.0).
//
// WAS HIER GEPRÜFT WIRD:
//   * die Belegung und der Stil kommen als Text aus den Einstellungen
//     (und ein unbekannter Text bedeutet "wie die App"),
//   * die Tastatur folgt der gewählten Belegung (QWERTZ hat das "z"
//     oben, QWERTY das "y"),
//   * die Einstellungen überstehen eine Neuinstallation: der Server
//     gibt sie zurück (profiles.ui_prefs),
//   * die Oberfläche bietet die Wahl an (und sie landet in den
//     Einstellungen).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/models/settings/tastatur_einstellungen.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/widgets/chat/secure_keyboard.dart';
import 'package:thestia/widgets/settings/tastatur_einstellungen.dart';

/// Der Speicher im RAM.
class _Speicher implements LocalStorage {
  final Map<String, String> _daten = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async =>
      _daten[key] = value;

  @override
  Future<String?> getString(String key) async => _daten[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _daten[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _daten[key] == null ? null : _daten[key] == 'true';

  @override
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
  });

  group('Die Belegung und der Stil', () {
    test('roundten über den gespeicherten Text', () {
      for (final belegung in TastaturBelegung.values) {
        expect(TastaturBelegungWert.ausWert(belegung.wert), belegung);
      }
      for (final stil in TastaturStil.values) {
        expect(TastaturStilWert.ausWert(stil.wert), stil);
      }
    });

    test('ein unbekannter Text bedeutet "wie die App"', () {
      expect(
        TastaturBelegungWert.ausWert('gibtesnicht'),
        TastaturBelegung.wieApp,
      );
      expect(TastaturBelegungWert.ausWert(null), TastaturBelegung.wieApp);
      expect(TastaturStilWert.ausWert('gibtesnicht'), TastaturStil.wieApp);
      expect(TastaturStilWert.ausWert(null), TastaturStil.wieApp);
    });
  });

  group('Die Einstellungen', () {
    test('die Schalter landen in den Einstellungen', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(_Speicher()),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setTastaturBelegung(TastaturBelegung.deutsch);
      await notifier.setTastaturStil(TastaturStil.appFarbe);
      await notifier.setTastaturFarbe(0xFF00FF00);

      final stand = container.read(settingsProvider);
      expect(stand.tastaturBelegung, 'deutsch');
      expect(stand.tastaturStil, 'appFarbe');
      expect(stand.tastaturFarbe, 0xFF00FF00);
    });

    test(
      'der Server gibt sie zurück (Neuinstallation, zweites Gerät)',
      () async {
        final container = ProviderContainer(
          overrides: <Override>[
            localStorageProvider.overrideWithValue(_Speicher()),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(settingsProvider.notifier);

        await notifier.applyServerUiPrefs(<String, dynamic>{
          'tastaturBelegung': 'englisch',
          'tastaturStil': 'eigeneFarbe',
          'tastaturFarbe': 0xFF112233,
        });

        final stand = container.read(settingsProvider);
        expect(stand.tastaturBelegung, 'englisch');
        expect(stand.tastaturStil, 'eigeneFarbe');
        expect(stand.tastaturFarbe, 0xFF112233);
      },
    );
  });

  group('Die Tastatur', () {
    testWidgets('sie folgt der gewählten Belegung', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecureKeyboard(
              layout: TastaturBelegung.deutsch,
              onCharacter: _zeichen,
              onBackspace: _nix,
            ),
          ),
        ),
      );
      await tester.pump();

      // QWERTZ: das "z" steht oben, das "y" unten.
      expect(
        tester.getTopLeft(find.text('y')).dy,
        greaterThan(tester.getTopLeft(find.text('z')).dy),
      );
    });

    testWidgets('sie nimmt die eigene Farbe', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecureKeyboard(
              layout: TastaturBelegung.deutsch,
              stil: TastaturStil.eigeneFarbe,
              // Ein dunkles Grün: darauf muss der Text hell sein,
              // sonst wäre er unlesbar.
              farbe: 0xFF1B5E20,
              onCharacter: _zeichen,
              onBackspace: _nix,
            ),
          ),
        ),
      );
      await tester.pump();

      // Der Text auf der Taste hat die gewählte Farbe - und ist auf
      // dem kräftigen Grün hell (sonst wäre er unlesbar).
      final text = tester.widget<Text>(find.text('q'));
      expect(text.style?.color, Colors.white);
    });

    testWidgets('QWERTY stellt das "y" nach oben', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecureKeyboard(
              layout: TastaturBelegung.englisch,
              onCharacter: _zeichen,
              onBackspace: _nix,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getTopLeft(find.text('y')).dy,
        lessThan(tester.getTopLeft(find.text('z')).dy),
      );
    });
  });

  group('Die Oberfläche', () {
    testWidgets('die Wahl landet in den Einstellungen', (tester) async {
      final container = ProviderContainer(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(_Speicher()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              // Im Bildschirm steckt der Bogen in einer Scroll-Ansicht -
              // im Test genauso (sonst läuft die Spalte über).
              body: SingleChildScrollView(child: TastaturEinstellungen()),
            ),
          ),
        ),
      );
      await tester.pump();

      // "Deutsch (QWERTZ)" wählen.
      await tester.tap(find.text('Deutsch (QWERTZ)'));
      await tester.pump();

      expect(container.read(settingsProvider).tastaturBelegung, 'deutsch');

      // "Eigene Farbe" wählen - dann erscheinen die Farbkreise.
      await tester.tap(find.text('Eigene Farbe'));
      await tester.pump();

      expect(container.read(settingsProvider).tastaturStil, 'eigeneFarbe');
    });
  });
}

/// Eine leere Aktion (die Tastatur wird im Test nicht bedient).
void _zeichen(String zeichen) {}

/// Eine leere Aktion (die Tastatur wird im Test nicht bedient).
void _nix() {}
