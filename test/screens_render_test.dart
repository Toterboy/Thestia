// Render-Tests fuer die drei umgebauten Screens (31.10.2026).
//
// ANLASS: Beim Wischen zwischen den Haupt-Reitern ist die App
// abgestuerzt - "A SingleTickerProviderStateMixin can only be used as
// a TickerProvider once". Gefunden hat das der UI-Vorschau-Test, also
// zufaellig. Ein Bildschirm, den niemand gerendert hat, ist geraten.
//
// Diese Tests pumpen die drei Screens WIRKLICH:
//   * Interessen (eingeklappte Blasen, Funken werden weggeschoben),
//   * Profil (Geburtstags-Flaeche ueber die ganze Flaeche),
//   * fremdes Profil (derselbe Geburtstags-Effekt).
//
// Geprueft wird: kein Absturz, kein Render-Overflow, die erwarteten
// Texte stehen da, und das Verhalten stimmt (Blase oeffnet, Funken
// werden nach unten geschoben, Geburtstags-Flaeche ist an/aus).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/mood_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/screens/interests/interessen_screen.dart';
import 'package:thestia/screens/profile/profile_detail_screen.dart';
import 'package:thestia/screens/profile/profile_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/mood_service.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/widgets/birthday_style.dart';

/// In-Memory-Implementierung von [LocalStorage] fuer Tests.
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> saveString(String key, String value) async => _data[key] = value;

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _data[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _data[key] == null ? null : _data[key] == 'true';

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _data[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _data[key] == null ? null : int.tryParse(_data[key]!);
}

/// Keystore ohne Plugin: liefert kein Profil (wie auf einem frischen
/// Geraet).
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String json) async {}

  @override
  Future<void> delete() async {}
}

/// Baut ein Profil mit heutigem Geburtstag.
///
/// [fremd] = true markiert das Profil als "fremd": Dann kommt der
/// Geburtstags-Hinweis aus dem Server-Feld (`birthdayToday`), beim eigenen
/// Profil wird er aus dem Geburtsdatum berechnet.
UserProfile _profilMitGeburtstag({
  String id = 'test-user',
  String name = 'Lena',
  bool fremd = false,
}) {
  final heute = DateTime.now();
  return UserProfile(
    id: id,
    name: name,
    bio: 'Hallo',
    birthDate: DateTime(1995, heute.month, heute.day),
    birthdayStyle: 'rose',
    birthdayToday: fremd,
  );
}

/// Der Dummy-Client, den der Mood-Service braucht.
///
/// Er wird nach jedem Test disposed - sonst bleibt der Auto-Refresh-
/// Timer des Clients stehen und der Test scheitert an "A Timer is
/// still pending".
late supabase.SupabaseClient _moodClient;

List<Override> _overrides(UserProfile profil) {
  final storage = _FakeLocalStorage();
  return [
    localStorageProvider.overrideWithValue(storage),
    secureProfileStoreProvider.overrideWithValue(_FakeSecureProfileStore()),
    profileProvider.overrideWith((ref) {
      final notifier = ProfileNotifier(storage, _FakeSecureProfileStore());
      notifier.setProfile(profil);
      return notifier;
    }),
    // Der Mood-Service greift beim Erzeugen auf den Supabase-Client zu.
    // Im Test gibt es keinen Server - deshalb ein Client, der nichts
    // erreichen kann (der Ladefehler wird vom Notifier abgefangen).
    moodServiceProvider.overrideWithValue(MoodService(_moodClient)),
  ];
}

Future<void> _pump(
  WidgetTester tester,
  Widget kind,
  UserProfile profil, {
  double scale = 1.0,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(profil),
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: kind,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _moodClient = supabase.SupabaseClient(
      'https://example.supabase.co',
      'test-key',
    );
  });

  tearDown(() async {
    // Sonst bleibt der Auto-Refresh-Timer des Clients stehen.
    await _moodClient.dispose();
  });

  group('Interessen-Screen', () {
    testWidgets('rendert mit den beiden geschlossenen Blasen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(tester, const InteressenScreen(), _profilMitGeburtstag());

      expect(tester.takeException(), isNull);
      // Beide Reiter stehen da.
      expect(find.text('Gesendet'), findsOneWidget);
      expect(find.text('Erhalten'), findsOneWidget);
      // Der Funken-Kopf (Symbol + Titel) steht IMMER - er ist nicht
      // Teil der Blasen.
      expect(find.byIcon(Icons.auto_awesome), findsWidgets);
    });

    testWidgets('das Oeffnen schiebt die Funken nach unten',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(tester, const InteressenScreen(), _profilMitGeburtstag());

      final funke = find.byIcon(Icons.auto_awesome).first;
      final vorher = tester.getRect(funke).top;

      // Blase oeffnen.
      await tester.tap(find.text('Erhalten'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final nachher = tester.getRect(find.byIcon(Icons.auto_awesome).first).top;
      expect(nachher, greaterThan(vorher),
          reason: 'Die Funken müssen beim Oeffnen nach unten '
              'geschoben werden');

      // Und wieder schliessen - dann stehen sie wieder oben.
      await tester.tap(find.text('Erhalten'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final zurueck = tester.getRect(find.byIcon(Icons.auto_awesome).first).top;
      expect(zurueck, closeTo(vorher, 1.0));
    });

    testWidgets('der Wechsel zwischen den Blasen funktioniert',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(tester, const InteressenScreen(), _profilMitGeburtstag());

      await tester.tap(find.text('Gesendet'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Erhalten'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Profil-Screen', () {
    testWidgets('zeigt die Geburtstags-Flaeche am Geburtstag',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(tester, const ProfileScreen(), _profilMitGeburtstag());

      expect(tester.takeException(), isNull);
      expect(find.text('Lena'), findsWidgets);

      final flaeche = tester.widget<BirthdayStyleSurface>(
        find.byType(BirthdayStyleSurface).first,
      );
      expect(flaeche.active, isTrue,
          reason: 'Am Geburtstag muss die ganze Flaeche getoent sein');
    });

    testWidgets('ohne Geburtstag bleibt die Flaeche inaktiv',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const profil = UserProfile(id: 'test-user', name: 'Lena', bio: 'Hallo');
      await _pump(tester, const ProfileScreen(), profil);

      expect(tester.takeException(), isNull);
      final flaeche = tester.widget<BirthdayStyleSurface>(
        find.byType(BirthdayStyleSurface).first,
      );
      expect(flaeche.active, isFalse);
    });
  });

  group('Fremdes Profil', () {
    testWidgets('zeigt die Geburtstags-Flaeche am Geburtstag',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(
        tester,
        const ProfileDetailScreen(userId: 'test-user'),
        _profilMitGeburtstag(name: 'Mira', fremd: true),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Mira'), findsWidgets);

      final flaeche = tester.widget<BirthdayStyleSurface>(
        find.byType(BirthdayStyleSurface).first,
      );
      expect(flaeche.active, isTrue);
    });

    testWidgets('zeigt das Mood der anderen Person', (tester) async {
      // NUTZERWUNSCH (31.10.2026): "Fuer Mood gilt das selbe" - die
      // Stimmung des Tages gehoert auch bei fremden Profilen dazu.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final profil = _profilMitGeburtstag(name: 'Mira', fremd: true)
          .copyWith(mood: 'happy');
      await _pump(
        tester,
        const ProfileDetailScreen(userId: 'test-user'),
        profil,
      );

      expect(tester.takeException(), isNull);
      // Das Mood steht als Chip neben dem Typ (NUTZERWUNSCH 31.10.2026:
      // "Fuer Mood gilt das selbe" - die Stimmung ist auch bei fremden
      // Personen sichtbar).
      expect(find.textContaining('Glücklich'), findsOneWidget);
      expect(find.byIcon(Icons.sentiment_very_satisfied), findsWidgets);
    });
  });

  group('Settings-Provider', () {
    test('laesst sich ohne Backend ueberschreiben', () {
      // Der Profil-Screen braucht die Einstellungen (Theme, Blind Mode).
      // Sie kommen aus dem lokalen Speicher - ohne Supabase laeuft das
      // ohne Fehler.
      final container = ProviderContainer(
        overrides: [localStorageProvider.overrideWithValue(_FakeLocalStorage())],
      );
      addTearDown(container.dispose);
      expect(container.read(settingsProvider).blindModeEnabled, isTrue);
    });
  });

  // ---------------------------------------------------------------
  // Accessibility: dieselben drei Screens bei grosser Systemschrift.
  // Android erlaubt bis 3,2x - dort darf nichts ueber den Rand laufen.
  // ---------------------------------------------------------------
  const scales = <String, double>{
    'normal (1.0x)': 1.0,
    'gross (2.0x)': 2.0,
    'maximum (3.2x)': 3.2,
  };

  scales.forEach((name, scale) {
    testWidgets('Interessen rendert ohne Overflow bei Schrift $name',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(
        tester,
        const InteressenScreen(),
        _profilMitGeburtstag(),
        scale: scale,
      );
      // Scrollen bis zum Ende.
      final scroller = find.descendant(
        of: find.byType(InteressenScreen),
        matching: find.byType(Scrollable),
      );
      if (tester.any(scroller)) {
        await tester.fling(scroller.first, const Offset(0, -900), 900);
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });
  });

  scales.forEach((name, scale) {
    testWidgets('Profil rendert ohne Overflow bei Schrift $name',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(tester, const ProfileScreen(), _profilMitGeburtstag(),
          scale: scale);
      final scroller = find.descendant(
        of: find.byType(ProfileScreen),
        matching: find.byType(Scrollable),
      );
      if (tester.any(scroller)) {
        await tester.fling(scroller.first, const Offset(0, -900), 900);
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });
  });

  scales.forEach((name, scale) {
    testWidgets('fremdes Profil rendert ohne Overflow bei Schrift $name',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(
        tester,
        const ProfileDetailScreen(userId: 'test-user'),
        _profilMitGeburtstag(name: 'Mira', fremd: true),
        scale: scale,
      );
      final scroller = find.descendant(
        of: find.byType(ProfileDetailScreen),
        matching: find.byType(Scrollable),
      );
      if (tester.any(scroller)) {
        await tester.fling(scroller.first, const Offset(0, -900), 900);
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });
  });
}
