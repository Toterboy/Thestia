// Render-Tests fuer die neuen Bildschirme (30.10.2026).
//
// ANLASS: Beim Wischen zwischen den Haupt-Reitern ist die App
// abgestuerzt - "A SingleTickerProviderStateMixin can only be used as
// a TickerProvider once". Gefunden hat das der UI-Vorschau-Test, also
// zufaellig. Ein Bildschirm, den niemand gerendert hat, ist geraten.
//
// Deshalb pumpen diese Tests die beiden neuen Bildschirme wirklich:
//   * "Connect to others" (Telefon & Social Media),
//   * die Sicherheits-Aufklaerung (alle Schritte).
//
// Geprueft wird nicht nur "kein Absturz", sondern auch: kein
// Render-Overflow, die erwarteten Texte stehen da, und die Schritte
// lassen sich durchklicken.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/models/contact_share_profile.dart';
import 'package:thestia/providers/contact_share_provider.dart';
import 'package:thestia/screens/onboarding/dating_safety_education_screen.dart';
import 'package:thestia/screens/qr/contact_share_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_contact_share_store.dart';

/// In-Memory-Implementierung von [LocalStorage] fuer Tests.
class _FakeStorage implements LocalStorage {
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

/// Kontakt-Store ohne Keystore: haelt den Stand nur im RAM.
class _FakeContactStore extends SecureContactShareStore {
  _FakeContactStore(this._profil);

  ContactShareProfile _profil;

  @override
  Future<ContactShareProfile> load() async => _profil;

  @override
  Future<void> save(ContactShareProfile profile) async => _profil = profile;

  @override
  Future<void> clear() async => _profil = const ContactShareProfile();
}

Widget _huelle(Widget kind, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: kind,
    ),
  );
}

void main() {
  // Telefon-Display: 390 x 844 dp (Pixel 7 / Pixel 8).
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Connect to others', () {
    testWidgets('rendert den leeren Zustand ohne Absturz',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_huelle(
        const ContactShareScreen(),
        overrides: [
          contactShareStoreProvider
              .overrideWithValue(_FakeContactStore(const ContactShareProfile())),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Der Screen erklaert, was passiert - und dass nichts zum Server geht.
      expect(find.textContaining('Speichere hier'), findsOneWidget);
      expect(find.textContaining('verschlüsselt'), findsWidgets);
      // Die Apps sind als empfohlen/nicht empfohlen gekennzeichnet.
      expect(find.text('nicht empfohlen'), findsNWidgets(3));
    });

    testWidgets('rendert gespeicherte Daten (Telefon + Apps)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const profil = ContactShareProfile(
        phone: '+49 170 1234567',
        entries: [
          ContactShareEntry(
            app: 'signal',
            label: 'Signal',
            handle: '@thorst',
            recommended: true,
          ),
        ],
      );

      await tester.pumpWidget(_huelle(
        const ContactShareScreen(),
        overrides: [
          contactShareStoreProvider
              .overrideWithValue(_FakeContactStore(profil)),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('+49 170 1234567'), findsOneWidget);
      expect(find.text('Signal'), findsOneWidget);
      // Der empfohlene Messenger ist als solcher gekennzeichnet (zwei
      // empfohlene Apps + die Abschnitts-Ueberschrift).
      expect(find.text('empfohlen'), findsNWidgets(3));
    });

    testWidgets('ein eigener Eintrag laesst sich anlegen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_huelle(
        const ContactShareScreen(),
        overrides: [
          contactShareStoreProvider
              .overrideWithValue(_FakeContactStore(const ContactShareProfile())),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Weitere App hinzufügen'), findsOneWidget);
      // Der Knopf steht unter den fuenf App-Kacheln - er ist auf einem
      // Telefon erst nach dem Scrollen erreichbar.
      await tester.ensureVisible(find.text('Weitere App hinzufügen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weitere App hinzufügen'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Die Felder fuer App-Name und Handle erscheinen.
      expect(find.text('App-Name'), findsOneWidget);
      expect(find.text('Name / Handle'), findsWidgets);
    });
  });

  group('Sicherheits-Aufklaerung', () {
    testWidgets('startet mit der Bestaetigungsseite', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_huelle(
        const DatingSafetyEducationScreen(),
        overrides: [localStorageProvider.overrideWithValue(_FakeStorage())],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Bevor du loslegst'), findsOneWidget);
      expect(find.text('Ich habe verstanden'), findsOneWidget);
      // Der Hinweis auf die fuenf Minuten steht da - er ist eine Zusage.
      expect(find.textContaining('5 Minuten'), findsOneWidget);
    });

    testWidgets('fuehrt von der Bestaetigung zur Frage und weiter',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_huelle(
        const DatingSafetyEducationScreen(),
        overrides: [localStorageProvider.overrideWithValue(_FakeStorage())],
      ));
      await tester.pumpAndSettle();

      // Schritt 1: Bestaetigung.
      await tester.tap(find.text('Ich habe verstanden'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Hast du schon einmal eine Dating-App benutzt?'),
          findsOneWidget);

      // Schritt 2: "Nein" -> die Aufklaerung startet.
      await tester.tap(find.text('Nein'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sicher daten'), findsOneWidget);
      expect(find.text('Seite 1 von 5'), findsOneWidget);
      expect(find.text('Nicht alles ist echt'), findsOneWidget);
    });

    testWidgets('die Aufklaerung laesst sich durchblaettern', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_huelle(
        const DatingSafetyEducationScreen(),
        overrides: [localStorageProvider.overrideWithValue(_FakeStorage())],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ich habe verstanden'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nein'));
      await tester.pumpAndSettle();

      // Bis zur letzten Seite weiterblaettern.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Weiter'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      expect(find.text('Seite 5 von 5'), findsOneWidget);
      expect(find.text('Hilfe holen'), findsOneWidget);
      expect(find.text('Fertig'), findsOneWidget);
    });
  });
}
