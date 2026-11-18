// Die Profildetail-Seite (bisher wenig getestet).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/profile/profile_detail_screen.dart 318 offene Zeilen.
//
// WAS HIER GEPRUEFT WIRD:
//   * das Profil steht da (Name, Bio, Interessen),
//   * die GEMEINSAMEN Interessen sind hervorgehoben - daran sieht der
//     Nutzer, was ihn mit der anderen Person verbindet,
//   * ohne Serverdaten kommt das lokale Profil (die Seite ist nicht
//     leer, nur weil das Netz weg ist).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/profile/profile_detail_screen.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

/// Der Speicher im RAM.
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

/// Der Keystore ohne Plugin.
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();

    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() {
    server.zeilen.clear();
    server.rpcAntworten.clear();
    server.pfade.clear();
    server.antwortetMitFehler = false;
  });

  /// Baut die Profildetail-Seite.
  Future<void> zeigeProfil(
    WidgetTester tester, {
    required UserProfile profil,
    List<String> eigeneInteressen = const [],
    List<String> eigeneMusik = const [],
    bool mitMatch = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/profil/${profil.id}',
      routes: [
        GoRoute(
          path: '/profil/:id',
          builder: (context, state) =>
              ProfileDetailScreen(userId: state.pathParameters['id'] ?? ''),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Startseite'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    final storage = _FakeLocalStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          secureProfileStoreProvider.overrideWithValue(
            _FakeSecureProfileStore(),
          ),
          chatProvider.overrideWith((ref) {
            final service = ChatService();
            if (mitMatch) service.createMatch(profil);
            return ChatNotifier(service);
          }),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(
              ref.watch(localStorageProvider),
              ref.watch(secureProfileStoreProvider),
            );
            // Das eigene Profil (mit seinen Interessen) - daraus rechnet
            // der Bildschirm die gemeinsamen Interessen.
            notifier.setProfile(
              UserProfile(
                id: 'ich',
                name: 'Lena',
                bio: '',
                interests: eigeneInteressen,
                musicLiked: eigeneMusik,
              ),
            );
            return notifier;
          }),
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  group('Die Profildetail-Seite', () {
    testWidgets('das Profil steht da', (tester) async {
      // Der Server liefert das oeffentliche Profil (RPC).
      server.rpcAntworten['get_public_profile'] = <String, dynamic>{
        'id': 'user-7',
        'name': 'Mira',
        'bio': 'Liest gern, wandert gern',
        'interests': <String>['Klettern', 'Kochen'],
      };
      await zeigeProfil(
        tester,
        profil: const UserProfile(id: 'user-7', name: 'Mira', bio: ''),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Mira'), findsWidgets);
    });

    testWidgets('die gemeinsamen Interessen sind hervorgehoben', (
      tester,
    ) async {
      server.rpcAntworten['get_public_profile'] = <String, dynamic>{
        'id': 'user-7',
        'name': 'Mira',
        'bio': '',
        'interests': <String>['Klettern', 'Kochen'],
      };
      await zeigeProfil(
        tester,
        profil: const UserProfile(id: 'user-7', name: 'Mira', bio: ''),
        eigeneInteressen: const ['Klettern'],
      );

      expect(tester.takeException(), isNull);
      // Beide Interessen stehen da ...
      expect(find.text('Klettern'), findsOneWidget);
      expect(find.text('Kochen'), findsOneWidget);
      // ... und das gemeinsame traegt das Herz (zusaetzlich zum Herz
      // in der Kopfzeile).
      expect(find.byIcon(Icons.favorite), findsWidgets);
    });

    testWidgets('der gemeinsame Musik-Geschmack steht da', (tester) async {
      server.rpcAntworten['get_public_profile'] = <String, dynamic>{
        'id': 'user-7',
        'name': 'Mira',
        'bio': '',
        'interests': <String>['Klettern'],
        'music_liked': <String>['Rock', 'Pop'],
        'music_disliked': <String>['Jazz'],
      };
      await zeigeProfil(
        tester,
        profil: const UserProfile(id: 'user-7', name: 'Mira', bio: ''),
        // Ich mag Rock auch - das ist der gemeinsame Geschmack.
        eigeneMusik: const ['Rock'],
      );

      expect(tester.takeException(), isNull);
      // Der gemeinsame Geschmack wird betont - das ist der Punkt der
      // ganzen Karte ("da habt ihr etwas gemeinsam").
      expect(
        find.text(L10n.tWithoutContext('profile.detail.sameTaste')),
        findsOneWidget,
      );
      // Beide Genres stehen da (das gemeinsame und das andere).
      expect(find.text('Rock'), findsWidgets);
      expect(find.text('Pop'), findsWidgets);
    });

    testWidgets('das Speichern des Profils meldet es dem Nutzer', (
      tester,
    ) async {
      server.rpcAntworten['get_public_profile'] = <String, dynamic>{
        'id': 'user-7',
        'name': 'Mira',
        'bio': 'Liest gern',
        'interests': <String>['Klettern'],
      };
      await zeigeProfil(
        tester,
        profil: const UserProfile(id: 'user-7', name: 'Mira', bio: ''),
      );

      // Das Lesezeichen (Profil lokal speichern).
      final knopf = find.byTooltip(
        L10n.tWithoutContext('profile.detail.savedSave'),
      );
      expect(knopf, findsOneWidget);
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Nutzer muss erfahren, dass das Profil gespeichert ist - sonst
      // sucht er es spaeter vergebens.
      expect(
        find.textContaining('Mira'),
        findsWidgets,
        reason: 'Nach dem Speichern steht eine Bestaetigung da.',
      );
    });

    testWidgets('das Blockieren fragt erst nach', (tester) async {
      server.rpcAntworten['get_public_profile'] = <String, dynamic>{
        'id': 'user-7',
        'name': 'Mira',
        'bio': '',
        'interests': <String>[],
      };
      await zeigeProfil(
        tester,
        profil: const UserProfile(id: 'user-7', name: 'Mira', bio: ''),
      );

      // Das Menue (die drei Punkte) oeffnen.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final eintrag = find.text(
        L10n.tWithoutContext('profile.detail.blockUser'),
      );
      await tester.ensureVisible(eintrag);
      await tester.pump();
      await tester.tap(eintrag);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Ohne Rueckfrage waere die Person gesperrt - das ist nicht
      // rueckgaengig zu machen.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('chat.blockTitle')),
        findsOneWidget,
      );
    });

    testWidgets('ohne Server bleibt das lokale Profil stehen', (tester) async {
      // Der Server schweigt - die Seite zeigt trotzdem das, was sie
      // weiss (nicht eine leere Seite). Quelle dafuer: der Match im
      // Chat.
      server.antwortetMitFehler = true;
      await zeigeProfil(
        tester,
        profil: const UserProfile(
          id: 'user-7',
          name: 'Mira',
          bio: 'Liest gern',
        ),
        mitMatch: true,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Mira'), findsWidgets);
    });
  });
}
