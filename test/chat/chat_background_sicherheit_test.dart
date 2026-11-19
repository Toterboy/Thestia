// Die Pfadpruefung des eigenen Chat-Hintergrunds.
//
// ANLASS (19.11.2026): `lib/utils/chat/chat_backgrounds.dart` war nur zu 82 %
// abgedeckt. Die Pruefung ist eine SICHERHEITSgrenze: ein manipulierter
// Einstellungs-Import darf nicht jeden beliebigen Dateipfad als
// Hintergrund einschleusen (sonst zeigt die App eine Datei aus fremden
// Bereichen an).
//
// WAS HIER GEPRUEFT WIRD:
//   * nur die Datei im App-Dokumentenverzeichnis mit dem EXAKTEN Namen
//     wird akzeptiert,
//   * alles andere wird abgelehnt,
//   * vor dem Binden des Verzeichnisses wird alles abgelehnt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/utils/chat/chat_backgrounds.dart';

void main() {
  group('Die Pfadpruefung des Hintergrundbildes', () {
    test('die eigene Datei wird akzeptiert', () {
      ChatBackgrounds.bindAppDocsDir('/app/documents');
      final datei = File('/app/documents/chat_bg_custom.jpg');
      expect(ChatBackgrounds.isOwnBackgroundFile(datei), isTrue);
    });

    test('eine Datei ausserhalb des Verzeichnisses wird abgelehnt', () {
      ChatBackgrounds.bindAppDocsDir('/app/documents');
      // DER GRUND: Ein Pfad aus dem Import darf nicht greifen.
      expect(
        ChatBackgrounds.isOwnBackgroundFile(File('/tmp/chat_bg_custom.jpg')),
        isFalse,
      );
    });

    test('ein aussteigender Pfad wird abgelehnt', () {
      // BEFUND (19.11.2026, gefunden von diesem Test): Der Pfad
      // 'documents/../fremd/chat_bg_custom.jpg' begann mit dem
      // Dokumentenverzeichnis - die Datei liegt aber AUSSERHALB davon.
      ChatBackgrounds.bindAppDocsDir('/app/documents');
      expect(
        ChatBackgrounds.isOwnBackgroundFile(
          File('/app/documents/../fremd/chat_bg_custom.jpg'),
        ),
        isFalse,
        reason:
            'Der Pfad darf nicht aus dem Verzeichnis herauszeigen - sonst '
            'koennte der Import eine beliebige Datei als Hintergrund '
            'einschleusen.',
      );
    });

    test('eine andere Datei im Verzeichnis wird abgelehnt', () {
      ChatBackgrounds.bindAppDocsDir('/app/documents');
      expect(
        ChatBackgrounds.isOwnBackgroundFile(File('/app/documents/urlaub.jpg')),
        isFalse,
      );
      expect(
        ChatBackgrounds.isOwnBackgroundFile(
          File('/app/documents/chat_bg_custom.png'),
        ),
        isFalse,
      );
    });

    test('ein Unterordner mit dem richtigen Namen wird abgelehnt', () {
      // DER GRUND: Der Pfad muss DIREKT im Dokumentenverzeichnis liegen -
      // ein Unterordner waere ein fremder Bereich.
      ChatBackgrounds.bindAppDocsDir('/app/documents');
      expect(
        ChatBackgrounds.isOwnBackgroundFile(
          File('/app/documents/fremd/chat_bg_custom.jpg'),
        ),
        isFalse,
      );
    });

    test('ohne gebundenes Verzeichnis wird alles abgelehnt', () {
      // Vor dem App-Start kennt der Dienst das Verzeichnis nicht - dann
      // darf er nichts akzeptieren.
      ChatBackgrounds.bindAppDocsDir('');
      expect(
        ChatBackgrounds.isOwnBackgroundFile(
          File('/app/documents/chat_bg_custom.jpg'),
        ),
        isFalse,
      );
    });
  });

  group('Die gueltigen Hintergruende', () {
    test('die Vorgaaben sind bekannt', () {
      expect(ChatBackgrounds.presets, contains(ChatBackgrounds.dots));
      expect(ChatBackgrounds.presets, contains(ChatBackgrounds.waves));
      expect(ChatBackgrounds.presets, isNot(contains(ChatBackgrounds.none)));
      expect(ChatBackgrounds.presets, isNot(contains(ChatBackgrounds.custom)));
    });

    test('nur die gueltigen IDs werden akzeptiert', () {
      expect(ChatBackgrounds.isValid(ChatBackgrounds.none), isTrue);
      expect(ChatBackgrounds.isValid(ChatBackgrounds.custom), isTrue);
      expect(ChatBackgrounds.isValid(ChatBackgrounds.hearts), isTrue);
      expect(ChatBackgrounds.isValid('nichtda'), isFalse);
      expect(ChatBackgrounds.isValid(''), isFalse);
    });

    test('jeder Hintergrund hat sein eigenes Text-Feld', () {
      expect(ChatBackgrounds.labelKey(ChatBackgrounds.none), 'chatbg.none');
      expect(ChatBackgrounds.labelKey(ChatBackgrounds.dots), 'chatbg.dots');
      expect(ChatBackgrounds.labelKey(ChatBackgrounds.custom), 'chatbg.custom');
    });
  });
}
