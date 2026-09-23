import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;

import 'package:wisp/models/message.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/services/random_chat_service.dart';
import 'package:wisp/services/relay_service.dart';
import 'package:wisp/services/supabase_service.dart';

/// Benachrichtigungs-Hook (vom App-Wurzel-Widget mit WidgetRef verdrahtet,
/// da Ref != WidgetRef). `title` darf null sein (Hook ergänzt den
/// l10n-Fallback-Namen über seinen Kontext).
typedef RelayInboxNotifier = Future<void> Function({
  required int id,
  String? title,
  required String body,
  required String senderId,
});

/// True, wenn die App gerade im Vordergrund ist (Delegation, damit der
/// Inbox-Ticker keine Lifecycle-Imports braucht).
bool appInForeground() {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}

/// Globaler Relay-Eingang (NUTZERWUNSCH "Ich muss im Chat sein, um
/// Nachrichten zu erhalten"): Solange die App im VORDERGRUND ist, aber
/// KEIN Chat-Screen offen ist, pollt der Eingang das E2E-Relay und
/// verteilt entschlüsselte Nachrichten in die richtige Session
/// (Funken-Match oder aktive Zufallschat-Session). Der Chat-Screen
/// übernimmt, sobald er offen ist (dann ist dieser Poller pausiert).
///
/// Zustellungslogik:
///  - Routierbar (Match-/Session-Zuordnung gelöst) -> chatProvider +
///    Lokal-Benachrichtigung (macht _maybeNotifyMessage) -> ack (löschen).
///  - NICHT routierbar -> NICHT acken: die Zeile bleibt im Relay und
///    wird vom zuständigen Chat-Screen abgeholt (kein Datenverlust).
class GlobalRelayInbox {
  GlobalRelayInbox(this._ref);

  /// WidgetRef (vom App-Wurzel-Widget) - hat dieselbe read-API und bleibt
  /// für die gesamte App-Laufzeit gültig. `dynamic` wegen Ref/WidgetRef-
  /// Trennung in Riverpod.
  // ignore: avoid_dynamic_calls
  final dynamic _ref;
  Timer? _timer;
  bool _busy = false;

  /// Gecachte aktive Zufallschat-Session (Session-Lookup nicht pro Tick).
  ({String sessionId, String partnerId})? _activeRandomChat;
  DateTime? _activeRandomChatAt;

  static const Duration _pollInterval = Duration(seconds: 6);
  static const Duration _sessionCacheTtl = Duration(seconds: 30);

  /// Benachrichtigungs-Hook (wird vom App-Wurzel-Widget gesetzt, da der
  /// Inbox-Pfad kein WidgetRef hat).
  static RelayInboxNotifier? notifier;

  void start() {
    _timer ??= Timer.periodic(_pollInterval, (_) => _tick());
    unawaited(_tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_busy) return;
    // Nur Vordergrund.
    if (!appInForeground()) return;
    // Chat-Screens pollen selbst (kein Doppel-Acking).
    if (_ref.read(activeChatIdProvider) != null) return;
    if (!SupabaseService.isInitialized) return;
    if (_busy) return;
    _busy = true;
    try {
      // ack: false - der Inbox-Poller ackt SELEKTIV nur routierte Zeilen
      // (sonst würde er Dating-Hour-Zeilen löschen, die ihr Screen noch
      // braucht).
      final pending =
          await _ref.read(relayServiceProvider).fetchPending(ack: false);
      if (pending.isEmpty) return;
      final acked = <int>[];
      for (final r in pending) {
        final routed = await _route(r);
        if (routed == null) continue; // Unroutierbar: Zeile bleibt liegen.
        final msg = Message(
          id: 'relay_${r.id}',
          senderId: r.senderId,
          receiverId: SupabaseService.currentUser?.id ?? '',
          text: r.text,
          timestamp: r.createdAt,
          type: r.kind == 'icebreaker'
              ? MessageType.icebreaker
              : MessageType.text,
        );
        // Ohne WidgetRef: addMessage ohne ref (kein _maybeNotifyMessage);
        // die Benachrichtigung läuft über den Hook unten.
        _ref.read(chatProvider.notifier).addMessage(routed, msg);
        unawaited(_notifyIncoming(routed, msg));
        acked.add(r.id);
      }
      await _ref.read(relayServiceProvider).ackRows(acked);
    } catch (e) {
      debugPrint('[RelayInbox] Poll fehlgeschlagen: $e');
    } finally {
      _busy = false;
    }
  }

  /// Ordnet eine Relay-Nachricht einer Chat-Session zu. Liefert die
  /// Session-/Match-ID oder null (= nicht zustellbar, nicht acken).
  Future<String?> _route(RelayMessage r) async {
    // 1) Funken-Match / gespeicherter QR-Kontakt (Partner bekannt)
    //    -> Match-ID (chatProvider-Key).
    final matches = _ref.read(chatProvider);
    for (final m in matches) {
      if (m.partner.id == r.senderId) {
        return m.id;
      }
    }
    // 2) Aktive Zufallschat-Session (Partner == Absender).
    final randomChat = await _resolveActiveRandomChat();
    if (randomChat != null && randomChat.partnerId == r.senderId) {
      return randomChat.sessionId;
    }
    // Unbekannter Absender (z. B. Dating-Hour-Chats): NICHT acken - der
    // zuständige Screen (mit bekannter Session-ID) holt sie ab.
    return null;
  }

  /// Lokale Benachrichtigung für eine zugestellte Nachricht (der Chat
  /// mit dem Absender ist geschlossen - siehe _tick-Gate).
  Future<void> _notifyIncoming(String routedKey, Message msg) async {
    final notify = notifier;
    if (notify == null) return;
    final matches = _ref.read(chatProvider);
    String? partnerName;
    for (final m in matches) {
      if (m.id == routedKey || m.partner.id == msg.senderId) {
        partnerName = m.partner.name;
        break;
      }
    }
    await notify(
      id: routedKey.hashCode & 0xFFFFFF,
      title: partnerName,
      body: msg.text,
      senderId: msg.senderId,
    );
  }

  /// Aktive Zufallschat-Session (30 s gecacht).
  Future<({String sessionId, String partnerId})?>
      _resolveActiveRandomChat() async {
    final now = DateTime.now();
    final cached = _activeRandomChat;
    if (cached != null &&
        _activeRandomChatAt != null &&
        now.difference(_activeRandomChatAt!) < _sessionCacheTtl) {
      return cached;
    }
    final service = _ref.read(randomChatServiceProvider);
    if (service == null) return null;
    try {
      final session = await service.getMyActiveSession() as dynamic;
      if (session == null ||
          session.sessionId == null ||
          session.partnerId == null) {
        _activeRandomChat = null;
        _activeRandomChatAt = DateTime.now();
        return null;
      }
      final result = (
        sessionId: session.sessionId as String,
        partnerId: session.partnerId as String,
      );
      _activeRandomChat = result;
      _activeRandomChatAt = DateTime.now();
      return result;
    } catch (e) {
      debugPrint('[RelayInbox] Session-Lookup fehlgeschlagen: $e');
      return null;
    }
  }
}
