import 'package:thestia/utils/common/json_leser.dart';

/// Typ einer Chat-Nachricht.
///
/// Erweitert das Modell, damit neben Text auch Bilder und
/// Sprachnachrichten darstellbar sind.
enum MessageType {
  /// Reiner Text.
  text,

  /// Bildnachricht (Pfad/URL in [mediaUrl]).
  image,

  /// Sprachnachricht (Pfad/URL in [mediaUrl], Dauer in [durationSeconds]).
  voice,

  /// Geteilte Eisbrecher-Frage (v0.9.1): wird BEIDEN Chat-Seiten gleichzeitig
  /// als mittige Bubble angezeigt und wandert wie jede Nachricht mit.
  icebreaker,

  /// System-Hinweis in der Mitte des Chats (v0.10.0): kein Text einer
  /// Person, sondern ein Hinweis der App - z. B. die Fünf-Minuten-Marke
  /// in der Dating Hour. Wird mittig dargestellt, wie die
  /// Eisbrecher-Fragen.
  notice,
}

/// Repräsentiert eine 1:1-Nachricht im Chat.
class Message {
  /// Eindeutige Nachrichten-ID.
  final String id;

  /// Prozess-weiter Sequenzzähler für [newId]: Reine
  /// Millisekunden-Zeitstempel kollidieren bei Bursts (zwei Nachrichten
  /// in derselben Millisekunde, Ping+Poll-Doppelabruf) und wurden dann
  /// per Dedup verworfen bzw. dupliziert angezeigt.
  static int _idSeq = 0;

  /// Erzeugt eine eindeutige Nachrichten-ID (`<prefix>_<ms>_<seq>`).
  static String newId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_idSeq++}';

  /// ID des Absenders.
  final String senderId;

  /// ID des Empfängers.
  final String receiverId;

  /// Nachrichtentext (bei Bild/Sprache optionaler Begleittext).
  final String text;

  /// Art der Nachricht (Text/Bild/Sprache).
  final MessageType type;

  /// Pfad/URL zum Medium (bei Bild/Sprache).
  final String? mediaUrl;

  /// Dauer der Sprachnachricht in Sekunden (nur bei [MessageType.voice]).
  final int durationSeconds;

  /// Zeitpunkt (Millisekunden seit Epoch).
  final DateTime timestamp;

  /// Bild kann nur EINMAL angesehen werden (View-Once).
  /// Nach dem Ansehen wird das Bild gelöscht und durch einen Platzhalter
  /// ersetzt. Schützt vor unkontrollierter Weiterverbreitung.
  final bool viewOnce;

  /// Ob der Empfänger das View-Once-Bild bereits gesehen hat.
  /// Nur relevant, wenn [viewOnce] = true und der aktuelle Nutzer
  /// der Empfänger (nicht Sender) ist.
  final bool viewed;

  const Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.text = '',
    this.type = MessageType.text,
    this.mediaUrl,
    this.durationSeconds = 0,
    required this.timestamp,
    this.viewOnce = false,
    this.viewed = false,
  });

  /// Erzeugt eine Nachricht aus einem JSON-Map.
  ///
  /// BEFUND (22.11.2026, Fuzzing): Die Casts hier waren ungeschützt -
  /// ein fehlendes oder falsch typisiertes Feld ließ die App
  /// abstürzen. Die Nachricht kommt aus der lokalen Historie und (über
  /// das Relay) vom Server: ein fremder Wert darf nicht abstürzen.
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: textOf(json, ['id']) ?? '',
      senderId: textOf(json, ['senderId']) ?? '',
      receiverId: textOf(json, ['receiverId']) ?? '',
      text: textOf(json, ['text']) ?? '',
      type: MessageType.values.firstWhere(
        (t) => t.name == (textOf(json, ['type']) ?? 'text'),
        orElse: () => MessageType.text,
      ),
      mediaUrl: textOf(json, ['mediaUrl']),
      durationSeconds: intOf(json, ['durationSeconds']) ?? 0,
      // Der Zeitstempel kommt aus dem lokalen Verlauf. Ein Zeitstempel
      // außerhalb des darstellbaren Bereichs wird verworfen (der Leser
      // prüft das) - `fromMillisecondsSinceEpoch` würde sonst werfen.
      timestamp:
          dateOf(json, ['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      viewOnce: boolOf(json, ['viewOnce']) ?? false,
      viewed: boolOf(json, ['viewed']) ?? false,
    );
  }

  /// Wandelt die Nachricht in ein JSON-Map um.
  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'receiverId': receiverId,
    'text': text,
    'type': type.name,
    'mediaUrl': mediaUrl,
    'durationSeconds': durationSeconds,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'viewOnce': viewOnce,
    'viewed': viewed,
  };

  /// True, wenn die Nachricht vom aktuellen Nutzer gesendet wurde.
  bool isFrom(String currentUserId) => senderId == currentUserId;

  Message copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? text,
    MessageType? type,
    String? mediaUrl,
    int? durationSeconds,
    DateTime? timestamp,
    bool? viewOnce,
    bool? viewed,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      timestamp: timestamp ?? this.timestamp,
      viewOnce: viewOnce ?? this.viewOnce,
      viewed: viewed ?? this.viewed,
    );
  }
}
