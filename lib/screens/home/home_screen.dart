import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/app_settings.dart';
import 'package:wisp/models/match.dart' as match_model;
import 'package:wisp/models/message.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/providers/find_your_match_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/screens/interests/interessen_screen.dart'
    show interessenInitialTabProvider;
import 'package:wisp/services/seen_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/l10n/app_strings.dart';

/// Öffnet Interessen auf dem passenden Tab per Push (v0.9.1): Likes ->
/// Erhalten (1), Funken/Nachrichten -> Funken (2). Zurück landet wieder
/// auf Aktuelles.
void _goToInteressenTab(BuildContext context, int tab) {
  try {
    ProviderScope.containerOf(context)
        .read(interessenInitialTabProvider.notifier)
        .state = tab;
  } catch (_) {}
  context.push(AppRoutes.interessen);
}

/// Start-/Dashboard-Screen ("Aktuelles") mit drei Bereichen:
/// - Neue Nachrichten (bis 5 Einträge mit Vorschau)
/// - Neue Likes (Anzahl + Navigation zu Likes-Screen)
/// - Neue Matches (Anzahl + Navigation zu Matches)
///
/// Badges verschwinden beim Ansehen (v0.9.1, Seen-Tracking) und die
/// Zähler laden neu bei Rückkehr (RouteObserver) und App-Resume.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with RouteAware, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      routeObserver.unsubscribe(this);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didPopNext() {
    // Von gepushter Seite zurück (z. B. Chat/Interessen): Zähler neu.
    _refreshCounts();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Aus Hintergrund zurück: Funken/Likes könnten sich geändert haben
    // (anderes Gerät) - neu laden.
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshCounts();
    }
  }

  void _refreshCounts() {
    try {
      ref.invalidate(pendingLikesCountProvider);
      ref.invalidate(receivedLikesProvider);
      ref.invalidate(serverMatchesProvider);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(profileProvider);
    final matches = ref.watch(chatProvider);
    // Seen-Version beobachten: Badges nach Ansehen neu berechnen.
    ref.watch(seenProvider);
    final seen = ref.read(seenProvider.notifier);

    // Ungelesene Nachrichten über alle Matches
    final newMessages = matches.fold<int>(
      0,
      (sum, m) => sum + m.unreadCount,
    );

    // Neue Likes = erhaltene, noch nicht angesehene (Fallback: Summe).
    final received =
        ref.watch(receivedLikesProvider).valueOrNull;
    final likedCount = received == null
        ? (ref.watch(pendingLikesCountProvider).valueOrNull ?? 0)
        : received
            .where((l) => !seen.likeIds.contains(l.likeId))
            .length;

    // Neue Funken = aktive Server-Funken, noch nicht angesehen, plus
    // QR-Kontakte mit ungelesenen Nachrichten (Fallback: lokale Anzahl).
    final serverMatches =
        ref.watch(serverMatchesProvider).valueOrNull;
    final int newMatches;
    if (serverMatches == null) {
      newMatches = matches.length;
    } else {
      final unseenServer = serverMatches
          .where((m) =>
              m.status == 'active' && !seen.matchIds.contains(m.matchId))
          .length;
      final unseenQr = matches
          .where((m) =>
              m.isQrContact &&
              m.unreadCount > 0 &&
              !seen.qrIds.contains(m.id))
          .length;
      newMatches = unseenServer + unseenQr;
    }

    // Neueste 5 Matches mit ungelesenen Nachrichten für Vorschau
    final recentMatchesWithMessages = matches
        .where((m) => m.unreadCount > 0)
        .toList()
      ..sort((a, b) => b.matchedAt.compareTo(a.matchedAt));
    final messagePreviews = recentMatchesWithMessages.take(5).toList();

    final name = profile.name.isNotEmpty
        ? profile.name
        : L10n.t(context, 'home.fallbackName');

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'home.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: L10n.t(context, 'home.settingsTooltip'),
            // P: push() statt go(), damit "Zurück" in den Einstellungen
            // exakt zum aufrufenden Screen (Aktuelles) zurückkehrt.
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Likes/Match-Stand vom Server neu einlesen.
          ref.invalidate(pendingLikesCountProvider);
          ref.invalidate(receivedLikesProvider);
          ref.invalidate(serverMatchesProvider);
          ref.invalidate(chatProvider);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: CustomScrollView(
          slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hallo, $name! 🙂',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Finde Verbindungen, die mehr sehen als nur ein Foto.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),

          // BEREICH 1: Neue Nachrichten
          _buildMessagesSection(
            context,
            ref,
            messagePreviews,
            newMessages,
            profile,
            settings,
          ),

          // BEREICH 2: Neue Likes
          _buildLikesSection(
            context,
            likedCount,
            profile,
          ),

          // BEREICH 3: Neue Matches
          _buildMatchesSection(
            context,
            newMatches,
            profile,
          ),

          // AKTIONS-BUTTONS: Leute entdecken & Zufallschat
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                children: [
                  PrimaryButton(
                    label: L10n.t(context, 'home.discover'),
                    icon: const Icon(Icons.favorite),
                    onPressed: () => context.go(AppRoutes.swipeModeSelection),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.chat_bubble),
                    label: Text(L10n.t(context, 'home.randomChat')),
                    onPressed: () => context.go(AppRoutes.randomChat),
                  ),
                ],
              ),
            ),
          ),

          // Abstand unten für SafeArea
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
      ),
    );
  }
}

/// BEREICH 1: Neue Nachrichten - zeigt bis zu 5 Personen mit Vorschau
Widget _buildMessagesSection(
  BuildContext context,
  WidgetRef ref,
  List<match_model.Match> matchesWithMessages,
  int totalNewMessages,
  UserProfile myProfile,
  AppSettings settings,
) {
  return SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            title: 'Neue Nachrichten',
            count: totalNewMessages,
            onTap: totalNewMessages > 0
                ? () => _goToInteressenTab(context, 2)
                : null,
          ),
          const SizedBox(height: 12),
          if (matchesWithMessages.isEmpty)
            SizedBox(
              width: double.infinity,
              child: _EmptyStateCard(
                icon: Icons.chat_bubble_outline,
                title: L10n.t(context, 'home.noMessages'),
                subtitle:
                    L10n.t(context, 'home.noMessagesSub'),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: matchesWithMessages.map((match_model.Match match) {
                final partner = match.partner;
                final lastMessage = _getLastMessagePreview(ref, match.id);
                final isPhotosVisible = AgeSafetyRules.arePhotosVisible(
                  targetAge: partner.age ?? 16,
                  viewerAge: myProfile.age ?? 16,
                  blindModeEnabled: settings.blindModeEnabled,
                  revealPhotosAfterMatch: settings.revealPhotosAfterMatch,
                  isMatched: match.photosUnlocked,
                );

                return SizedBox(
                  width: double.infinity,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () {
                        // Gelesen + Funke gesehen markieren (Badge weg).
                        ref.read(chatProvider.notifier).markRead(match.id);
                        final seenBox =
                            ref.read(seenProvider.notifier);
                        if (match.isQrContact) {
                          seenBox.markQrSeen([match.id]);
                        } else {
                          final id = int.tryParse(match.id);
                          if (id != null) seenBox.markMatchesSeen([id]);
                        }
                        context.push(AppRoutes.chatDetailPath(match.id));
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: isPhotosVisible
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : Colors.grey.shade300,
                              child: !isPhotosVisible
                                  ? const Icon(Icons.visibility_off, color: Colors.white)
                                  : const Icon(Icons.person, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          partner.name,
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (match.unreadCount > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.primary,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '${match.unreadCount}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(color: Colors.white),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    lastMessage,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    ),
  );
}

/// Helper: letzte Nachricht als Preview-Text
String _getLastMessagePreview(WidgetRef ref, String matchId) {
  final messages = ref.read(chatProvider.notifier).messagesFor(matchId);
  if (messages.isEmpty) return 'Keine Nachrichten';
  final last = messages.last;
  switch (last.type) {
    case MessageType.image:
      return '🖼️ Bild';
    case MessageType.voice:
      return '🎤 Sprachnachricht (${last.durationSeconds}s)';
    default:
      return last.text;
  }
}

/// BEREICH 2: Neue Likes
Widget _buildLikesSection(
  BuildContext context,
  int likedCount,
  UserProfile myProfile,
) {
  return SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            title: 'Neue Likes',
            count: likedCount,
            onTap: likedCount > 0
                ? () => _goToInteressenTab(context, 1)
                : null,
          ),
          const SizedBox(height: 12),
          if (likedCount == 0)
            SizedBox(
              width: double.infinity,
child: _EmptyStateCard(
icon: Icons.favorite_border,
title: L10n.t(context, 'home.noLikes'),
                subtitle: L10n.t(context, 'home.discoverSub'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: Card(
                child: InkWell(
                  onTap: () => _goToInteressenTab(context, 1),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.favorite,
                          color: Theme.of(context).colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$likedCount ${likedCount == 1 ? 'neues Like' : 'neue Likes'}',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tippe, um zu sehen, wer dich geliked hat',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// BEREICH 3: Neue Matches
Widget _buildMatchesSection(
  BuildContext context,
  int newMatches,
  UserProfile myProfile,
) {
  return SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            title: 'Neue Funken',
            count: newMatches,
            onTap: newMatches > 0
                ? () => _goToInteressenTab(context, 2)
                : null,
          ),
          const SizedBox(height: 12),
          if (newMatches == 0)
            SizedBox(
              width: double.infinity,
child: _EmptyStateCard(
icon: Icons.people_outline,
title: L10n.t(context, 'home.noSparks'),
                subtitle: L10n.t(context, 'home.likesSub'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: Card(
                child: InkWell(
                  onTap: () => _goToInteressenTab(context, 2),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.people_outline,
                          color: Theme.of(context).colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$newMatches ${newMatches == 1 ? 'neuer Funke' : 'neue Funken'}',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tippe, um alle Funken zu sehen',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Section-Header mit Titel, Anzahl und optionaler Navigation
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    this.onTap,
  });

  final String title;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        if (onTap != null)
          TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: Text(
              count > 0
                  ? L10n.tf(context, 'home.viewCount',
                      {'count': '$count'})
                  : L10n.t(context, 'home.viewAll'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
      ],
    );
  }
}

/// Leere Status-Karte für Bereiche ohne Inhalt
class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      // Clip.none: Bei großen Systemschriften kann die zentrierte Titel-
      // Zeile minimal über die Glyphen-Box hinausragen - ein Kanten-Clip
      // der Card würde dann einzelne Buchstaben (z. B. das "n" in
      // "Keine neuen Funken") abschneiden.
      clipBehavior: Clip.none,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
              overflow: TextOverflow.visible,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
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
