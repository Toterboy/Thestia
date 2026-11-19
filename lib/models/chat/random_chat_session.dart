/// Status einer Zufallschat-Session (serverseitiges Matching).
enum RandomChatStatus {
  waiting,
  active,
  ended;

  static RandomChatStatus fromString(String? value) {
    switch (value) {
      case 'active':
        return RandomChatStatus.active;
      case 'ended':
        return RandomChatStatus.ended;
      default:
        return RandomChatStatus.waiting;
    }
  }
}

/// Ergebnis der Random-Chat-RPCs (`join_random_chat`,
/// `get_random_chat_session`). Enthält ausschließlich die Paarung -
/// Nachrichteninhalte laufen E2E-verschlüsselt über den P2P-DataChannel.
class RandomChatSession {
  const RandomChatSession({
    this.sessionId,
    this.partnerId,
    this.status = RandomChatStatus.waiting,
  });

  final String? sessionId;
  final String? partnerId;
  final RandomChatStatus status;

  bool get isMatched => status == RandomChatStatus.active && partnerId != null;

  factory RandomChatSession.fromJson(Map<String, dynamic> json) {
    return RandomChatSession(
      sessionId: json['sessionId'] as String?,
      partnerId: json['partnerId'] as String?,
      status: RandomChatStatus.fromString(json['status'] as String?),
    );
  }
}
