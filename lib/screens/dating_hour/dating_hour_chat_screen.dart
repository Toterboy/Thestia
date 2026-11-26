import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:thestia/models/dating_hour/dating_hour_models.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/interests/interessen_screen.dart'
    show interessenInitialTabProvider;
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/utils/chat/chat_backgrounds.dart';
import 'package:thestia/widgets/chat/chat_bubbles.dart';
import 'package:thestia/widgets/chat/funke_overlay.dart';
import 'package:thestia/widgets/chat/secure_composer.dart';
import 'package:thestia/services/dating_hour/dating_hour_service.dart';
import 'package:thestia/services/dating_hour/find_your_match_service.dart';
import 'package:thestia/services/server/supabase_database_service.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/relay_service.dart';
import 'package:thestia/utils/common/best_effort.dart';

part 'parts/datinghourdialoge.dart';

part 'parts/datinghourp2p.dart';

part 'parts/datinghoursitzung.dart';

part 'parts/persecond.dart';
part 'parts/persecondstate.dart';
part 'parts/timerbar.dart';
part 'parts/pulsingborder.dart';
part 'parts/pulsingborderstate.dart';
part 'parts/emptychatstate.dart';
part 'parts/messagebubble.dart';
part 'parts/shyquestionchips.dart';
part 'parts/chatinput.dart';
part 'parts/decisionbuttons.dart';
part 'parts/waitingforpartner.dart';

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
  ConsumerState<DatingHourChatScreen> createState() =>
      _DatingHourChatScreenState();
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

  /// Der Timer ist aus- und wieder einblendbar
  /// (NUTZERWUNSCH 04.11.2026: "einen Timer gibt, den man sichtbar
  /// und unsichtbar machen kann"). Manche wollen die Zeit nicht
  /// sehen - das Gespräch soll nicht nach Zeit aussehen.
  bool _showTimer = true;

  /// Die Fünf-Minuten-Marke wurde schon im Chat gezeigt.
  ///
  /// Sie ist ein HINWEIS der App, keine Nachricht einer Person. Sie
  /// steht deshalb nur einmal im Verlauf und wird nicht gesendet.
  bool _fiveMinuteNoticeShown = false;

  /// Die Notifier der beiden "aktiver Chat"-Markierungen.
  ///
  /// BEFUND (14.11.2026, gefunden von einem Test): Im `dispose()` darf
  /// nicht mehr auf `ref` zugegriffen werden - Riverpod hat den
  /// Consumer-State da schon abgeräumt ("Cannot use ref after the widget
  /// was disposed"). Das war bei JEDEM Verlassen des Chats ein Fehler
  /// (im Debug ein roter Bildschirm, im Release eine Fehlermeldung).
  ///
  /// DER WEG: Die Notifier werden schon im `initState` geholt. Der
  /// StateNotifier lebt länger als der Screen - so wird die
  /// Notification-Unterdrückung wirklich wieder aufgehoben. Sonst bliebe
  /// sie bis zum App-Ende stehen und die Meldungen des Partners kämen
  /// nicht mehr an.
  late final StateController<String?> _aktiveChatId;
  late final StateController<String?> _aktiveChatPeerId;

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
    // Die Notifier der "aktiver Chat"-Markierungen jetzt holen: im
    // dispose() ist `ref` nicht mehr benutzbar (siehe die Erklärung
    // beim Feld).
    _aktiveChatId = ref.read(activeChatIdProvider.notifier);
    _aktiveChatPeerId = ref.read(activeChatPeerIdProvider.notifier);
    // NUTZERWUNSCH: Keine Benachrichtigung, solange dieser Chat sichtbar
    // ist (Nachrichten erscheinen direkt auf dem Bildschirm).
    //
    // WICHTIG (06.11.2026): Riverpod verbietet Provider-Schreibzugriffe
    // im Lebenszyklus ("Tried to modify a provider while the widget tree
    // was building"). Die Zuweisung wartet deshalb einen Frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _aktiveChatId.state = widget.sessionId;
    });
    _loadSession();
    _startTimer();
  }

  @override
  void dispose() {
    // Aktiven Chat freigeben (Notification-Unterdrückung nur solange der
    // Chat sichtbar ist) - über die Notifier, weil `ref` hier nicht mehr
    // benutzt werden darf (siehe die Erklärung beim Feld).
    //
    // DER WEG (BEFUND 18.11.2026, gefunden von einem Test): Das Rücksetzen
    // muss einen Frame warten. Wird der Bildschirm während eines
    // Routenwechsels abgeräumt (der Bildschirm springt zu den Funken),
    // passiert das dispose() MITTEN IM AUFBAU - und Riverpod verbietet
    // das Ändern eines Providers während des Aufbaus ("Tried to modify
    // a provider while the widget tree was building"). Die Markierung
    // blieb dann stehen: die Benachrichtigungen des Gesprächs blieben
    // unterdrückt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bestEffortSync('aktiven Chat freigeben', () {
        if (_aktiveChatId.state == widget.sessionId) {
          _aktiveChatId.state = null;
        }
        if (_aktiveChatPeerId.state == _peerId) {
          _aktiveChatPeerId.state = null;
        }
      });
    });
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
      if (_timer == null && _session != null && !_session!.bothDecided) {
        _startTimer();
        _loadSession();
      }
    }
  }

  /// Holt Relay-Nachrichten des Partners ab (Fallback bei fehlendem
  /// DataChannel). Läuft über den bestehenden 1-s-Timer gedrosselt
  /// (alle ~5 s) plus sofort per Wake-up-Ping.
  final Set<String> _seenDhRelayIds = {};

  /// Handshake-Retry, gedrosselt (der 1-s-Timer ruft max. alle 25 s auf).
  DateTime? _lastDhHandshakeRetry;

  @override
  Widget build(BuildContext context) {
    final messages = ref
        .watch(chatProvider.notifier)
        .messagesFor(widget.sessionId);
    final session = _session;
    final partnerName = session != null
        ? (session.isParticipantA(_currentUserId ?? '')
              ? 'Teilnehmer B'
              : 'Teilnehmer A')
        : 'Verbinde...';
    // Nutzerwunsch Gruppierung: Namens-Header an Gruppenstarts (max. 3
    // Nachrichten / 3 Minuten pro Gruppe), Zeit an jeder Bubble.
    final bubbleGroups = computeBubbleGroups(messages);

    // Partner-Gewohnheiten: aus public_profiles laden und als Chips zeigen.
    final partnerId = session?.getPeerId(_currentUserId ?? '');

    // Altersdifferenz-Hinweis: >= 10 Jahre Unterschied (einmalig oben im
    // Chat sichtbar, solange der Screen offen ist).
    final myAge = ref.watch(profileProvider).age;
    final showAgeGapHint =
        _ageWarningShown &&
        myAge != null &&
        _partnerAge != null &&
        (myAge - _partnerAge!).abs() >= 10;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(partnerName, style: const TextStyle(fontSize: 16)),
            if (session != null && _showTimer)
              // v0.9.1: E2E-Badge zentriert im verfügbaren Titel-Raum
              // (nutzt den Leerraum sauber aus statt rechtsbündig).
              // Die Sekunden-Anzeige tickt isoliert (_PerSecond), damit
              // nicht der ganze Screen pro Sekunde rebuildet (Akku).
              //
              // NUTZERWUNSCH 04.11.2026: Der Timer ist aus- und
              // wieder einblendbar.
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
                      // BREITER TEXT (14.11.2026, gefunden von einem Test):
                      // "Ende zu Ende verschlüsselt" passte nicht neben
                      // der Zeit in die Kopfzeile - auf einem schmalen
                      // Gerät (oder bei großer Schrift) lief der Text
                      // rechts aus der Leiste ("RenderFlex overflowed by
                      // 140 pixels"). `Flexible` kürzt den Text
                      // statt ihn abzuschneiden.
                      Flexible(
                        child: Text(
                          L10n.t(context, 'dh.chat.e2e'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          // In der zweiten Phase (nach den 5 Minuten)
                          // zählt der Timer bis zum automatischen
                          // Funke - und wird blau, damit man sieht,
                          // dass er eine andere Bedeutung hat.
                          color: session.isDecisionPhase
                              ? Colors.blue
                              : session.remainingSeconds > 60
                              ? Colors.green
                              : session.remainingSeconds > 30
                              ? Colors.orange
                              : Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _formatTime(
                            session.isDecisionPhase
                                ? session.autoMatchSecondsLeft
                                : session.remainingSeconds,
                          ),
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
                      .fetchPublicProfile(partnerId),
                ),
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
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(h, style: const TextStyle(fontSize: 9)),
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
        actions: [
          // Der Timer ist aus- und wieder einblendbar
          // (NUTZERWUNSCH 04.11.2026).
          IconButton(
            tooltip: L10n.t(
              context,
              _showTimer ? 'dh.chat.timerHide' : 'dh.chat.timerShow',
            ),
            icon: Icon(
              _showTimer ? Icons.timer : Icons.timer_off_outlined,
              size: 20,
            ),
            onPressed: () {
              setState(() => _showTimer = !_showTimer);
            },
          ),
          // Das Gespräch beenden - von einer Seite aus, jederzeit.
          // Ein beendetes Gespräch erhält KEINEN automatischen Funke.
          if (session != null && !session.isCompleted)
            IconButton(
              tooltip: L10n.t(context, 'dh.chat.endConversation'),
              icon: const Icon(Icons.call_end, size: 20),
              onPressed: _endConversation,
            ),
        ],
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
                  if (session != null && !session.bothDecided && _showTimer)
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
                  if (session != null && session.bothDecided)
                    _buildOutcomeBanner(session),

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
                              final group =
                                  idx >= 0 && idx < bubbleGroups.length
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
                  // Eingabe oder Entscheidungs-Buttons
                  //
                  // NUTZERWUNSCH 04.11.2026: "Wenn die 5 Minuten vorbei
                  // sind, soll ... eine Nachricht kommen, dass die 5 Minuten
                  // um sind und sich langsam entschieden werden soll."
                  //
                  // Die 5 Minuten sind deshalb eine ENTSCHEIDUNGSphase, nicht
                  // das Ende des Gesprächs: Der Chat bleibt bedienbar, und
                  // die Entscheidung kommt ZUSATZLICH dazu. Vorher hat der
                  // abgelaufene Timer den Eingabebereich ersetzt - es war
                  // danach nicht mehr möglich, weiterzuschreiben, und das
                  // Gespräch war nach 5 Minuten beendet, bevor der
                  // automatische Funke bei Minute 10 überhaupt greifen konnte.
                  if (session != null && !session.bothDecided) ...[
                    if (!_hasVoted) ...[
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
                    ] else
                      _WaitingForPartner(
                        onBack: () {
                          if (mounted) context.go(AppRoutes.datingHourEvent);
                        },
                      ),
                    // In der Entscheidungsphase (nach den 5 Minuten) wird die
                    // Entscheidung angeboten - der Chat bleibt aber offen.
                    if (session.isExpired && !_hasVoted)
                      _DecisionButtons(
                        onAccept: () => _handleDecision(true),
                        onReject: () => _handleDecision(false),
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

  /// Setzt den Zustand - aufrufbar auch aus den Erweiterungen.
  ///
  /// DER GRUND: In einer Erweiterung darf `setState` nicht aufgerufen
  /// werden (der Analyser erlaubt es nur in Instanzmitgliedern einer
  /// State-Klasse). Diese Methode gehört zur Klasse - die Erweiterung
  /// ruft sie auf.
  void _setzeState(VoidCallback fn) => setState(fn);
}
