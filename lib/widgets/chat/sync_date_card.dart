import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/dating_hour/sync_date_provider.dart';

/// Die Karte des Sync-Dates im Chat.
///
/// DER WEG (Plan 0.11.0, "Begegnung statt Bildschirm"): Zwei Menschen,
/// die weit auseinander wohnen, treffen sich zur selben Zeit an
/// verschiedenen Orten. Diese Karte steht im Chat:
///
/// * der Vorschlag (mit der Idee und dem Zeitpunkt) - der Partner
///   nimmt an oder sagt ab,
/// * danach der gemeinsame Countdown und der Anruf-Knopf,
/// * und w\u00e4hrend des Dates l\u00e4sst nur dieser Chat (die Sperre
///   sitzt im App-Rahmen, nicht in der Karte).
///
/// Die Karte selbst zeichnet nichts, wenn es kein Date gibt - sie
/// st\u00f6rt den Chat also nicht.
class SyncDateCard extends ConsumerStatefulWidget {
  const SyncDateCard({
    super.key,
    required this.matchId,
    required this.partnerName,
    required this.onCall,
  });

  /// Die Match-ID (der Serverstand des Dates).
  final String matchId;

  /// Der Name des Partners (für "X wartet noch auf die Antwort").
  final String partnerName;

  /// Der Anruf-Knopf: der Aufrufer startet den Sprachanruf.
  final VoidCallback onCall;

  @override
  ConsumerState<SyncDateCard> createState() => _SyncDateCardState();
}

class _SyncDateCardState extends ConsumerState<SyncDateCard> {
  Timer? _ticker;

  /// Der Anbieter der Sperre (für das Aufräumen beim Schließen).
  late final void Function(String?) _sperre;

  /// Haben wir die Sperre selbst gesetzt?
  ///
  /// DER GRUND: Nach dem Abbau darf der Ref nicht mehr benutzt werden -
  /// deshalb merkt sich die Karte ihren Stand hier.
  bool _sperreGesetzt = false;

  @override
  void initState() {
    super.initState();
    final sperre = ref.read(syncDateSperreProvider.notifier);
    _sperre = (wert) => sperre.state = wert;
    // DER TICKER: Der Countdown bewegt sich jede Sekunde.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Die Sperre aufheben: der Chat wird verlassen - das Date läuft
    // zwar noch, aber der Nutzer ist woanders (oder die App schließt).
    if (_sperreGesetzt) {
      _sperre(null);
      _sperreGesetzt = false;
    }
    super.dispose();
  }

  /// Setzt oder löst die Sperre (je nachdem, ob das Date läuft).
  void _sperreSetzen(bool laeuft) {
    if (laeuft) {
      if (!_sperreGesetzt) {
        _sperre(widget.matchId);
        _sperreGesetzt = true;
      }
    } else if (_sperreGesetzt) {
      _sperre(null);
      _sperreGesetzt = false;
    }
  }

  /// Der Zeitpunkt (kurz und lesbar).
  String _zeit(DateTime zeit) =>
      DateFormat('dd.MM. HH:mm').format(zeit.toLocal());

  /// Wie lange es noch dauert (bis zum Start).
  String _noch(Duration d) {
    if (d.isNegative) return '0:00';
    final stunden = d.inHours;
    final minuten = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sekunden = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (stunden > 0) return '$stunden:$minuten:$sekunden';
    return '$minuten:$sekunden';
  }

  @override
  Widget build(BuildContext context) {
    // LOKALE KONTAKTE (QR) haben keine Datenbank-Match-ID - für sie
    // gibt es kein Sync-Date (und überhaupt keinen Serverstand).
    if (int.tryParse(widget.matchId) == null) {
      return const SizedBox.shrink();
    }
    // DIE SPERRE: Solange das Date läuft, ist nur dieser Chat
    // benutzbar (Betreiber, 27.11.2026).
    ref.listen(syncDateProvider(widget.matchId), (prev, next) {
      _sperreSetzen(next?.laeuft ?? false);
    });

    final date = ref.watch(syncDateProvider(widget.matchId));
    if (date == null) return const SizedBox.shrink();
    _sperreSetzen(date.laeuft);

    final notifier = ref.read(syncDateProvider(widget.matchId).notifier);
    final idee = L10n.t(context, date.idea.textKey);
    final scheme = Theme.of(context).colorScheme;

    // DER VORSCHLAG: Einer hat vorgeschlagen, der andere wartet noch.
    if (!date.acceptedByMe) {
      return _karte(
        farbe: scheme.secondaryContainer,
        icon: Icons.schedule,
        titel: L10n.t(context, 'sync.cardTitle'),
        text: L10n.tf(context, 'sync.proposed', {
          'name': date.proposedByMe ? widget.partnerName : widget.partnerName,
          'idee': idee,
        }),
        zeile: _zeit(date.startAt),
        aktionen: <Widget>[
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: Text(L10n.t(context, 'sync.accept')),
            onPressed: () => notifier.accept(),
          ),
          TextButton(
            onPressed: () => notifier.decline(),
            child: Text(L10n.t(context, 'sync.decline')),
          ),
        ],
      );
    }

    // ICH HABE ANGENOMMEN, DER PARTNER NOCH NICHT.
    if (!date.acceptedByPartner) {
      return _karte(
        farbe: scheme.secondaryContainer,
        icon: Icons.hourglass_empty,
        titel: L10n.t(context, 'sync.cardTitle'),
        text: L10n.tf(context, 'sync.waiting', {'name': widget.partnerName}),
        zeile: _zeit(date.startAt),
        aktionen: <Widget>[
          TextButton(
            onPressed: () => notifier.decline(),
            child: Text(L10n.t(context, 'sync.decline')),
          ),
        ],
      );
    }

    // BEIDE SIND DABEI: der Countdown und der Anruf.
    final rest = date.startAt.difference(DateTime.now());
    final laeuft = rest.isNegative;
    return _karte(
      farbe: scheme.primaryContainer,
      icon: laeuft ? Icons.local_fire_department : Icons.celebration,
      titel: L10n.t(context, 'sync.cardTitle'),
      text: L10n.tf(context, 'sync.accepted', {
        'idee': idee,
        'zeit': _zeit(date.startAt),
      }),
      zeile: laeuft ? L10n.t(context, 'sync.startNow') : _noch(rest),
      aktionen: <Widget>[
        FilledButton.icon(
          icon: const Icon(Icons.call),
          label: Text(L10n.t(context, 'sync.startNow')),
          onPressed: widget.onCall,
        ),
      ],
    );
  }

  /// Die Karte (das Gerüst ist bei allen drei Zuständen gleich).
  Widget _karte({
    required Color farbe,
    required IconData icon,
    required String titel,
    required String text,
    required String zeile,
    required List<Widget> aktionen,
  }) {
    final theme = Theme.of(context);
    return Card(
      color: farbe,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(text),
            const SizedBox(height: 4),
            Text(
              zeile,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: aktionen),
          ],
        ),
      ),
    );
  }
}
