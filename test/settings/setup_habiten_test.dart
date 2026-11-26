// Die zweite Hälfte der Ersteinrichtung: Gewohnheiten, Geburtstags-Stil,
// Profilbild und die Formular-Zweige.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/screens/onboarding/parts/einrichtungspeichern.dart 66 offene Zeilen
// und für lib/screens/onboarding/parts/einrichtungsaufbau.dart 73 offene
// Zeilen - der Weg vom Formular zum Server war ungetestet.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Gewohnheiten (Rauchen, Alkohol, Drogen) und der Dealbreaker
//     landen beim Server - nicht nur lokal (sonst wären sie nach der
//     Ersteinrichtung wieder weg),
//   * der Geburtstags-Stil landet beim Server,
//   * das Profilbild: ohne Bild-Picker bekommt der Nutzer eine Meldung
//     (sonst passiert gar nichts und der Nutzer wundert sich),
//   * das Land und das Bundesland werden mitgespeichert,
//   * die Altersregeln greifen bei Minderjährigen (Altersspanne und
//     Suchradius werden geklemmt, "Ganz Deutschland" ist gesperrt).
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
// Das Plattform-Interface wird von image_picker exportiert, aber nicht
// weitergereicht - der Test setzt die Attrappe darüber.
// ignore: depend_on_referenced_packages
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/gender.dart';
import 'package:thestia/models/profile/habitude_level.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/providers/settings/user_preferences_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/onboarding/settings_privacy_once_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/utils/common/constants.dart';
import 'package:thestia/widgets/profile/music_taste_widgets.dart';
import 'package:thestia/widgets/settings/habitude_selector.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

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

/// Der Bildauswahl-Ersatz (liefert eine feste Datei).
class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker(this.datei);

  final String datei;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile(datei);
}

/// Der Bildauswahl-Ersatz, der einen Fehler meldet.
///
/// DAS IST DER FEHLFALL: Auf einem Gerät, auf dem die Galerie nicht
/// erreichbar ist, wirft der Bild-Picker. Ohne Meldung an den Nutzer
/// würde er denken, sein Bild sei geladen - und so wäre es nicht.
class _FehlerBildPicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    throw StateError('Die Galerie ist nicht erreichbar.');
  }
}

/// Der Bildauswahl-Ersatz, der abbricht (der Nutzer hat abgebrochen).
class _AbbrecherBildPicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => null;
}

/// Der Zuschneider-Ersatz (liefert dieselbe Datei zurück).
class _FakeCropper extends ImageCropperPlatform {
  _FakeCropper(this.datei);

  final String datei;

  @override
  Future<CroppedFile?> cropImage({
    required String sourcePath,
    int? maxWidth,
    int? maxHeight,
    CropAspectRatio? aspectRatio,
    ImageCompressFormat compressFormat = ImageCompressFormat.jpg,
    int compressQuality = 90,
    List<PlatformUiSettings>? uiSettings,
  }) async => CroppedFile(datei);
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

    // HIVE: die verschlüsselten Schlüssel (Signal-Protokoll) liegen in
    // Hive-Boxen - ohne initialisierten Hive schlägt der Aufbau fehl.
    final tempDir = await Directory.systemTemp.createTemp('thesia_habiten');
    Hive.init(tempDir.path);

    // ANGEMELDET: Ohne Sitzung gibt der Server-Dienst nichts frei
    // ("Nicht eingeloggt") - es würde nichts gespeichert.
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockKeystore();
    // DIE AUFNAHME: die Vorstellung kann mit Stimme aufgenommen werden -
    // ohne den Ersatz wartet der Aufruf endlos.
    mockAufnahme();
    server.schreibvorgaenge.clear();
    server.zeilen.clear();
  });

  /// Baut die Ersteinrichtung und liefert den Container der Provider.
  ///
  /// [geburtsdatum] decides, ob die Altersregeln greifen (ein
  /// Minderjähriger bekommt eine engere Altersspanne und einen kleineren
  /// Suchradius).
  ///
  /// [breite] ist die Breite des Bildschirms. Manche Zeilen brauchen mehr
  /// Platz (das Feld "Bundesland" misst das längste Bundesland).
  Future<ProviderContainer> zeigeEinrichtung(
    WidgetTester tester, {
    DateTime? geburtsdatum,
    double breite = 390,
  }) async {
    await tester.binding.setSurfaceSize(Size(breite, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/einrichtung',
      routes: [
        GoRoute(
          path: '/einrichtung',
          builder: (context, state) => const SettingsPrivacyOnceScreen(),
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
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(
              ref.watch(localStorageProvider),
              ref.watch(secureProfileStoreProvider),
            );
            notifier.setProfile(
              UserProfile(
                id: 'ich',
                name: 'Lena',
                bio: '',
                birthDate: geburtsdatum,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    return ProviderScope.containerOf(
      tester.element(find.byType(SettingsPrivacyOnceScreen)),
    );
  }

  /// Tippt auf "Weiter" und wartet die Seitenanimation ab.
  Future<void> weiter(WidgetTester tester) async {
    await tester.tap(find.text(L10n.tWithoutContext('onb.next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Füllt die Pflichtangaben der Profilseite (Bio und ein Interesse).
  Future<void> fuelleFormular(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextFormField).first,
      'Ich mag lange Spaziergaenge am Fluss.',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Ein Interesse wählen (der Chip liegt unterhalb der Falz).
    final chip = find.widgetWithText(
      FilterChip,
      AppConstants.presetInterests.first,
    );
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Geht zur Profilseite und füllt sie (Bio und ein Interesse).
  Future<void> fuelleProfil(WidgetTester tester) async {
    await weiter(tester);
    await fuelleFormular(tester);
  }

  /// Geht bis zur Gewohnheiten-Seite (Schritt 7 von 10).
  Future<void> geheZuGewohnheiten(WidgetTester tester) async {
    await fuelleProfil(tester);
    await weiter(tester); // Vorstellung
    await weiter(tester); // Geburtstag
    await weiter(tester); // Musik
    await weiter(tester); // Gewohnheiten
  }

  /// Wartet, bis die Server-Anfragen durch sind.
  Future<void> warteAufServer(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Das letzte Profil-Update, das den Schlüssel enthält.
  Map<String, dynamic>? profilUpdateMit(String schluessel) {
    for (final s in server.schreibvorgaenge.reversed) {
      if (s['tabelle'] == 'profiles' && s.containsKey(schluessel)) return s;
    }
    return null;
  }

  /// Das Auswahlfeld (Dropdown) mit dem angegebenen Label.
  Finder dropdownMitLabel(String label) => find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> && w.decoration.labelText == label,
  );

  /// Wählt im Dropdown den gewünschten Wert.
  Future<void> waehleImDropdown<T>(
    WidgetTester tester,
    Finder feld,
    String wert,
  ) async {
    await tester.ensureVisible(feld);
    await tester.pump();
    await tester.tap(feld);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final eintrag = find.widgetWithText(DropdownMenuItem<T>, wert);
    expect(eintrag, findsWidgets, reason: 'Der Wert $wert fehlt im Menue.');
    await tester.tap(eintrag.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Tippt auf den Chip einer Gewohnheit (z. B. "Täglich" beim Rauchen).
  Future<void> tippeGewohnheit(
    WidgetTester tester,
    HabitudeTopic thema,
    HabitudeLevel stufe,
  ) async {
    final wahl = find.byWidgetPredicate(
      (w) => w is HabitudeSelector && w.topic == thema,
    );
    expect(wahl, findsOneWidget, reason: 'Die Auswahl fehlt.');

    final chip = find.descendant(
      of: wahl,
      matching: find.widgetWithText(ChoiceChip, stufe.label),
    );
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Setzt den Bildauswahl-Ersatz (und stellt ihn danach wieder her).
  void setzeBildpicker(ImagePickerPlatform ersatz) {
    final alter = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = ersatz;
    addTearDown(() => ImagePickerPlatform.instance = alter);
  }

  /// Lässt die Entprell-Timer (1,5 s) der Präferenz-Synchronisation
  /// ablaufen - sonst steht am Testende ein offener Timer.
  Future<void> lassTimerLaufen(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
  }

  group('Die Gewohnheiten in der Ersteinrichtung', () {
    testWidgets('Rauchen, Alkohol und Drogen landen beim Server', (
      tester,
    ) async {
      await zeigeEinrichtung(tester);
      await geheZuGewohnheiten(tester);

      await tippeGewohnheit(tester, HabitudeTopic.smoking, HabitudeLevel.daily);
      await tippeGewohnheit(
        tester,
        HabitudeTopic.alcohol,
        HabitudeLevel.occasionally,
      );
      await tippeGewohnheit(tester, HabitudeTopic.drugs, HabitudeLevel.never);

      // "Weiter" auf der Gewohnheiten-Seite speichert die Angaben.
      await weiter(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);

      final update = profilUpdateMit('smoking');
      expect(update, isNotNull, reason: 'Es muss ein Update geben.');
      expect(update!['smoking'], HabitudeLevel.daily.toServer());
      expect(update['alcohol'], HabitudeLevel.occasionally.toServer());
      expect(update['drugs'], HabitudeLevel.never.toServer());
    });

    testWidgets('der Dealbreaker wird mitgespeichert', (tester) async {
      final container = await zeigeEinrichtung(tester);
      await geheZuGewohnheiten(tester);

      // DER SCHALTER: "Dealbreaker: gleicher Konsum".
      final schalter = find.widgetWithText(
        SwitchListTile,
        L10n.tWithoutContext('profile.edit.habitsDealbreaker'),
      );
      await tester.ensureVisible(schalter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(schalter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await weiter(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);

      final update = profilUpdateMit('habits_dealbreaker');
      expect(update, isNotNull, reason: 'Es muss ein Update geben.');
      expect(update!['habits_dealbreaker'], isTrue);
      // Und auch lokal steht der Schalter jetzt an.
      expect(container.read(settingsProvider).habitsDealbreaker, isTrue);
    });

    testWidgets('ohne Angabe werden die Felder geleert', (tester) async {
      await zeigeEinrichtung(tester);
      await geheZuGewohnheiten(tester);

      await weiter(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);

      // Ohne Auswahl wird "keine Angabe" geschrieben - das Feld darf nicht
      // einfach fehlen (der Server würde den alten Wert behalten).
      final update = profilUpdateMit('smoking');
      expect(update, isNotNull, reason: 'Es muss ein Update geben.');
      expect(update!.containsKey('smoking'), isTrue);
      expect(update['smoking'], isNull);
      expect(update['alcohol'], isNull);
      expect(update['drugs'], isNull);
      expect(update['habits_dealbreaker'], isFalse);
    });
  });

  group('Der Geburtstags-Stil in der Ersteinrichtung', () {
    testWidgets('der gewaehlte Stil landet beim Server', (tester) async {
      await zeigeEinrichtung(tester);
      await fuelleProfil(tester);
      await weiter(tester); // Vorstellung
      await weiter(tester); // Geburtstag

      // DER STIL: die großen Kacheln sind eine Zeile mit Chips.
      final chip = find.widgetWithText(
        InkWell,
        L10n.tWithoutContext('birthday.style.midnight'),
      );
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await weiter(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);

      final update = profilUpdateMit('birthday_style');
      expect(update, isNotNull, reason: 'Es muss ein Update geben.');
      expect(update!['birthday_style'], 'midnight');
    });
  });

  group('Das Profilbild in der Ersteinrichtung', () {
    testWidgets('ein Fehler beim Bildwaehlen kommt beim Nutzer an', (
      tester,
    ) async {
      setzeBildpicker(_FehlerBildPicker());

      await zeigeEinrichtung(tester);
      await weiter(tester); // Profilseite

      // DER KNOPF: das Kamerasymbol neben dem Avatar.
      final knopf = find.byTooltip(L10n.tWithoutContext('setup.photoTooltip'));
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);

      // DER NUTZER MUST ES WISSEN: ohne Meldung würde er denken, das
      // Bild wäre geladen - und so wäre es nicht.
      expect(
        find.text(L10n.tWithoutContext('setupp.photoFail')),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass das Bild nicht hochgeladen wurde.',
      );
    });

    testWidgets('ein abgebrochener Dialog bleibt folgenlos', (tester) async {
      setzeBildpicker(_AbbrecherBildPicker());

      await zeigeEinrichtung(tester);
      await weiter(tester); // Profilseite

      final knopf = find.byTooltip(L10n.tWithoutContext('setup.photoTooltip'));
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Der Nutzer hat abgebrochen - das ist kein Fehler, also gibt es
      // auch keine Fehlermeldung. Und es wurde nichts hochgeladen.
      expect(find.byType(SnackBar), findsNothing);
      expect(profilUpdateMit('photos'), isNull);
    });

    testWidgets('das gewaehlte Bild landet beim Server', (tester) async {
      // EIN ECHTES BILD: der Weg liest die Datei wirklich und lässt die
      // Metadaten entfernen - das braucht echte Bilddaten.
      final ordner = Directory.systemTemp.createTempSync('setup_bild');
      final datei = File('${ordner.path}/bild.jpg');
      final bild = img.Image(width: 40, height: 40);
      img.fill(bild, color: img.ColorRgb8(180, 140, 200));
      datei.writeAsBytesSync(img.encodeJpg(bild));
      addTearDown(() {
        try {
          if (ordner.existsSync()) {
            ordner.deleteSync(recursive: true);
          }
        } catch (e) {
          // Der Temp-Ordner wird ohnehin irgendwann vom System geräumt -
          // das Löschen darf den Test aber nicht scheitern lassen.
          debugPrint('Der Temp-Ordner blieb liegen: $e');
        }
      });

      setzeBildpicker(_FakeImagePicker(datei.path));
      final alterCropper = ImageCropperPlatform.instance;
      addTearDown(() => ImageCropperPlatform.instance = alterCropper);
      ImageCropperPlatform.instance = _FakeCropper(datei.path);

      await zeigeEinrichtung(tester);
      await weiter(tester); // Profilseite

      final knopf = find.byTooltip(L10n.tWithoutContext('setup.photoTooltip'));
      await tester.ensureVisible(knopf);
      await tester.pump();

      // DER BILDWEG: er liest die Datei in einem eigenen Isolate - das
      // braucht echte Zeit, nicht die Test-Uhr.
      await tester.runAsync(() async {
        await tester.tap(knopf);
        for (var i = 0; i < 60; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump();
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);

      // DER SERVER: das Bild gehört in profiles.photos.
      final update = profilUpdateMit('photos');
      expect(update, isNotNull, reason: 'Es muss ein Update geben.');
      final bilder = update!['photos'];
      expect(bilder, isA<List<dynamic>>());
      expect((bilder as List<dynamic>).length, 1);
      // Und der Nutzer bekommt die Erfolgsmeldung.
      expect(
        find.text(L10n.tWithoutContext('setupp.photoDone')),
        findsOneWidget,
      );
    });
  });

  group('Die Formular-Zweige der Ersteinrichtung', () {
    testWidgets('das Land und das Bundesland werden gespeichert', (
      tester,
    ) async {
      await zeigeEinrichtung(tester);
      await weiter(tester); // Profilseite

      // DAS LAND: ohne Angabe steht es auf "Deutschland".
      await waehleImDropdown<String>(
        tester,
        dropdownMitLabel(L10n.tWithoutContext('setupp.countryLabel')),
        kSupportedCountries[1],
      );

      // DAS BUNDESLAND: es ist optional, der Wert landet im Profil.
      await waehleImDropdown<String>(
        tester,
        dropdownMitLabel(L10n.tWithoutContext('setupp.stateOptional')),
        kGermanStates[1],
      );

      await fuelleFormular(tester);
      await weiter(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);

      final update = profilUpdateMit('country');
      expect(update, isNotNull, reason: 'Es muss ein Update geben.');
      expect(update!['country'], kSupportedCountries[1]);
      expect(update['state'], kGermanStates[1]);
    });

    testWidgets('ein abgewahltes Interesse wird nicht gespeichert', (
      tester,
    ) async {
      await zeigeEinrichtung(tester);
      await weiter(tester); // Profilseite

      // DIE BIO: ohne sie darf der Schritt nicht weitergehen (und dann
      // wird auch nichts gespeichert).
      await tester.enterText(
        find.byType(TextFormField).first,
        'Ich mag lange Spaziergaenge am Fluss.',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // ZWEI INTERESSEN WÄHLEN ...
      for (final interesse in AppConstants.presetInterests.take(2)) {
        final chip = find.widgetWithText(FilterChip, interesse);
        await tester.ensureVisible(chip);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(chip);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      // ... UND EINES WIEDER ABWÄHLEN.
      final chip = find.widgetWithText(
        FilterChip,
        AppConstants.presetInterests[1],
      );
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await weiter(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);

      final update = profilUpdateMit('interests');
      expect(update, isNotNull, reason: 'Es muss ein Update geben.');
      expect(update!['interests'], <String>[
        AppConstants.presetInterests.first,
      ]);
    });
  });

  group('Die Altersregeln in der Ersteinrichtung', () {
    testWidgets('bei Minderjaehrigen werden Spanne und Radius geklemmt', (
      tester,
    ) async {
      // EIN MINDERJÄHRIGER: 16 Jahre alt.
      final container = await zeigeEinrichtung(
        tester,
        geburtsdatum: DateTime(DateTime.now().year - 16, 5, 4),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // DIE ALTERSSPANNE: 18-65 passt nicht zu einem 16-Jährigen - der
      // Server liefert für Minderjährige nur 16 und 17. Der gespeicherte
      // Stand wird deshalb auf den erlaubten Bereich geklemmt.
      final settings = container.read(settingsProvider);
      expect(settings.ageRangeMin, 17);
      expect(settings.ageRangeMax, 17);

      // DER SUCHRADIUS: höchstens 25 km.
      expect(
        container.read(userPreferencesProvider).maxDistanceKm,
        25,
        reason:
            'Ein Minderjaehriger darf nicht weiter als 25 km suchen - der '
            'Server wuerde den Filter ohnehin kippen.',
      );

      // DER HINWEIS: der Nutzer soll wissen, warum der Radius so klein ist.
      expect(
        find.text(L10n.tWithoutContext('setupp.radiusMinorHint')),
        findsOneWidget,
      );

      await lassTimerLaufen(tester);
    });

    testWidgets('bei Minderjaehrigen ist "Ganz Deutschland" gesperrt', (
      tester,
    ) async {
      await zeigeEinrichtung(
        tester,
        geburtsdatum: DateTime(DateTime.now().year - 16, 5, 4),
      );

      // DAS MENÜ: der Modus "Ganz Deutschland" ist ausgegraut.
      final auswahl = find.byType(DropdownButtonFormField<DistanceFilterMode>);
      await tester.ensureVisible(auswahl.first);
      await tester.pump();
      await tester.tap(auswahl.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final eintrag = find.widgetWithText(
        DropdownMenuItem<DistanceFilterMode>,
        DistanceFilterMode.germany.label,
      );
      expect(eintrag, findsWidgets, reason: 'Der Modus fehlt im Menue.');
      final element = tester.widget<DropdownMenuItem<DistanceFilterMode>>(
        eintrag.last,
      );
      expect(
        element.enabled,
        isFalse,
        reason:
            'Ein Minderjaehriger darf nicht "Ganz Deutschland" waehlen - der '
            'Server wuerde den Filter ohnehin auf 25 km setzen.',
      );

      await lassTimerLaufen(tester);
    });

    testWidgets('der Modus "Ganz Deutschland" wird zurueckgesetzt', (
      tester,
    ) async {
      final container = await zeigeEinrichtung(
        tester,
        geburtsdatum: DateTime(DateTime.now().year - 16, 5, 4),
      );

      // DER VORGESTELLTE STAND: ein gepatchter Client hat "Ganz
      // Deutschland" gesetzt - der Bildschirm muss das zurücknehmen.
      await container
          .read(userPreferencesProvider.notifier)
          .setDistanceFilterMode(DistanceFilterMode.germany);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        container.read(userPreferencesProvider).distanceFilterMode,
        DistanceFilterMode.distanceKm,
        reason:
            'Der Modus "Ganz Deutschland" muss bei Minderjaehrigen auf die '
            'Entfernung zurueckfallen.',
      );

      await lassTimerLaufen(tester);
    });
  });

  group('Die weiteren Schritte der Ersteinrichtung', () {
    testWidgets('der Vorstellungstext landet beim Server', (tester) async {
      await zeigeEinrichtung(tester);
      await fuelleProfil(tester);
      await weiter(tester); // Vorstellung

      await tester.enterText(
        find.byType(TextFormField).first,
        'Ich bin gern draussen unterwegs.',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await weiter(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);

      final update = profilUpdateMit('intro_text');
      expect(update, isNotNull, reason: 'Es muss ein Update geben.');
      expect(update!['intro_text'], 'Ich bin gern draussen unterwegs.');
    });

    testWidgets('der Musik-Geschmack landet beim Server', (tester) async {
      await zeigeEinrichtung(tester);
      await fuelleProfil(tester);
      await weiter(tester); // Vorstellung
      await weiter(tester); // Geburtstag
      await weiter(tester); // Musik

      // EIN GENRE: die Chips stehen für die "mag ich"-Liste.
      final chip = find.widgetWithText(FilterChip, kMusicGenres.first.label);
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // LIEBLINGSSONG UND -BAND: die beiden Textfelder der Musik-Seite.
      await tester.enterText(
        find.byType(TextFormField).first,
        'Atemlos durch die Nacht',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'Von Tag zu Nacht',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await weiter(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);

      final update = profilUpdateMit('music_liked');
      expect(update, isNotNull, reason: 'Es muss ein Update geben.');
      expect(update!['music_liked'], contains(kMusicGenres.first.slug));
      expect(update['favorite_song'], 'Atemlos durch die Nacht');
      expect(update['favorite_band'], 'Von Tag zu Nacht');
    });

    testWidgets('die Beziehungsform wird gespeichert', (tester) async {
      final container = await zeigeEinrichtung(tester);

      await waehleImDropdown<RelationshipType>(
        tester,
        find.byType(DropdownButtonFormField<RelationshipType>).first,
        L10n.tWithoutContext('profile.edit.rel.dating'),
      );

      expect(
        container.read(userPreferencesProvider).relationshipType,
        RelationshipType.dating,
        reason: 'Die Beziehungsform gehoert zum Profil des Nutzers.',
      );

      await lassTimerLaufen(tester);
    });

    testWidgets('das Filter "Bundesland" fragt das Bundesland ab', (
      tester,
    ) async {
      // DER BREITER BILDSCHIRM: das Feld "Bundesland" misst das längste
      // Bundesland ("Nordrhein-Westfalen") - auf einem schmalen Gerät
      // läuft der Text dabei aus dem Rahmen. Für diesen Weg zählt nur,
      // dass die Auswahl da ist und der Wert ankommt.
      await zeigeEinrichtung(tester, breite: 520);

      // DER MODUS: "Bundesland" statt "Entfernung".
      await waehleImDropdown<DistanceFilterMode>(
        tester,
        find.byType(DropdownButtonFormField<DistanceFilterMode>).first,
        DistanceFilterMode.state.label,
      );

      // JETZT gibt es die Bundesland-Auswahl (statt des Schiebers).
      final auswahl = dropdownMitLabel(
        L10n.tWithoutContext('setupp.stateLabel'),
      );
      expect(auswahl, findsOneWidget);

      await waehleImDropdown<String>(tester, auswahl, kGermanStates[2]);

      expect(
        tester.widget<DropdownButtonFormField<String>>(auswahl).initialValue,
        kGermanStates[2],
      );

      await lassTimerLaufen(tester);
    });

    testWidgets('das Bundesland-Feld laeuft auf einem schmalen Bildschirm '
        'nicht aus dem Rahmen', (tester) async {
      // DER SCHMALE BILDSCHIRM: 390 Pixel (der Normalfall).
      //
      // BEFUND (24.11.2026): Ohne "isExpanded" lief das Feld um 41 Pixel
      // aus dem Rahmen (der Text des längsten Bundeslands). Die beiden
      // anderen Dropdowns derselben Seite hatten es - dieses nicht.
      await zeigeEinrichtung(tester);

      await waehleImDropdown<DistanceFilterMode>(
        tester,
        find.byType(DropdownButtonFormField<DistanceFilterMode>).first,
        DistanceFilterMode.state.label,
      );

      // JETZT gibt es die Bundesland-Auswahl.
      final auswahl = dropdownMitLabel(
        L10n.tWithoutContext('setupp.stateLabel'),
      );
      expect(auswahl, findsOneWidget);

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Das Feld muss auf einem normalen Bildschirm passen - sonst '
            'sieht der Nutzer einen abgeschnittenen Text.',
      );

      await lassTimerLaufen(tester);
    });

    testWidgets('der Modus "Ganz Deutschland" erklaert sich', (tester) async {
      await zeigeEinrichtung(tester);

      await waehleImDropdown<DistanceFilterMode>(
        tester,
        find.byType(DropdownButtonFormField<DistanceFilterMode>).first,
        DistanceFilterMode.germany.label,
      );

      // DER HINWEIS: der Nutzer soll wissen, was dieser Modus bedeutet.
      expect(
        find.text(L10n.tWithoutContext('setupp.germanyNote')),
        findsOneWidget,
      );

      await lassTimerLaufen(tester);
    });
  });
}
