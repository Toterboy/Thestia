import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;

import 'package:thestia/models/message.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/services/find_your_match_service.dart'
    show findYourMatchServiceProvider;
import 'package:thestia/services/random_chat_service.dart';
import 'package:thestia/services/relay_poll_backoff.dart';
import 'package:thestia/services/relay_service.dart';
import 'package:thestia/services/supabase_service.dart';

/// Benachrichtigungs-Hook (vom App-Wurzel-Widget mit WidgetRef verdrahtet,
/// da Ref != WidgetRef). `title` darf null sein (Hook ergänzt den
/// l10n-Fallback-Namen über seinen Kontext).
typedef RelayInboxNotifier =
    Future<void> Function({
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

  /// Gecachte Server-Funken: Partner-ID -> lokale Match-ID.
  ///
  /// BEFUND (09.11.2026): Nur fuer die Zuordnung fremder Relay-Zeilen
  /// (siehe [_route]). Der Cache verhindert, dass der RPC bei jedem
  /// Poll-Takt erneut laeuft.
  Map<String, String>? _serverMatchLookup;
  DateTime? _serverMatchLookupAt;

  /// Wie lange der Server-Funken-Cache gilt (30 s - wie die Session).
  static const Duration _serverMatchLookupTtl = Duration(seconds: 30);

  /// Poll-Takt: Leerfall UND Fehlerfall strecken das Intervall bis 45 s,
  /// erfolgreiche Zustellung geht sofort auf 6 s zurueck. Die Logik
  /// liegt in [RelayPollBackoff] (dort testbar, ohne Widget-Binding).
  final RelayPollBackoff _backoff = RelayPollBackoff();

  static const Duration _sessionCacheTtl = Duration(seconds: 30);

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
    _timer = Timer(_backoff.next, () async {
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
      _backoff.reset();
      _schedule();
      unawaited(_tick());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Backoff eine Stufe zurücksetzen (Zustellung war erfolgreich).
  void _resetBackoff() {
    if (_backoff.step != 0) {
      _backoff.onDelivered();
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
      final pending = await _ref
          .read(relayServiceProvider)
          .fetchPending(ack: false);
      await _handlePending(pending);
    } catch (e) {
      // WICHTIG: auch der Fehlerfall streckt das Intervall. Vorher stand
      // hier nur ein debugPrint, der Backoff-Step blieb 0 - bei totem
      // Netz pollte der Eingang dauerhaft alle 6 s, ohne Leere und ohne
      // Zustellung als Gegenwert. Genau das erzeugte die Dauerlast.
      _backoff.onFailure();
      debugPrint('[RelayInbox] Poll fehlgeschlagen: $e');
    } finally {
      _busy = false;
    }
  }

  /// Zustellungs-Logik. Wirft absichtlich NICHT - [_tick] und
  /// [debugPollOnce] fangen beide und strecken den Backoff.
  Future<void> _handlePending(List<RelayMessage> pending) async {
    if (pending.isEmpty) {
      // Leer -> eine Stufe langsamer. Ruhezustand kostet fast nichts.
      _backoff.onEmpty();
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
  }

  /// Ein Poll-Durchlauf mit beliebigem Fetch-Ergebnis, ohne Supabase und
  /// ohne Widget-Binding. Nur fuer Tests - ruft bewusst denselben
  /// Fehlerpfad wie [_tick], damit die Regression dort unten (Fehler
  /// streckt das Intervall nicht) tatsaechlich auffällt.
  @visibleForTesting
  Future<int> debugPollOnce({
    required List<RelayMessage> pending,
    bool throwBeforeHandling = false,
  }) async {
    try {
      if (throwBeforeHandling) throw StateError('kein Netz');
      await _handlePending(pending);
    } catch (e) {
      _backoff.onFailure();
    }
    return _backoff.step;
  }

  /// Aktuelle Backoff-Stufe (0 = schnellstes Intervall). Nur fuer Tests.
  @visibleForTesting
  int get debugBackoffStep => _backoff.step;

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

    // 1b) Server-Funke, dessen lokales Match noch fehlt.
    //
    // BEFUND (09.11.2026, Betreiber): "Nachrichten kommen nicht richtig
    // an. Eine Benachrichtigung gab es aber ich sehe die Nachricht
    // nicht."
    //
    // DER GRUND: Der lokale chatProvider kennt einen Server-Funke erst,
    // wenn sein Chat geoeffnet wurde. Vorher fand die Zuordnung hier
    // nichts -> die Zeile blieb im Relay liegen und der Nutzer sah
    // NICHTS (die Benachrichtigung kam trotzdem, weil sie der Server
    // schickt).
    //
    // JETZT: Der Funke wird einmalig vom Server geholt und lokal
    // wiederhergestellt. Danach ist die Zuordnung moeglich.
    final restored = await _restoreServerMatchFor(r.senderId);
    if (restored != null) return restored;
    // 2) Aktive Zufallschat-Session (Partner == Absender).
    final randomChat = await _resolveActiveRandomChat();
    if (randomChat != null && randomChat.partnerId == r.senderId) {
      return randomChat.sessionId;
    }
    // Unbekannter Absender (z. B. Dating-Hour-Chats): NICHT acken - der
    // zuständige Screen (mit bekannter Session-ID) holt sie ab.
    return null;
  }

  /// Stellt einen Server-Funke lokal wieder her, damit eine Relay-
  /// Nachricht ihm zugeordnet werden kann.
  ///
  /// BEFUND (09.11.2026): Ohne das blieb die Nachricht unsichtbar (siehe
  /// [_route]). Der Server-Funke wird hier einmalig geholt
  /// (`list_my_matches_with_state`) und mit derselben Match-ID lokal
  /// angelegt - genau so, wie der Chat-Screen es tut. Damit stimmen
  /// Match-ID und Chat-Route zusammen.
  ///
  /// Best-Effort: Scheitert der RPC, bleibt null - die Zeile bleibt
  /// liegen (kein Datenverlust) und wird beim naechsten Poll erneut
  /// versucht.
  Future<String?> _restoreServerMatchFor(String partnerId) async {
    if (!SupabaseService.isInitialized) return null;
    // Nicht bei jedem Poll neu laden: der Server-Funkensatz aendert
    // sich selten, und der RPC ist der teuerste Schritt hier.
    final now = DateTime.now();
    if (_serverMatchLookupAt != null &&
        now.difference(_serverMatchLookupAt!) < _serverMatchLookupTtl) {
      return _serverMatchLookup?[partnerId];
    }
    try {
      final service = _ref.read(findYourMatchServiceProvider);
      final matches = await service.listMatchesWithState();
      final map = <String, String>{};
      for (final m in matches) {
        map[m.partner.id] = m.matchId.toString();
      }
      _serverMatchLookup = map;
      _serverMatchLookupAt = DateTime.now();
      final matchId = map[partnerId];
      if (matchId == null) return null;
      // Lokal anlegen (gleiche ID wie die Chat-Route) - sonst findet
      // der Chat-Screen das Match nicht.
      final partner = matches
          .firstWhere((m) => m.partner.id == partnerId)
          .partner;
      _ref
          .read(chatProvider.notifier)
          .restoreServerMatch(matchId, partner, DateTime.now());
      return matchId;
    } catch (e) {
      debugPrint('[RelayInbox] Server-Funke nicht ladbar: $e');
      return null;
    }
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
