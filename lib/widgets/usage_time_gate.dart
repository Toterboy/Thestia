import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/guardian_status.dart';
import 'package:thestia/providers/guardian_provider.dart';

/// Sperrt die App ausserhalb der von den Elternteilen erlaubten Zeit.
///
/// WICHTIG - und das muss man ehrlich sagen: Das ist eine HAUSREGEL, kein
/// Sicherheitsmerkmal. Sie laeuft auf dem Geraet des Jugendlichen. Wer
/// ein gerootetes Geraet hat oder die APK selbst baut, kommt an ihr
/// vorbei - genau wie an jeder anderen Einstellung der App.
///
/// Der Weg, den die App geht, ist trotzdem der richtige: Die PIN des
/// Elternteils schuetzt die Einstellung VOR dem Jugendlichen (die
/// Pruefung laeuft serverseitig, Migration 167), und die Sperre selbst
/// verhindert dieversehentliche Ueberschreitung. Wer sie wirklich
/// umgehen will, kann das - das weiss der Betreiber und sollte es auch
/// wissen.
class UsageTimeGate extends ConsumerStatefulWidget {
  const UsageTimeGate({super.key, required this.child});

  final Widget child;

  /// Liegt die aktuelle Uhrzeit im erlaubten Fenster?
  ///
  /// Der Vergleich laeuft in der Zeitzone des Geraets - die Eltern
  /// stellen die Zeiten in der Zeit ein, in der das Kind sie erlebt.
  ///
  /// Sonderfaelle:
  ///   * start == end: eine leere Spanne. Das ist eine Fehlgabe, keine
  ///     Sperre - sonst waere die App unbenutzbar und niemand wuesste
  ///     warum. Also: keine Begrenzung.
  ///   * start > end: das Fenster laeuft ueber Mitternacht (z. B. 20:00
  ///     bis 06:00).
  static bool isWithinWindow({
    required int nowMinutes,
    required int startMinutes,
    required int endMinutes,
  }) {
    if (startMinutes == endMinutes) return true;
    if (startMinutes < endMinutes) {
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    }
    return nowMinutes >= startMinutes || nowMinutes < endMinutes;
  }

  @override
  ConsumerState<UsageTimeGate> createState() => _UsageTimeGateState();
}

class _UsageTimeGateState extends ConsumerState<UsageTimeGate>
    with WidgetsBindingObserver {
  Timer? _ticker;

  /// Laeuft die App im Vordergrund? Im Hintergrund wird der Ticker
  /// angehalten - ein Dart-Isolate arbeitet im Hintergrund weiter, und
  /// jeder Weckruf kostet Akku.
  bool _imVordergrund = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Der Ticker haengt an der Sperre: er laeuft nur, wenn ueberhaupt
    // eine Nutzungszeit begrenzt ist. Sonst weckt er 2880 Mal am Tag
    // einen Nutzer, der gar keine Beschraenkung hat.
    ref.listenManual<GuardianStatus>(guardianProvider, (prev, next) {
      _tickerAnpassen(next);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final vordergrund = state == AppLifecycleState.resumed;
    if (vordergrund != _imVordergrund) {
      _imVordergrund = vordergrund;
      _tickerAnpassen(ref.read(guardianProvider));
    }
    if (mounted) setState(() {});
  }

  /// Startet oder stoppt den Ticker passend zur Lage.
  void _tickerAnpassen(GuardianStatus status) {
    final sperreAktiv =
        status.usageLimitEnabled &&
        status.usageStartMin != null &&
        status.usageEndMin != null;

    if (!sperreAktiv || !_imVordergrund) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    if (_ticker != null) return;
    // Alle 30 Sekunden nachsehen: sonst bleibt die App offen, wenn die
    // erlaubte Zeit ablaeuft, und der Jugendliche merkt es erst beim
    // naechsten Bildschirmwechsel.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(guardianProvider);
    final start = status.usageStartMin;
    final end = status.usageEndMin;

    if (!status.usageLimitEnabled || start == null || end == null) {
      return widget.child;
    }

    final now = DateTime.now();
    final erlaubt = UsageTimeGate.isWithinWindow(
      nowMinutes: now.hour * 60 + now.minute,
      startMinutes: start,
      endMinutes: end,
    );
    if (erlaubt) return widget.child;

    return UsageLockedScreen(endMinutes: end);
  }
}

/// Der Sperrbildschirm.
class UsageLockedScreen extends StatelessWidget {
  const UsageLockedScreen({super.key, required this.endMinutes});

  final int endMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = (endMinutes ~/ 60).toString().padLeft(2, '0');
    final m = (endMinutes % 60).toString().padLeft(2, '0');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bedtime_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  L10n.t(context, 'guardian.usageLockTitle'),
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  L10n.tf(context, 'guardian.usageLockText', {'time': '$h:$m'}),
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  L10n.t(context, 'guardian.usageLockHint'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
