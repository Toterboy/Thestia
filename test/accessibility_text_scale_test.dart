import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/models/contact_share_profile.dart';
import 'package:thestia/providers/contact_share_provider.dart';
import 'package:thestia/screens/onboarding/dating_safety_education_screen.dart';
import 'package:thestia/screens/qr/contact_share_screen.dart';
import 'package:thestia/screens/settings/settings_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_contact_share_store.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/widgets/dock_tab_bar.dart';

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

/// Kontakt-Store ohne Keystore: haelt den Stand nur im RAM.
class _FakeContactStore extends SecureContactShareStore {
  _FakeContactStore(this._profil);

  ContactShareProfile _profil;

  @override
  Future<ContactShareProfile> load() async => _profil;

  @override
  Future<void> save(ContactShareProfile profile) async => _profil = profile;
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

  scales.forEach((name, scale) {
    testWidgets(
        'Sicherheits-Aufklaerung rendert ohne Overflow bei Schrift $name',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider
                .overrideWithValue(SharedPreferencesStorage(prefs)),
          ],
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const MaterialApp(home: DatingSafetyEducationScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);

      // Der Knopf muss auch bei grosser Schrift erreichbar bleiben.
      expect(find.text('Ich habe verstanden'), findsOneWidget);
      final knopf = tester.getRect(find.text('Ich habe verstanden'));
      expect(knopf.bottom, lessThanOrEqualTo(844),
          reason: 'Der Knopf liegt unterhalb des Bildschirms');
    });
  });

  scales.forEach((name, scale) {
    testWidgets('Connect to others rendert ohne Overflow bei Schrift $name',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contactShareStoreProvider.overrideWithValue(
              _FakeContactStore(const ContactShareProfile(
                phone: '+49 170 1234567',
                entries: [
                  ContactShareEntry(
                    app: 'signal',
                    label: 'Signal',
                    handle: '@thorst',
                    recommended: true,
                  ),
                ],
              )),
            ),
          ],
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const MaterialApp(home: ContactShareScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Die ganze Seite durchscrollen - auch unten darf nichts platzen.
      final scroller = find.descendant(
        of: find.byType(ContactShareScreen),
        matching: find.byType(Scrollable),
      );
      if (tester.any(scroller)) {
        await tester.fling(scroller.first, const Offset(0, -1200), 1200);
        await tester.pump();
        await tester.fling(scroller.first, const Offset(0, -2000), 2000);
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });
  });

  scales.forEach((name, scale) {
    testWidgets('Das Dock rendert ohne Overflow bei Schrift $name',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: Scaffold(
              body: const Center(child: Text('Inhalt')),
              bottomNavigationBar: DockTabBar(
                index: 0,
                onSelected: (_) {},
                tabs: const [
                  DockTab(route: '/', icon: Icons.newspaper, labelKey: 'nav.home'),
                  DockTab(
                    route: '/entdecken',
                    icon: Icons.favorite,
                    labelKey: 'nav.discover',
                  ),
                  DockTab(
                    route: '/interessen',
                    icon: Icons.people,
                    labelKey: 'nav.interests',
                  ),
                  DockTab(
                    route: '/profil',
                    icon: Icons.person,
                    labelKey: 'nav.profile',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      // ALLE vier Reiter tragen ihre Beschriftung (NUTZERWUNSCH
      // 30.10.2026) - auch bei grosser Schrift, und ohne Abschneiden.
      for (final beschriftung in const [
        'Aktuelles',
        'Entdecken',
        'Interessen',
        'Profil',
      ]) {
        expect(find.text(beschriftung), findsOneWidget,
            reason: 'Beschriftung "$beschriftung" fehlt');
      }
    });
  });
}
