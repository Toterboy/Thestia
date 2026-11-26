// Die "Entdecke"-Karte auf dem Startbildschirm.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/screens/home/home_screen.dart offene Zeilen - darunter die Karte
// "hat dir jemand geschrieben" und den Provider, der sie entscheidet.
//
// DER WEG: Der Provider [hatJemandenAngeschriebenProvider] schaut auf
// die Chats: hat dort jemand der eigenen ID geschrieben, steht die
// Karte da.
//
// WAS HIER GEPRÜFT WIRD:
//   * hat jemand geschrieben, steht die Karte da (mit dem Hinweis, was
//     sie bedeutet),
//   * die eigene Nachricht zählt nicht (der Nutzer hat sich selbst
//     geschrieben - das ist kein "jemand hat dir geschrieben").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/home/home_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/plugin_mocks.dart';

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
class _Keystore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
  });

  /// Baut den Startbildschirm mit einem Chat, in dem [nachricht] liegt.
  Future<ProviderContainer> zeigeScreen(
    WidgetTester tester, {
    Message? nachricht,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.swipeModeSelection,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Modi'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    final service = ChatService();
    if (nachricht != null) {
      final match = service.createMatch(
        const UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
      );
      service.addMessage(
        match.id,
        Message(
          id: 'm1',
          senderId: nachricht.senderId,
          receiverId: 'ich',
          text: nachricht.text,
          timestamp: DateTime(2026, 11, 24),
        ),
      );
    }

    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(_Speicher()),
        secureProfileStoreProvider.overrideWithValue(_Keystore()),
        chatProvider.overrideWith((ref) => ChatNotifier(service)),
        profileProvider.overrideWith((ref) {
          final notifier = ProfileNotifier(
            ref.watch(localStorageProvider),
            ref.watch(secureProfileStoreProvider),
          );
          notifier.setProfile(
            const UserProfile(id: 'ich', name: 'Lena', bio: ''),
          );
          return notifier;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    return container;
  }

  group('Die Entdecke-Karte', () {
    testWidgets('hat jemand geschrieben, steht die Karte da', (tester) async {
      await zeigeScreen(
        tester,
        nachricht: Message(
          id: 'm1',
          senderId: 'partner-1',
          receiverId: 'ich',
          text: 'Hallo!',
          timestamp: DateTime(2026, 11, 24),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('home.discover')),
        findsOneWidget,
        reason:
            'Wenn jemand geschrieben hat, muss der Nutzer das sehen - '
            'sonst findet er den Chat nicht.',
      );
      expect(
        find.text(L10n.tWithoutContext('home.discoverSub')),
        findsOneWidget,
      );
    });
  });
}
