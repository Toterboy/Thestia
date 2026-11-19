import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/models/dating_hour/dating_hour_models.dart';
import 'package:thestia/providers/dating_hour/dating_hour_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/providers/settings/user_preferences_provider.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/dating_hour/dating_hour_preferences_screen.dart'
    show genderPrefFromList;
import 'package:thestia/services/dating_hour/dating_hour_service.dart';
import 'package:thestia/services/server/notification_service.dart';
import 'package:thestia/services/server/server_time_service.dart';
import 'package:thestia/utils/common/constants.dart';

part 'parts/participantprogress.dart';
part 'parts/activesessionbutton.dart';
part 'parts/activesessionbuttonstate.dart';
part 'parts/servertimewarningbanner.dart';
part 'parts/loadingscreen.dart';
part 'parts/errorscreen.dart';
part 'parts/noeventscreen.dart';
part 'parts/eventstatuscard.dart';
part 'parts/infochip.dart';
part 'parts/primaryactionbutton.dart';
part 'parts/eventinfocard.dart';
part 'parts/inforow.dart';
part 'parts/rulescard.dart';
part 'parts/ruleitem.dart';

/// Haupt-Screen für den Dating Hour Event.
///
/// Zeigt das aktuelle/nächste Event aus Supabase, den Countdown bis zum Start
/// (verifizierte Serverzeit) und erlaubt Opt-in/Opt-out. Während des Events
/// wird bei einer aktiven Session ein "Zum Chat"-Button angezeigt.
class DatingHourEventScreen extends ConsumerStatefulWidget {
  const DatingHourEventScreen({super.key});

  @override
  ConsumerState<DatingHourEventScreen> createState() =>
      _DatingHourEventScreenState();
}

class _DatingHourEventScreenState extends ConsumerState<DatingHourEventScreen>
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    _startAutoRefresh();
    _startCountdown();
  }

  /// AKKU (03.11.2026): Die beiden Timer laufen nur im Vordergrund.
  ///
  /// Vorher pollt der Screen alle 30 Sekunden den Server - auch dann,
  /// wenn die App im Hintergrund ist und der Screen gar nicht sichtbar
  /// ist. Der Screen bleibt im Backstack gemountet, der Timer lief also
  /// unbegrenzt weiter.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAutoRefresh();
      _startCountdown();
      ref.invalidate(currentDatingHourEventProvider);
      return;
    }
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (remindAt.isBefore(now) ||
        remindAt.difference(now) > const Duration(hours: 24)) {
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
        content: Text(L10n.t(ctx, 'dh.event.joinConfirmBody')),
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
            content: Text(
              L10n.tf(context, 'common.errorWith', {'error': e.message}),
            ),
          ),
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
            content: Text(
              L10n.tf(context, 'common.errorWith', {'error': e.message}),
            ),
          ),
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
          content: Text(
            rejoin
                ? L10n.t(context, 'dh.event.autoJoinOn')
                : L10n.t(context, 'dh.event.autoJoinOff'),
          ),
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
              '${L10n.t(context, 'dh.event.prefsNote')}',
            ),
          ),
        );
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.t(
                context,
                'dh.event.autoJoinFailed',
              ).replaceAll('{error}', e.message),
            ),
          ),
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
                        Icon(
                          Icons.event_busy,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            L10n.t(context, 'dh.event.cancelledToday'),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
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
              _buildActionArea(
                event,
                isRunning,
                isEnded,
                isParticipating,
                canJoin,
              ),
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
    context,
    m == 1 ? 'dh.duration.minute' : 'dh.duration.minutes',
    {'m': '$m'},
  );
  String hrs(int h) => L10n.tf(
    context,
    h == 1 ? 'dh.duration.hour' : 'dh.duration.hours',
    {'h': '$h'},
  );
  if (minutes < 60) return mins(minutes);
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return hrs(h);
  return '${hrs(h)} ${mins(m)}';
}

String _formatDate(DateTime date) {
  const days = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
  return '${days[date.weekday % 7]}, ${date.day}.${date.month}.${date.year}';
}

String _pad(int value) => value.toString().padLeft(2, '0');
