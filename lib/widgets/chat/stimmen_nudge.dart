import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/utils/common/best_effort.dart';

/// Der sanfte Nudge Richtung Anruf (Plan 0.11.0, "Begegnung statt
/// Bildschirm").
///
/// DER WEG: "Bei Distanz-Funken den Chat sanft Richtung Anruf/
/// Sprachnachricht nudge ('Stimmen verbinden mehr als Texte')." Wer
/// 300 Kilometer entfernt wohnt, schreibt sich Text - dabei verbunden
/// man sich viel besser.
///
/// DER TON: sanft. Ein schmaler Streifen über dem Chat, kein Dialog,
/// kein Pflicht. Wer ihn wegwischt, kommt nicht wieder.
///
/// EINMAL JE CHAT: Der Merker liegt im lokalen Speicher - der Nudge
/// erscheint also einmal und dann nicht mehr (der App-Neustart ändert
/// das nicht).
class StimmenNudge extends ConsumerStatefulWidget {
  const StimmenNudge({
    super.key,
    required this.matchId,
    required this.entfernungKm,
    required this.onCall,
  });

  /// Die Match-ID (der Merker je Chat).
  final String matchId;

  /// Die Entfernung zum Partner (in Kilometern).
  final double entfernungKm;

  /// Der Anruf-Knopf.
  final VoidCallback onCall;

  /// Ab dieser Entfernung ist ein Anruf sinnvoller als Text.
  static const double grenzeKm = 50;

  /// Der Merker (die Chats, in denen der Nudge schon war).
  static const String merkerKey = 'stimmen_nudge_chats';

  @override
  ConsumerState<StimmenNudge> createState() => _StimmenNudgeState();
}

class _StimmenNudgeState extends ConsumerState<StimmenNudge> {
  /// Schon gezeigt? (null = noch nicht geprüft).
  bool? _bereitsGezeigt;

  /// Der Nutzer hat den Streifen weggewischt.
  bool _weg = false;

  @override
  void initState() {
    super.initState();
    _pruefe();
  }

  /// Prüft den Merker (und merkt sich den Chat, wenn er neu ist).
  Future<void> _pruefe() async {
    final storage = ref.read(localStorageProvider);
    final ids = await bestEffortOr<List<String>>(
      'stimmenNudge.lesen',
      () async {
        final roh = await storage.getString(StimmenNudge.merkerKey);
        if (roh == null || roh.isEmpty) return <String>[];
        final liste = jsonDecode(roh);
        if (liste is! List) return <String>[];
        return liste.map((e) => '$e').toList();
      },
      <String>[],
    );
    if (!mounted) return;
    final schonDa = ids.contains(widget.matchId);
    setState(() => _bereitsGezeigt = schonDa);
    if (schonDa) return;
    // DER MERKER: Der Nudge kommt nur einmal je Chat - er wird gemerkt,
    // sobald er das erste Mal dasteht.
    await bestEffort('stimmenNudge.schreiben', () async {
      await storage.saveString(
        StimmenNudge.merkerKey,
        jsonEncode(<String>[...ids, widget.matchId]),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Zu nah beieinander: da ist ein Anruf nicht nötig.
    if (widget.entfernungKm <= StimmenNudge.grenzeKm) {
      return const SizedBox.shrink();
    }
    // Noch nicht geprüft oder schon gewesen oder weggewischt.
    if (_bereitsGezeigt != false || _weg) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(
              Icons.graphic_eq,
              size: 18,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                L10n.t(context, 'chat.stimmenNudge'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: widget.onCall,
              child: Text(L10n.t(context, 'chat.stimmenNudgeCall')),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              tooltip: L10n.t(context, 'common.close'),
              color: scheme.onSecondaryContainer,
              onPressed: () => setState(() => _weg = true),
            ),
          ],
        ),
      ),
    );
  }
}
