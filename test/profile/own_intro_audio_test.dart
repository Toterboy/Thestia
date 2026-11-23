// Der Abspiel-Knopf der eigenen Vorstellung (im eigenen Profil).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/profile/parts/ownintroaudioplayerstate.dart 35 offene Zeilen
// bei 18 % Abdeckung. Der Knopf ist der Weg, mit dem der Nutzer seine
// eigene Vorstellung anhoeren kann - und er ist der einzige Weg, zu
// sehen, ob die Aufnahme ueberhaupt da ist.
//
// WAS HIER GEPRUEFT WIRD:
//   * ohne Aufnahme steht der Hinweis "keine Aufnahme" da,
//   * mit Aufnahme gibt es den Abspiel-Knopf,
//   * fehlt die Datei auf dem Server, wird das gemeldet (nicht still
//     nichts getan),
//   * ein Fehler beim Laden wird gemeldet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/screens/profile/profile_screen.dart';
import 'package:thestia/services/server/supabase_storage_service.dart';
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
class _Keystore implements SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Der Speicher-Dienst als Ersatz.
///
/// DER GRUND: Der echte Dienst holt eine signierte URL vom Server. Im
/// Test reicht der Ersatz: er meldet die URL (oder eben keine).
class _FakeSpeicher extends SupabaseStorageService {
  _FakeSpeicher(super.client, {this.url, this.fehler});

  /// Die URL, die geliefert wird (null = die Datei fehlt).
  final String? url;

  /// Der Fehler, den der Dienst werfen soll.
  final Object? fehler;

  @override
  Future<String?> getSignedAvatarUrl(String path) async {
    final f = fehler;
    if (f != null) throw f;
    return url;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // DER AUDIO-PLAYER: Der Abspiel-Knopf nutzt ihn - ohne den Ersatz
    // schlaegt der Aufbau fehl.
    mockAudioPlayer();
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

  /// Baut das eigene Profil (mit oder ohne Aufnahme).
  Future<void> zeige(
    WidgetTester tester, {
    required bool mitAufnahme,
    _FakeSpeicher? speicher,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _Speicher();
    final secure = _Keystore();
    final profil = UserProfile(
      id: 'ich',
      name: 'Lena',
      bio: 'Hallo aus Hamburg',
      birthDate: DateTime.now().subtract(const Duration(days: 24 * 365)),
      isVerified: true,
      introAudioPath: mitAufnahme ? 'ich/intro.m4a' : null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          secureProfileStoreProvider.overrideWithValue(secure),
          supabaseStorageServiceProvider.overrideWithValue(
            speicher ??
                _FakeSpeicher(
                  supabase.Supabase.instance.client,
                  url: 'https://example.supabase.co/intro.m4a',
                ),
          ),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(storage, secure);
            notifier.setProfile(profil);
            return notifier;
          }),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Oeffnet die Vorstellungs-Vorschau (Profil-Menue -> Vorstellung).
  Future<void> oeffneVorstellung(WidgetTester tester) async {
    final profilKnopf = find.widgetWithText(
      FilledButton,
      L10n.tWithoutContext('profile.profileBtn'),
    );
    await tester.ensureVisible(profilKnopf);
    await tester.pump();
    await tester.tap(profilKnopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.text(L10n.tWithoutContext('profile.menu.introPreview')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Der Abspiel-Knopf der eigenen Vorstellung', () {
    testWidgets('ohne Aufnahme steht der Hinweis da', (tester) async {
      await zeige(tester, mitAufnahme: false);
      await oeffneVorstellung(tester);

      expect(
        find.text(L10n.tWithoutContext('profile.intro.audioEmpty')),
        findsOneWidget,
        reason:
            'Ohne Aufnahme muss der Nutzer wissen, dass es keine gibt - '
            'sonst sucht er nach einem Knopf, den es nicht gibt.',
      );
    });

    testWidgets('mit Aufnahme gibt es den Abspiel-Knopf', (tester) async {
      await zeige(tester, mitAufnahme: true);
      await oeffneVorstellung(tester);

      expect(
        find.text(L10n.tWithoutContext('profile.intro.listen')),
        findsOneWidget,
        reason:
            'Der Nutzer muss seine eigene Vorstellung anhoeren koennen - '
            'das ist der ganze Zweck des Knopfes.',
      );
    });

    testWidgets('fehlt die Datei, wird das gemeldet', (tester) async {
      await zeige(
        tester,
        mitAufnahme: true,
        speicher: _FakeSpeicher(supabase.Supabase.instance.client, url: null),
      );
      await oeffneVorstellung(tester);

      await tester.tap(find.text(L10n.tWithoutContext('profile.intro.listen')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text(L10n.tWithoutContext('profile.intro.audioMissing')),
        findsOneWidget,
        reason:
            'Die Datei fehlt auf dem Server - der Nutzer muss es erfahren, '
            'statt auf einen Knopf zu tippen, der nichts tut.',
      );
    });

    testWidgets('ein Fehler beim Laden wird gemeldet', (tester) async {
      await zeige(
        tester,
        mitAufnahme: true,
        speicher: _FakeSpeicher(
          supabase.Supabase.instance.client,
          fehler: StateError('Server kaputt'),
        ),
      );
      await oeffneVorstellung(tester);

      await tester.tap(find.text(L10n.tWithoutContext('profile.intro.listen')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text(L10n.tWithoutContext('profile.intro.audioLoadError')),
        findsOneWidget,
        reason:
            'Ein Fehler darf nicht still bleiben - der Nutzer soll wissen, '
            'dass seine Aufstellung gerade nicht laeuft.',
      );
    });
  });
}
