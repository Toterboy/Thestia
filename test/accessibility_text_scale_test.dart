import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/screens/settings/settings_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

/// Noop-Variante des Secure-Storages (kein Plugin im Widget-Test noetig).
class _NoopSecureStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      null;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}
}

Future<void> _pumpSettings(WidgetTester tester, double scale) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider
            .overrideWithValue(SharedPreferencesStorage(prefs)),
        secureProfileStoreProvider
            .overrideWithValue(SecureProfileStore(_NoopSecureStorage())),
      ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const MaterialApp(home: SettingsScreen()),
        ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Accessibility: Wichtige Screens duerfen auch bei grosser Systemschrift
/// (Android erlaubt bis 3.2x) keine Render-Overflow-Exception werfen.
void main() {
  const scales = <String, double>{
    'normal (1.0x)': 1.0,
    'gross (2.0x)': 2.0,
    'maximum (3.2x)': 3.2,
  };

  scales.forEach((name, scale) {
    testWidgets('Einstellungen rendern ohne Overflow bei Schrift $name',
        (tester) async {
      await _pumpSettings(tester, scale);
      // Scrollen bis zum Ende: Auch unten darf nichts platzen.
      final scroller = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(SingleChildScrollView),
      );
      if (tester.any(scroller)) {
        await tester.fling(scroller.first, const Offset(0, -1500), 1500);
        await tester.pump();
        await tester.fling(scroller.first, const Offset(0, -2500), 2500);
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });
  });
}
