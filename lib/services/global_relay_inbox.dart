import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;

import 'package:thestia/models/message.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/services/random_chat_service.dart';
import 'package:thestia/services/relay_service.dart';
import 'package:thestia/services/supabase_service.dart';

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
class GlobalRelayInbox with WidgetsBindingObserver {
  GlobalRelayInbox(this._ref);

  /// WidgetRef (vom App-Wurzel-Widget) - hat dieselbe read-API und bleibt
  /// für die gesamte App-Laufzeit gültig. `dynamic` wegen Ref/WidgetRef-
  /// Trennung in Riverpod.
  // ignore: avoid_dynamic_calls
  final dynamic _ref;
  Timer? _timer;
  bool _busy = false;
  bool _running = false;
  bool _foreground = true;

  /// Gecachte aktive Zufallschat-Session (Session-Lookup nicht pro Tick).
  ({String sessionId, String partnerId})? _activeRandomChat;
  DateTime? _activeRandomChatAt;

  static const Duration _pollInterval = Duration(seconds: 6);
  static const Duration _maxInterval = Duration(seconds: 45);

  /// Leerer-Backoff: Solange nichts kommt, wird das Intervall gestreckt
  /// (bis [_maxInterval]). Vorher pollte der Eingang stur alle 6 s, auch
  /// wenn seit Stunden keine Relay-Zeile existiert - das war einer der
  /// größten Dauer-Verbraucher im Vordergrund. Kommt wieder etwas an,
  /// geht es sofort auf [_pollInterval] zurück (Latenz bleibt erhalten).
  static const List<Duration> _backoffLadder = [
    _pollInterval,
    Duration(seconds: 12),
    Duration(seconds: 25),
    _maxInterval,
  ];
  static const Duration _sessionCacheTtl = Duration(seconds: 30);
  int _backoffStep = 0;

  /// Benachrichtigungs-Hook (wird vom App-Wurzel-Widget gesetzt, da der
  /// Inbox-Pfad kein WidgetRef hat).
  static RelayInboxNotifier? notifier;

  void start() {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _foreground = appInForeground();
    _schedule();
    unawaited(_tick());
  }

  void stop() {
    _running = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  /// Timer neu aufsetzen (Einmal-Timer statt periodic: erlaubt ein
  /// variables Intervall und echtes Pausieren im Hintergrund).
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_running || !_foreground) return;
    final step = _backoffStep.clamp(0, _backoffLadder.length - 1);
    _timer = Timer(_backoffLadder[step], () async {
      await _tick();
      _schedule();
    });
  }

  /// Hintergrund: Timer anhalten. Im Vordergrund mit frischem Intervall
  /// weiter (der Nutzer soll beim Zurückkommen sofort Nachrichten sehen).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    if (fg) {
      _backoffStep = 0;
      _schedule();
      unawaited(_tick());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Backoff eine Stufe zurücksetzen (Zustellung war erfolgreich).
  void _resetBackoff() {
    if (_backoffStep != 0) {
      _backoffStep = 0;
      _schedule();
    }
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
      if (pending.isEmpty) {
        // Leer -> eine Stufe langsamer. Ruhezustand kostet fast nichts.
        if (_backoffStep < _backoffLadder.length - 1) {
          _backoffStep++;
        } else if (_backoffLadder.last < _maxInterval) {
          _backoffStep = _backoffLadder.length - 1;
        }
        return;
      }
      _resetBackoff();
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
