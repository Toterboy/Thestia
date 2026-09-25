import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Audit M-17: Entschlüsselte Voice-Notes (`thestia_incoming_*.m4a`,
/// historisch `wisp_incoming_*.m4a`) wurden in
/// das System-Temp-Verzeichnis geschrieben und NIE gelöscht - der
/// E2E-Versprechen ("Inhalte existieren nur im Speicher") wurde damit am
/// Ruhe-Zustand untergraben.
///
/// Diese Utility löscht alle entschlüsselten Temp-Audio-Reste. Sie wird
/// aufgerufen:
/// - bei der Account-Löschung ([AuthNotifier.deleteAccount]),
/// - optional beim App-Start (Aufräumen alter Reste).
///
/// Die eigentliche Prävention passiert in chat_detail_screen.dart: Die
/// Datei wird nach der Wiedergabe/ beim Verlassen des Chats sofort
/// entfernt; hier handelt es sich um den garantierten Aufräum-Lauf.
Future<void> cleanupDecryptedTempFiles() async {
  try {
    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if ((name.startsWith('thestia_incoming_') ||
              name.startsWith('wisp_incoming_')) &&
          name.endsWith('.m4a')) {
        try {
          await entity.delete();
        } catch (_) {
          // Einzelne Datei gesperrt -> überspringen, Rest weiter aufräumen.
        }
      }
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[TEMP_CLEANUP] fehlgeschlagen: $e');
  }
}
