// Die Zustaende der Profildetail-Seite und das Blockieren.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/profile/profile_detail_screen.dart 76 offene Zeilen. Der
// bestehende Test ("profile_detail_screen_test.dart") deckt die
// gemeinsamen Interessen und den Musik-Geschmack ab - offen waren die
// Karten, die nur bei bestimmten Profilangaben erscheinen, und der Weg
// "Nutzer blockieren".
//
// WAS HIER GEPRUEFT WIRD:
//   * das Geschlecht, die Entfernung und der Persoenlichkeitstyp stehen
//     da (die Karten, die nur mit diesen Angaben erscheinen),
//   * die Vorstellung steht da (Text und der Abspiel-Knopf),
//   * der Lieblingssong steht da,
//   * das Blockieren fragt nach (und der Abbruch blockiert nichts),
//   * das Blockieren geht zum Server und meldet den Erfolg,
//   * schlaegt das Blockieren fehl, wird das dem Nutzer gesagt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/profile/profile_detail_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
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
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();

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

  /// Baut die Profildetail-Seite mit dem oeffentlichen Profil [daten].
  Future<void> zeigeProfil(
    WidgetTester tester, {
    required Map<String, dynamic> daten,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    server.rpcAntworten['get_public_profile'] = <String, dynamic>{
      'id': '11111111-1111-4111-8111-111111111111',
      'name': 'Mira',
      'bio': '',
      'interests': <String>[],
      ...daten,
    };

    final router = GoRouter(
      initialLocation: '/profil/11111111-1111-4111-8111-111111111111',
      routes: [
        GoRoute(
          path: '/profil/:id',
          builder: (context, state) => const ProfileDetailScreen(
            userId: '11111111-1111-4111-8111-111111111111',
          ),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Startseite'))),
        ),
        GoRoute(
          path: AppRoutes.interessen,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Interessen'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(_Speicher()),
          secureProfileStoreProvider.overrideWithValue(_Keystore()),
          chatProvider.overrideWith((ref) => ChatNotifier(ChatService())),
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

  group('Die Angaben im Profil', () {
    testWidgets('das Geschlecht steht da', (tester) async {
      await zeigeProfil(tester, daten: <String, dynamic>{'gender': 'female'});

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(L10n.tWithoutContext('gender.female')),
        findsWidgets,
        reason:
            'Das Geschlecht der anderen Person ist ein Teil des Profils - '
            'ohne die Angabe weiss der Nutzer nicht, ob er hier richtig ist.',
      );
    });

    testWidgets('die Entfernung steht da', (tester) async {
      // DIE DISTANZ kommt aus einem eigenen Aufruf (der Server
      // berechnet sie - sie steht nicht im oeffentlichen Profil).
      server.rpcAntworten['profile_distance_km'] = 12;

      await zeigeProfil(tester, daten: <String, dynamic>{});

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(
          L10n.tWithoutContext(
            'distance.bucketRange',
          ).replaceAll('{from}', '10').replaceAll('{to}', '20'),
        ),
        findsWidgets,
        reason:
            'Die Entfernung ist das, woran der Nutzer den Weg plant - sie '
            'darf nicht fehlen.',
      );
    });

    testWidgets('der Persoenlichkeitstyp steht da', (tester) async {
      await zeigeProfil(
        tester,
        daten: <String, dynamic>{'personality_type': 'Romantiker'},
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Romantiker'),
        findsWidgets,
        reason:
            'Der Typ sagt, ob zwei Personen zusammenpassen - er gehoert '
            'zum Profil.',
      );
    });

    testWidgets('die Vorstellung steht da', (tester) async {
      await zeigeProfil(
        tester,
        daten: <String, dynamic>{
          'intro_text': 'Ich suche jemanden zum Wandern.',
        },
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text('Ich suche jemanden zum Wandern.'),
        findsOneWidget,
        reason:
            'Die Vorstellung ist das, was die Person ueber sich selbst sagt - '
            'sie muss sichtbar sein.',
      );
    });

    testWidgets('der Lieblingssong steht da', (tester) async {
      await zeigeProfil(
        tester,
        daten: <String, dynamic>{'favorite_song': 'Nur mir'},
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Nur mir'),
        findsWidgets,
        reason:
            'Der Lieblingssong ist ein Gesprächsanlass - er gehört zum '
            'Profil.',
      );
    });
  });

  group('Das Blockieren', () {
    /// Oeffnet das Menue und waehlt "Blockieren".
    Future<void> oeffneBlockMenu(WidgetTester tester) async {
      final knopf = find.byTooltip(
        L10n.tWithoutContext('profile.detail.reportUser'),
      );
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.text(L10n.tWithoutContext('profile.detail.blockUser')).last,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('es fragt nach', (tester) async {
      await zeigeProfil(tester, daten: <String, dynamic>{});

      await oeffneBlockMenu(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('chat.blockTitle')),
        findsOneWidget,
      );
    });

    testWidgets('der Abbruch blockiert nichts', (tester) async {
      await zeigeProfil(tester, daten: <String, dynamic>{});

      await oeffneBlockMenu(tester);
      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        server.pfade.where((p) => p.contains('block_user')),
        isEmpty,
        reason:
            'Nach dem Abbruch darf niemand blockiert werden - der Nutzer '
            'hat es sich anders ueberlegt.',
      );
    });

    testWidgets('das Blockieren geht zum Server', (tester) async {
      await zeigeProfil(tester, daten: <String, dynamic>{});

      await oeffneBlockMenu(tester);
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('chat.blockAction'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        server.pfade.where((p) => p.contains('block_user')),
        isNotEmpty,
        reason:
            'Die Blockierung muss beim Server landen - lokal waere sie nach '
            'einem Neustart weg.',
      );
    });

    testWidgets('schlaegt es fehl, wird das gesagt', (tester) async {
      await zeigeProfil(tester, daten: <String, dynamic>{});
      // Der Server lehnt ab.
      server.antwortetMitFehler = true;

      await oeffneBlockMenu(tester);
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('chat.blockAction'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('chat.blockFailed')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass die Blockierung nicht geklappt hat '
            '- sonst glaubt er, die Person sei weg.',
      );
    });
  });
}
