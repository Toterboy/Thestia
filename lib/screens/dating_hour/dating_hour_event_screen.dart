import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/dating_hour_models.dart';
import 'package:wisp/providers/dating_hour_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/screens/dating_hour/dating_hour_preferences_screen.dart'
    show genderPrefFromList;
import 'package:wisp/services/dating_hour_service.dart';
import 'package:wisp/services/notification_service.dart';
import 'package:wisp/services/server_time_service.dart';
import 'package:wisp/utils/constants.dart';

/// Haupt-Screen für den Dating Hour Event.
///
/// Zeigt das aktuelle/nächste Event aus Supabase, den Countdown bis zum Start
/// (verifizierte Serverzeit) und erlaubt Opt-in/Opt-out. Während des Events
/// wird bei einer aktiven Session ein "Zum Chat"-Button angezeigt.
class DatingHourEventScreen extends ConsumerStatefulWidget {
  const DatingHourEventScreen({super.key});

  @override
  ConsumerState<DatingHourEventScreen> createState() => _DatingHourEventScreenState();
}

class _DatingHourEventScreenState extends ConsumerState<DatingHourEventScreen> {
  Timer? _refreshTimer;
  Timer? _countdownTimer;
  String? _reminderScheduledFor;

  // Guard: Rejoin-Abfrage nach Event-Ende nur einmal pro Screen-Lebensdauer.
  bool _rejoinAsked = false;

  // Guard: Auto-Beitritt nur einmal pro Screen-Besuch versuchen (kein Loop
  // mit dem Provider-Refresh nach joinEvent).
  bool _autoJoinAttempted = false;

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
    _startCountdown();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    // V: Regelmäßiger Refresh vom Server, damit Status-Wechsel (scheduled ->
    // active -> ended) und neu zugewiesene Sessions zeitnah angezeigt werden.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(currentDatingHourEventProvider);
    });
  }

  void _startCountdown() {
    // V: Countdown läuft auf verifizierter Serverzeit, nicht DateTime.now().
    // v0.9.1 (Akku): Die Anzeige ist minutengenau ("in X Minuten"), ein
    // 20-Sekunden-Takt genügt statt Sekunden-Rebuilds des ganzen Screens.
    _countdownTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Plant EINMALIG die Benachrichtigung "10 Minuten vor Beginn".
  ///
  /// Läuft über die lokale OS-Planung (zonedSchedule) und feuert damit
  /// AUCH bei geschlossener App. Nur wenn der Nutzer teilnimmt (Opt-in)
  /// wird erinnert. Der Einzel-Schalter "Dating Hour Erinnerung" wird
  /// zusätzlich geprüft.
  void _scheduleStartReminder(DatingHourEvent event, bool isParticipating) {
    if (!isParticipating) return;
    final settings = ref.read(settingsProvider);
    if (!settings.notifyDatingHour) return;

    final start = DateTime(
      event.eventDate.year,
      event.eventDate.month,
      event.eventDate.day,
      event.startHour,
      event.startMinute,
    );
    final remindAt = start.subtract(const Duration(minutes: 10));
    final now = ServerTimeService.instance.getVerifiedNow();
    if (remindAt.isBefore(now) || remindAt.difference(now) > const Duration(hours: 24)) {
      return;
    }

    final key = '${event.id}_${event.eventDate.toIso8601String()}';
    if (_reminderScheduledFor == key) return;
    _reminderScheduledFor = key;

    NotificationService.instance.scheduleAt(
      id: event.id.hashCode,
      when: remindAt,
      title: L10n.t(context, 'dh.event.startingSoon'),
      body: 'In 10 Minuten geht es los, sei dabei!',
      channelId: 'events',
    );
  }

  /// Entfernt eine geplante Erinnerung (z. B. nach Opt-out).
  void _cancelStartReminder(DatingHourEvent event) {
    NotificationService.instance.cancel(event.id.hashCode);
    _reminderScheduledFor = null;
  }

  Future<void> _joinEvent() async {
    // Explizite Bestätigung: Die Teilnahme darf NUR über diesen Flow
    // entstehen (kein automatischer Beitritt durch Refresh oder
    // Präferenzen-Speichern).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'dh.event.joinConfirmTitle')),
        content: Text(
          L10n.t(ctx, 'dh.event.joinConfirmBody'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'dh.event.join')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final service = ref.read(datingHourServiceProvider);
    // Defaults aus der Einrichtung übernehmen (identisch zum
    // Präferenzen-Screen, solange der Nutzer dort nichts angepasst hat).
    final settings = ref.read(settingsProvider);
    final userPrefs = ref.read(userPreferencesProvider);
    final preferences = DatingHourPreferences(
      ageMin: settings.ageRangeMin.clamp(18, 99),
      ageMax: settings.ageRangeMax.clamp(18, 99),
      genderPreference: genderPrefFromList(userPrefs.genderPreferences),
      preferredTrait: 'Humor',
      maxDistanceKm: settings.maxDistanceKm.toDouble(),
    );
    try {
      await service.joinEvent(AppConstants.currentUserId, preferences);
      ref.invalidate(currentDatingHourEventProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'dh.event.joined'))),
        );
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

  Future<void> _leaveEvent() async {
    final service = ref.read(datingHourServiceProvider);
    try {
      final event = await service.getCurrentOrNextEvent();
      await service.leaveEvent(AppConstants.currentUserId);
      if (event != null) _cancelStartReminder(event);
      ref.invalidate(currentDatingHourEventProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'dh.event.left'))),
        );
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

  /// Ende des Events + letzte Entscheidung getroffen: Einmalig fragen, ob
  /// der Nutzer beim nächsten Mal automatisch wieder dabei sein will.
  Future<void> _askRejoin() async {
    final rejoin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'dh.event.bye')),
        content: Text(L10n.t(context, 'dh.event.autoJoinAsk')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(context, 'dh.event.noThanks')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'dh.event.yesPlease')),
          ),
        ],
      ),
    );
    if (rejoin == null || !mounted) return;
    await ref.read(settingsProvider.notifier).setDatingHourAutoJoin(rejoin);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(rejoin
              ? L10n.t(context, 'dh.event.autoJoinOn')
              : L10n.t(context, 'dh.event.autoJoinOff')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Automatischer Wiederbeigritt (datingHourAutoJoin): Nutzt dieselben
  /// Default-Präferenzen wie der manuelle Beitritt.
  Future<void> _autoJoin() async {
    final service = ref.read(datingHourServiceProvider);
    final settings = ref.read(settingsProvider);
    final userPrefs = ref.read(userPreferencesProvider);
    final preferences = DatingHourPreferences(
      ageMin: settings.ageRangeMin.clamp(18, 99),
      ageMax: settings.ageRangeMax.clamp(18, 99),
      genderPreference: genderPrefFromList(userPrefs.genderPreferences),
      preferredTrait: 'Humor',
      maxDistanceKm: settings.maxDistanceKm.toDouble(),
    );
    try {
      await service.joinEvent(AppConstants.currentUserId, preferences);
      ref.invalidate(currentDatingHourEventProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${L10n.t(context, 'dh.event.welcomeBack')} '
                '${L10n.t(context, 'dh.event.prefsNote')}'),
          ),
        );
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'dh.event.autoJoinFailed').replaceAll('{error}', e.message))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(currentDatingHourEventProvider);

    return eventAsync.when(
      loading: () => const _LoadingScreen(),
      error: (err, _) => _ErrorScreen(error: err.toString()),
      data: (event) {
        if (event == null) return const _NoEventScreen();
        return _buildEventContent(event);
      },
    );
  }

  Widget _buildEventContent(DatingHourEvent event) {
    // V: Status/Countdown-Properties von [event] verwenden intern
    // [ServerTimeService.instance.getVerifiedNow()], niemals DateTime.now().
    final isRunning = event.isRunningNow;
    final isEnded = event.isEnded;
    final isParticipating = event.currentUserParticipating;
    final canJoin = event.canJoin;
    final minutesUntilStart = event.minutesUntilStart;
    final minutesUntilEnd = event.minutesUntilEnd;

    // Erinnerung planen: Benachrichtigung genau 10 Minuten vor Beginn
    // (nur bei Teilnahme; feuert auch bei geschlossener App).
    if (!isRunning && !isEnded && minutesUntilStart > 0) {
      _scheduleStartReminder(event, isParticipating);
    }

    // Event beendet + Nutzer war dabei: einmalig fragen, ob er beim
    // nächsten Mal automatisch wieder dabei sein will.
    if (isEnded && isParticipating && !_rejoinAsked) {
      _rejoinAsked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _askRejoin();
      });
    }

    // Auto-Beitritt: Hat der Nutzer beim letzten Event-Ende "Ja, gerne"
    // gewählt, nimmt er automatisch wieder teil (ohne erneute Bestätigung).
    if (ref.read(settingsProvider).datingHourAutoJoin &&
        isRunning &&
        !isParticipating &&
        canJoin &&
        !_autoJoinAttempted) {
      _autoJoinAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoJoin();
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // System-Zurück/Geste: zurück zur Entdeckung statt App-Beendigung
        // (die Route wurde per context.go erreicht - kein Stack zum poppen).
        if (mounted) context.go(AppRoutes.swipeModeSelection);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'dh.event.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Dating Hour wird via context.go(...) erreicht (kein Stack zum
          // poppen) -> zurück zum Entdecken-Tab navigieren.
          onPressed: () => context.go(AppRoutes.swipeModeSelection),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Event UND aktive Session neu laden.
              ref.invalidate(currentDatingHourEventProvider);
              ref.invalidate(myActiveDatingHourSessionProvider);
            },
            tooltip: L10n.t(context, 'common.refresh'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // B-05: Ohne verifizierte Server-Zeit sind Countdown/Status
            // manipulationsanfällig (lokale Uhr) — Nutzer transparent warnen.
            if (!ServerTimeService.instance.isVerified)
              const _ServerTimeWarningBanner(),
            // Event fällt aus: zu wenige Teilnehmer (Migration 067).
            if (event.status == 'cancelled') ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.event_busy,
                          color: Theme.of(context).colorScheme.onErrorContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          L10n.t(context, 'dh.event.cancelledToday'),
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Fortschritt zum Teilnehmer-Ziel: "X von 20" + was fehlt
            // (Ziel in der DB-Logik verankert, Migration 067).
            if (event.status != 'cancelled') ...[
              _ParticipantProgress(eventId: event.id),
              const SizedBox(height: 16),
            ],
            _EventStatusCard(
              event: event,
              isRunning: isRunning,
              isEnded: isEnded,
              isParticipating: isParticipating,
              minutesUntilStart: minutesUntilStart,
              minutesUntilEnd: minutesUntilEnd,
            ),
            const SizedBox(height: 24),
            _buildActionArea(event, isRunning, isEnded, isParticipating, canJoin),
            const SizedBox(height: 24),
            const _EventInfoCard(),
            const SizedBox(height: 24),
            const _RulesCard(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildActionArea(
    DatingHourEvent event,
    bool isRunning,
    bool isEnded,
    bool isParticipating,
    bool canJoin,
  ) {
    if (isEnded) {
      return _PrimaryActionButton(
        icon: Icons.event_busy,
        label: L10n.t(context, 'dh.event.ended'),
        onPressed: null,
        color: Colors.grey,
      );
    }

    if (isRunning && isParticipating) {
      return _ActiveSessionButton(eventId: event.id);
    }

    if (isRunning && !isParticipating && canJoin) {
      return _PrimaryActionButton(
        icon: Icons.login,
        label: L10n.t(context, 'dh.event.joinNow'),
        onPressed: _joinEvent,
        color: Colors.green,
      );
    }

    if (!isRunning && isParticipating) {
      return _PrimaryActionButton(
        icon: Icons.event_busy,
        label: L10n.t(context, 'dh.event.leave'),
        onPressed: _leaveEvent,
        color: Colors.red,
      );
    }

    if (!isRunning && canJoin && !isParticipating) {
      return Column(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.tune),
            label: Text(L10n.t(context, 'dh.prefs.setBtn')),
            onPressed: () => context.go(AppRoutes.datingHourPreferences),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 16),
          _PrimaryActionButton(
            icon: Icons.event_available,
            label: L10n.t(context, 'dh.event.join'),
            onPressed: _joinEvent,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      );
    }

    return _PrimaryActionButton(
      icon: Icons.schedule,
      label:
          '${L10n.t(context, 'dh.nextEventIn')} ${_formatDuration(context, event.minutesUntilStart)}',
      onPressed: null,
      color: Colors.grey,
    );
  }
}

String _formatDuration(BuildContext context, int minutes) {
  String mins(int m) => L10n.tf(
      context, m == 1 ? 'dh.duration.minute' : 'dh.duration.minutes',
      {'m': '$m'});
  String hrs(int h) => L10n.tf(
      context, h == 1 ? 'dh.duration.hour' : 'dh.duration.hours',
      {'h': '$h'});
  if (minutes < 60) return mins(minutes);
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return hrs(h);
  return '${hrs(h)} ${mins(m)}';
}

/// Teilnehmer-Anzeige (v0.9.1, Migration 096): Es gibt KEIN Mindestziel
/// mehr, die Dating Hour fällt nie wegen zu weniger Leute aus. Die Karte
/// zeigt nur, wie viele dabei sind.
class _ParticipantProgress extends ConsumerWidget {
  const _ParticipantProgress({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<int>(
      future:
          ref.read(datingHourServiceProvider).getParticipantCount(eventId),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.groups,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        L10n.tf(context, 'dh.event.participants',
                            {'n': '$count'}),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  L10n.t(context, 'dh.event.participantsSub'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Button, der die aktive Session des Users während eines Events anzeigt.
class _ActiveSessionButton extends ConsumerWidget {
  const _ActiveSessionButton({required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(myActiveDatingHourSessionProvider(eventId));

    return sessionAsync.when(
        loading: () => _PrimaryActionButton(
          icon: Icons.hourglass_top,
          label: L10n.t(context, 'dh.searching'),
        onPressed: null,
        color: Colors.grey,
      ),
      error: (err, _) => _PrimaryActionButton(
        icon: Icons.error_outline,
        label: L10n.t(context, 'dh.event.loadError'),
        onPressed: null,
        color: Colors.red,
      ),
      data: (session) {
        if (session == null) {
          return _PrimaryActionButton(
            icon: Icons.search,
            label: L10n.t(context, 'dh.event.searchingPartner'),
            onPressed: null,
            color: Colors.grey,
          );
        }
        return _PrimaryActionButton(
          icon: Icons.chat_bubble,
          label: L10n.t(context, 'dh.event.toChat'),
          onPressed: () => context.go(AppRoutes.datingHourChatPath(session.id)),
          color: Colors.pink,
        );
      },
    );
  }
}

/// Warn-Banner, wenn die Server-Zeit (noch) nicht verifiziert ist (B-05).
class _ServerTimeWarningBanner extends StatelessWidget {
  const _ServerTimeWarningBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              L10n.t(context, 'dh.event.localTimeWarn'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ladebildschirm.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'dh.event.title'))),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// Fehlerbildschirm.
class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'dh.event.title'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              L10n.t(context, 'dh.event.loadErrorFull').replaceAll('{error}', error.toString()),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hinweis, wenn kein Event verfügbar ist.
class _NoEventScreen extends StatelessWidget {
  const _NoEventScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'dh.event.title'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            L10n.t(context, 'dh.event.nonePlanned'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Status-Karte für das Event.
class _EventStatusCard extends StatelessWidget {
  const _EventStatusCard({
    required this.event,
    required this.isRunning,
    required this.isEnded,
    required this.isParticipating,
    required this.minutesUntilStart,
    required this.minutesUntilEnd,
  });

  final DatingHourEvent event;
  final bool isRunning;
  final bool isEnded;
  final bool isParticipating;
  final int minutesUntilStart;
  final int minutesUntilEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = isRunning
        ? L10n.t(context, 'dh.event.liveNow')
        : isEnded
            ? L10n.t(context, 'dh.event.ended')
            : L10n.tf(context, 'dh.event.nextAt',
                {'date': _formatDate(event.eventDate)});

    return Card(
      color: isRunning ? colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRunning ? Icons.radio_button_checked : Icons.schedule,
                  color: isRunning
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isRunning ? colorScheme.onPrimaryContainer : null,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_pad(event.startHour)}:${_pad(event.startMinute)} bis ${_pad(event.endHour)}:${_pad(event.endMinute)} Uhr',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isRunning ? colorScheme.onPrimaryContainer : null,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InfoChip(
                  icon: Icons.people,
                  label: isParticipating
                    ? L10n.t(context, 'dh.event.chipParticipating')
                    : L10n.t(context, 'dh.event.chipNotParticipating'),
                  color: isRunning ? colorScheme.onPrimaryContainer : null,
                ),
                if (isRunning)
                  _InfoChip(
                    icon: Icons.timer,
                    label: L10n.tf(context, 'dh.event.remaining',
                        {'d': _formatDuration(context, minutesUntilEnd)}),
                    color: colorScheme.onPrimaryContainer,
                  )
                else if (!isEnded && minutesUntilStart > 0)
                  _InfoChip(
                    icon: Icons.timer,
                    label: L10n.tf(context, 'dh.event.startIn',
                        {'d': _formatDuration(context, minutesUntilStart)}),
                    color: colorScheme.primary,
                  ),
              ],
            ),
            if (!isRunning && !isEnded && minutesUntilStart > 0) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: 1 - (minutesUntilStart / (24 * 60)).clamp(0.0, 1.0),
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ],
            if (isParticipating) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isRunning
                      ? colorScheme.onPrimaryContainer.withValues(alpha: 0.1)
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: isRunning
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isRunning
                            ? L10n.t(context,
                                'dh.event.participatingLive')
                            : L10n.t(context,
                                'dh.event.participatingWaiting'),
                        style: TextStyle(
                          color: isRunning
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const days = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
  return '${days[date.weekday % 7]}, ${date.day}.${date.month}.${date.year}';
}

String _pad(int value) => value.toString().padLeft(2, '0');

/// Info-Chip Widget.
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: effectiveColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: effectiveColor,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

/// Primärer Aktions-Button.
class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: onPressed != null ? color : Colors.grey,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Event-Info Karte.
class _EventInfoCard extends StatelessWidget {
  const _EventInfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.t(context, 'dh.info.title'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.favorite,
              title: L10n.t(context, 'dh.feature.realChat'),
              subtitle: L10n.t(context, 'dh.feature.noPhotos'),
            ),
            _InfoRow(
              icon: Icons.timer,
              title: L10n.t(context, 'dh.info.timeTitle'),
              subtitle: L10n.t(context, 'dh.info.timeSub'),
            ),
            _InfoRow(
              icon: Icons.lock,
              title: L10n.t(context, 'dh.feature.e2eTitle'),
              subtitle: L10n.t(context, 'dh.feature.e2eSub'),
            ),
            _InfoRow(
              icon: Icons.people,
              title: L10n.t(context, 'dh.info.liveTitle'),
              subtitle: L10n.t(context, 'dh.info.liveSub'),
            ),
            _InfoRow(
              icon: Icons.refresh,
              title: L10n.t(context, 'dh.info.retryTitle'),
              subtitle: L10n.t(context, 'dh.info.retrySub'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Regeln-Karte.
class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.t(context, 'dh.event.rulesTitle'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _RuleItem('1', L10n.t(context, 'dh.event.rule.1')),
            _RuleItem('2', L10n.t(context, 'dh.event.rule.2')),
            _RuleItem('3', L10n.t(context, 'dh.event.rule.3')),
            _RuleItem('4', L10n.t(context, 'dh.event.rule.4')),
            _RuleItem('5', L10n.t(context, 'dh.event.rule.5')),
            _RuleItem('6', L10n.t(context, 'dh.event.rule.6')),
            _RuleItem('7', L10n.t(context, 'dh.event.rule.7')),
            _RuleItem('8', L10n.t(context, 'dh.event.rule.8')),
            _RuleItem('9', L10n.t(context, 'dh.event.rule.9')),
          ],
        ),
      ),
    );
  }
}

class _RuleItem extends StatelessWidget {
  const _RuleItem(this.number, this.text);
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
