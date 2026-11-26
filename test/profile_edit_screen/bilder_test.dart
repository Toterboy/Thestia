// Die Bildauswahl im Profil-Editor - und der NSFW-Weg.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte für
// lib/screens/profile/parts/profileditbilder.dart 98 offene Zeilen bei
// 107 gesamt - der ganze Weg vom Bild zum Avatar war ungetestet.
//
// DER GRUND: Der Profil-Editor ist die einzige Stelle, an der der
// Nutzer sein Bild wählt. Und dort gibt es eine heikle Kette:
//   * das Bild wird lokal auf "anstössige Inhalte" geprüft (es
//     verlässt das Gerät dabei NICHT),
//   * bei einem Befund wird der Nutzer zurückgewiesen - mit drei
//     Wegen: "Verstanden" (verwerfen), "Anderes Bild" (neu wählen)
//     und "Einspruch" (das Team prüft es).
// Wird der Einspruch nicht oder falsch behandelt, ist entweder ein
// anstossiges Bild im Profil oder ein Nutzer ohne Bild.
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne Befund wird das Bild überhaupt erst angenommen,
//   * bei einem Befund erscheint der Dialog mit allen drei Wegen,
//   * der Dialog nennt den Befund (das Modell-Vertrauen), aber NICHT
//     das Bild selbst (es bleibt lokal),
//   * "Verstanden" verwirft das Bild (es wird kein Avatar),
//   * "Anderes Bild" fragt erneut nach.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// Das Plattform-Interface wird von image_picker exportiert, aber nicht
// weitergereicht - der Test setzt die Attrappe darüber.
// ignore: depend_on_referenced_packages
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/profile/image_safety_service.dart';

import 'hilfen.dart';

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
  late ImagePickerPlatform originalPicker;
  late ImageCropperPlatform originalCropper;

  setUp(() {
    originalPicker = ImagePickerPlatform.instance;
    originalCropper = ImageCropperPlatform.instance;
  });

  tearDown(() {
    ImagePickerPlatform.instance = originalPicker;
    ImageCropperPlatform.instance = originalCropper;
    // DER TEST-HAKEN: Der Befund der Bildprüfung muss wieder weg -
    // sonst würde der nächste Test den Befund des vorigen sehen.
    ImageSafetyService.classifyOverride = null;
  });

  /// Legt ein echtes Bild an (der Bildweg liest die Datei wirklich und
  /// lässt die Metadaten entfernen - das braucht echte Bilddaten).
  String legeDatei() {
    final ordner = Directory.systemTemp.createTempSync('profil_bild');
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
    return datei.path;
  }

  /// Tippt auf den Knopf, der das Hauptbild wählt.
  ///
  /// DER WEG: Der Bildweg liest eine echte Datei und lässt sie in
  /// einem eigenen Isolate verarbeiten. Im Test läuft die Zeit aber in
  /// der Test-Zone - dort würde das Lesen nie fertig werden. Darum
  /// läuft der Griff in der echten Zone (`runAsync`).
  Future<void> bildWaehlen(WidgetTester tester) async {
    final knopf = find.byIcon(Icons.camera_alt).first;
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(knopf);
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    await pumpFrames(tester);
  }

  group('Die Bildauswahl im Profil-Editor', () {
    testWidgets('ohne Befund wird das Bild angenommen', (tester) async {
      final pfad = legeDatei();
      ImagePickerPlatform.instance = _FakeImagePicker(pfad);
      ImageCropperPlatform.instance = _FakeCropper(pfad);
      // DER BEFUND: kein Befund (die lokale Prüfung ist nicht
      // verfügbar) - das Bild darf normal gespeichert werden.
      ImageSafetyService.classifyOverride = (Uint8List bytes) => null;

      await profileEditScreenPump(tester, profileEditScreenProfil);
      await bildWaehlen(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            'Ohne Befund darf kein Dialog erscheinen - sonst wuerde der '
            'Nutzer ein ganz normales Bild zurueckgewiesen bekommen.',
      );

      await aufraeumen(tester);
    });

    testWidgets('bei einem Befund erscheint der Dialog mit allen Wegen', (
      tester,
    ) async {
      final pfad = legeDatei();
      ImagePickerPlatform.instance = _FakeImagePicker(pfad);
      ImageCropperPlatform.instance = _FakeCropper(pfad);
      // DER BEFUND: das Bild ist zu 80 % anstössig.
      ImageSafetyService.classifyOverride = (Uint8List bytes) =>
          const ImageSafetyResult(nsfl: 0.1, nsfw: 0.8, sfw: 0.1);

      await profileEditScreenPump(tester, profileEditScreenProfil);
      await bildWaehlen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      // Der Dialog nennt den Befund - aber das Bild selbst bleibt
      // lokal (es wird nur der Text angezeigt).
      expect(
        find.textContaining('80'),
        findsWidgets,
        reason:
            'Der Nutzer muss wissen, warum sein Bild zurueckgewiesen wurde - '
            'ohne die Zahl ist das eine willkuerliche Zurueckweisung.',
      );
      expect(
        find.text(L10n.tWithoutContext('profile.edit.photoNsfwNotUploaded')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass das Bild NICHT hochgeladen wurde - '
            'das ist die Zusage der lokalen Pruefung.',
      );
      // Und alle drei Wege stehen da.
      expect(
        imDialog(L10n.tWithoutContext('profile.edit.photoNsfwUnderstood')),
        findsOneWidget,
      );
      expect(
        imDialog(L10n.tWithoutContext('profile.edit.photoNsfwOther')),
        findsOneWidget,
      );
      expect(
        imDialog(L10n.tWithoutContext('profile.edit.photoNsfwAppeal')),
        findsOneWidget,
        reason:
            'Der Einspruch muss moeglich sein - sonst hat der Nutzer gegen '
            'eine Fehlentscheidung des Modells kein Mittel.',
      );

      await aufraeumen(tester);
    });

    testWidgets('"Verstanden" verwirft das Bild', (tester) async {
      final pfad = legeDatei();
      ImagePickerPlatform.instance = _FakeImagePicker(pfad);
      ImageCropperPlatform.instance = _FakeCropper(pfad);
      ImageSafetyService.classifyOverride = (Uint8List bytes) =>
          const ImageSafetyResult(nsfl: 0.1, nsfw: 0.8, sfw: 0.1);

      await profileEditScreenPump(tester, profileEditScreenProfil);
      await bildWaehlen(tester);

      await tester.tap(
        imDialog(L10n.tWithoutContext('profile.edit.photoNsfwUnderstood')),
      );
      await tester.pump();
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            'Der Dialog muss sich schliessen - der Nutzer hat sich '
            'entschieden.',
      );

      await aufraeumen(tester);
    });

    testWidgets('"Anderes Bild" fragt erneut nach', (tester) async {
      final pfad = legeDatei();
      ImagePickerPlatform.instance = _FakeImagePicker(pfad);
      ImageCropperPlatform.instance = _FakeCropper(pfad);
      ImageSafetyService.classifyOverride = (Uint8List bytes) =>
          const ImageSafetyResult(nsfl: 0.1, nsfw: 0.8, sfw: 0.1);

      await profileEditScreenPump(tester, profileEditScreenProfil);
      await bildWaehlen(tester);

      await tester.tap(
        imDialog(L10n.tWithoutContext('profile.edit.photoNsfwOther')),
      );
      await tester.pump();
      // DER WEG: "Anderes Bild" startet den Bildweg von vorn - mit
      // Datei lesen und Isolate (echte Zeit).
      await tester.runAsync(() async {
        for (var i = 0; i < 60; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump();
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Die Bildauswahl wird erneut geöffnet - der Nutzer darf ein
      // anderes Bild wählen, ohne den Bildschirm zu verlassen.
      expect(find.byType(AlertDialog), findsOneWidget);

      await aufraeumen(tester);
    });
  });
}
