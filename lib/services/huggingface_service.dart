import 'package:flutter/foundation.dart';

import 'package:thestia/utils/constants.dart';

/// NSFW-Bild-Moderation – zurzeit per Feature-Flag DEAKTIVIERT
/// (AppConstants.nsfwModerationEnabled, Betreiber-Entscheidung).
///
/// SICHERHEIT (Audit B1): Das frühere Design schickte Bilder mit einem via
/// --dart-define eingebetteten Hugging-Face-Token direkt vom Client an die
/// HF-API. Jedes in die App kompilierte Token ist aus APK/IPA extrahierbar
/// – die Lücke wurde geschlossen, indem Token und URL vollständig aus dem
/// Client entfernt wurden.
///
/// Die echte Implementierung wird später serverseitig als Edge Function
/// erfolgen (Token liegt dann ausschließlich als Function-Secret
/// HF_API_TOKEN bei Supabase). Das Aufruf-Format von [checkImage] bleibt
/// identisch, damit der Service dann drop-in ersetzt werden kann.
///
/// Aktuelles Verhalten (Flag = false): Bilder werden ohne Prüfung
/// durchgelassen (`isSafe: true`); die aufrufende
/// PhotoModerationService-Schicht erzeugt dann auch KEINEN
/// photo_moderation-DB-Eintrag (keine Admin-Warteschlange).
class HuggingFaceService {
  HuggingFaceService._();

  static Future<
      ({
        bool isSafe,
        bool isNsfw,
        bool needsReview,
        Map<String, dynamic> categories,
        String label,
      })> checkImage(Uint8List imageBytes) async {
    if (!AppConstants.nsfwModerationEnabled) {
      if (kDebugMode) {
        debugPrint('[HF] NSFW-Moderation deaktiviert (Feature-Flag). '
            'Bild wird ohne Prüfung durchgelassen.');
      }
      return (
        isSafe: true,
        isNsfw: false,
        needsReview: false,
        categories: <String, dynamic>{},
        label: 'moderation_disabled',
      );
    }

    // Flag aktiv, aber noch keine serverseitige Implementierung deployed:
    // fail-closed (nichts ungeprüft durchlassen).
    if (kDebugMode) {
      debugPrint(
        '[HF] NSFW-Moderation aktiv, aber Edge-Function-Implementierung '
        'fehlt, Bild → pending_review.',
      );
    }
    return (
      isSafe: false,
      isNsfw: false,
      needsReview: true,
      categories: <String, dynamic>{},
      label: 'moderation_unavailable',
    );
  }
}
