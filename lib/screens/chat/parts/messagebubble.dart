// Der Teil '_MessageBubble'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

/// Sprechende Blase für Text-, Bild- und Sprachnachrichten mit
/// Playback-Unterstützung für Voice.
///
/// Nutzerwunsch Gruppierung: [showName] blendet den Absendernamen über
/// der Bubble ein (neue Gruppe nach Senderwechsel, > 3 Minuten Abstand
/// oder max. 3 Nachrichten am Stück). Jede Nachricht bleibt in ihrer
/// eigenen Bubble und trägt eine kleine Zeitanzeige.
class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.msg,
    required this.mine,
    required this.blurEnabled,
    required this.onReportImage,
    this.showName = false,
    this.senderName = '',
    this.onDelete,
  });

  final Message msg;
  final bool mine;

  /// Bilder (fremder Seite) standardmäßig verpixelt anzeigen?
  final bool blurEnabled;

  /// Meldet dieses Bild als unangemessenen Inhalt.
  final void Function(Message msg) onReportImage;

  /// Namens-Header über der Bubble anzeigen (Gruppenstart)?
  final bool showName;

  /// Anzuzeigender Absendername (z. B. "Du" oder Partnername).
  final String senderName;

  /// "Für alle löschen" (nur eigene Textnachrichten).
  ///
  /// BEFUND (11.11.2026): Wie bei Whatsapp - die Nachricht wird für
  /// beide Seiten ungelesbar, mit einem Hinweis im Verlauf.
  final void Function(Message msg)? onDelete;

  /// Uhrzeit (HH:mm) der Nachricht, lokal formatiert.
  ///
  /// Das Format-Objekt wird einmal pro State-Instanz erzeugt: `DateFormat.Hm()`
  /// löst bei jedem Aufruf die Locale neu auf - das war bei langen
  /// Verlaufen ein spürbarer Kostenfaktor (pro Bubble pro Build).
  static final DateFormat _timeFormat = DateFormat.Hm();

  String get _timeLabel {
    try {
      return _timeFormat.format(msg.timestamp.toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}
