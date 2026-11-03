import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/data_deletion_service.dart';
import 'package:thestia/widgets/buttons.dart';

/// Screen zum Loeschen einzelner Datenkategorien.
///
/// Das Konto bleibt erhalten - nur die angekreuzten Daten gehen. Die
/// Loeschung ist unwiderruflich, deshalb gibt es vor dem Loeschen eine
/// Bestaetigung, die auflistet, was genau verschwindet.
///
/// Der Server macht die Arbeit (Edge Function `delete-user-data`).
/// Dieser Screen schickt nur die Auswahl.
class DeleteDataScreen extends ConsumerStatefulWidget {
  const DeleteDataScreen({super.key});

  @override
  ConsumerState<DeleteDataScreen> createState() => _DeleteDataScreenState();
}

class _DeleteDataScreenState extends ConsumerState<DeleteDataScreen> {
  final _gewaehlt = <String>{};
  bool _arbeitet = false;

  /// Die Kategorien mit ihrem Text.
  ///
  /// Jede Zeile sagt, WAS genau verschwindet - und, wenn etwas auch die
  /// Gegenseite betrifft, dass es das tut. Das ist der Punkt: eine
  /// Loeschung, die im Hintergrund auch den Chat der anderen Person
  /// beendet, muss das sagen.
  List<({String key, String titel, String text})> _kategorien() {
    return [
      (
        key: 'fotos',
        titel: L10n.t(context, 'del.fotos'),
        text: L10n.t(context, 'del.fotosSub'),
      ),
      (
        key: 'standort',
        titel: L10n.t(context, 'del.standort'),
        text: L10n.t(context, 'del.standortSub'),
      ),
      (
        key: 'profil',
        titel: L10n.t(context, 'del.profil'),
        text: L10n.t(context, 'del.profilSub'),
      ),
      (
        key: 'likes',
        titel: L10n.t(context, 'del.likes'),
        text: L10n.t(context, 'del.likesSub'),
      ),
      (
        key: 'funken',
        titel: L10n.t(context, 'del.funken'),
        text: L10n.t(context, 'del.funkenSub'),
      ),
      (
        key: 'nachrichten',
        titel: L10n.t(context, 'del.nachrichten'),
        text: L10n.t(context, 'del.nachrichtenSub'),
      ),
      (
        key: 'geraete',
        titel: L10n.t(context, 'del.geraete'),
        text: L10n.t(context, 'del.geraeteSub'),
      ),
      (
        key: 'stimmung',
        titel: L10n.t(context, 'del.stimmung'),
        text: L10n.t(context, 'del.stimmungSub'),
      ),
      (
        key: 'meldungen',
        titel: L10n.t(context, 'del.meldungen'),
        text: L10n.t(context, 'del.meldungenSub'),
      ),
      (
        key: 'transit',
        titel: L10n.t(context, 'del.transit'),
        text: L10n.t(context, 'del.transitSub'),
      ),
      (
        key: 'elternaufsicht',
        titel: L10n.t(context, 'del.elternaufsicht'),
        text: L10n.t(context, 'del.elternaufsichtSub'),
      ),
    ];
  }

  Future<void> _loeschen(List<String> kategorien) async {
    if (kategorien.isEmpty) return;

    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'del.confirmTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.t(ctx, 'del.confirmText')),
            const SizedBox(height: 12),
            for (final k in kategorien)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '· ${_titelVon(k)}',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              L10n.t(ctx, 'del.irreversible'),
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: Theme.of(ctx).colorScheme.error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'del.deleteBtn')),
          ),
        ],
      ),
    );
    if (bestaetigt != true || !mounted) return;

    setState(() => _arbeitet = true);
    final result = await ref
        .read(dataDeletionServiceProvider)
        .deleteCategories(kategorien);
    if (!mounted) return;
    setState(() {
      _arbeitet = false;
      if (result.ok) _gewaehlt.removeAll(kategorien);
    });

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          result.ok
              ? L10n.t(ctx, 'del.doneTitle')
              : L10n.t(ctx, 'del.partialTitle'),
        ),
        content: Text(
          result.ok
              ? L10n.t(ctx, 'del.doneText')
              : L10n.t(ctx, 'del.partialText'),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'common.ok')),
          ),
        ],
      ),
    );
  }

  String _titelVon(String key) {
    for (final k in _kategorien()) {
      if (k.key == key) return k.titel;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kategorien = _kategorien();

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'del.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              L10n.t(context, 'del.intro'),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 8),
            Text(
              L10n.t(context, 'del.intro2'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final k in kategorien)
                      CheckboxListTile(
                        value: _gewaehlt.contains(k.key),
                        title: Text(k.titel),
                        subtitle: Text(
                          k.text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.35,
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _gewaehlt.add(k.key);
                          } else {
                            _gewaehlt.remove(k.key);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: L10n.t(context, 'del.deleteBtn'),
              loading: _arbeitet,
              onPressed: _arbeitet || _gewaehlt.isEmpty
                  ? null
                  : () => _loeschen(_gewaehlt.toList()),
            ),
            const SizedBox(height: 32),
            // Alles loeschen: das Konto bleibt, der Inhalt nicht.
            Text(
              L10n.t(context, 'del.allTitle'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              L10n.t(context, 'del.allText'),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _arbeitet ? null : () => _loeschen(['alles']),
              child: Text(L10n.t(context, 'del.allBtn')),
            ),
            const SizedBox(height: 24),
            Text(
              L10n.t(context, 'del.accountHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              // Die vollstaendige Kontoloeschung liegt im
              // Datenschutz-Screen - dort mit MFA-Step-up.
              onPressed: () => context.push(AppRoutes.privacy),
              child: Text(L10n.t(context, 'del.accountLink')),
            ),
          ],
        ),
      ),
    );
  }
}
