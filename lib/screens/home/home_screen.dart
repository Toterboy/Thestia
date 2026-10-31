import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/models/app_settings.dart';
import 'package:thestia/models/match.dart' as match_model;
import 'package:thestia/models/message.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/find_your_match_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/interests/interessen_screen.dart'
    show interessenInitialTabProvider;
import 'package:thestia/services/seen_service.dart';
import 'package:thestia/utils/age_safety_rules.dart';
import 'package:thestia/l10n/app_strings.dart';

/// Hat der Nutzer schon wirklich jemanden angeschrieben?
///
/// NUTZERWUNSCH (27.10.2026): der Einstie in "Leute entdecken" soll
/// auf Aktuelles so lange stehen, bis der Nutzer einen Modus wirklich
/// BENUTZT hat - und damit gemeint ist nicht "angefasst", sondern
/// "mit jemandem geschrieben".
///
/// Die Definition im Auftrag war: "bis man eine der modi einmal genutzt
/// hat und dabei auch so richtig, also mit jemandem geschrieben hat".
///
/// Zwei Signale, und beide zaehlen:
///
///   * Es gibt einen **Funke** (Match). Dann hat der Nutzer die App
///     benutzt - das ist der ausdruecklich genannte Fall ("Funke ->
///     der Button geht weg").
///   * In einem Chat liegt eine **von mir gesendete** Nachricht. Dann
///     war es kein blosses Anschauen, sondern ein Gespraech.
///
/// Gesendet wird ueber [Message.senderId] verglichen - ungelesene
/// Nachrichten zaehlen NICHT, sonst waere der Button schon nach dem
/// ersten erhaltenen Funke weg, obwohl nie geschrieben wurde.
final hatJemandenAngeschriebenProvider = Provider<bool>((ref) {
  final meineId = ref.watch(profileProvider).id;
  if (meineId.isEmpty) return false;

  // 1) Funke? Dann ist die App benutzt.
  final funken = ref.watch(serverMatchesProvider).valueOrNull;
  if (funken != null && funken.isNotEmpty) return true;

  // 2) Selbst geschrieben? Dann gab es ein echtes Gespraech.
  final matches = ref.watch(chatProvider);
  if (matches.isEmpty) return false;
  final notifier = ref.read(chatProvider.notifier);
  for (final m in matches) {
    for (final nachricht in notifier.messagesFor(m.id)) {
      if (nachricht.senderId == meineId) return true;
    }
  }
  return false;
});

/// Der Einstieg in die Begegnungs-Modi (NUTZERWUNSCH, 27.10.2026).
///
/// Bewusst eine Karte und kein PrimaryButton: die Karte kann Erklaerung
/// und Icon aufnehmen und sitzt dabei in derselben Spalte wie die
/// Abschnitte darunter - der bisherige Button am Seitenende sah aus wie
/// ein Anhang.
///
/// Der Einstieg verschwindet, sobald der Nutzer wirklich jemanden
/// angeschrieben hat (siehe [hatJemandenAngeschriebenProvider]).
class _EntdeckeCard extends StatelessWidget {
  const _EntdeckeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.favorite, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.t(context, 'home.discover'),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      L10n.t(context, 'home.discoverSub'),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

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
    // Verifikationsstatus fuer den Hinweis (v0.10.0).
    final verificationState = ref.watch(profileProvider).verificationState;
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
          // NUTZERWUNSCH (30.10.2026): QR-Symbol direkt neben den
          // Einstellungen - der Weg zu "Connect to others" soll nicht
          // erst durch das Entdecken-Menue fuehren.
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: L10n.t(context, 'home.qrTooltip'),
            onPressed: () => context.push(AppRoutes.qrScan),
          ),
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
            // Verifikations-Hinweis (v0.10.0).
            //
            // Zwei Zustaende, zwei Texte: wer noch gar nicht geprueft
            // hat, wird zur Verifizierung eingeladen; wer die Pruefung
            // schon beantragt hat, wartet - dafuer gibt es nichts zu
            // tun, und das steht so da.
            //
            // Der Hinweis verschwindet, sobald freigegeben wurde. Er
            // steht bewusst OBEN, nicht in einer eigenen Sektion: er
            // betrifft den Vollzugang, und der ist die Voraussetzung
            // fuer die Modi.
            if (verificationState != VerificationState.verified)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      leading: Icon(
                        verificationState ==
                                VerificationState.underReview
                            ? Icons.hourglass_top
                            : Icons.verified_user_outlined,
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                      title: Text(
                        L10n.t(
                          context,
                          verificationState ==
                                  VerificationState.underReview
                              ? 'verify.stateUnderReview'
                              : 'verify.stateUnverified',
                        ),
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        L10n.t(
                          context,
                          verificationState ==
                                  VerificationState.underReview
                              ? 'dm.lockedBodyReview'
                              : 'dm.lockedBody',
                        ),
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                      ),
                      trailing: verificationState ==
                              VerificationState.underReview
                          ? null
                          : Icon(
                              Icons.chevron_right,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                      onTap: verificationState ==
                              VerificationState.underReview
                          ? null
                          : () =>
                              context.push(AppRoutes.verificationInfo),
                    ),
                  ),
                ),
              ),
            // Pausiert-Hinweis (v0.9.1): Profil unsichtbar – mit Abkürzung
            // zu den Einstellungen zum Entpausieren.
            if (settings.paused)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: ListTile(
                      leading: Icon(
                        Icons.pause_circle_outline,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                      ),
                      title: Text(
                        L10n.t(context, 'paused.homeTitle'),
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        L10n.t(context, 'paused.homeBody'),
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.settings),
                    ),
                  ),
                ),
              ),
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

          // AKTIONS-BUTTON: Leute entdecken
          //
          // NUTZERWUNSCH (27.10.2026): die beiden Buttons am ENDE der
          // Seite ("Leute entdecken" und "Zufallschat starten") sollen
          // verschwinden. Der Einstieg gehoert nach OBEN - direkt unter
          // die Begruessung, wo er im Blick ist, bevor die Liste
          // beginnt. Frueher stand die Karte am Seitenende; das war
          // genau die Stelle, von der sie weg sollte.
          //
          // Er bleibt stehen, bis der Nutzer wirklich jemanden
          // angeschrieben hat (siehe
          // [hatJemandenAngeschriebenProvider]). Wer nur empfaengt,
          // hat die App noch nicht benutzt - da hilft der Einstieg noch.
          //
          // Der Zufallschat-BUTTON ist entfallen: er war eine zweite
          // Aktion auf derselben Flaeche, ohne erkennbaren Grund -
          // "Zufallschat" ist ein Modus und laesst sich im Auswahl-
          // screen waehlen, der ohnehin ueber "Leute entdecken" erreicht
          // wird.
          if (!ref.watch(hatJemandenAngeschriebenProvider))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _EntdeckeCard(
                  onTap: () => context.go(AppRoutes.swipeModeSelection),
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
        // Expanded: der Titel gibt dem Button Platz, statt selbst
        // ueber den Rand zu laufen (RenderFlex-Overflow bei grosser
        // Systemschrift).
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
