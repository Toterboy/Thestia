import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/models/match.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/find_your_match_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/find_your_match_service.dart';
import 'package:thestia/services/report_service.dart';
import 'package:thestia/services/relay_service.dart';
import 'package:thestia/services/seen_service.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/widgets/end_spark_dialog.dart';
import 'package:thestia/widgets/funke_overlay.dart';
import 'package:thestia/widgets/intro_audio_player.dart';
import 'package:thestia/widgets/states.dart';
import 'package:thestia/l10n/app_strings.dart';

/// Automatisches Nachladen eines Tabs (v0.9.1): bei Rückkehr von einem
/// gepushten Screen (RouteObserver.didPopNext, z. B. aus dem Chat) und
/// bei App-Resume (anderes Gerät könnte Likes/Funken geändert haben).
/// Einbindung: `with RouteAware, WidgetsBindingObserver, _AutoReloadTab`
/// und [reloadTab] implementieren.
mixin _AutoReloadTab<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, RouteAware, WidgetsBindingObserver {
  /// Lädt den Tab-Inhalt neu (wird von den Observer-Callbacks aufgerufen).
  Future<void> reloadTab();

  @override
  void didPopNext() {
    if (mounted) unawaited(reloadTab());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(reloadTab());
    }
  }

  /// In initState aufrufen.
  void autoReloadInit() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// In didChangeDependencies aufrufen.
  void autoReloadSubscribe(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  /// In dispose aufrufen.
  void autoReloadDispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      routeObserver.unsubscribe(this);
    } catch (_) {}
  }
}

/// Gewünschter Start-Tab für den Interessen-Reiter (v0.9.1): Aktionen wie
/// "Funke kühlen" navigieren hierher und wollen direkt den Funken-Tab (2)
/// zeigen - sonst wirkt der gekühlte Funke als "komplett weg". Wird beim
/// Öffnen genau einmal verbraucht und auf 0 zurückgesetzt.
final interessenInitialTabProvider = StateProvider<int>((ref) => 0);

/// Verwalten-Modus der Funken-Liste (NUTZERWUNSCH: Ein-/Ausgang über das
/// AppBar-Icon, Zustand wird zwischen den Tabs geteilt - die AppBar
/// gehört zum Screen, die Liste zum Tab).
final matchSelectModeProvider = StateProvider<bool>((ref) => false);

/// Reiter "Interessen" mit drei Bereichen:
///   1. Eigene Likes (noch kein Match)
///   2. Erhaltene Likes (Vorstellung ansehen/anhören, Match bestätigen/ablehnen)
///   3. Matches (Quiz-Zugang, danach Chat)
class InteressenScreen extends ConsumerStatefulWidget {
  const InteressenScreen({super.key});

  @override
  ConsumerState<InteressenScreen> createState() => _InteressenScreenState();
}

class _InteressenScreenState extends ConsumerState<InteressenScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    // NUTZERWUNSCH: Der Reiter "Interessen" landet IMMER beim Funken-Tab
    // (Index 2) - bei "Eigene Likes" entstand der Eindruck, man hoffe auf
    // neue Likes; im Funken-Tab sieht man die aktuellen Kontakte. Der
    // interessenInitialTabProvider (z. B. "Funke kühlen") behält Vorrang,
    // er zeigt ohnehin auf den Funken-Tab.
    final initial =
        ref.read(interessenInitialTabProvider).clamp(0, 2).toInt();
    _tabController =
        TabController(length: 3, vsync: this, initialIndex: initial == 0 ? 2 : initial);
    if (initial != 0) {
      ref.read(interessenInitialTabProvider.notifier).state = 0;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(L10n.t(context, 'interests.title')),
        // NUTZERWUNSCH: "Verwalten" als Icon statt Textbutton in der
        // Funken-Liste (sparte Platz; der Ein-/Ausgang des Auswähl-Modus
        // bleibt in der Liste selbst).
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: L10n.t(context, 'interests.manage'),
            onPressed: () =>
                ref.read(matchSelectModeProvider.notifier).state = true,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          // Abgerundete Klick-Animation (kein eckiger Aufblitzer).
          splashBorderRadius: const BorderRadius.all(Radius.circular(24)),
          tabs: [
            Tab(text: L10n.t(context, 'interests.tabSent')),
            Tab(text: L10n.t(context, 'interests.tabReceived')),
            Tab(text: L10n.t(context, 'interests.tabSparks')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _OwnLikesTab(),
          _ReceivedLikesTab(),
          _MatchesTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Eigene Likes
// ---------------------------------------------------------------------------

class _OwnLikesTab extends ConsumerStatefulWidget {
  const _OwnLikesTab();

  @override
  ConsumerState<_OwnLikesTab> createState() => _OwnLikesTabState();
}

class _OwnLikesTabState extends ConsumerState<_OwnLikesTab>
    with RouteAware, WidgetsBindingObserver, _AutoReloadTab {
  List<ReceivedLike> _likes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    autoReloadInit();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    autoReloadSubscribe(context);
  }

  @override
  void dispose() {
    autoReloadDispose();
    super.dispose();
  }

  @override
  Future<void> reloadTab() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      _likes = await service.listMyLikes();
    } catch (e) {
      debugPrint('[Interessen] Eigene Likes fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeLike(ReceivedLike like) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      await Supabase.instance.client
          .from('likes')
          .delete()
          .eq('user_id', userId)
          .eq('liked_user_id', like.profile.id);
      if (mounted) {
        setState(() => _likes.removeWhere((l) => l.likeId == like.likeId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'interests.likeWithdrawn'))),
        );
      }
    } catch (e) {
      debugPrint('[Interessen] Like entfernen fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_likes.isEmpty) {
      // v0.9.1-Fix (Android 16): Auch im Leerzustand pull-to-refresh
      // ermöglichen - RefreshIndicator braucht ein scrollbares Child mit
      // AlwaysScrollableScrollPhysics (sonst löst Pull bei kurzer/leerer
      // Liste nie aus, auf Android 16 mit enforced edge-to-edge fiel das
      // besonders auf).
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: EmptyState(
              icon: Icons.favorite_border,
              title: L10n.t(context, 'interests.emptySentTitle'),
              message: L10n.t(context, 'interests.emptySentBody'),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _likes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final like = _likes[i];
          final profile = like.profile;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(profile.name),
                    subtitle: Text([
                      '${profile.age ?? '?'} Jahre',
                      // Serverseitig berechnete Distanz (5-km-Schritte).
                      if (profile.distanceKm > 0) profile.distanceLabel,
                    ].join(' · ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: L10n.t(context, 'interests.likeWithdrawTooltip'),
                      onPressed: () => _removeLike(like),
                    ),
                  ),
                  if (profile.introAudioPath != null) ...[
                    const SizedBox(height: 4),
                    IntroAudioPlayer(targetUserId: profile.id),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Erhaltene Likes
// ---------------------------------------------------------------------------

class _ReceivedLikesTab extends ConsumerStatefulWidget {
  const _ReceivedLikesTab();

  @override
  ConsumerState<_ReceivedLikesTab> createState() => _ReceivedLikesTabState();
}

class _ReceivedLikesTabState extends ConsumerState<_ReceivedLikesTab>
    with RouteAware, WidgetsBindingObserver, _AutoReloadTab {
  List<ReceivedLike> _likes = [];
  bool _loading = true;
  int? _busyLikeId;

  @override
  void initState() {
    super.initState();
    autoReloadInit();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    autoReloadSubscribe(context);
  }

  @override
  void dispose() {
    autoReloadDispose();
    super.dispose();
  }

  @override
  Future<void> reloadTab() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      _likes = await service.listReceivedLikes();
      // Angesehen = Badge auf Aktuelles weg (v0.9.1, Seen-Tracking).
      unawaited(ref
          .read(seenProvider.notifier)
          .markLikesSeen(_likes.map((l) => l.likeId)));
      ref.invalidate(receivedLikesProvider);
    } catch (e) {
      debugPrint('[Interessen] Erhaltene Likes fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(ReceivedLike like, {required bool accept}) async {
    if (_busyLikeId != null) return;
    setState(() => _busyLikeId = like.likeId);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      await service.respondToLike(like.likeId, accept: accept);
      if (!mounted) return;
      setState(() => _likes.removeWhere((l) => l.likeId == like.likeId));
      if (accept) {
        await FunkeOverlay.show(context);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? L10n.tf(context, 'interests.sparkAccepted',
                    {'name': like.profile.name})
                : L10n.tf(context, 'interests.likeDeclined',
                    {'name': like.profile.name}),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[Interessen] Antwort fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.tf(context, 'common.errorWith', {'error': '$e'}))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyLikeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_likes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: EmptyState(
              icon: Icons.favorite_border,
              title: L10n.t(context, 'interests.emptyReceivedTitle'),
              message: L10n.t(context, 'interests.emptyReceivedBody'),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _likes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final like = _likes[i];
          final profile = like.profile;
          final busy = _busyLikeId == like.likeId;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: const Icon(Icons.visibility_off,
                          color: Colors.white),
                    ),
                    title: Text([
                      '${profile.name}, ${profile.age ?? '?'}',
                      if (profile.distanceKm > 0) profile.distanceLabel,
                    ].join(' · ')),
                    subtitle: Text(
                      profile.introText.isNotEmpty
                          ? profile.introText
                          : L10n.t(context, 'interests.likedYou'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () =>
                        context.go(AppRoutes.profileDetailPath(profile.id)),
                  ),
                  if (profile.introAudioPath != null) ...[
                    const SizedBox(height: 8),
                    IntroAudioPlayer(targetUserId: profile.id),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              busy ? null : () => _respond(like, accept: false),
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: Text(L10n.t(context, 'interests.decline')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              busy ? null : () => _respond(like, accept: true),
                          icon: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.favorite),
                          label: Text(L10n.t(context, 'interests.sparkConfirmBtn')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3: Matches
// ---------------------------------------------------------------------------

class _MatchesTab extends ConsumerStatefulWidget {
  const _MatchesTab();

  @override
  ConsumerState<_MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends ConsumerState<_MatchesTab>
    with RouteAware, WidgetsBindingObserver, _AutoReloadTab {
  List<MatchWithState> _serverMatches = [];
  bool _loading = true;
  /// Chats verwalten (v0.8.0): Mehrfachauswahl + "Aus Liste entfernen".
  /// Ein-/Ausgang über das AppBar-Icon (NUTZERWUNSCH: weniger Platz);
  /// der Zustand lebt im [matchSelectModeProvider] (AppBar <-> Tab).
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    autoReloadInit();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    autoReloadSubscribe(context);
  }

  @override
  void dispose() {
    autoReloadDispose();
    super.dispose();
  }

  @override
  Future<void> reloadTab() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      _serverMatches = await service.listMatchesWithState();
      // 72-Stunden-Regel (Betreiber-Entscheidung): Aktive Funken, in denen
      // 72 h niemand geschrieben hat, wandern RUHIG unter "Erschlossene
      // Funken" - die App räumt auf, gibt die Verbindung aber nie ganz auf
      // (Re-Funke jederzeit möglich). Frisch entstandene Funken (z. B. aus
      // einem Zufallschat, der "nicht so gut lief") bleiben mindestens
      // 3 Tage aktiv - niemand soll zu schnell aufgeben.
      await _autoCoolStaleSparks();
      // Angesehen = Badge auf Aktuelles weg (v0.9.1, Seen-Tracking).
      final seenBox = ref.read(seenProvider.notifier);
      unawaited(seenBox
          .markMatchesSeen(_serverMatches.map((m) => m.matchId)));
      unawaited(seenBox.markQrSeen(ref
          .read(chatProvider)
          .where((m) => m.isQrContact)
          .map((m) => m.id)));
      ref.invalidate(serverMatchesProvider);
    } catch (e) {
      debugPrint('[Interessen] Matches laden fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Schwelle für die automatische Kühlung inaktiver Funken.
  static const Duration _autoCoolAfter = Duration(hours: 72);

  /// Kühlt aktive Funken ohne letzte Aktivität älter als [_autoCoolAfter]
  /// automatisch (status -> cooled via cool_match-RPC). Letzte Aktivität =
  /// letzte LOCALE Nachricht (E2E: der Server kennt Inhalte nie) oder,
  /// falls kein Verlauf existiert, die Match-Erstellung.
  Future<void> _autoCoolStaleSparks() async {
    if (!SupabaseService.isInitialized) return;
    final cutoff = DateTime.now().subtract(_autoCoolAfter);
    final stale = <MatchWithState>[];
    for (final m in _serverMatches) {
      if (m.status != 'active') continue;
      if (_lastSparkActivity(m).isBefore(cutoff)) stale.add(m);
    }
    if (stale.isEmpty) return;
    final staleIds = stale.map((m) => m.matchId).toSet();
    var cooledAny = false;
    for (final m in stale) {
      try {
        await ref.read(findYourMatchServiceProvider).coolMatch(m.matchId);
        cooledAny = true;
      } catch (_) {
        // Bereits gekühlt (Gegenseite war schneller) oder Netzwerkfehler:
        // ignorieren, beim nächsten Laden wird erneut geprüft.
      }
    }
    if (cooledAny && mounted) {
      // Lokal sofort umziehen (ohne erneuten Server-Roundtrip).
      _serverMatches = _serverMatches
          .where((m) => !staleIds.contains(m.matchId))
          .followedBy(stale.map((m) => MatchWithState(
                matchId: m.matchId,
                partner: m.partner,
                unlockLevel: m.unlockLevel,
                failedAttempts: m.failedAttempts,
                createdVia: m.createdVia,
                status: 'cooled',
                createdAt: m.createdAt,
                resparkedAt: m.resparkedAt,
                passedAt: m.passedAt,
                lastAttemptAt: m.lastAttemptAt,
              )))
          .toList();
    }
  }

  /// Zeitpunkt der letzten Aktivität eines Funkens: letzte lokale
  /// Nachricht, sonst der letzte RE-FUNKE (Karenzzeit, Migration 101 -
  /// ohne sie hätte die Auto-Kühlung jeden frisch entfachten Funken beim
  /// nächsten Laden sofort wieder gekühlt), sonst die Match-Erstellung.
  DateTime _lastSparkActivity(MatchWithState m) {
    final msgs = ref.read(chatProvider.notifier).messagesFor('${m.matchId}');
    var last = m.createdAt ?? DateTime.now();
    final resparked = m.resparkedAt;
    if (resparked != null && resparked.isAfter(last)) last = resparked;
    if (msgs.isNotEmpty && msgs.last.timestamp.isAfter(last)) {
      last = msgs.last.timestamp;
    }
    return last;
  }

  void _toggleSelect(int matchId) {
    setState(() {
      if (!_selected.add(matchId)) {
        _selected.remove(matchId);
      }
      if (_selected.isEmpty) {
        ref.read(matchSelectModeProvider.notifier).state = false;
      }
    });
  }

  Future<void> _hideSelected() async {
    final service = ref.read(findYourMatchServiceProvider);
    var failed = 0;
    for (final id in _selected) {
      try {
        await service.hideMatch(id);
      } catch (e) {
        debugPrint('[Interessen] hide fehlgeschlagen ($id): $e');
        failed++;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failed == 0
              ? L10n.tf(context, 'interests.hiddenCount',
                  {'n': '${_selected.length}'})
              : L10n.tf(context, 'interests.hideFailed', {
                  'failed': '$failed',
                  'total': '${_selected.length}',
                })),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    setState(() {
      _selected.clear();
    });
    ref.read(matchSelectModeProvider.notifier).state = false;
    _load();
  }

  /// Funke direkt in der Liste kühlen (v0.9.1): active -> cooled.
  ///
  /// Mit dem gleichen Ehrlich-Dialog wie im Chat (ruhig vs. Absage-Text).
  /// Ein gewählter Absage-Text geht E2E-verschlüsselt über das Relay raus
  /// (kein Chat nötig). Optimistisch SOFORT lokal auf "cooled" setzen (die
  /// App "merkt" es dadurch direkt, kein doppeltes Kühlen möglich);
  /// "bereits gekühlt" vom Server zählt als Erfolg statt Fehler.
  Future<void> _cool(MatchWithState match) async {
    if (match.cooled) {
      _load();
      return;
    }
    final choice = await showEndSparkDialog(context);
    if (choice == null || !mounted) return;
    final goodbye =
        goodbyeTextForChoice(context, choice);
    if (goodbye != null) {
      // Absage-Text ohne geöffneten Chat zustellen (Relay, best-effort).
      try {
        await ref.read(relayServiceProvider).storeText(
              peerId: match.partner.id,
              text: goodbye,
            );
        if (SupabaseService.isInitialized) {
          await SupabaseService.client.functions.invoke(
            'notify-user',
            body: {
              'kind': 'messages',
              'target_user_id': match.partner.id,
            },
          );
        }
      } catch (_) {}
      if (!mounted) return;
    }
    setState(() {
      _serverMatches = _serverMatches
          .map((m) => m.matchId == match.matchId
              ? MatchWithState(
                  matchId: m.matchId,
                  partner: m.partner,
                  unlockLevel: m.unlockLevel,
                  failedAttempts: m.failedAttempts,
                  createdVia: m.createdVia,
                  status: 'cooled',
                  createdAt: m.createdAt,
                  resparkedAt: m.resparkedAt,
                  passedAt: m.passedAt,
                  lastAttemptAt: m.lastAttemptAt,
                )
              : m)
          .toList();
    });
    try {
      await ref.read(findYourMatchServiceProvider).coolMatch(match.matchId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tf(context, 'interests.cooledDone',
                {'name': match.partner.name})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Bereits gekühlt (z. B. Doppel-Tap): kein Fehler, nur neu laden.
      if (e.toString().toLowerCase().contains('bereits gekuehlt')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.tf(context, 'interests.cooledDone',
                  {'name': match.partner.name})),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tf(context, 'common.errorWith',
                {'error': '$e'})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    _load();
  }

  /// Funke direkt in der Liste entfernen (ausblenden, nur für mich).
  Future<void> _hide(MatchWithState match) async {
    try {
      await ref.read(findYourMatchServiceProvider).hideMatch(match.matchId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tf(context, 'interests.hiddenOne',
                {'name': match.partner.name})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tf(context, 'common.errorWith',
                {'error': '$e'})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// "Re-Funke ohne Druck": gekühlte Verbindung mit einem Tap reaktivieren.
  Future<void> _respark(MatchWithState match) async {
    try {
      await ref.read(findYourMatchServiceProvider).resparkMatch(match.matchId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(L10n.tf(context, 'interests.resparkDone', {'name': match.partner.name})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'interests.resparkFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Gespeichertes Profil (persistenter QR-Kontakt) entfernen - mit
  /// Bestätigung, da der zugehörige Chat/Verlauf mit verloren geht.
  Future<void> _deleteSavedProfile(
    BuildContext context,
    WidgetRef ref,
    Match contact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'interests.deleteSavedTitle')),
        content: Text(L10n.tf(
          ctx,
          'interests.deleteSavedBody',
          {'name': contact.partner.name},
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'intro.discardKeep')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(L10n.t(ctx, 'intro.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !ref.context.mounted) return;
    ref.read(chatProvider.notifier).deleteQrContact(contact.id);
    if (ref.context.mounted) {
      ScaffoldMessenger.of(ref.context).showSnackBar(
        SnackBar(
          content: Text(L10n.tf(
              ref.context, 'profile.detail.savedRemoved',
              {'name': contact.partner.name})),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // NUTZERWUNSCH "Verwalten funktioniert nicht richtig": Der Modus lebt
    // im Provider - der Tab muss ihn WATCHEN (sonst reagierte der
    // AppBar-Button nicht sichtbar) und bei Wechsel das Auswahl-Set
    // leeren.
    ref.listen<bool>(matchSelectModeProvider, (prev, next) {
      if (prev != next) setState(() => _selected.clear());
    });
    // QR-Kontakte sind nur lokal gespeichert (kein DB-Match).
    final qrContacts =
        ref.watch(chatProvider).where((m) => m.isQrContact).toList();
    final selectMode = ref.watch(matchSelectModeProvider);

    // v0.8.0: aktive Funken oben, gekühlte ("Erschlossene Funken") unten -
    // ohne Countdown, ohne Ablauf-Benachrichtigung, ohne Verlängerungsdruck.
    final activeMatches =
        _serverMatches.where((m) => m.status == 'active').toList();
    final cooledMatches =
        _serverMatches.where((m) => m.status == 'cooled').toList();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_serverMatches.isEmpty && qrContacts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: EmptyState(
              icon: Icons.chat_bubble_outline,
              title: L10n.t(context, 'interests.emptySparksTitle'),
              message: L10n.t(context, 'interests.emptySparksBody'),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        // v0.9.1-Fix (Android 16): Ohne AlwaysScrollable löst Pull bei
        // kurzer Liste nie aus - Tab 1/2 hatten die Physics, Tab 3 nicht.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (_serverMatches.isNotEmpty) ...[
            // NUTZERWUNSCH: Der "Verwalten"-Textbutton nahm zu viel Platz
            // ein. Er lebt jetzt als Icon-Button in der AppBar (aktiver
            // Modus: Abbrechen + Zähler bleiben hier in der Zeile).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  if (selectMode) ...[
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selected.clear();
                        });
                        ref.read(matchSelectModeProvider.notifier).state =
                            false;
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(L10n.t(context, 'common.cancel')),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _selected.isEmpty ? null : _hideSelected,
                      icon: const Icon(Icons.visibility_off, size: 18),
                      label: Text(L10n.tf(context, 'interests.hideSelected',
                          {'n': '${_selected.length}'})),
                    ),
                  ] else ...[
                    const Spacer(),
                  ],
                ],
              ),
            ),
          ],
          if (qrContacts.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.bookmark,
              title: L10n.t(context, 'interests.savedTitle'),
              subtitle: L10n.t(context, 'interests.savedSub'),
            ),
            ...qrContacts.map((m) => ListTile(
                  leading: GestureDetector(
                    onTap: () => context.push(
                      AppRoutes.profileDetailPath(m.partner.id),
                    ),
                    child: const CircleAvatar(
                      child: Icon(Icons.person),
                    ),
                  ),
                  title: Text('${m.partner.name}, ${m.partner.age}'),
                  subtitle: Text(L10n.t(context, 'interests.savedTileSub')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (m.unreadCount > 0)
                        Badge.count(count: m.unreadCount),
                      IconButton(
                        icon: const Icon(Icons.person_outline),
                        tooltip: L10n.t(
                            context, 'profile.detail.aboutMe'),
                        onPressed: () => context.push(
                          AppRoutes.profileDetailPath(m.partner.id),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        tooltip: L10n.t(context, 'qr.savedDeleteTooltip'),
                        onPressed: () =>
                            _deleteSavedProfile(context, ref, m),
                      ),
                    ],
                  ),
                  onTap: () {
                    ref.read(chatProvider.notifier).markRead(m.id);
                    // Gelesen + gesehen (Badges weg, v0.9.1).
                    unawaited(ref
                        .read(seenProvider.notifier)
                        .markQrSeen([m.id]));
                    // Push: Zurück landet wieder exakt hier (gleicher Tab).
                    context.push(AppRoutes.chatDetailPath(m.id));
                  },
                )),
            const SizedBox(height: 8),
            const Divider(indent: 16, endIndent: 16),
          ],
          if (activeMatches.isNotEmpty) ...[
_SectionHeader(
icon: Icons.favorite,
title: L10n.t(context, 'interests.sparksTitle'),
subtitle: L10n.t(context, 'interests.matchesSub'),
),
            ...activeMatches.map((m) {
              if (selectMode) {
                return CheckboxListTile(
                  value: _selected.contains(m.matchId),
                  onChanged: (_) => _toggleSelect(m.matchId),
                  title: Text('${m.partner.name}, ${m.partner.age ?? '?'}'),
                  secondary: const Icon(Icons.chat_bubble_outline),
                );
              }
              return _MatchTile(
                match: m,
                // v0.9.0-Feedback: "Auf die Person klicken -> kommt direkt
                // das Kennenlern-Quiz" - jetzt öffnet die Kachel IMMER den
                // Chat; das Quiz ist als Button im Chat erreichbar (es
                // schaltet nur das Foto frei). Das Profil (inkl.
                // Vorstellung) ist über den Personen-Button erreichbar.
                // Kühlen/Entfernen geht direkt über das Menü (v0.9.1).
                // Push: Zurück landet wieder exakt hier (gleicher Tab).
                onTap: () {
                  ref.read(chatProvider.notifier).markRead(
                        m.matchId.toString(),
                      );
                  unawaited(ref
                      .read(seenProvider.notifier)
                      .markMatchesSeen([m.matchId]));
                  context.push(
                      AppRoutes.chatDetailPath(m.matchId.toString()));
                },
                onProfile: () => context.push(
                  AppRoutes.profileDetailPath(m.partner.id),
                ),
                onCool: () => _cool(m),
                onHide: () => _hide(m),
              );
            }),
          ],
          // "Erschlossene Funken" (v0.8.0): gekühlte Verbindungen, ganz
          // unten. KEIN Countdown, KEINE Ablauf-Benachrichtigung, KEINE
          // "jetzt verlängern!"-Aktion - nur der freiwillige Re-Funke.
          if (cooledMatches.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(indent: 16, endIndent: 16),
            _SectionHeader(
              icon: Icons.archive_outlined,
              title: L10n.t(context, 'interests.cooledTitle'),
              subtitle: L10n.t(context, 'interests.cooledSub'),
            ),
            ...cooledMatches.map((m) => _CooledMatchTile(
                  match: m,
                  onOpen: () {
                    ref
                        .read(chatProvider.notifier)
                        .markRead(m.matchId.toString());
                    unawaited(ref
                        .read(seenProvider.notifier)
                        .markMatchesSeen([m.matchId]));
                    context.push(
                        AppRoutes.chatDetailPath(m.matchId.toString()));
                  },
                  onProfile: () => context.push(
                    AppRoutes.profileDetailPath(m.partner.id),
                  ),
                  onRespark: () => _respark(m),
                )),
          ],
        ],
      ),
    );
  }
}

/// Kachel für "Erschlossene Funken" (status = cooled): gedimmt, mit
/// Re-Funke-Button (ein Tap, ohne Frist, ohne Benachrichtigung).
class _CooledMatchTile extends StatelessWidget {
  const _CooledMatchTile({
    required this.match,
    required this.onOpen,
    required this.onProfile,
    required this.onRespark,
  });

  final MatchWithState match;
  final VoidCallback onOpen;
  final VoidCallback onProfile;
  final VoidCallback onRespark;

  @override
  Widget build(BuildContext context) {
    final p = match.partner;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.5),
      child: ListTile(
        onTap: onOpen,
        leading: GestureDetector(
          onTap: onProfile,
          child: const CircleAvatar(child: Icon(Icons.person_outline)),
        ),
        title: Text('${p.name}, ${p.age ?? '?'}'),
        subtitle: Text(
          p.bio.isNotEmpty ? p.bio : L10n.t(context, 'interests.noBio'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip:
                  L10n.t(context, 'profile.detail.aboutMe'),
              onPressed: onProfile,
            ),
            FilledButton.tonalIcon(
              onPressed: onRespark,
              icon: const Icon(Icons.local_fire_department, size: 18),
              label: Text(L10n.t(context, 'interests.resparkBtn')),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  )),
          const SizedBox(width: 8),
          Expanded(
            child: Text(subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
        ],
      ),
    );
  }
}

class _MatchTile extends ConsumerWidget {
  const _MatchTile({
    required this.match,
    required this.onTap,
    required this.onProfile,
    required this.onCool,
    required this.onHide,
  });

  final MatchWithState match;
  final VoidCallback onTap;
  final VoidCallback onProfile;
  final VoidCallback onCool;
  final VoidCallback onHide;

  /// Blockieren aus dem Funken-Menü (NUTZERWUNSCH): Gleicher Dialog und
  /// Ablauf wie im Chat (Bestätigung -> blockUser -> Funken-Tab).
  Future<void> _confirmBlockTile(
    BuildContext context,
    WidgetRef ref,
    MatchWithState m,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.block, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(L10n.t(ctx, 'chat.blockTitle'))),
          ],
        ),
        content: Text(L10n.tf(
            ctx, 'chat.blockBody', {'name': m.partner.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(L10n.t(ctx, 'chat.blockAction')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await SupabaseDatabaseService(SupabaseService.client)
          .blockUser(m.partner.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.tf(
              context, 'chat.blockedDone', {'name': m.partner.name})),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.blockFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = match.partner;
    // Quiz-Hinweis erst nach 50-70 Nachrichten (pro Chat deterministisch,
    // gleiche Schwelle wie im Chat-Screen).
    final threshold =
        50 + (match.matchId.toString().hashCode.abs() % 21);
    final msgCount = ref
        .watch(chatProvider.notifier)
        .messagesFor(match.matchId.toString())
        .length;
    final showQuizHint = !match.quizPassed &&
        match.createdVia == 'find_match' &&
        msgCount >= threshold;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: GestureDetector(
          onTap: onProfile,
          child: CircleAvatar(
            radius: 28,
            child: match.quizPassed
                ? const Icon(Icons.person)
                : const Icon(Icons.visibility_off),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text([
                '${p.name}, ${p.age ?? '?'}',
                if (p.distanceKm > 0) p.distanceLabel,
              ].join(' · ')),
            ),
            // KEINE Streaks/Flammen-Zählung (v0.9.0-Feedback).
          ],
        ),
        subtitle: Text(
          match.quizPassed
              ? L10n.t(context, 'interests.photoUnlocked')
              : showQuizHint
                  ? L10n.t(context, 'interests.quizPending')
                  : p.bio.isNotEmpty
                      ? p.bio
                      : L10n.t(context, 'interests.noBio'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // v0.9.1: Kein Bild-/Status-Icon mehr; die 3 Punkte stehen ganz
        // rechts.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: L10n.t(context, 'profile.detail.aboutMe'),
              onPressed: onProfile,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: L10n.t(context, 'chat.more'),
              onSelected: (value) {
                switch (value) {
                  case 'cool':
                    onCool();
                  case 'hide':
                    onHide();
                  case 'report':
                    showReportUserDialog(
                      context: context,
                      ref: ref,
                      reportedUserId: p.id,
                      reportedUserName: p.name,
                    );
                  case 'block':
                    _confirmBlockTile(context, ref, match);
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'cool',
                  child: ListTile(
                    leading: const Icon(Icons.ac_unit_outlined),
                    title: Text(L10n.t(context, 'interests.coolBtn')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'hide',
                  child: ListTile(
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: Text(
                        L10n.t(context, 'interests.hideOneBtn')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                // NUTZERWUNSCH: Melden/Blockieren auch im Funken-Menü.
                PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(L10n.t(context, 'profile.detail.reportUser')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: ListTile(
                    leading: const Icon(Icons.block, color: Colors.red),
                    title: Text(L10n.t(context, 'profile.detail.blockUser')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
