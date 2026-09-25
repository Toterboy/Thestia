import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/services/whats_new_service.dart';
import 'package:thestia/widgets/birthday_style.dart';

/// "Neu in dieser Version"-Screen (NUTZERWUNSCH): Bei einem App-Update
/// bekommen bereits registrierte Nutzer einmalig die Änderungs-
/// Kurzfassung - plus Nachfragen zu NEUEN Angaben (aktuell: Geburtstags-
/// Stil, Migration 115). Der Router leitet hier einmalig hin (Gate im
/// app_router), dieser Screen navigiert sich am Ende zu Home ab.
///
/// Anti-Problem-Design:
///  - Der Build wird VOR der Anzeige markiert (Kill-Schutz, siehe
///    WhatsNewService) - der Screen ist also optional, nie Zwang.
///  - Nur-Upgrade-Speicherung: Geburtstags-Stil wird nur überschrieben,
///    wenn der Nutzer aktiv wählt (Vorauswahl = aktueller Stand).
///  - Server-Sync best effort (updateOwnProfile); offline bleibt die
///    lokale Wahl erhalten und der Auto-Sync holt nach.
class WhatsNewScreen extends ConsumerStatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  ConsumerState<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends ConsumerState<WhatsNewScreen> {
  int _currentBuild = 0;
  List<String> _keys = const [];
  String? _pickedStyle;
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final build = await WhatsNewService.currentBuild();
    final storage = ref.read(localStorageProvider);
    final shown = await WhatsNewService.shownBuild(storage);
    if (!mounted) return;
    setState(() {
      _currentBuild = build;
      _keys = WhatsNewService.keysFor(
          currentBuild: build, shownBuild: shown);
      _loaded = true;
    });
  }

  Future<void> _finish() async {
    // Geburtstags-Stil persistieren (lokal immer; Server best effort).
    final currentStyle = ref.read(profileProvider).birthdayStyle;
    await ref.read(profileProvider.notifier).update(
          birthdayStyle: _pickedStyle ?? currentStyle,
        );
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseDatabaseService(SupabaseService.client)
            .updateOwnProfile({
          'birthday_style': _pickedStyle ?? currentStyle,
        });
      } catch (_) {
        // Fail-open: Lokal gespeichert, Auto-Sync holt es nach.
      }
    }
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.t(context, 'whatsnew.title'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'whatsnew.title')),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final key in _keys) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          L10n.t(context, key),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // Neue Angaben (z. B. Geburtstags-Stil) direkt hier abfragen.
              if (WhatsNewService.hasNewInputs(_currentBuild)) ...[
                const SizedBox(height: 12),
                Text(
                  L10n.t(context, 'whatsnew.inputsTitle'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                BirthdayStylePicker(
                  selected: _pickedStyle ??
                      BirthdayStyle.orDefault(profile.birthdayStyle),
                  onSelected: (style) =>
                      setState(() => _pickedStyle = style),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.celebration_outlined),
                label: Text(L10n.t(context, 'whatsnew.cta')),
                onPressed: _finish,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
