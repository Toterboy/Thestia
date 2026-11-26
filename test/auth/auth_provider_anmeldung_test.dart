// Der Auth-Anbieter: Registrieren, Anmelden, Abmelden.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte für
// lib/providers/auth/auth_provider.dart 109 offene Zeilen - darunter
// die Registrierung und die Anmeldung.
//
// DER GRUND: Der Anbieter ist die Quelle der Wahrheit für "wer ist
// angemeldet". Drei Dinge sind dort heikel:
//   * nach der Registrierung merkt er sich die E-Mail-Adresse UND das
//     Passwort - nur im Speicher, für den stillen Auto-Login nach der
//     Bestätigung. Vergisst er das, bleibt der Nutzer auf dem
//     Bestätigungs-Screen hängen,
//   * nach der Anmeldung räumt er die Merkliste wieder auf (das
//     Passwort darf nicht liegen bleiben),
//   * ein Fehler muss als Fehler ankommen - nicht als "nicht
//     angemeldet" (dann würde der Nutzer denkt, sein Konto sei weg).
//
// WAS HIER GEPRÜFT WIRD:
//   * die Registrierung merkt sich Adresse und Passwort (nur im Speicher),
//   * die Registrierung setzt das Profil,
//   * ein Registrierungsfehler wird als Fehler gemeldet,
//   * nach der Anmeldung sind die Merkdaten weg,
//   * das Abmelden meldet "nicht angemeldet".
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/providers/auth/auth_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/services/auth/auth_exception.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/plugin_mocks.dart';
import '../support/router_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    mockKeystore();
    mockZeitzone();
    // HIVE: Das Abmelden räumt die verschlüsselten Boxen auf - ohne
    // initialisierten Hive scheitert es.
    await mockHive();
  });

  /// Baut den Container mit dem Auth-Anbieter.
  ///
  /// DER WEG: Die Wiederherstellung läuft im Hintergrund und setzt
  /// danach den Status - wenn der Test sofort danach anmeldet, wird
  /// sein Ergebnis gleich wieder überschrieben. Der Test wartet sie
  /// deshalb ab.
  Future<ProviderContainer> baueContainer(TestAuth auth) async {
    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(TestSpeicher()),
        secureProfileStoreProvider.overrideWithValue(TestKeystore()),
        settingsProvider.overrideWith((ref) => TestEinstellungen(ref)),
        profileProvider.overrideWith((ref) => TestProfil()),
        authProvider.overrideWith(
          (ref) => AuthNotifier(auth, ref.read(profileProvider.notifier), ref),
        ),
      ],
    );
    addTearDown(container.dispose);
    // DER ANBIETER: Er wird jetzt erzeugt (sonst entstünde er erst im
    // Test und die Wiederherstellung liefe danach).
    container.read(authProvider.notifier);
    // Und die Wiederherstellung wird abgewartet - sonst setzt sie den
    // Status gleich wieder auf "nicht angemeldet".
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return container;
  }

  group('Der Auth-Anbieter', () {
    test('die Registrierung merkt sich Adresse und Passwort', () async {
      final container = await baueContainer(TestAuth(eingeloggt: false));

      await container
          .read(authProvider.notifier)
          .register(
            name: 'Lena',
            email: 'lena@example.de',
            password: 'Passwort123!',
            gender: 'female',
            birthDate: DateTime(1996, 6, 15),
          );
      // DER SYNC: Nach der Registrierung läuft der Abgleich mit dem
      // Server im Hintergrund. Der Test wartet ihn ab - sonst läuft er
      // nach dem Abbau des Containers weiter.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        container.read(pendingVerificationEmailProvider),
        'lena@example.de',
        reason:
            'Die Adresse muss gemerkt sein - sonst kann die App die '
            'Bestaetigungs-Mail nicht erneut senden.',
      );
      final merkliste = container.read(pendingVerificationCredentialsProvider);
      expect(merkliste, isNotNull);
      expect(merkliste!.email, 'lena@example.de');
      expect(
        merkliste.password,
        'Passwort123!',
        reason:
            'Das Passwort wird nur im Speicher gemerkt - damit sich die '
            'App nach der Bestaetigung selbst anmelden kann.',
      );
      expect(container.read(authProvider).valueOrNull, isTrue);
    });

    test('die Registrierung setzt das Profil', () async {
      final container = await baueContainer(TestAuth(eingeloggt: false));

      await container
          .read(authProvider.notifier)
          .register(
            name: 'Lena',
            email: 'lena@example.de',
            password: 'Passwort123!',
            gender: 'female',
            birthDate: DateTime(1996, 6, 15),
          );

      final profil = container.read(profileProvider);
      expect(profil.name, 'Lena');
      expect(profil.id, 'ich');
    });

    test('ein Registrierungsfehler wird als Fehler gemeldet', () async {
      final container = await baueContainer(
        TestAuth(
          eingeloggt: false,
          registrierungsFehler: StateError('Die E-Mail ist gesperrt.'),
        ),
      );

      // DER FEHLER WIRD DURCHGEREICHT: der Anbieter setzt den Zustand
      // auf "Fehler" UND wirft weiter - so zeigt die Oberfläche die
      // Meldung an.
      await expectLater(
        container
            .read(authProvider.notifier)
            .register(
              name: 'Lena',
              email: 'gesperrt@example.de',
              password: 'Passwort123!',
              gender: 'female',
              birthDate: DateTime(1996, 6, 15),
            ),
        throwsStateError,
      );

      expect(
        container.read(authProvider).hasError,
        isTrue,
        reason:
            'Ein Fehler muss als Fehler ankommen - sonst glaubt der '
            'Nutzer, die Registrierung sei geglueckt.',
      );
      expect(
        container.read(pendingVerificationEmailProvider),
        isNull,
        reason:
            'Nach einem Fehler darf keine Merkliste entstehen - der '
            'Nutzer hat ja kein Konto.',
      );
    });

    test('nach der Anmeldung sind die Merkdaten weg', () async {
      final container = await baueContainer(TestAuth(eingeloggt: false));

      // Erst merken (wie nach der Registrierung), dann anmelden.
      container.read(pendingVerificationEmailProvider.notifier).state =
          'lena@example.de';
      container.read(pendingVerificationCredentialsProvider.notifier).state = (
        email: 'lena@example.de',
        password: 'Passwort123!',
        createdAt: DateTime.now(),
        name: 'Lena',
        gender: 'female',
        birthDate: DateTime(1996, 6, 15),
      );

      await container
          .read(authProvider.notifier)
          .login(email: 'lena@example.de', password: 'Passwort123!');

      expect(
        container.read(pendingVerificationEmailProvider),
        isNull,
        reason:
            'Nach der Anmeldung darf die Adresse nicht mehr gemerkt sein - '
            'der Nutzer ist angemeldet.',
      );
      expect(
        container.read(pendingVerificationCredentialsProvider),
        isNull,
        reason:
            'Das Passwort darf nach der Anmeldung nicht mehr im Speicher '
            'liegen.',
      );
      expect(container.read(authProvider).valueOrNull, isTrue);
    });

    test('ein Anmeldefehler wird als Fehler gemeldet', () async {
      final container = await baueContainer(
        TestAuth(
          eingeloggt: false,
          anmeldeFehler: AppException('E-Mail oder Passwort ist falsch.'),
        ),
      );

      await expectLater(
        container
            .read(authProvider.notifier)
            .login(email: 'lena@example.de', password: 'falsch'),
        throwsA(isA<AppException>()),
      );

      expect(
        container.read(authProvider).hasError,
        isTrue,
        reason:
            'Ein Anmeldefehler muss als Fehler ankommen - sonst landet '
            'der Nutzer wieder auf dem Login und weiss nicht warum.',
      );
    });

    test('das Abmelden meldet "nicht angemeldet"', () async {
      final container = await baueContainer(TestAuth());

      await container.read(authProvider.notifier).logout();

      expect(
        container.read(authProvider).valueOrNull,
        isFalse,
        reason:
            'Nach dem Abmelden muss der Status "nicht angemeldet" sein - '
            'sonst waere der Router auf der Startseite und der Nutzer '
            'koennte die Chats der anderen noch sehen.',
      );
    });
  });
}
