import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
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

class _UsageTimeGateState extends ConsumerState<UsageTimeGate> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Alle 30 Sekunden nachsehen: sonst bleibt die App offen, wenn die
    // erlaubte Zeit ablaeuft, und der Jugendliche merkt es erst beim
    // naechsten Bildschirmwechsel.
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
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
