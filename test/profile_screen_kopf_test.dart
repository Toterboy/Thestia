// Die Kopfangaben des eigenen Profils.
//
// ANLASS (19.11.2026): `lib/screens/profile/profile_screen.dart` war nur
// zu 48 % abgedeckt. Die Kopfzeile ist das, was der Nutzer zuerst
// sieht: Alter, Geschlecht, Bundesland. Ein Fehler dort ist sofort
// sichtbar - und die Zeile stand frueher doppelt im File (einmal mit
// dem Ort, einmal mit dem Bundesland), was zu zwei verschiedenen
// Anzeigen fuehren konnte.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Kopfzeile nennt Alter, Geschlecht und Bundesland,
//   * ohne Bundesland endet die Zeile nicht mit einem Trennzeichen,
//   * ein unbekanntes Geschlecht macht die Zeile nicht kaputt,
//   * der Persoenlichkeitstyp steht als Chip da,
//   * ohne Namen steht "Unbekannt" (nicht eine leere Zeile).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/gender.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/screens/profile/profile_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

/// Der Speicher im RAM.
class _FakeLocalStorage implements LocalStorage {
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

/// Der Keystore ohne Plugin (das Profil wird nicht gesichert).
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Das eigene Profil im Test (alles anpassbar).
UserProfile _profil({
  String name = 'Lena',
  String? gender = 'female',
  String? state,
  String? personalityType,
  int? alter = 30,
}) {
  return UserProfile(
    id: 'ich',
    name: name,
    bio: 'Hallo',
    birthDate: alter == null
        ? null
        : DateTime.now().subtract(Duration(days: alter * 365)),
    gender: gender,
    state: state,
    personalityType: personalityType,
  );
}

void main() {
  setUpAll(() async {
    // DER SPEICHER DES GERAETS: der Auth-Client holt sich daraus die
    // Sitzung - ohne den Mock schlaegt der Aufbau fehl.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    // Der Supabase-Client wird genau einmal fuer die ganze Datei
    // aufgesetzt: die Stimmungskarte des Profils liest ihn.
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: FakeSupabaseServer(userId: 'ich'),
      authOptions: const supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
        persistSession: false,
        autoRefreshToken: false,
      ),
    );
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockKeystore();
  });

  Future<ProviderContainer> zeigeScreen(
    WidgetTester tester,
    UserProfile profil,
  ) async {
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
          notifier.setProfile(profil);
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
            notifier.setProfile(profil);
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

  /// Die Kopfzeile (Alter, Geschlecht, Bundesland).
  String kopfzeile(WidgetTester tester) {
    final texte = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>();
    // Die Zeile ist die mit dem Alter (oder dem Hinweis "unbekannt").
    for (final t in texte) {
      if (t.contains(L10n.tWithoutContext('profile.years'))) return t;
      if (t.contains(L10n.tWithoutContext('profile.ageUnknown'))) return t;
    }
    return '';
  }

  group('Die Kopfzeile', () {
    testWidgets('nennt Alter, Geschlecht und Bundesland', (tester) async {
      await zeigeScreen(tester, _profil(gender: 'female', state: 'Hamburg'));

      final zeile = kopfzeile(tester);
      expect(zeile, isNotEmpty);
      // Das Alter rechnet der Screen aus dem Geburtsdatum - der Test
      // rechnet mit derselben Quelle (sonst waere "30" gegen "29" der
      // Fehler, nicht der Bildschirm).
      expect(zeile, contains('${_profil().age}'));
      expect(
        zeile,
        contains(L10n.tWithoutContext(Gender.female.labelKey)),
        reason: 'Das Geschlecht muss in der Kopfzeile stehen.',
      );
      expect(zeile, contains('Hamburg'));
    });

    testWidgets('ohne Bundesland endet sie nicht mit einem Trennzeichen', (
      tester,
    ) async {
      await zeigeScreen(tester, _profil(state: null));

      final zeile = kopfzeile(tester);
      expect(zeile, isNotEmpty);
      expect(
        zeile.trim(),
        isNot(endsWith('·')),
        reason:
            'Ohne Bundesland darf die Zeile nicht mit dem Trennzeichen '
            'enden - das sieht kaputt aus.',
      );
    });

    testWidgets('mit leerem Bundesland auch nicht', (tester) async {
      await zeigeScreen(tester, _profil(state: '   '));

      final zeile = kopfzeile(tester);
      expect(zeile.trim(), isNot(endsWith('·')));
    });

    testWidgets('ein unbekanntes Geschlecht bricht die Zeile nicht', (
      tester,
    ) async {
      await zeigeScreen(tester, _profil(gender: 'unbekannt'));

      expect(tester.takeException(), isNull);
      final zeile = kopfzeile(tester);
      expect(zeile, isNotEmpty);
      expect(
        zeile,
        isNot(contains('unbekannt')),
        reason: 'Ein unbekannter Wert darf nicht als Text erscheinen.',
      );
    });

    testWidgets('ohne Alter steht "unbekannt"', (tester) async {
      await zeigeScreen(tester, _profil(alter: null));

      final zeile = kopfzeile(tester);
      expect(zeile, contains(L10n.tWithoutContext('profile.ageUnknown')));
    });
  });

  group('Der Persoenlichkeitstyp', () {
    testWidgets('steht als Chip da', (tester) async {
      await zeigeScreen(tester, _profil(personalityType: 'ENFP'));

      expect(
        find.textContaining('ENFP'),
        findsWidgets,
        reason: 'Der Persoenlichkeitstyp muss sichtbar sein.',
      );
      expect(find.byType(Chip), findsWidgets);
    });

    testWidgets('ohne Typ steht kein Chip', (tester) async {
      await zeigeScreen(tester, _profil());

      expect(find.textContaining('ENFP'), findsNothing);
    });
  });

  group('Der Name', () {
    testWidgets('ohne Namen steht "Unbekannt"', (tester) async {
      await zeigeScreen(tester, _profil(name: ''));

      expect(
        find.text(L10n.tWithoutContext('profile.unknown')),
        findsWidgets,
        reason:
            'Ein leerer Name sieht kaputt aus - lieber "Unbekannt" als eine '
            'leere Zeile.',
      );
    });
  });

  group('Die Knöpfe der Kopfzeile', () {
    testWidgets('QR-Profil und Einstellungen stehen da', (tester) async {
      await zeigeScreen(tester, _profil());

      expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });
  });
}
