// Das eigene Profil (bisher kaum getestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/profile/profile_screen.dart 309 offene Zeilen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich mit dem eigenen Profil (kein Absturz,
//     kein Render-Overflow),
//   * der Name steht da, das Verifiziert-Abzeichen auch,
//   * die beiden Knoepfe in der Kopfzeile (QR-Code, Einstellungen).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/screens/profile/profile_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

import 'support/plugin_mocks.dart';

/// Der Speicher im RAM (die App liest die Einstellungen daraus).
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _daten = {};

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

/// Der Keystore ohne Plugin (das Profil wird nicht gesichert).
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Das eigene Profil im Test.
UserProfile _profil() => UserProfile(
  id: 'ich',
  name: 'Lena',
  bio: 'Hallo aus Hamburg',
  birthDate: DateTime.now().subtract(const Duration(days: 24 * 365)),
  isVerified: true,
);

void main() {
  setUpAll(() async {
    // DER SPEICHER DES GERAETS: der Auth-Client holt sich daraus die
    // Sitzung - ohne den Mock schlaegt der Aufbau fehl.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // Der Supabase-Client wird genau einmal fuer die ganze Datei
    // aufgesetzt: die Stimmungskarte des Profils liest ihn. Ohne die
    // drei Optionen (kein Timer, kein Speicher, kein Deeplink-Observer)
    // scheitert der Aufbau auf dem CI-Runner.
    await mockPfadProvider();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // DER KEYSTORE: die Einstellungen kommen aus dem verschluesselten
    // Speicher - ohne den Mock ruft der Test auf dem CI-Runner das
    // echte Plugin (das findet dort keine libsecret-Sitzung).
    mockKeystore();
  });

  Future<ProviderContainer> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _FakeLocalStorage();
    final secure = _FakeSecureProfileStore();
    final container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
        secureProfileStoreProvider.overrideWithValue(secure),
        profileProvider.overrideWith((ref) {
          final notifier = ProfileNotifier(storage, secure);
          notifier.setProfile(_profil());
          return notifier;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          secureProfileStoreProvider.overrideWithValue(secure),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(storage, secure);
            notifier.setProfile(_profil());
            return notifier;
          }),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return container;
  }

  testWidgets('der Bildschirm baut sich ohne Absturz', (tester) async {
    await zeigeScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('der eigene Name steht da', (tester) async {
    await zeigeScreen(tester);

    expect(find.text('Lena'), findsWidgets);
  });

  testWidgets('das Verifiziert-Abzeichen steht neben dem Namen', (
    tester,
  ) async {
    await zeigeScreen(tester);

    expect(
      find.byIcon(Icons.verified),
      findsWidgets,
      reason:
          'Ein verifiziertes Profil traegt das Abzeichen - das sieht der '
          'Nutzer auch bei anderen (es ist Absicht, kein Leaken).',
    );
  });

  testWidgets('die Knoepfe in der Kopfzeile stehen da', (tester) async {
    await zeigeScreen(tester);

    expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  group('Das Profil-Menue', () {
    /// Oeffnet das Profil-Menue (der Knopf mit dem Personensymbol).
    Future<void> oeffneMenue(WidgetTester tester) async {
      await zeigeScreen(tester);

      final knopf = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('profile.profileBtn'),
      );
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('das Menue bietet alle Wege', (tester) async {
      await oeffneMenue(tester);

      expect(tester.takeException(), isNull);
      // Bearbeiten, Vorschau und die Vorstellung.
      expect(
        find.text(L10n.tWithoutContext('profile.menu.edit')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('profile.menu.preview')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('profile.menu.introPreview')),
        findsOneWidget,
      );
    });

    testWidgets('die Vorstellungs-Vorschau zeigt den Text', (tester) async {
      await oeffneMenue(tester);

      await tester.tap(
        find.text(L10n.tWithoutContext('profile.menu.introPreview')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Das eigene Profil mit der Vorstellung steht in der Vorschau.
      expect(find.text('Lena'), findsWidgets);
    });
  });
}
