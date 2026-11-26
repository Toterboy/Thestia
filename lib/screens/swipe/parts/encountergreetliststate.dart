// Der Teil '_EncounterGreetListState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

class _EncounterGreetListState extends ConsumerState<_EncounterGreetList> {
  final Set<String> _pinged = {};

  String _ago(BuildContext context, DateTime seenAt) {
    final d = DateTime.now().difference(seenAt);
    if (d.inSeconds < 60) return L10n.t(context, 'transit.justNow');
    if (d.inMinutes < 60) {
      return L10n.tf(context, 'transit.minutesAgo', {
        'count': d.inMinutes.toString(),
      });
    }
    return L10n.tf(context, 'transit.hoursAgo', {
      'count': d.inHours.toString(),
    });
  }

  Future<void> _greet(TransitEncounter e) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SoftPingSheet(token: e.token),
    );
    if (ok == true && mounted) {
      setState(() => _pinged.add(e.token));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'transit.pingSent')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 2-Stunden-Ruhezeit (v0.9.0): Auch nach Radar-Ende bleiben gesehene
    // Personen sichtbar - die Liste zeigt softEncounters (2 h) statt
    // nur frische (45 min). WATCH statt READ (Fix "Button verschwindet"):
    // ohne Watch liefen neue Encounters/Grüß-Buttons nie nach - der
    // encounterCount im State ist der Rebuild-Trigger, die Liste selbst
    // kommt aus dem Encounter-Cache.
    final transit = ref.watch(transitProvider);
    final encounters = ref.read(transitProvider.notifier).softEncounters();
    if (encounters.isEmpty) {
      return Text(
        L10n.t(context, 'transit.noEncounters'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    // BEFUND (11.11.2026, Idee 4): Die Liste zeigte höchstens 10
    // Personen, ohne dass man es merkte - wer 25 Menschen in der Nähe
    // hatte, sah 10. Die Gesamtzahl steht jetzt über der Liste.
    final alle = transit.encounterCount;
    final gezeigt = encounters.take(10).toList();
    return Column(
      children: [
        if (alle > gezeigt.length)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              L10n.tf(context, 'transit.nearbyCount', {
                'count': '$alle',
                'shown': '${gezeigt.length}',
              }),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final e in gezeigt)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.person_outline),
            title: Text(_ago(context, e.seenAt)),
            trailing: _pinged.contains(e.token)
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : TextButton(
                    onPressed: () => _greet(e),
                    child: Text(L10n.t(context, 'transit.greet')),
                  ),
          ),
      ],
    );
  }
}
