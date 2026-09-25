// Tests für die reine Demo-Modus-Entscheidung (G-01).
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/utils/demo_mode.dart';

void main() {
  group('resolveDemoMode', () {
    test('Release-Build: immer false (auch mit Flag und Platzhalter-URL)', () {
      expect(
        resolveDemoMode(
          isReleaseMode: true,
          isSupabaseInitialized: true,
          demoModeFlag: true,
          baseUrl: 'https://example.com',
        ),
        isFalse,
      );
      expect(
        resolveDemoMode(
          isReleaseMode: true,
          isSupabaseInitialized: false,
          demoModeFlag: true,
          baseUrl: '',
        ),
        isFalse,
      );
    });

    test('Aktive Supabase-Session: immer false (echtes Backend)', () {
      expect(
        resolveDemoMode(
          isReleaseMode: false,
          isSupabaseInitialized: true,
          demoModeFlag: true,
          baseUrl: 'https://example.com',
        ),
        isFalse,
      );
    });

    test('Explizites DEMO_MODE-Flag: true', () {
      expect(
        resolveDemoMode(
          isReleaseMode: false,
          isSupabaseInitialized: false,
          demoModeFlag: true,
          baseUrl: 'https://api.thestia.de',
        ),
        isTrue,
      );
    });

    test('Ohne Flag: URL-Heuristik greift (Platzhalter-Config → Demo)', () {
      bool resolve(String baseUrl) => resolveDemoMode(
            isReleaseMode: false,
            isSupabaseInitialized: false,
            demoModeFlag: false,
            baseUrl: baseUrl,
          );

      expect(resolve('https://example.com'), isTrue);
      expect(resolve('http://localhost:8080'), isTrue);
      expect(resolve(''), isTrue);
    });

    test('Ohne Flag: echte Backend-URL → kein Demo', () {
      expect(
        resolveDemoMode(
          isReleaseMode: false,
          isSupabaseInitialized: false,
          demoModeFlag: false,
          baseUrl: 'https://api.thestia.de',
        ),
        isFalse,
      );
      expect(
        resolveDemoMode(
          isReleaseMode: false,
          isSupabaseInitialized: false,
          demoModeFlag: false,
          baseUrl: 'https://jftuigjbmmuvrckbchqo.supabase.co',
        ),
        isFalse,
      );
    });
  });
}