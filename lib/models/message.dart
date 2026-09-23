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
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      text: json['text'] as String? ?? '',
      type: MessageType.values.firstWhere(
        (t) => t.name == (json['type'] as String? ?? 'text'),
        orElse: () => MessageType.text,
      ),
      mediaUrl: json['mediaUrl'] as String?,
      durationSeconds: (json['durationSeconds'] as num? ?? 0).toInt(),
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      viewOnce: json['viewOnce'] as bool? ?? false,
      viewed: json['viewed'] as bool? ?? false,
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
