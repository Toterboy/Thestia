import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:thestia/models/dating_hour_models.dart';
import 'package:thestia/models/message.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/interests/interessen_screen.dart'
    show interessenInitialTabProvider;
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/chat_backgrounds.dart';
import 'package:thestia/widgets/chat_bubbles.dart';
import 'package:thestia/widgets/funke_overlay.dart';
import 'package:thestia/services/dating_hour_service.dart';
import 'package:thestia/services/find_your_match_service.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/p2p_chat_service.dart';
import 'package:thestia/services/relay_service.dart';

/// Screen für den aktiven Dating Hour Chat (5-Minuten-Timer).
///
/// Lädt die Session serverseitig anhand ihrer ID, zeigt den Countdown bis zum
/// Ablauf und ermöglicht die Entscheidung (Annehmen/Ablehnen). Bei beidseitigem
/// Accept wird ein Match erzeugt und zur Matches-Seite navigiert.
///
/// Nachrichten laufen E2E-verschlüsselt: primär über den P2P-DataChannel
/// ([P2PChatService]) - identisch zum 1:1-Chat; bei geschlossenem Kanal
/// über den Server-Relay (Migration 093/106), der Server sieht nur
/// Ciphertext. Kein Nachrichteninhalt im Klartext Richtung Server.
class DatingHourChatScreen extends ConsumerStatefulWidget {
  const DatingHourChatScreen({required this.sessionId, super.key});
  final String sessionId;

  @override
  ConsumerState<DatingHourChatScreen> createState() => _DatingHourChatScreenState();
}

class _DatingHourChatScreenState extends ConsumerState<DatingHourChatScreen>
    with WidgetsBindingObserver {
  /// Cache: Partner-Profil nur einmal pro Session laden.
  final Map<String, Future<Map<String, dynamic>?>> partnerHabitsCache = {};
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _timer;
  DatingHourSession? _session;
  String? _currentUserId;
  String? _peerId;
  bool _hasVoted = false;
  bool _showDecision = false;

  /// Alter des Chat-Partners (aus public_profiles) - für den
  /// Altersdifferenz-Hinweis (Migration: >= 10 Jahre Differenz).
  int? _partnerAge;
  bool _ageWarningShown = false;

  // E2E-P2P-Verbindung (Signal Protocol + WebRTC DataChannel).
  P2PChatService? _p2p;
  StreamSubscription<String>? _msgSub;
  StreamSubscription<void>? _pingSub;
  bool _p2pInitStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // NUTZERWUNSCH: Keine Benachrichtigung, solange dieser Chat sichtbar
    // ist (Nachrichten erscheinen direkt auf dem Bildschirm).
    ref.read(activeChatIdProvider.notifier).state = widget.sessionId;
    _loadSession();
    _startTimer();
  }

  @override
  void dispose() {
    // Aktiven Chat freigeben (Notification-Unterdrückung nur solange der
    // Chat sichtbar ist).
    if (ref.read(activeChatIdProvider) == widget.sessionId) {
      ref.read(activeChatIdProvider.notifier).state = null;
    }
    if (ref.read(activeChatPeerIdProvider) == _peerId) {
      ref.read(activeChatPeerIdProvider.notifier).state = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _msgSub?.cancel();
    _pingSub?.cancel();
    _p2p?.disconnect();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hintergrund: Timer (inkl. 10-s-RPC-Polling) pausieren (v0.9.1,
    // Akku). Vordergrund: neu starten (Session-Stand wird nachgeholt).
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
      _timer = null;
    } else if (state == AppLifecycleState.resumed && mounted) {
      if (_timer == null &&
          _session != null &&
          !_session!.bothDecided) {
        _startTimer();
        _loadSession();
      }
    }
  }

  /// Lädt das Alter des Chat-Partners (RPC get_public_profile, Migration
  /// 080 - Nachfolger der public_profiles-View; nur das Alter) und zeigt
  /// bei >= 10 Jahren Differenz einen Hinweis im Chat an.
  Future<void> _loadPartnerAge(DatingHourSession session) async {
    try {
      final myAge = ref.read(profileProvider).age;
      if (myAge == null) return;
      final myId = _currentUserId;
      if (myId == null) return;
      final peerId = session.getPeerId(myId);
      final row = await SupabaseService.client.rpc(
        'get_public_profile',
        params: {'p_user_id': peerId},
      );
      if (row == null) return;
      final partnerAge = ((row as Map)['age'] as num?)?.toInt();
      if (partnerAge == null || !mounted) return;
      setState(() => _partnerAge = partnerAge);
      final diff = (myAge - partnerAge).abs();
      if (diff >= 10) {
        setState(() => _ageWarningShown = true);
      }
    } catch (e) {
      debugPrint('[DatingHourChat] Partner-Alter konnte nicht geladen werden: $e');
    }
  }

  /// Baut die E2E-P2P-Verbindung zum Chat-Partner auf (einmalig pro Screen).
  Future<void> _initP2P(DatingHourSession session) async {
    if (_p2pInitStarted) return;
    _p2pInitStarted = true;

    final p2p = ref.read(p2pChatServiceProvider);
    _p2p = p2p;

    // Eigene ID strikt aus der Supabase-Session (Fix): Stale Secure-Store-
    // oder Demo-Fallbacks ('me') erzeugen ein Signaling-Topic ohne die
    // echte auth.uid() -> RLS verweigert den Join, Nachrichten adressieren
    // den falschen Peer. Ohne Session: kein P2P, kein Relay.
    final myId = SupabaseService.currentUser?.id;
    if (myId == null || myId.isEmpty) {
      debugPrint('[DatingHourChat] Keine Supabase-Session - P2P übersprungen.');
      return;
    }
    _currentUserId = myId;
    final peerId = session.getPeerId(_currentUserId!);
    _peerId = peerId;
    // NUTZERWUNSCH: Notification-Unterdrückung (lokal + Server-Push)
    // solange dieser Chat sichtbar ist.
    ref.read(activeChatPeerIdProvider.notifier).state = peerId;

    // Eingehende (bereits entschlüsselte) Nachrichten in den Verlauf.
    _msgSub = p2p.incomingMessages.listen((text) {
      if (!mounted) return;
      final msg = Message(
        id: Message.newId('p2p'),
        senderId: peerId,
        receiverId: _currentUserId!,
        text: text,
        timestamp: DateTime.now(),
      );
      ref.read(chatProvider.notifier).addMessage(widget.sessionId, msg, ref: ref);
    });

    // Relay-Wake-up: Partner hat eine Relay-Nachricht hinterlegt.
    _pingSub?.cancel();
    _pingSub = p2p.relayPing.listen((_) {
      if (mounted) unawaited(_fetchRelay());
    });

    try {
      await p2p.connect(myUserId: _currentUserId!, peerId: peerId);
    } catch (e) {
      debugPrint('[DatingHourChat] P2P Verbindung fehlgeschlagen: $e');
    }
  }

  Future<void> _loadSession() async {
    final service = ref.read(datingHourServiceProvider);
    try {
      final session = await service.getSession(widget.sessionId);
      if (mounted) {
        setState(() => _session = session);
      }
      // Partner-Alter laden (für den Altersdifferenz-Hinweis).
      if (session != null) {
        _loadPartnerAge(session);
      }
      // P2P-Verbindung zum Partner aufbauen, sobald die Session bekannt ist.
      if (session != null) {
        await _initP2P(session);
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(L10n.tf(context, 'common.errorWith',
                  {'error': e.message}))),
        );
      }
    }
  }

  void _startTimer() {
    // V: Countdown basiert auf verifizierter Serverzeit, damit die 5 Minuten
    // manipulationssicher sind. Batterie/Netz schonen: Die Sekunden-Anzeige
    // läuft in eigenen Mini-Widgets (_PerSecond, nur sie rebuilden), dieser
    // Timer feuert die Ablauf-Logik und die Session-Abfrage alle
    // 10 Sekunden (vorher: VOLLER Screen-Rebuild JEDE Sekunde + RPC).
    // Sobald beidseitig entschieden ist, endet der Timer ganz (v0.9.1).
    var ticksSinceSync = 0;
    var slowTicks = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;

      final session = _session;
      if (session == null) return;
      if (session.bothDecided) {
        // Nach beidseitiger Entscheidung: Session-Polls stoppen, aber den
        // Relay-Abruf weiterlaufen lassen (Fix: sonst kommen späte
        // Nachrichten des Partners nie an, solange der Screen offen ist).
        slowTicks++;
        if (slowTicks % 3 == 0) {
          unawaited(_fetchRelay());
        }
        return;
      }

      // Wenn abgelaufen und noch keine Entscheidung angezeigt wird.
      if (session.isExpired && !_showDecision) {
        _showDecisionDialog();
      }

      // Während der Timer läuft, frischen wir den Session-Status im
      // Hintergrund auf, um gegenseitige Entscheidungen zu erkennen.
      // Zusätzlich (Relay-Fallback): Relay-Nachrichten des Partners alle
      // ~3 s abholen (LATENZ: war 5 s) und den P2P-Handshake alle ~25 s
      // erneut versuchen. Der Wake-up-Ping liefert sofort - der Timer
      // fängt nur verlorene Pings ab.
      slowTicks++;
      if (slowTicks % 3 == 0) {
        unawaited(_fetchRelay());
      }
      if (slowTicks % 25 == 0) {
        unawaited(_retryHandshakeThrottled());
      }
      ticksSinceSync++;
      if (ticksSinceSync >= 10 && _shouldPollSession(session)) {
        ticksSinceSync = 0;
        await _loadSession();
        _evaluateSessionOutcome();
      }
    });
  }

  bool _shouldPollSession(DatingHourSession session) {
    // Nur pollen, wenn noch nicht final entschieden und der Timer läuft oder
    // gerade abgelaufen ist.
    if (session.isCompleted) return false;
    return true;
  }

  void _showDecisionDialog() {
    setState(() => _showDecision = true);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _session == null) return;

    // IDs ZUERST prüfen (Fix: _currentUserId!-Crash bei fehlender Session
    // + Ghost-Bubble mit receiverId '' bei fehlendem Peer).
    final myId = _currentUserId;
    final peerId = _peerId;
    if (myId == null || myId.isEmpty || peerId == null || peerId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'dh.chat.sendFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    _messageController.clear();

    // Lokal für die Anzeige ablegen (kein Mock-Auto-Reply) ...
    final localMsg = Message(
      id: Message.newId('local'),
      senderId: myId,
      receiverId: peerId,
      text: text,
      timestamp: DateTime.now(),
    );
    ref.read(chatProvider.notifier).addMessage(widget.sessionId, localMsg, ref: ref);

    // ... und ECHT E2E-verschlüsselt zustellen: erst direkt per
    // P2P-DataChannel, bei geschlossenem Kanal über den Server-Relay
    // (Migration 093/106 - Dating-Hour-Sessions sind relay-berechtigt).
    // Vorher gab es NUR den P2P-Pfad: Ohne Direktverbindung lief die
    // Nachricht still in die Outbox und kam im 5-Minuten-Fenster nie an.
    try {
      if (await _p2p?.trySendText(text) == true) {
        return;
      }
    } catch (_) {}
    try {
      await ref
          .read(relayServiceProvider)
          .storeText(peerId: peerId, text: text);
      // Dual-Delivery-Schutz: trySendText oben hat bei geschlossenem Kanal
      // bereits in die Outbox eingereiht - nach erfolgreichem Relay-Store
      // muss der Eintrag raus, sonst Doppelzustellung bei Kanalöffnung.
      _p2p?.dequeueText(text);
      unawaited(_p2p?.sendRelayPing());
      // NUTZERWUNSCH: Push, dass eine Nachricht wartet (nur Metadaten;
      // Beziehung = offene Dating-Hour-Session).
      unawaited(() async {
        try {
          await SupabaseService.client.functions.invoke(
            'notify-user',
            body: {'kind': 'messages', 'target_user_id': peerId},
          );
        } catch (_) {}
      }());
      return;
    } catch (e) {
      debugPrint('[DatingHourChat] Relay-Send fehlgeschlagen: $e');
    }
    try {
      await _p2p?.sendText(text);
    } catch (e) {
      debugPrint('[DatingHourChat] Sende-Fehler: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'dh.chat.sendFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Holt Relay-Nachrichten des Partners ab (Fallback bei fehlendem
  /// DataChannel). Läuft über den bestehenden 1-s-Timer gedrosselt
  /// (alle ~5 s) plus sofort per Wake-up-Ping.
  final Set<String> _seenDhRelayIds = {};

  Future<void> _fetchRelay() async {
    final peerId = _peerId;
    if (peerId == null || peerId.isEmpty || !mounted) return;
    if (!SupabaseService.isInitialized) return;
    try {
      final pending =
          await ref.read(relayServiceProvider).fetchPending(from: peerId);
      if (!mounted || pending.isEmpty) return;
      for (final r in pending) {
        final msgId = 'relay_${r.id}';
        if (_seenDhRelayIds.contains(msgId)) continue;
        _seenDhRelayIds.add(msgId);
        final msg = Message(
          id: msgId,
          senderId: peerId,
          receiverId: _currentUserId ?? '',
          text: r.text,
          timestamp: r.createdAt,
        );
        ref.read(chatProvider.notifier).addMessage(widget.sessionId, msg, ref: ref);
      }
    } catch (_) {
      // Netzwerkfehler: nächster Timer-Takt versucht es erneut.
    }
  }

  /// Handshake-Retry, gedrosselt (der 1-s-Timer ruft max. alle 25 s auf).
  DateTime? _lastDhHandshakeRetry;

  Future<void> _retryHandshakeThrottled() async {
    final p2p = _p2p;
    if (p2p == null || !mounted) return;
    if (p2p.isConnected) return;
    if (!SupabaseService.isInitialized) return;
    final myId = _currentUserId;
    final peerId = _peerId;
    if (myId == null || myId.isEmpty || peerId == null || peerId.isEmpty) {
      return;
    }
    final now = DateTime.now();
    if (_lastDhHandshakeRetry != null &&
        now.difference(_lastDhHandshakeRetry!) <
            const Duration(seconds: 25)) {
      return;
    }
    _lastDhHandshakeRetry = now;
    try {
      await p2p.ensureConnected(myUserId: myId, peerId: peerId);
    } catch (e) {
      debugPrint('[DatingHourChat] Handshake-Retry fehlgeschlagen: $e');
    }
  }

  Future<void> _handleDecision(bool accept) async {
    if (_session == null) return;

    final service = ref.read(datingHourServiceProvider);
    try {
      final updated = await service.recordDecision(
        widget.sessionId,
        _currentUserId!,
        accept,
      );

      if (updated != null && mounted) {
        setState(() {
          _session = updated;
          _hasVoted = true;
          _showDecision = true;
        });
        _evaluateSessionOutcome();
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(L10n.tf(context, 'common.errorWith',
                  {'error': e.message}))),
        );
      }
    }
  }

  void _evaluateSessionOutcome() {
    final session = _session;
    if (session == null || !session.bothDecided) return;

    if (session.isMutualMatch) {
      _createMatchAndNavigate(session);
    } else if (session.isRejected) {
      _showRejectionMessage(_getDefaultRejectionMessage());
    }
  }

  Future<void> _createMatchAndNavigate(DatingHourSession session) async {
    final partnerId = session.getPeerId(_currentUserId!);

    // v0.9.0-Fix (Gerätetest): Der Funke wurde vorher NUR LOKAL erzeugt
    // (Platzhalter 'Dein Gegenüber') - der Partner sah ihn nie, das Profil
    // war unbekannt und der Funke verschwand nach Neuinstallation. Jetzt:
    // serverseitiger Like -> bestehende Mutual-Like-Pipeline erzeugt das
    // kanonische Match (fuer BEIDE, samt Push), und das ECHTE Profil
    // wird geladen.
    //
    // NUTZERWUNSCH "Doppelte Funken": Der lokale addMatch legte parallel
    // zur Server-Pipeline einen ZWEITEN Funken mit anderer ID an (bei
    // gegenseitigem Liken). Jetzt: lokale Anlage NUR als Offline-Fallback,
    // wenn der Server-Like scheitert.
    var partnerProfile = UserProfile(
      id: partnerId,
      name: 'Dein Gegenüber',
      bio: '',
      interests: [],
    );
    var serverMatchOk = false;
    if (SupabaseService.isInitialized) {
      try {
        final fym = ref.read(findYourMatchServiceProvider);
        await fym.likeUser(partnerId);
        serverMatchOk = true;
        final row = await SupabaseDatabaseService(SupabaseService.client)
            .fetchPublicProfile(partnerId);
        if (row != null) {
          partnerProfile = UserProfile.fromJson({
            'id': row['user_id'],
            'name': row['name'] ?? 'Dein Gegenüber',
            'bio': row['bio'] ?? '',
            'interests': row['interests'] ?? <dynamic>[],
            'photos': row['photos'],
            'gender': row['gender'],
            'birthDate': null,
          });
        }
      } catch (e) {
        debugPrint('[DH-Chat] Funke-Server-Sync fehlgeschlagen: $e');
      }
    }

    if (!serverMatchOk) {
      // Offline: lokaler Funke, damit der Chat nicht leer endet.
      ref.read(chatProvider.notifier).addMatch(partnerProfile, ref: ref);
    }

    if (mounted) {
      await FunkeOverlay.show(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(L10n.t(context, 'dh.chat.sparkJumped'))),
        );
      }
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        // Direkt auf den Funken-Tab (v0.9.1): sonst landet man auf
        // "Gesendet" und der neue Funke wirkt unsichtbar.
        try {
          ProviderScope.containerOf(context)
              .read(interessenInitialTabProvider.notifier)
              .state = 2;
        } catch (_) {}
        context.go(AppRoutes.interessen);
      }
    }
  }

  void _showRejectionMessage(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.favorite_border, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(L10n.t(context, 'dh.chat.noSpark')),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) context.go(AppRoutes.datingHourEvent);
            },
            child: Text(L10n.t(context, 'dh.chat.keepSearching')),
          ),
        ],
      ),
    );
  }

  String _getDefaultRejectionMessage() {
    const messages = [
      'Diese Verbindung hat leider nicht ganz gepasst. Aber keine Sorge, das sagt nichts über dich aus! Wir suchen gleich jemand Neues für dich.',
      'Manchmal funkt es einfach nicht, und das ist völlig okay! Dein nächster Funke wartet schon.',
      'Nicht jede Begegnung führt zum Funken. Aber jeder Chat bringt dich näher an die richtige Person. Weiter so!',
      'Schade, dass es nicht gepasst hat. Aber hey: Du hast dich getraut, dich zu zeigen! Das nächste Gespräch kommt bestimmt.',
    ];
    return messages[DateTime.now().millisecondsSinceEpoch % messages.length];
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider.notifier).messagesFor(widget.sessionId);
    final session = _session;
    final partnerName = session != null
        ? (session.isParticipantA(_currentUserId ?? '') ? 'Teilnehmer B' : 'Teilnehmer A')
        : 'Verbinde...';
    // Nutzerwunsch Gruppierung: Namens-Header an Gruppenstarts (max. 3
    // Nachrichten / 3 Minuten pro Gruppe), Zeit an jeder Bubble.
    final bubbleGroups = computeBubbleGroups(messages);

    // Partner-Gewohnheiten: aus public_profiles laden und als Chips zeigen.
    final partnerId = session?.getPeerId(_currentUserId ?? '');

    // Altersdifferenz-Hinweis: >= 10 Jahre Unterschied (einmalig oben im
    // Chat sichtbar, solange der Screen offen ist).
    final myAge = ref.watch(profileProvider).age;
    final showAgeGapHint = _ageWarningShown &&
        myAge != null &&
        _partnerAge != null &&
        (myAge - _partnerAge!).abs() >= 10;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(partnerName, style: const TextStyle(fontSize: 16)),
            if (session != null)
              // v0.9.1: E2E-Badge zentriert im verfügbaren Titel-Raum
              // (nutzt den Leerraum sauber aus statt rechtsbündig).
              // Die Sekunden-Anzeige tickt isoliert (_PerSecond), damit
              // nicht der ganze Screen pro Sekunde rebuildet (Akku).
              _PerSecond(
                builder: (_) => Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock,
                        size: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(L10n.t(context, 'dh.chat.e2e'),
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: session.remainingSeconds > 60
                              ? Colors.green
                              : session.remainingSeconds > 30
                                  ? Colors.orange
                                  : Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _formatTime(session.remainingSeconds),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (partnerId != null)
                FutureBuilder<Map<String, dynamic>?>(
                  future: partnerHabitsCache.putIfAbsent(
                      partnerId,
                      () => ref
                          .read(supabaseDatabaseServiceProvider)
                          .fetchPublicProfile(partnerId)),
                  builder: (ctx, snap) {
                    final habits = <String>[];
                    final row = snap.data;
                    if (row != null) {
                      final s = row['smoking'] as String?;
                      final a = row['alcohol'] as String?;
                      final d = row['drugs'] as String?;
                      if (s != null && s.isNotEmpty) {
                        habits.add('Rauchen: $s');
                      }
                      if (a != null && a.isNotEmpty) {
                        habits.add('Alkohol: $a');
                      }
                      if (d != null && d.isNotEmpty) {
                        habits.add('Drogen: $d');
                      }
                    }
                    if (habits.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          for (final h in habits)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(h,
                                  style: const TextStyle(fontSize: 9)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmLeave(),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Builder(
        builder: (context) {
          final bg = ref.watch(settingsProvider);
          return Stack(
            children: [
              Positioned.fill(
                child: ChatBackgroundView(
                  backgroundId: bg.chatBackground,
                  customPath: bg.chatBackgroundPath,
                ),
              ),
              Column(
          children: [
          // Timer-Balken (tickt isoliert, v0.9.1, Akku).
          if (session != null && !session.bothDecided)
            _PerSecond(
              builder: (_) => _TimerBar(
                remainingSeconds: session.remainingSeconds,
                totalSeconds: 300,
              ),
            ),

          // Altersdifferenz-Hinweis (>= 10 Jahre Unterschied).
          if (showAgeGapHint)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Colors.orange.shade900,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hinweis: Ihr seid $myAge und $_partnerAge Jahre alt - '
                      'es liegen mindestens 10 Jahre zwischen euch. Bitte '
                      'geht respektvoll miteinander um.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Status-Hinweis (Match / Kein Match / Warte)
          if (session != null && session.bothDecided) _buildOutcomeBanner(session),

          // Chat-Bereich
          Expanded(
            child: messages.isEmpty
                ? _EmptyChatState(
                    partnerName: partnerName,
                    onIceBreaker: () => _sendIceBreaker(),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final idx = messages.length - 1 - i;
                      final msg = messages[idx];
                      final mine = msg.isFrom(_currentUserId ?? '');
                      final group = idx >= 0 && idx < bubbleGroups.length
                          ? bubbleGroups[idx]
                          : (showName: true, showTime: true);
                      return _MessageBubble(
                        msg: msg,
                        mine: mine,
                        showName: group.showName,
                        senderName: mine
                            ? L10n.t(context, 'chat.you')
                            : partnerName,
                      );
                    },
                  ),
          ),

          // Eingabe oder Entscheidungs-Buttons
          if (session != null && !session.bothDecided) ...[
            if (!_showDecision && !session.isExpired) ...[
              // Frage-Karten für Schüchterne (v0.8.0): ein Tap übernimmt
              // eine sanfte Frage aus einem thematischen Bereich.
              _ShyQuestionChips(
                onPick: (question) {
                  _messageController.text = question;
                  _sendMessage();
                },
              ),
              _ChatInput(
                controller: _messageController,
                onSend: _sendMessage,
              ),
            ]
            else if (_showDecision && !_hasVoted)
              _DecisionButtons(
                onAccept: () => _handleDecision(true),
                onReject: () => _handleDecision(false),
              )
            else if (_hasVoted)
              _WaitingForPartner(
                onBack: () {
                  if (mounted) context.go(AppRoutes.datingHourEvent);
                },
              ),
              ],
            ],
          ),
        ],
      );
    },
      ),
    );
  }

  Widget _buildOutcomeBanner(DatingHourSession session) {
    if (session.isMutualMatch) {
      return Container(
        width: double.infinity,
        color: Colors.green,
        padding: const EdgeInsets.all(12),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Ein Funke ist übersprungen!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      color: Colors.orange,
      padding: const EdgeInsets.all(12),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, color: Colors.white),
          SizedBox(width: 8),
          Text(
                  'Kein Funke diesmal, aber weiter so!',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _sendIceBreaker() async {
    final iceBreakers = [
      'Hey! Was war das Beste, das dir diese Woche passiert ist? 😊',
      'Wenn du morgen überall auf der Welt aufwachen könntest, wo wärst du? ✨',
      'Was ist dein liebstes "Guilty Pleasure"? 🤭',
      'Hast du ein verborgenes Talent? 🎯',
      'Was würdest du tun, wenn du für einen Tag unsichtbar wärst? 👻',
    ];
    _messageController.text = iceBreakers[DateTime.now().millisecondsSinceEpoch % iceBreakers.length];
    _sendMessage();
  }

  void _confirmLeave() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'dh.chat.leaveTitle')),
        content: Text(
          L10n.t(ctx, 'dh.chat.leaveBody'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(context, 'dh.chat.stay')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _handleDecision(false); // Verlassen = Ablehnen
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(L10n.t(context, 'dh.chat.leaveDecline')),
          ),
        ],
      ),
    );
  }
}

/// Baut sein Child jede Sekunde neu (v0.9.1, Akku): Sekunden-Anzeigen
/// (Countdown, Timer-Balken) ticken isoliert, statt den ganzen Screen
/// pro Sekunde zu rebuilden.
class _PerSecond extends StatefulWidget {
  const _PerSecond({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_PerSecond> createState() => _PerSecondState();
}

class _PerSecondState extends State<_PerSecond> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Timer-Balken oben im Chat.
class _TimerBar extends StatelessWidget {
  const _TimerBar({required this.remainingSeconds, required this.totalSeconds});
  final int remainingSeconds;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final progress = remainingSeconds / totalSeconds;
    final color = remainingSeconds > 60
        ? Colors.green
        : remainingSeconds > 30
            ? Colors.orange
            : Colors.red;

    return SizedBox(
      height: 4,
      child: Stack(
        children: [
          Container(
            color: color.withValues(alpha: 0.2),
          ),
          FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(color: color),
          ),
          if (remainingSeconds <= 30)
            Positioned.fill(
              child: _PulsingBorder(color: color),
            ),
        ],
      ),
    );
  }
}

class _PulsingBorder extends StatefulWidget {
  const _PulsingBorder({required this.color});
  final Color color;

  @override
  State<_PulsingBorder> createState() => _PulsingBorderState();
}

class _PulsingBorderState extends State<_PulsingBorder> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: widget.color.withValues(alpha: _controller.value),
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Leerer Chat-State mit Ice-Breaker.
class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({required this.partnerName, required this.onIceBreaker});
  final String partnerName;
  final VoidCallback onIceBreaker;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              L10n.tf(context, 'dh.chat.sayHello', {'name': partnerName}),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ihr habt 5 Minuten Zeit, euch kennenzulernen. '
              'Danach entscheidet ihr beide: Funke oder weitersuchen?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.lightbulb_outline),
              label: Text(L10n.t(context, 'dh.chat.icebreakerBtn')),
              onPressed: onIceBreaker,
            ),
          ],
        ),
      ),
    );
  }
}

/// Nachrichtenblase.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {required this.msg,
      required this.mine,
      this.showName = false,
      this.senderName = ''});
  final Message msg;
  final bool mine;

  /// Namens-Header über der Bubble anzeigen (Gruppenstart)?
  final bool showName;

  /// Anzuzeigender Absendername.
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final color = mine
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = mine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurfaceVariant;
    String timeLabel = '';
    try {
      timeLabel = DateFormat.Hm().format(msg.timestamp.toLocal());
    } catch (_) {}

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showName && senderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2, left: 4, right: 4),
              child: Text(
                senderName,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomRight: mine
                    ? const Radius.circular(4)
                    : const Radius.circular(18),
                bottomLeft: mine
                    ? const Radius.circular(18)
                    : const Radius.circular(4),
              ),
            ),
            child: Text(
              msg.text,
              style: TextStyle(color: textColor),
            ),
          ),
          if (timeLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 6, right: 6),
              child: Text(
                timeLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
  }
}

/// Frage-Karten für Schüchterne (v0.8.0): 3 thematische sanfte Vorschläge
/// (Reise / Alltag / Träume) - ein Tap übernimmt die Frage. Die Fragen
/// rotieren pro Runde, damit es nicht repetitive Textbausteine sind.
class _ShyQuestionChips extends StatelessWidget {
  const _ShyQuestionChips({required this.onPick});

  final void Function(String question) onPick;

  static const _themes = <String, List<String>>{
    'Reise ✈️': [
      'Welche Stadt möchte du unbedingt mal besuchen?',
      'Bester Reise-Moment deines Lebens?',
      'Flug, Zug oder Auto, was magst du am liebsten?',
    ],
    'Alltag ☀️': [
      'Was war heute dein kleines Glück?',
      'Kaffee oder Tee, und wie dazu?',
      'Was hilft dir wirklich beim Abschalten?',
    ],
    'Träume 🌙': [
      'Wovon würdest du am liebsten träumen?',
      'Was würdest du machen mit einem freien Monat?',
      'Welcher Traum hat noch nicht angefangen zu brennen?',
    ],
  };

  @override
  Widget build(BuildContext context) {
    // Pro Theme eine Frage, rotiert pro Aufruf (Datum + Stunde).
    final rotation = DateTime.now().hour;
    final chips = <(String, String)>[];
    var themeIndex = 0;
    for (final entry in _themes.entries) {
      final questions = entry.value;
      final q = questions[(rotation + themeIndex) % questions.length];
      chips.add((entry.key, q));
      themeIndex++;
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final (theme, question) in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(theme, style: const TextStyle(fontSize: 12)),
                tooltip: question,
                onPressed: () => onPick(question),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chat-Eingabebereich.
class _ChatInput extends StatelessWidget {
  const _ChatInput({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: L10n.t(context, 'dh.chat.hint'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
                maxLines: null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send),
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entscheidungs-Buttons (Annehmen/Ablehnen).
class _DecisionButtons extends StatelessWidget {
  const _DecisionButtons({required this.onAccept, required this.onReject});
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L10n.t(context, 'dh.chat.timeUp'),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: Text(L10n.t(context, 'dh.chat.decline')),
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.favorite),
                    label: Text(L10n.t(context, 'dh.chat.accept')),
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              L10n.t(context, 'dh.chat.bothMustAccept'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Warten auf Partner-Entscheidung.
class _WaitingForPartner extends StatelessWidget {
  const _WaitingForPartner({this.onBack});
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              L10n.t(context, 'dh.chat.voted'),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              L10n.t(context, 'dh.chat.resultPending'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (onBack != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: Text(L10n.t(context, 'dh.chat.backToOverview')),
                onPressed: onBack,
              ),
          ],
        ),
      ),
    );
  }
}
