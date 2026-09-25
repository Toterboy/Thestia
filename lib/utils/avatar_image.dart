import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show BuildContext, Color, Colors, Theme;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'package:thestia/utils/exif_stripper.dart';

/// Profilbild auswaehlen und interaktiv quadratisch zuschneiden.
///
/// Wird von der Einrichtung ("Dein Profil") und "Profil bearbeiten"
/// genutzt, damit beide identisch funktionieren. Gibt null zurueck, wenn
/// der Nutzer abgebrochen hat. [context] ist optional und faerbt den
/// Crop-Screen im aktiven Theme.
Future<Uint8List?> pickAndCropAvatar([BuildContext? context]) async {
  // Farben VOR den async-Aufrufen lesen (keine Context-Nutzung nach Gaps).
  final scheme = context == null ? null : Theme.of(context).colorScheme;
  final brand = scheme?.primary ?? const Color(0xFFE9457B);
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 90,
  );
  if (picked == null) return null;

  // Quadratischer Zuschnitt (1:1) - Avatare werden kreisfoermig gezeigt.
  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 85,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Bild zuschneiden',
        toolbarColor: brand,
        toolbarWidgetColor: scheme?.onPrimary ?? Colors.white,
        activeControlsWidgetColor: brand,
        lockAspectRatio: true,
        hideBottomControls: false,
      ),
      IOSUiSettings(
        title: 'Bild zuschneiden',
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
      ),
    ],
  );
  if (cropped == null) return null;

  final bytes = await cropped.readAsBytes();
  if (kDebugMode) {
    debugPrint('[AvatarImage] zugeschnitten: ${bytes.length} Bytes');
  }
  // Audit M-21: EXIF (GPS, Geräteinfos) explizit entfernen - der Avatar
  // wird an Matches ausgeliefert. Fail-closed: Ohne erfolgreiches
  // Re-Encoding wird kein Bild hochgeladen.
  return stripImageMetadata(bytes);
}
