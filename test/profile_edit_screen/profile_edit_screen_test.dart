// Die Tests 'profile_edit_screen' (Teil 1).
//
// DER WEG: Die Testdatei war zu lang (> 1000 Zeilen). Die Tests
// sind nach Themen aufgeteilt; die Helfer liegen in
// test/support/profile_edit_screen_hilfen.dart.

// Widget-Tests fuer den Profil-Editor ("Profil bearbeiten").
//
// ANLASS: Die Coverage-Messung (13.11.2026) zeigte fuer
// lib/screens/profile/profile_edit_screen.dart 583 offene Zeilen. Der
// Screen ist die einzige Stelle, an der der Nutzer sein Profil
// aendert - und der Betreiber hat dort im November 2026 gemeldet:
// "Wenn man Buttons auswählt, z. B. in den Profileinstellungen, sollen
// sie sich nicht in die nächste Zeile durch auswählen verschieben."
//
// WAS HIER GEPRUEFT WIRD:
//   * der Screen zeigt die Werte des Profils,
//   * der Zurück-Knopf fragt nach ungespeicherten Änderungen
//     ("Speichern?"-Nachfrage) und bietet Speichern/Verwerfen/Abbrechen,
//   * "Speichern" meldet Erfolg, ein Serverfehler wird gemeldet,
//   * ein ungültiges Formular wird abgewiesen (mit Hinweis),
//   * die Chips (Interessen, Gesundheit, Musik) springen beim Auswählen
//     NICHT in die nächste Zeile (StableChip) - und die Auswahl wird
//     übernommen.
//
// OHNE SERVER: Der Supabase-Client bekommt einen [FakeSupabaseServer].
// Damit kann der Test den Erfolgsfall UND den Fehlerfall stellen,
// ohne Netz und ohne Wartezeit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Das Plattform-Interface wird von permission_handler exportiert, aber
// nicht weitergereicht - der Test setzt die Attrappe darueber.
// ignore: depend_on_referenced_packages
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/screens/profile/profile_edit_screen.dart';
import 'package:thestia/services/location_check_service.dart';
import 'package:thestia/utils/location_privacy.dart';
import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

import 'hilfen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();

    // Der Supabase-Client zeigt auf den Fake-Server: es geht KEINE
    // Anfrage raus. Der Client wird nur EINMAL initialisiert (das ist
    // eine globale Singleton-Variable) - deshalb hier und nicht im Test.
    server = FakeSupabaseServer(userId: 'ich');
    // DER PFAD-KANAL: sonst ruft der Test auf dem CI-Runner
    // das echte Plugin (das findet dort kein XDG-Verzeichnis).
    await mockPfadProvider();
    // DER KEYSTORE: dasselbe Spiel - auf dem Linux-Runner
    // gibt es keine libsecret-Sitzung.
    mockKeystore();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
      ),
    );
    // Angemeldet sein: ohne Konto darf die App nicht schreiben
    // ("Nicht eingeloggt").
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Jeder Test startet mit einem gesunden Server.
    server.antwortetMitFehler = false;
    server.rpcAntworten.clear();
    server.zeilen.clear();
    server.schreibvorgaenge.clear();
    // Die Berechtigungen: ohne diesen Ersatz ruft der Bildschirm das
    // echte Plugin (im Test gibt es das nicht).
    PermissionHandlerPlatform.instance = ProfileEditScreenBerechtigungen();
  });
  group('Der Einspruch gegen ein Foto', () {
    testWidgets('eine Freigabe fragt nach, ob das Bild uebernommen wird', (
      tester,
    ) async {
      server.rpcAntworten['get_my_photo_appeal'] = <String, dynamic>{
        'id': 'appeal-1',
        'status': 'approved',
        'storagePath': 'einspruch/foto.jpg',
      };

      await profileEditScreenPump(tester, profileEditScreenProfil);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('profile.appeal.approvedTitle')),
        findsOneWidget,
        reason:
            'Nach der Freigabe muss der Nutzer entscheiden, ob das Bild '
            'sein Profilfoto wird.',
      );
    });

    testWidgets('eine Ablehnung wird erklaert und quittiert', (tester) async {
      server.rpcAntworten['get_my_photo_appeal'] = <String, dynamic>{
        'id': 'appeal-2',
        'status': 'rejected',
        'storagePath': 'einspruch/foto.jpg',
      };

      await profileEditScreenPump(tester, profileEditScreenProfil);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('profile.appeal.rejectedTitle')),
        findsOneWidget,
        reason:
            'Eine Ablehnung muss der Nutzer kennen - sonst wartet er '
            'unendlich auf eine Entscheidung.',
      );

      // Der Dialog wartet, bis der Nutzer ihn wegklickt - erst DANACH
      // wird die Entscheidung quittiert.
      final ok = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('profile.appeal.okBtn'),
      );
      expect(ok, findsOneWidget);
      await tester.tap(ok);
      await pumpFrames(tester);
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pump(const Duration(milliseconds: 120));
      }

      // Und die Entscheidung wird quittiert - sonst kommt der Dialog
      // bei jedem Oeffnen wieder.
      expect(
        server.pfade.any((p) => p.contains('acknowledge_photo_appeal')),
        isTrue,
        reason: 'Die Entscheidung muss dem Server gemeldet werden.',
      );
    });
  });
  group('Die Altersregeln im Formular', () {
    testWidgets('ein zu grosser Suchradius wird korrigiert', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Minderjaehrig (16) - fuer sie ist der Suchradius auf 25 km
      // begrenzt. Gespeichert war aber "ganz Deutschland" mit 200 km.
      final profil = UserProfile(
        id: 'ich',
        name: 'Lena',
        bio: 'Hallo',
        birthDate: DateTime(2010, 6, 15),
        interests: const <String>['Musik'],
      );
      final container = await profileEditScreenPump(
        tester,
        profil,
        gespeicherteEinstellungen: const {
          'maxDistanceKm': 200,
          'distanceFilterMode': 'germany',
        },
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Die gespeicherten Werte muessen auf die Regel geklemmt werden -
      // sonst zeigt die App mehr, als der Server erlaubt (der Server
      // begrenzt es serverseitig auf 25 km).
      final prefs = container.read(userPreferencesProvider);
      expect(
        prefs.maxDistanceKm,
        25,
        reason:
            'Der Suchradius muss auf 25 km geklemmt werden - der Server '
            'laesst fuer Minderjaehrige nichts groesseres zu.',
      );
      expect(prefs.distanceFilterMode, DistanceFilterMode.distanceKm);

      // Der entprellte Server-Sync muss abgelaufen sein, sonst steht am
      // Ende ein Timer.
      await aufraeumen(tester);
    });
  });
  group('Profil bearbeiten', () {
    testWidgets('zeigt die Werte des Profils', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await profileEditScreenPump(tester, profileEditScreenProfil);

      expect(tester.takeException(), isNull);
      expect(find.text('Profil bearbeiten'), findsOneWidget);
      // Der Name steht im Feld ...
      expect(find.text('Lena'), findsOneWidget);
      // ... und die Bio auch.
      expect(find.text('Hallo aus Hamburg'), findsOneWidget);

      await aufraeumen(tester);
    });

    testWidgets('der Zurück-Knopf fragt nach ungespeicherten Änderungen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
      );

      // Der Name aendern - das Feld ist das erste TextFormular.
      await tester.enterText(find.byType(TextFormField).first, 'Lena Neu');
      await pumpFrames(tester);
      expect(container.read(profileEditDirtyProvider), isTrue);

      // Der Zurück-Knopf fragt nach.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Ungespeicherte Änderungen'), findsOneWidget);
      // Alle drei Wege stehen da: Speichern, Verwerfen, Abbrechen.
      expect(imDialog('Speichern'), findsOneWidget);
      expect(imDialog('Verwerfen'), findsOneWidget);
      expect(imDialog('Abbrechen'), findsOneWidget);

      await aufraeumen(tester);
    });

    testWidgets('"Verwerfen" lässt die Änderung fallen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
      );

      await tester.enterText(find.byType(TextFormField).first, 'Lena Neu');
      await pumpFrames(tester);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await pumpFrames(tester);
      await tester.tap(imDialog('Verwerfen'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Das Profil ist unveraendert ...
      expect(container.read(profileProvider).name, 'Lena');
      // ... der Dirty-Flag ist zurueckgesetzt ...
      expect(container.read(profileEditDirtyProvider), isFalse);
      // ... und der Screen ist verlassen.
      expect(find.text('Mein Profil'), findsOneWidget);

      await aufraeumen(tester);
    });

    testWidgets('"Speichern" im Dialog speichert das Profil', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
      );

      await tester.enterText(find.byType(TextFormField).first, 'Lena Neu');
      await pumpFrames(tester);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await pumpFrames(tester);
      await tester.tap(imDialog('Speichern'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der neue Name steht im Profil ...
      expect(container.read(profileProvider).name, 'Lena Neu');
      // ... der Dirty-Flag ist zurueck ...
      expect(container.read(profileEditDirtyProvider), isFalse);
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(find.text('Profil gespeichert'), findsOneWidget);

      await aufraeumen(tester);
    });

    testWidgets('der Speichern-Knopf meldet einen Serverfehler', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
      );

      await tester.enterText(find.byType(TextFormField).first, 'Lena Neu');
      await pumpFrames(tester);
      await scrolleZumSpeichern(tester);

      // Der Server schweigt ab jetzt.
      server.antwortetMitFehler = true;

      await tester.tap(find.text('Speichern').last);
      // Die Verifikation wiederholt dreimal (mit Wartezeit) - die
      // Meldung kommt erst danach.
      final gemeldet = await warteAuf(
        tester,
        find.textContaining('Server-Sync fehlgeschlagen'),
      );

      expect(tester.takeException(), isNull);
      // Lokal ist gespeichert ...
      expect(container.read(profileProvider).name, 'Lena Neu');
      // ... aber der Nutzer wird gewarnt: der Server hat es nicht.
      expect(
        gemeldet,
        isTrue,
        reason:
            'Ein gescheiterter Server-Sync muss dem Nutzer gesagt werden - '
            'sonst glaubt er, die Änderung sei auch serverseitig angekommen.',
      );

      await aufraeumen(tester);
    });

    testWidgets('ein ungültiges Formular wird abgewiesen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
      );

      // Der Name leer - der Validator verlangt mindestens zwei Zeichen.
      await tester.enterText(find.byType(TextFormField).first, 'x');
      await pumpFrames(tester);
      await scrolleZumSpeichern(tester);

      await tester.tap(find.text('Speichern').last);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Nutzer erfaehrt, dass es nicht gespeichert wurde.
      expect(find.textContaining('Es fehlen noch Angaben'), findsWidgets);
      // Und das Profil ist unveraendert.
      expect(container.read(profileProvider).name, 'Lena');

      await aufraeumen(tester);
    });

    testWidgets('ein Interessen-Chip springt beim Auswählen nicht', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
      );

      // Zum Abschnitt "Interessen" scrollen.
      final chip = find.widgetWithText(FilterChip, 'Fotografie');
      await tester.scrollUntilVisible(
        chip,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpFrames(tester);

      final vorher = tester.getRect(chip);
      await tester.tap(chip);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(chip),
        vorher,
        reason:
            'BEFUND (13.11.2026, Betreiber): ein ausgewaehltes Chip darf '
            'nicht in die naechste Zeile springen - das fuehlt sich wie '
            'ein Fehlklick an.',
      );
      // Und die Auswahl ist angekommen (die Interessen stehen sofort
      // im Profil, nicht erst beim Speichern).
      expect(container.read(profileProvider).interests, contains('Fotografie'));

      await aufraeumen(tester);
    });

    testWidgets('ein Gesundheits-Chip springt nicht und merkt sich die Wahl', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await profileEditScreenPump(tester, profileEditScreenProfil);

      // "Nie" beim Rauchen - das erste "Nie" gehört zum Rauchen.
      final chip = find.widgetWithText(ChoiceChip, 'Nie').first;
      await tester.scrollUntilVisible(
        chip,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpFrames(tester);

      final vorher = tester.getRect(chip);
      await tester.tap(chip);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getRect(chip), vorher);
      // Die Auswahl ist als getroffen markiert.
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);

      await aufraeumen(tester);
    });

    testWidgets('ein Musik-Chip springt nicht und merkt sich die Wahl', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await profileEditScreenPump(tester, profileEditScreenProfil);

      final chip = find.widgetWithText(FilterChip, 'Rock');
      await tester.scrollUntilVisible(
        chip,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpFrames(tester);

      final vorher = tester.getRect(chip);
      await tester.tap(chip);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getRect(chip), vorher);
      expect(tester.widget<FilterChip>(chip).selected, isTrue);

      await aufraeumen(tester);
    });
  });
  group('Die Bilder im Profil', () {
    testWidgets('ein entferntes Bild kommt beim Server nicht mehr an', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await profileEditScreenPump(tester, profilMitBildern);

      expect(tester.takeException(), isNull);
      // Drei Bilder = drei Entfernen-Knoepfe (einer je Kachel).
      final knoepfe = find.byIcon(Icons.close);
      expect(
        knoepfe,
        findsNWidgets(3),
        reason:
            'Zu jedem Bild gehoert ein Entfernen-Knopf - sonst kann der '
            'Nutzer sein Bild nie wieder loswerden.',
      );

      // Die mittlere Kachel (Slot 1) leeren.
      await tester.tap(knoepfe.at(1));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Bildschirm weiss jetzt, dass sich etwas geaendert hat.
      expect(
        container.read(profileEditDirtyProvider),
        isTrue,
        reason:
            'Nach dem Entfernen eines Bildes muss der Bildschirm als '
            '"geaendert" gelten - sonst ginge der Aenderung beim '
            'Zurueckgehen verloren.',
      );

      await scrolleZumSpeichern(tester);
      await tester.tap(find.text('Speichern').last);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);

      // DER SERVER-CHECK: Der Schreibvorgang mit den Fotos.
      final mitFotos = server.schreibvorgaenge
          .where((v) => v['tabelle'] == 'profiles' && v['photos'] != null)
          .toList();
      expect(
        mitFotos,
        isNotEmpty,
        reason:
            'Die Fotos muessen zum Server gehen - sonst sieht der '
            'Nutzer sein Bild zwar entfernt, auf anderen Geraeten aber '
            'weiterhin.',
      );
      final gesendet = (mitFotos.last['photos'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();

      expect(
        gesendet,
        isNot(contains('ich/photos/2.jpg')),
        reason:
            'Das entfernte Bild darf NICHT mehr beim Server stehen - '
            'sonst ist es nach dem Neustart wieder da.',
      );
      expect(
        gesendet,
        contains('ich/photos/3.jpg'),
        reason:
            'Die Galerie rueckt nach: das dritte Bild nimmt den Platz '
            'des entfernten ein - sonst waere eine Luecke in der '
            'Galerie.',
      );

      // Und auch lokal ist es weg.
      expect(
        container.read(profileProvider).photos,
        isNot(contains('ich/photos/2.jpg')),
      );

      await aufraeumen(tester);
    });
  });
  group('Die Standortermittlung', () {
    testWidgets('der Standort wird erkannt, gerastert und gespeichert', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final ortService = FakeOrtService(position: profileEditScreenPosition());

      final container = await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
        ortService: ortService,
      );

      expect(tester.takeException(), isNull);

      // Der GPS-Knopf sitzt am Bundesland-Feld (das steht weit unten im
      // Formular - erst dorthin scrollen).
      final gps = find.byIcon(Icons.my_location);
      expect(gps, findsOneWidget);
      await tester.scrollUntilVisible(
        gps,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpFrames(tester);
      await tester.tap(gps);
      await pumpFrames(tester);

      // Die Offenlegung kommt VOR der Berechtigung (das verlangt
      // Google Play) - der Nutzer muss sie bestaetigen.
      expect(
        find.text(L10n.tWithoutContext('location.disclosureTitle')),
        findsOneWidget,
        reason:
            'Ohne Offenlegung fragt die App die Berechtigung im Hintergrund '
            'ab - das verlangt Google Play nicht.',
      );
      await tester.tap(
        find.text(L10n.tWithoutContext('location.disclosureAccept')),
      );
      await pumpFrames(tester);

      // Der Standort wurde abgefragt ...
      expect(
        ortService.abfragen,
        greaterThan(0),
        reason: 'Der Knopf muss den Standort wirklich abfragen.',
      );

      // ... und auf dem 5-km-Raster gespeichert (nicht der exakte Punkt).
      final erwartet = LocationPrivacy.snapToGrid(53.5511, 9.9937);
      final profil = container.read(profileProvider);
      expect(
        profil.locationLat,
        erwartet.lat,
        reason:
            'Der Standort muss auf dem Raster liegen - sonst speichert die '
            'App genauer, als sie verspricht.',
      );
      expect(profil.locationLng, erwartet.lng);

      // Und der Standort geht zum Server (in der Tabelle, die nur der
      // Eigentuemer lesen darf - nicht in profiles).
      final orte = server.schreibvorgaenge
          .where((v) => v['tabelle'] == 'profile_locations')
          .toList();
      expect(
        orte,
        isNotEmpty,
        reason:
            'Der Standort muss zum Server - sonst sieht niemand, in der '
            'Naehe der Nutzer ist.',
      );
      expect(orte.last['lat'], erwartet.lat);

      // Und der Nutzer bekommt die Bestaetigung.
      expect(
        find.text(L10n.tWithoutContext('profile.edit.locationDetected')),
        findsOneWidget,
      );

      // Der Standort wird auch serverseitig geprueft (Massen-Fake-
      // Konten) - das muss raus.
      final pruefung =
          container.read(locationCheckServiceProvider) as FakeStandortPruefung;
      expect(
        pruefung.aufrufe,
        isNotEmpty,
        reason:
            'Der Standort muss auch serverseitig geprueft werden - sonst '
            'faellt eine Massen-Anmeldung mit demselben Standort nicht '
            'auf.',
      );
      expect(pruefung.aufrufe.last['newLatitude'], erwartet.lat);

      await aufraeumen(tester);
    });

    testWidgets('ohne Berechtigung wird kein Standort gespeichert', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Die Berechtigung wird verweigert (der Nutzer sagt Nein zur
      // Offenlegung) - dann darf kein Standort im Profil landen.
      final ortService = FakeOrtService(position: profileEditScreenPosition());

      final container = await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
        ortService: ortService,
      );

      expect(tester.takeException(), isNull);

      // Der GPS-Knopf sitzt am Bundesland-Feld (das steht weit unten im
      // Formular - erst dorthin scrollen).
      final gps = find.byIcon(Icons.my_location);
      await tester.scrollUntilVisible(
        gps,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpFrames(tester);
      await tester.tap(gps);
      await pumpFrames(tester);

      // Die Offenlegung abbrechen.
      final abbrechen = find.text(L10n.tWithoutContext('common.cancel'));
      expect(abbrechen, findsOneWidget);
      await tester.tap(abbrechen);
      await pumpFrames(tester);

      // Der Standort wurde NICHT abgefragt ...
      expect(ortService.abfragen, 0);
      // ... und nichts steht im Profil.
      expect(container.read(profileProvider).locationLat, isNull);

      await aufraeumen(tester);
    });
  });
}
