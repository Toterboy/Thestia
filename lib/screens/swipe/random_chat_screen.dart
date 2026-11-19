import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/chat/random_chat_session.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/dating_hour/find_your_match_service.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/dating_hour/random_chat_service.dart';
import 'package:thestia/services/chat/relay_service.dart';
import 'package:thestia/services/server/supabase_database_service.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/widgets/chat/chat_bubbles.dart';
import 'package:thestia/widgets/chat/secure_composer.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/utils/common/best_effort.dart';

part 'parts/zufallchataktionen.dart';

part 'parts/zufallchatverbindung.dart';

part 'parts/zufallchatsuche.dart';

part 'parts/searchingview.dart';
part 'parts/connectingview.dart';
part 'parts/errorview.dart';

/// Zufallschat: echtes Matching über die Supabase-Warteschlange
/// (Migration 032) und E2E-verschlüsselter Chat über den P2P-DataChannel.
///
/// Ablauf:
///  1. join_random_chat() - sofortiger Partner oder Warteschlange.
///  2. Polling (2 s), bis ein Partner gematcht wurde.
///  3. P2P-Verbindung (Signal Protocol + WebRTC) - Nachrichten verlassen
///     das Gerät nur verschlüsselt.
class RandomChatScreen extends ConsumerStatefulWidget {
  const RandomChatScreen({super.key});

  @override
  ConsumerState<RandomChatScreen> createState() => _RandomChatScreenState();
}

enum _RandomChatState { searching, matched, chat, error, ended }

class _RandomChatScreenState extends ConsumerState<RandomChatScreen>
    with WidgetsBindingObserver {
  final _ctrl = TextEditingController();

  _RandomChatState _state = _RandomChatState.searching;
  String? _sessionId;
  String? _partnerId;
  String? _myUserId;
  UserProfile? _partner;
  String? _errorKey;
  bool _leaving = false;

  P2PChatService? _p2p;
  StreamSubscription<String>? _msgSub;
  StreamSubscription<RTCDataChannelState>? _dcSub;
  StreamSubscription<RTCIceConnectionState>? _iceSub;
  StreamSubscription<void>? _pingSub;
  Timer? _pollTimer;
  Timer? _statusTimer;
  // Handshake-Retry (v0.9.1-Fix): Drosselung, max. alle 25 s.
  DateTime? _lastHandshakeRetry;
  // Auto-Rejoin (Fix "Suche bricht nach Sekunden ab"): Verlässt der
  // frisch gematchte Partner den Chat sofort wieder (typisch bei
  // P2P-Fehlern), bekam die Suchende Seite 'ended' und zeigte einen
  // Fehler. Stattdessen: automatisch neu in die Warteschlange.
  int _rejoinCount = 0;
  // True, wenn der Match SOFORT beim join() zustande kam (= Reconnect auf
  // eine bestehende/Alt-Session, evtl. mit totem Partner). Solche Sessions
  // bekommen eine kürzere Deadline und werden bei Timeout automatisch
  // verlassen und neu gesucht (Fix "Android-16-Gerät sucht nicht").
  bool _instantReconnect = false;
  // Relay-Fallback (Mobilfunk/CGNAT, kein TURN): Kommt kein direkter
  // DataChannel zustande, läuft der Chat E2E-verschlüsselt über den
  // Supabase-Relay (Migration 093/098) weiter statt in einer Fehler-
  // Sackgasse zu enden.
  bool _relayMode = false;
  Timer? _relayTimer;
  final Set<String> _seenRelayIds = {};
  // Ehrlicher Verbindungsstatus: erst der offene DataChannel zahlt
  // (nicht der Screen-State) - Fix "AppBar zeigt 'verbunden' ohne
  // Verbindung".
  bool _dataChannelOpen = false;
  // Verbindungs-Deadline: ohne offenen DataChannel nach 45 s -> sichtbarer
  // Fehler statt stiller "verbunden"-Optik.
  DateTime? _handshakeDeadline;

  /// Die Notifier der beiden "aktiver Chat"-Markierungen.
  ///
  /// BEFUND (13.11.2026, gefunden von einem Test): `ref.read` im
  /// `dispose()` wirft - Riverpod hat den Consumer-State da schon
  /// abgeraeumt ("Cannot use ref after the widget was disposed"). Damit
  /// blieb die Notification-Unterdrueckung fuer diesen Chat BIS ZUM
  /// APP-ENDE stehen: die Meldungen des Partners kamen nicht an.
  ///
  /// DER WEG (14.11.2026): Die Notifier werden im `initState` geholt.
  /// Der StateNotifier lebt laenger als der Screen - so wird die
  /// Unterdrueckung wirklich wieder aufgehoben.
  late final StateController<String?> _aktiveChatId;
  late final StateController<String?> _aktiveChatPeerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Die Notifier jetzt holen: im dispose() ist `ref` nicht mehr
    // benutzbar (siehe die Erklaerung beim Feld).
    _aktiveChatId = ref.read(activeChatIdProvider.notifier);
    _aktiveChatPeerId = ref.read(activeChatPeerIdProvider.notifier);
    Future.microtask(_join);
  }

  @override
  void dispose() {
    // Aktiven Chat freigeben (Notification-Unterdrueckung nur solange der
    // Chat sichtbar ist).
    //
    // BEFUND (13.11.2026, gefunden von einem Test): `ref.read` im
    // dispose() wirft - Riverpod hat den Consumer-State da schon
    // abgeraeumt ("Cannot use ref after the widget was disposed"). Damit
    // blieb die Notification-Unterdrueckung fuer diesen Chat BIS ZUM
    // APP-ENDE stehen: die Meldungen des Partners kamen nicht an.
    // Der Chat-Screen macht es seit langem richtig (mit try/catch).
    //
    // DER WEG (14.11.2026): Ueber die Notifier, die schon im initState
    // geholt wurden - damit wird die Markierung WIRKLICH geloescht.
    //
    // DER WEG (18.11.2026, gefunden von einem Test): Das Ruecksetzen
    // muss einen Frame warten. Wird der Bildschirm waehrend eines
    // Routenwechsels abgeraeumt (der Nutzer beendet den Chat), passiert
    // das dispose() MITTEN IM AUFBAU - und Riverpod verbietet das
    // Aendern eines Providers waehrend des Aufbaus ("Tried to modify a
    // provider while the widget tree was building"). Die Markierung
    // blieb dann stehen: die Meldungen des Partners kamen nicht an.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bestEffortSync('aktiven Chat freigeben', () {
        if (_aktiveChatId.state == (_sessionId ?? 'random')) {
          _aktiveChatId.state = null;
        }
        if (_aktiveChatPeerId.state == _partnerId) {
          _aktiveChatPeerId.state = null;
        }
      });
    });
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _statusTimer?.cancel();
    _relayTimer?.cancel();
    _msgSub?.cancel();
    _dcSub?.cancel();
    _iceSub?.cancel();
    _pingSub?.cancel();
    _p2p?.disconnect();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hintergrund: Polling-Timer pausieren (v0.9.1, Akku). Vordergrund:
    // neu starten (nur solange Suche/Chat aktiv).
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _statusTimer?.cancel();
      _statusTimer = null;
      _relayTimer?.cancel();
      _relayTimer = null;
    } else if (state == AppLifecycleState.resumed && mounted && !_leaving) {
      if (_state == _RandomChatState.searching && _pollTimer == null) {
        _startSearchPolling();
      } else if (_state == _RandomChatState.chat && _statusTimer == null) {
        _startStatusPolling();
      }
      if (_relayMode && _relayTimer == null) {
        _startRelayPolling();
      }
    }
  }

  // ------------------------------------------------------------- Matching --

  /// Relay-Polling im Relay-Modus als Einmal-Timer mit variablem Intervall.
  ///
  /// Der Wake-up-Ping liefert Nachrichten sofort; dieser Timer fängt nur
  /// verlorene Pings ab. Ein Chat ohne Verkehr ist der Normalfall, deshalb
  /// wird das Intervall bei leerem Ergebnis gestreckt (2 s -> 6 s -> 15 s)
  /// statt 1800 RPCs pro Stunde zu feuern. Kommt etwas an, geht es sofort
  /// auf 2 s zurueck.
  static const List<Duration> _relayIntervals = [
    Duration(seconds: 2),
    Duration(seconds: 6),
    Duration(seconds: 15),
  ];
  int _relayBackoffStep = 0;

  Message _localMessage(String text, {required String senderId}) {
    return Message(
      id: Message.newId('p2p'),
      senderId: senderId,
      receiverId: senderId == _myUserId
          ? (_partnerId ?? '')
          : (_myUserId ?? ''),
      text: text,
      timestamp: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // KRITISCHER UI-FIX: ref.watch(chatProvider) watcht den STATE
    // (List<Match>) — rebuildet bei jeder addMessage. Vorher stand hier
    // ref.watch(chatProvider.notifier), das den Notifier selbst watcht
    // (der NIE wechselt) — die UI rebuildete daher NIE, und Nachrichten
    // "verschwanden im Nichts", obwohl sie im Store waren.
    ref.watch(chatProvider);
    final messages = ref
        .read(chatProvider.notifier)
        .messagesFor(_sessionId ?? 'random');
    final partner = _partner;
    // Nutzerwunsch Gruppierung: Namens-Header an Gruppenstarts (max. 3
    // Nachrichten / 3 Minuten pro Gruppe), Zeit an jeder Bubble.
    final bubbleGroups = computeBubbleGroups(messages);

    return PopScope(
      // BEFUND (13.11.2026, Betreiber: "Wenn man zurueck wischt bei
      // Zufallschat, wird man nicht nochmal gefragt, ob man ihn beenden
      // moechte"): Das System-Zurueck (Wischen vom Rand oder der
      // Zurueck-Knopf des Systems) sprang ohne Rueckfrage aus dem
      // Zufallschat - der Partner blieb auf der Plattform stehen und die
      // Sitzung lief weiter.
      //
      // Der Knopf oben links fragt schon - jetzt fragt auch das Wischen.
      // `canPop: false` ist noetig, damit der System-Zurueck ueberhaupt
      // bei uns landet (sonst wuerde Flutter poppen, ohne uns zu fragen).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _confirmLeave(),
          ),
          title: Text(partner?.name ?? L10n.t(context, 'random.fallbackTitle')),
          actions: [
            if (_state == _RandomChatState.chat)
              IconButton(
                icon: const Icon(Icons.favorite),
                tooltip: L10n.t(context, 'random.likeTooltip'),
                onPressed: _likePartner,
              ),
            IconButton(
              icon: const Icon(Icons.block),
              tooltip: L10n.t(context, 'random.endTooltip'),
              onPressed: _confirmLeave,
            ),
          ],
        ),
        body: switch (_state) {
          _RandomChatState.searching => const _SearchingView(),
          _RandomChatState.matched => const _ConnectingView(),
          _RandomChatState.error => _ErrorView(
            message: L10n.t(context, _errorKey ?? 'random.errorUnavailable'),
          ),
          _RandomChatState.ended => _ErrorView(
            message: L10n.t(context, 'random.errorEnded'),
          ),
          _RandomChatState.chat => Column(
            children: [
              // Verbindungsstatus als abgerundetes Popup (Banner) — mit
              // Ladekreis, wenn der Verbindungsaufbau läuft.
              Container(
                margin: const EdgeInsets.only(top: 8, left: 16, right: 16),
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: _dataChannelOpen
                      ? Colors.green.withValues(alpha: 0.12)
                      : _relayMode
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_dataChannelOpen &&
                        !_relayMode &&
                        _state == _RandomChatState.chat) ...[
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                    ] else ...[
                      Icon(
                        _dataChannelOpen
                            ? Icons.check_circle_outline
                            : Icons.cloud_sync_outlined,
                        size: 14,
                        color: _dataChannelOpen
                            ? Colors.green
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        _dataChannelOpen
                            ? 'Verbunden (E2E P2P)'
                            : _relayMode
                            ? L10n.t(context, 'random.relayStatus')
                            : 'Verbindung wird hergestellt…',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.chat_bubble_outline,
                                size: 56,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                L10n.tf(context, 'random.hello', {
                                  'name':
                                      partner?.name ??
                                      L10n.t(context, 'random.helloDefault'),
                                }),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        reverse: true,
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final idx = messages.length - 1 - i;
                          final msg = messages[idx];
                          final mine = msg.isFrom(_myUserId ?? '');
                          final group = idx >= 0 && idx < bubbleGroups.length
                              ? bubbleGroups[idx]
                              : (showName: true, showTime: true);
                          final name = mine
                              ? L10n.t(context, 'chat.you')
                              : (partner?.name ??
                                    L10n.t(
                                      context,
                                      'random.fallbackPartnerName',
                                    ));
                          String timeLabel = '';
                          bestEffortSync('Hm.format', () {
                            timeLabel = DateFormat.Hm().format(
                              msg.timestamp.toLocal(),
                            );
                          });
                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: mine
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (group.showName)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 2,
                                      left: 4,
                                      right: 4,
                                    ),
                                    child: Text(
                                      name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                    ),
                                  ),
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                        0.75,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mine
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    msg.text,
                                    style: TextStyle(
                                      color: mine
                                          ? Colors.white
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (timeLabel.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 2,
                                      left: 6,
                                      right: 6,
                                    ),
                                    child: Text(
                                      timeLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant
                                                .withValues(alpha: 0.7),
                                            fontSize: 10,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              // Die eigene Tastatur (v0.10.1): die Systemtastatur sieht
              // keinen einzelnen Buchstaben.
              SecureComposer(
                controller: _ctrl,
                hintText: L10n.t(context, 'random.hint'),
                onSend: _send,
              ),
            ],
          ),
        },
      ),
    );
  }

  /// Setzt den Zustand - aufrufbar auch aus den Erweiterungen.
  ///
  /// DER GRUND: In einer Erweiterung darf `setState` nicht aufgerufen
  /// werden (der Analyser erlaubt es nur in Instanzmitgliedern einer
  /// State-Klasse). Diese Methode gehoert zur Klasse - die Erweiterung
  /// ruft sie auf.
  void _setzeState(VoidCallback fn) => setState(fn);
}
