import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/theme/app_theme.dart';

void main() {
  group('AppTheme-Cache', () {
    test('of() liefert fuer gleiche (Schema, Helligkeit) dieselbe Instanz',
        () {
      // Stabile Identitaet ist der Kern des Fixes: nur so ersetzt ein
      // Settings-Change das Theme nicht durch eine neue Objekt-Identitaet
      // (was previously eine erneute Theme-Animation ausloeste).
      final a = AppTheme.of(ThestiaTheme.classic, Brightness.light);
      final b = AppTheme.of(ThestiaTheme.classic, Brightness.light);
      expect(identical(a, b), isTrue);
    });

    test('hell und dunkel sowie verschiedene Schemata sind getrennt', () {
      final light = AppTheme.of(ThestiaTheme.classic, Brightness.light);
      final dark = AppTheme.of(ThestiaTheme.classic, Brightness.dark);
      final ocean = AppTheme.of(ThestiaTheme.ocean, Brightness.light);

      expect(identical(light, dark), isFalse);
      expect(identical(light, ocean), isFalse);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(ocean.colorScheme.primary,
          isNot(ThestiaTheme.classic.primaryColor));
    });

    test('light()/dark() erzeugen dieselben Werte wie of()', () {
      for (final theme in ThestiaTheme.values) {
        expect(
          AppTheme.light(theme: theme).colorScheme.primary,
          AppTheme.of(theme, Brightness.light).colorScheme.primary,
        );
        expect(
          AppTheme.dark(theme: theme).colorScheme.primary,
          AppTheme.of(theme, Brightness.dark).colorScheme.primary,
        );
      }
    });

    test('Dark-Mode-AppBar hat helle Schrift (kein Schwarz auf Dunkel)', () {
      final dark = AppTheme.of(ThestiaTheme.classic, Brightness.dark);
      final light = AppTheme.of(ThestiaTheme.classic, Brightness.light);
      // Transparente AppBar: die Schriftfarbe muss der Helligkeit folgen,
      // sonst ist sie im Dark-Mode unlesbar.
      expect(dark.appBarTheme.foregroundColor, Colors.white);
      expect(light.appBarTheme.foregroundColor, Colors.black87);
    });

    test('alle Schemata liefern ein vollständiges Theme', () {
      for (final theme in ThestiaTheme.values) {
        for (final brightness in Brightness.values) {
          final data = AppTheme.of(theme, brightness);
          expect(data.useMaterial3, isTrue);
          expect(data.brightness, brightness);
          expect(data.cardTheme, isNotNull);
          expect(data.inputDecorationTheme, isNotNull);
          expect(data.extensions, isNotEmpty);
        }
      }
    });
  });
}
