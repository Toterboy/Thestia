// Die Fehlerseite (Fallback fuer unbekannte Routen).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/core/error_screen.dart nur 4,5 % Abdeckung. Die Seite ist
// die letzte Rueckfallebene: wenn eine Route nicht existiert oder der
// Nutzer nicht dahin darf, sieht er DIESEN Bildschirm.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Seite erklaert, was passiert ist, und bietet einen Ausgang,
//   * der Ausgang fuehrt eingeloggte Nutzer nach Hause,
//   * nicht eingeloggte Nutzer kommen zur Anmeldung (wenn sie den
//     Willkommenstext schon gesehen haben) oder zum Willkommenstext.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/auth/auth_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/screens/core/error_screen.dart';
import 'package:thestia/services/auth/app_auth_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

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

/// Der Keystore ohne Plugin.
class _Keystore implements SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Der Auth-Dienst als Ersatz - der Test setzt den Zustand selbst.
class _Auth implements AppAuthService {
  _Auth(this.eingeloggt);

  /// Meldet der Dienst eine Sitzung?
  ///
  /// DER GRUND: Die Wiederherstellung laeuft im Hintergrund - sie darf
  /// den Zustand des Tests nicht ueberschreiben.
  final bool eingeloggt;

  @override
  Future<bool> restoreSession() async => eingeloggt;

  @override
  Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    required DateTime birthDate,
    double? latitude,
    double? longitude,
    String? captchaToken,
  }) async => UserProfile(id: 'neu', name: name, bio: '', birthDate: birthDate);

  @override
  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {}

  @override
  Future<void> loginWithPasskey({String? captchaToken}) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> deleteAccount() async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
  });

  /// Baut die Fehlerseite mit dem gewuenschten Zustand.
  Future<void> zeige(
    WidgetTester tester, {
    required bool eingeloggt,
    required bool introGesehen,
  }) async {
    final storage = _Speicher();
    final secure = _Keystore();

    final router = GoRouter(
      initialLocation: '/kaputt',
      routes: [
        GoRoute(path: '/kaputt', builder: (ctx, state) => const ErrorScreen()),
        GoRoute(
          path: '/',
          builder: (ctx, state) => const Scaffold(body: Text('Startseite')),
        ),
        GoRoute(
          path: '/login',
          builder: (ctx, state) => const Scaffold(body: Text('Anmeldung')),
        ),
        GoRoute(
          path: '/welcome',
          builder: (ctx, state) => const Scaffold(body: Text('Willkommen')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(storage),
        secureProfileStoreProvider.overrideWithValue(secure),
        settingsProvider.overrideWith((ref) {
          final notifier = SettingsNotifier(storage, ref);
          if (introGesehen) {
            notifier.state = notifier.state.copyWith(introSeen: true);
          }
          return notifier;
        }),
        profileProvider.overrideWith((ref) => ProfileNotifier(storage, secure)),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            _Auth(eingeloggt),
            ref.read(profileProvider.notifier),
            ref,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    // DER ZUSTAND: Die Wiederherstellung laeuft im Hintergrund - der
    // Test setzt den Status deshalb selbst (und danach gewinnt er).
    container.read(authProvider.notifier).state = eingeloggt
        ? const AsyncValue.data(true)
        : const AsyncValue.data(false);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Die Fehlerseite', () {
    testWidgets('sie erklaert den Zustand und bietet einen Ausgang', (
      tester,
    ) async {
      await zeige(tester, eingeloggt: true, introGesehen: false);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('error.notFoundTitle')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass er hier falsch ist - ein leerer '
            'Bildschirm waere wie ein Absturz.',
      );
      expect(
        find.text(L10n.tWithoutContext('error.goHome')),
        findsOneWidget,
        reason: 'Es muss einen Ausgang geben.',
      );
    });

    testWidgets('eingeloggte Nutzer kommen nach Hause', (tester) async {
      await zeige(tester, eingeloggt: true, introGesehen: false);

      await tester.tap(find.text(L10n.tWithoutContext('error.goHome')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Startseite'),
        findsOneWidget,
        reason:
            'Wer angemeldet ist, will zurueck in die App - nicht nochmal '
            'zur Anmeldung.',
      );
    });

    testWidgets('nicht angemeldete Nutzer kommen zur Anmeldung', (
      tester,
    ) async {
      await zeige(tester, eingeloggt: false, introGesehen: true);

      await tester.tap(find.text(L10n.tWithoutContext('error.goHome')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Anmeldung'),
        findsOneWidget,
        reason:
            'Wer den Willkommenstext schon gesehen hat, gehoert zur '
            'Anmeldung - der Willkommenstext waere eine zusaetzliche '
            'Runde.',
      );
    });

    testWidgets('wer den Willkommenstext noch nicht sah, bekommt ihn', (
      tester,
    ) async {
      await zeige(tester, eingeloggt: false, introGesehen: false);

      await tester.tap(find.text(L10n.tWithoutContext('error.goHome')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Willkommen'),
        findsOneWidget,
        reason:
            'Wer noch nie in der App war, muss erst den Willkommenstext '
            'sehen - sonst fehlen ihm die Regeln.',
      );
    });
  });
}
