import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:thestia/models/message.dart';
import 'package:thestia/models/random_chat_session.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/routing/app_router.dart';import 'package:thestia/services/find_your_match_service.dart';
import 'package:thestia/services/p2p_chat_service.dart';
import 'package:thestia/services/random_chat_service.dart';
import 'package:thestia/services/relay_service.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/widgets/chat_bubbles.dart';
import 'package:thestia/l10n/app_strings.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_join);
  }

  @override
  void dispose() {
    // Aktiven Chat freigeben (Notification-Unterdrückung nur solange der
    // Chat sichtbar ist).
    if (ref.read(activeChatIdProvider) == (_sessionId ?? 'random')) {
      ref.read(activeChatIdProvider.notifier).state = null;
    }
    if (ref.read(activeChatPeerIdProvider) == _partnerId) {
      ref.read(activeChatPeerIdProvider.notifier).state = null;
    }
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

  Future<void> _join() async {
    final service = ref.read(randomChatServiceProvider);
    if (service == null) {
      if (mounted) {
        setState(() {
          _state = _RandomChatState.error;
          _errorKey = 'random.errorOffline';
        });
      }
      return;
    }

    // Ein Retry bei transientem RPC-Fehler, bevor die Fehlermeldung kommt
    // (z. B. Netzwerkwechsel kurz nach dem Screen-Öffnen).
    var session = await service.join();
    if (session == null) {
      await Future.delayed(const Duration(milliseconds: 1500));
      session = await service.join();
    }
    if (!mounted) return;

    if (session == null || session.sessionId == null) {
      setState(() {
        _state = _RandomChatState.error;
        _errorKey = 'random.errorNoPartner';
      });
      return;
    }

    _sessionId = session.sessionId;
    if (session.isMatched) {
      _instantReconnect = true; // Reconnect auf (Alt-)Session.
      await _onMatched(session);
    } else {
      _instantReconnect = false;
      if (mounted) setState(() => _state = _RandomChatState.searching);
      _startSearchPolling();
    }
  }

  void _startSearchPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final service = ref.read(randomChatServiceProvider);
      final sessionId = _sessionId;
      if (service == null || sessionId == null || !mounted) return;
      final session = await service.getSession(sessionId);
      if (!mounted || session == null) return;
      if (session.status == RandomChatStatus.ended) {
        _pollTimer?.cancel();
        if (_state != _RandomChatState.chat) {
          if (!_leaving && mounted && _rejoinCount < 5) {
            // Partner hat kurz gematcht und ist sofort wieder gegangen:
            // weitersuchen statt abbrechen (begrenzt gegen Loop).
            _rejoinCount++;
            setState(() => _state = _RandomChatState.searching);
            await _join();
            return;
          }
          setState(() => _state = _RandomChatState.error);
          _errorKey = 'random.errorUnavailable';
        }
        return;
      }
      if (session.isMatched) {
        _pollTimer?.cancel();
        await _onMatched(session);
      }
    });
  }

  Future<void> _onMatched(RandomChatSession session) async {
    _sessionId = session.sessionId;
    _partnerId = session.partnerId;
    if (mounted) setState(() => _state = _RandomChatState.matched);

    // Partner-Profil laden (Name/Alter für die Anzeige). Best effort.
    if (_partnerId != null && SupabaseService.isInitialized) {
      try {
        final row = await SupabaseDatabaseService(SupabaseService.client)
            .fetchPublicProfile(_partnerId!);
        if (row != null && mounted) {
          setState(() {
            _partner = UserProfile(
              id: _partnerId!,
                name: (row['name'] as String?) ??
                    L10n.t(context, 'random.fallbackPartnerName'),
              bio: '',
              interests: const [],
              city: row['city'] as String? ?? '',
            );
          });
        }
      } catch (e) {
        debugPrint('[RandomChat] Profil laden fehlgeschlagen: $e');
      }
    }
    if (_partner == null && mounted) {
setState(() {
  _partner = UserProfile(
      id: _partnerId!,
      name: L10n.t(context, 'random.fallbackPartnerName'),
      bio: '');
});
    }

    await _initP2P();
    // Verbindungs-Deadline (Backstop - das ECHTE Scheitern meldet der
    // ICE-Listener früher): Instant-Reconnects (Match stand schon beim
    // join() fest) bekommen eine kürzere Frist.
    _handshakeDeadline = DateTime.now().add(
      Duration(seconds: _instantReconnect ? 15 : 25),
    );
    if (mounted) setState(() => _state = _RandomChatState.chat);
    _startStatusPolling();
    // NUTZERWUNSCH: Keine Benachrichtigung, solange dieser Chat sichtbar
    // ist (Nachrichten erscheinen direkt auf dem Bildschirm). Die
    // Partner-ID dient dem Server-Push-Handler (Metadaten enthalten den
    // Absender), die Session-ID dem lokalen Nachrichtenpfad.
    ref.read(activeChatIdProvider.notifier).state = _sessionId ?? 'random';
    ref.read(activeChatPeerIdProvider.notifier).state = _partnerId;
  }

  /// Baut die E2E-P2P-Verbindung zum gematchten Partner auf.
  Future<void> _initP2P() async {
    final p2p = ref.read(p2pChatServiceProvider);
    _p2p = p2p;

    // Eigene ID strikt aus der Supabase-Session (Fix): Stale Secure-Store-
    // Werte (alter Account, Demo-'me') erzeugen ein Signaling-Topic, das
    // die echte auth.uid() nicht enthaelt -> Realtime-RLS verweigert den
    // Join und das Peer-Pinning verwirft jede Nachricht. Ohne Session
    // gibt es hier bewusst KEINEN Fallback mehr, sondern einen Fehler.
    final myId = SupabaseService.currentUser?.id;
    if (myId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'random.notLoggedIn')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    _myUserId = myId;
    final peerId = _partnerId!;

    _msgSub = p2p.incomingMessages.listen((text) {
      if (!mounted) return;
      final msg = _localMessage(text, senderId: peerId);
      ref.read(chatProvider.notifier)
          .addMessage(_sessionId ?? 'random', msg, ref: ref);
    });

    // Ehrlicher Verbindungsstatus: den echten DataChannel-Zustand
    // abbilden statt des Screen-States.
    _dcSub?.cancel();
    _dcSub = p2p.connectionState.listen((state) {
      if (!mounted) return;
      final open = state == RTCDataChannelState.RTCDataChannelOpen;
      if (open) {
        _handshakeDeadline = null; // Verbunden: Deadline obsolet.
        _rejoinCount = 0; // ECHT verbunden: Rejoin-Budget zurücksetzen.
        if (_relayMode) {
          // Upgrade: Direkter Kanal kam doch noch zustande (Partner
          // hat erneut verbunden) - zurück auf P2P, Relay-Polling stoppen,
          // Status-Polling neu starten (Fix: Partner-Left-Erkennung und
          // Retry liefen nach dem Upgrade sonst nie wieder).
          _relayMode = false;
          _relayTimer?.cancel();
          _relayTimer = null;
          _startStatusPolling();
        }
      }
      if (open != _dataChannelOpen) {
        setState(() => _dataChannelOpen = open);
      }
    });

    // Sofort-Fallback: Meldet ICE definitives Scheitern (Failed), nicht
    // erst auf die ganze Deadline warten - Mobilfunk-Nutzer chatten
    // dann über den E2E-Relay, ohne die Wartezeit.
    _iceSub?.cancel();
    _iceSub = p2p.iceConnectionState.listen((state) {
      if (!mounted || _leaving) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _handshakeDeadline = null;
        _enterRelayMode();
      }
    });

    // Relay-Wake-up: Der Partner hat eine Relay-Nachricht hinterlegt -
    // sofort abholen statt auf den nächsten Poll-Takt zu warten.
    // LATENZ-FIX: Reaktion auch außerhalb des Relay-Modus - wer zuerst
    // in den Relay-Modus wechselt, muss nicht auf den ersten Poll des
    // Partners warten; der fetch ist mit from-Filter harmlos.
    _pingSub?.cancel();
    _pingSub = p2p.relayPing.listen((_) {
      if (mounted && !_leaving) {
        unawaited(_fetchRelay());
      }
    });

    try {
      await p2p.connect(myUserId: _myUserId!, peerId: peerId);
    } catch (e) {
      debugPrint('[RandomChat] P2P Verbindung fehlgeschlagen: $e');
      if (mounted) {
        // 404 = Partner-Gerät hat noch kein Schlüssel-Bundle veröffentlicht
        // (startet gerade erst die neue App-Version). KEIN harter Fehler:
        // freundlicher Wartezustand, die 25-s-Wiederholung verbindet
        // automatisch, sobald das Bundle da ist.
        final waitingForPartner = e.toString().contains('404');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              waitingForPartner
                  ? L10n.t(context, 'random.waitingForPartner')
                  : L10n.tf(context, 'random.connectFailed',
                      {'error': '$e'}),
            ),
            behavior: SnackBarBehavior.floating,
            duration: waitingForPartner
                ? const Duration(seconds: 6)
                : const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Prüft regelmäßig, ob der Partner die Session verlassen hat - und
  /// versucht nebenbei den P2P-Handshake erneut, solange kein direkter
  /// Kanal steht (erstes Offer geht leicht ins Leere, wenn der Peer noch
  /// nicht subscribed ist). Läuft der Handshake trotz Retries in die
  /// Verbindungs-Deadline, wird ein sichtbarer Fehler gemeldet.
  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final service = ref.read(randomChatServiceProvider);
      final sessionId = _sessionId;
      if (service == null || sessionId == null || !mounted) return;
      final session = await service.getSession(sessionId);
      if (!mounted || session == null) return;
      if (session.status == RandomChatStatus.ended && !_leaving) {
        _statusTimer?.cancel();
        _showPartnerLeftDialog();
        return;
      }
      // Verbindungs-Timeout: DataChannel nie offen geworden. Der Chat wird
      // NICHT verlassen (Betreiber-Entscheidung) - stattdessen
      // RELAY-FALLBACK mit dem AKTUELLEN Partner: Nachrichten laufen
      // E2E-verschlüsselt über den Server (Mobilfunk/CGNAT ohne TURN).
      // Kommt der direkte Kanal später doch zustande, schaltet der Chat
      // automatisch zurück.
      final p2p = _p2p;
      if (p2p != null &&
          !p2p.isDataChannelOpen &&
          _handshakeDeadline != null &&
          DateTime.now().isAfter(_handshakeDeadline!)) {
        _handshakeDeadline = null;
        _enterRelayMode();
        return;
      }
      if (!_relayMode) {
        await _retryHandshakeThrottled();
      }
    });
  }

  /// Schaltet in den Relay-Fallback-Modus (kein direkter Kanal, z. B.
  /// Mobilfunk/CGNAT): Chat läuft E2E-verschlüsselt über den Server-Relay
  /// weiter. Vorher geschriebene Nachrichten (Outbox) werden nachgeliefert.
  void _enterRelayMode() {
    if (_leaving || !mounted || _sessionId == null || _partnerId == null) {
      return;
    }
    if (_relayMode) return;
    _statusTimer?.cancel();
    setState(() {
      _relayMode = true;
      _state = _RandomChatState.chat;
    });
    // Diagnose sichtbar machen: Der Nutzer soll WISSEN, dass der Router
    // (AP-Isolation) oder das Mobilfunknetz die Direktverbindung blockiert.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'random.relayNoDirect')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
    final relayPeer = _partnerId!;
    final p2p = _p2p;
    if (p2p != null) {
      unawaited(p2p
          .drainOutboxViaRelay((text) => ref
              .read(relayServiceProvider)
              .storeText(peerId: relayPeer, text: text))
          .then((_) => unawaited(p2p.sendRelayPing())));
    }
    _startRelayPolling();
  }

  /// Handshake-Retry, gedrosselt auf max. einen Versuch alle 25 Sekunden
  /// (nur im geöffneten Chat im Vordergrund). Im Relay-Modus aus: Der
  /// Chat läuft ohnehin, erneute P2P-Versuche kosten nur Akku/Requests.
  Future<void> _retryHandshakeThrottled() async {
    final p2p = _p2p;
    if (_relayMode) return;
    if (_state != _RandomChatState.chat || p2p == null || !mounted) return;
    if (p2p.isConnected) return;
    if (!SupabaseService.isInitialized) return;
    final myId = _myUserId;
    final peerId = _partnerId;
    if (myId == null || peerId == null) return;
    final now = DateTime.now();
    if (_lastHandshakeRetry != null &&
        now.difference(_lastHandshakeRetry!) <
            const Duration(seconds: 25)) {
      return;
    }
    _lastHandshakeRetry = now;
    try {
      await p2p.ensureConnected(myUserId: myId, peerId: peerId);
    } catch (e) {
      debugPrint('[RandomChat] Handshake-Retry fehlgeschlagen: $e');
    }
  }

  // ------------------------------------------------------------------ Chat --

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    if (_partnerId == null || _myUserId == null) {
      // Allein in der Warteschlange (Test mit nur einem Konto) oder ohne
      // Session: still verwerfen statt irrefuehrendem Sende-Fehler.
      return;
    }
    _ctrl.clear();

    final local = _localMessage(text, senderId: _myUserId!);
    ref.read(chatProvider.notifier)
        .addMessage(_sessionId ?? 'random', local, ref: ref);

    // Relay-Modus (kein direkter Kanal, z. B. Mobilfunk): E2E-verschlüsselt
    // über den Server-Relay zustellen statt über den DataChannel. Danach
    // Wake-up-Ping an den Partner (sofortige Zustellung statt Polling).
    if (_relayMode) {
      try {
        await ref
            .read(relayServiceProvider)
            .storeText(peerId: _partnerId!, text: text);
        unawaited(_p2p?.sendRelayPing());
        // NUTZERWUNSCH "Nachrichten ohne Chat-Screen": Push an die Person,
        // dass eine Nachricht wartet (serverseitig generierter Text, nur
        // Metadaten; Beziehung = aktive Zufallschat-Session, Migration im
        // notify-user-Update).
        unawaited(() async {
          try {
            await SupabaseService.client.functions.invoke(
              'notify-user',
              body: {'kind': 'messages', 'target_user_id': _partnerId},
            );
          } catch (_) {}
        }());
      } catch (e) {
        debugPrint('[RandomChat] Relay-Send fehlgeschlagen: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'random.sendFailed')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      return;
    }

    try {
      await _p2p?.sendText(text);
    } catch (e) {
      debugPrint('[RandomChat] Sende-Fehler: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'random.sendFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ------------------------------------------------------------- Relay --

  /// Polling im Relay-Modus: alle 2 s abholen (Partner speichert neue
  /// Nachrichten serverseitig zwischen; der Wake-up-Ping liefert SOFORT,
  /// dieser Timer fängt verlorene Pings ab - Latenz-Kompromiss Akku).
  /// Läuft nur bei offenem Chat im Vordergrund.
  void _startRelayPolling() {
    _relayTimer?.cancel();
    _relayTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _leaving || !_relayMode) return;
      await _fetchRelay();
    });
    unawaited(_fetchRelay());
  }

  Future<void> _fetchRelay() async {
    final peerId = _partnerId;
    if (peerId == null || !SupabaseService.isInitialized) return;
    try {
      // Nur Zeilen des AKTUELLEN Partners abholen/bestätigen.
      final pending =
          await ref.read(relayServiceProvider).fetchPending(from: peerId);
      if (!mounted || pending.isEmpty) return;
      for (final r in pending) {
        final msgId = 'relay_${r.id}';
        if (_seenRelayIds.contains(msgId)) continue;
        _seenRelayIds.add(msgId);
        final msg = _localMessage(r.text, senderId: peerId);
        ref.read(chatProvider.notifier)
            .addMessage(_sessionId ?? 'random', msg, ref: ref);
      }
    } catch (_) {
      // Netzwerkfehler: nächster Poll-Takt versucht es erneut.
    }
  }

  Message _localMessage(String text, {required String senderId}) {
    return Message(
      id: Message.newId('p2p'),
      senderId: senderId,
      receiverId:
          senderId == _myUserId ? (_partnerId ?? '') : (_myUserId ?? ''),
      text: text,
      timestamp: DateTime.now(),
    );
  }

  /// Liken: markiert den Zufallspartner als gefallen.
  ///
  /// NUTZERWUNSCH "Doppelte Funken / einseitiger Funke": Der lokale
  /// Match-Eintrag entstand NUR auf der Likenden-Seite (einseitiger
  /// Funke) und bei gegenseitigem Liken sogar ZWEIMAL (lokal + Server-
  /// Pipeline). Jetzt: NUR der serverseitige Like - der Funke entsteht
  /// serverseitig in der Bestandspipeline, sobald BEIDE geliked haben
  /// (kanonisches Match für beide), nie einseitig und nie doppelt.
  Future<void> _likePartner() async {
    final partner = _partner;
    if (partner == null) return;
    if (SupabaseService.isInitialized) {
      try {
        await ref.read(findYourMatchServiceProvider).likeUser(partner.id);
      } catch (e) {
        debugPrint('[RandomChat] Server-Like fehlgeschlagen: $e');
      }
      // Push an die Person (sie sieht den Like in "Erhalten").
      try {
        await SupabaseService.client.functions.invoke(
          'notify-user',
          body: {'kind': 'likes', 'target_user_id': partner.id},
        );
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              L10n.t(context, 'random.likeSentWaiting')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'random.leaveTitle')),
        content: Text(L10n.t(ctx, 'random.leaveBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(L10n.t(ctx, 'random.leaveConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _leaving = true;
    final service = ref.read(randomChatServiceProvider);
    final sessionId = _sessionId;
    if (service != null && sessionId != null) {
      await service.leave(sessionId);
    }
    await _p2p?.disconnect();
    ref.read(chatProvider.notifier).dissolveMatch(sessionId ?? 'random');
    if (mounted) {
      context.go(AppRoutes.swipeModeSelection);
    }
  }

  void _showPartnerLeftDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'random.endedTitle')),
        content: Text(L10n.t(context, 'random.partnerLeft')),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) context.go(AppRoutes.swipeModeSelection);
            },
            child: Text(L10n.t(context, 'random.backToDiscover')),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- UI --

  @override
  Widget build(BuildContext context) {
    // KRITISCHER UI-FIX: ref.watch(chatProvider) watcht den STATE
    // (List<Match>) — rebuildet bei jeder addMessage. Vorher stand hier
    // ref.watch(chatProvider.notifier), das den Notifier selbst watcht
    // (der NIE wechselt) — die UI rebuildete daher NIE, und Nachrichten
    // "verschwanden im Nichts", obwohl sie im Store waren.
    ref.watch(chatProvider);
    final messages =
        ref.read(chatProvider.notifier).messagesFor(_sessionId ?? 'random');
    final partner = _partner;
    // Nutzerwunsch Gruppierung: Namens-Header an Gruppenstarts (max. 3
    // Nachrichten / 3 Minuten pro Gruppe), Zeit an jeder Bubble.
    final bubbleGroups = computeBubbleGroups(messages);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _confirmLeave(),
        ),
        title: Text(partner?.name ??
            L10n.t(context, 'random.fallbackTitle')),
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
            message: L10n.t(
                context, _errorKey ?? 'random.errorUnavailable'),
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
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
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
                    if (!_dataChannelOpen && !_relayMode &&
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
                              const Icon(Icons.chat_bubble_outline,
                                  size: 56, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                L10n.tf(context, 'random.hello', {
                                  'name': partner?.name ??
                                      L10n.t(context,
                                          'random.helloDefault')
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
                                  L10n.t(context,
                                      'random.fallbackPartnerName'));
                          String timeLabel = '';
                          try {
                            timeLabel = DateFormat.Hm()
                                .format(msg.timestamp.toLocal());
                          } catch (_) {}
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
                                        bottom: 2, left: 4, right: 4),
                                    child: Text(
                                      name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                    ),
                                  ),
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            0.75,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mine
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    msg.text,
                                    style: TextStyle(
                                      color: mine
                                          ? Colors.white
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (timeLabel.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 2, left: 6, right: 6),
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
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          maxLines: 5,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText: L10n.t(context, 'random.hint'),
                            border: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(24)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      },
    );
  }
}

class _SearchingView extends StatelessWidget {
  const _SearchingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(L10n.t(context, 'random.searching')),
            const SizedBox(height: 8),
            Text(
              L10n.t(context, 'random.searchingSub'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectingView extends StatelessWidget {
  const _ConnectingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(L10n.t(context, 'random.connecting')),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
