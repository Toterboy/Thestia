import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/find_your_match_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/widgets/intro_audio_player.dart';
import 'package:wisp/widgets/intro_editor.dart';
import 'package:wisp/l10n/app_strings.dart';

/// "Find your Match": Kennenlernen über die Vorstellung (Text oder Audio)
/// statt über Fotos.
///
/// Ablauf: Eigene Vorstellung hinterlegen (Text + Audio sind Pflicht) ->
/// Vorstellung anhören/lesen -> Liken oder überspringen. Ein Like landet als
/// gerichteter Like bei der anderen Person (Reiter "Interessen" ->
/// "Erhaltene Likes"), die dort über Match oder Ablehnung entscheidet.
class FindYourMatchScreen extends ConsumerStatefulWidget {
  const FindYourMatchScreen({super.key});

  @override
  ConsumerState<FindYourMatchScreen> createState() =>
      _FindYourMatchScreenState();
}

class _FindYourMatchScreenState extends ConsumerState<FindYourMatchScreen> {
  bool _liking = false;
  bool _showIntroSetup = false;

  String _introText = '';
  String? _introAudioPath;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    _introText = profile.introText;
    _introAudioPath = profile.introAudioPath;
    _showIntroSetup = !IntroEditor.isValid(
      text: _introText,
      audioPath: _introAudioPath,
    );
    if (!_showIntroSetup) {
      Future.microtask(() => ref.read(findYourMatchProvider.notifier).load());
    }
  }

  Future<void> _saveIntro() async {
    if (!IntroEditor.isValid(text: _introText, audioPath: _introAudioPath)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'match.required')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await ref.read(profileProvider.notifier).update(
          introText: _introText.trim(),
          introAudioPath: _introAudioPath,
          clearIntroAudio: _introAudioPath == null,
        );
    try {
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'intro_text': _introText.trim(),
          'intro_audio_path': _introAudioPath,
        });
      }
    } catch (e) {
      debugPrint('[FindYourMatch] Intro-Server-Sync fehlgeschlagen: $e');
    }
    if (!mounted) return;
    setState(() => _showIntroSetup = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t(context, 'fym.introSaved')),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await ref.read(findYourMatchProvider.notifier).load();
  }

  Future<void> _like(UserProfile profile) async {
    if (_liking) return;
    setState(() => _liking = true);
    final ok = await ref.read(findYourMatchProvider.notifier).like();
    if (!mounted) return;
    setState(() => _liking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Du hast ${profile.name} geliked! 💚 '
                  'Bei gegenseitigem Interesse entsteht ein Funke.'
              : 'Like konnte nicht gespeichert werden.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref.watch(findYourMatchProvider);
    final notifier = ref.read(findYourMatchProvider.notifier);
    final current = candidates.isEmpty ? null : candidates.first;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'match.title')),
        actions: [
          if (!_showIntroSetup)
            IconButton(
              icon: const Icon(Icons.record_voice_over),
              tooltip: L10n.t(context, 'match.editIntro'),
              onPressed: () => setState(() => _showIntroSetup = true),
            ),
        ],
      ),
      body: _showIntroSetup
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.headphones, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    L10n.t(context, 'match.createFirst'),
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    L10n.t(context, 'match.createSub'),
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  IntroEditor(
                    initialText: _introText,
                    initialAudioPath: _introAudioPath,
                    onChanged: (text, audioPath) {
                      _introText = text;
                      _introAudioPath = audioPath;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saveIntro,
                    icon: const Icon(Icons.check),
                    label: Text(L10n.t(context, 'match.saveContinue')),
                  ),
                ],
              ),
            )
          : current == null
              ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.headphones,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      L10n.t(context, 'match.empty'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L10n.t(context, 'match.emptyTip'),
                      style: const TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: notifier.loading ? null : notifier.load,
                      icon: const Icon(Icons.refresh),
                      label: Text(L10n.t(context, 'match.reload')),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: const Icon(Icons.visibility_off,
                                      color: Colors.white),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                       Text(
                                         '${current.name}${current.age != null ? ', ${current.age}' : ''}',
                                         style: Theme.of(context)
                                             .textTheme
                                             .titleLarge
                                             ?.copyWith(
                                                 fontWeight: FontWeight.bold),
                                       ),
                                       // Verbindungs-Score (0-100):
                                       // Distanz + gemeinsame Interessen +
                                       // Musik (serverseitig berechnet).
                                       if (current.matchScore != null)
                                         Text(
                                           'Match: ${current.matchScore} %',
                                           style: Theme.of(context)
                                               .textTheme
                                               .labelLarge
                                               ?.copyWith(
                                                 color: Theme.of(context)
                                                     .colorScheme
                                                     .primary,
                                                 fontWeight: FontWeight.bold,
                                               ),
                                         ),
                                      if (current.city.isNotEmpty)
                                        Text(
                                          current.city,
                                          style: const TextStyle(
                                              color: Colors.grey),
                                        ),
                                      // Distanz in 5-km-Schritten (ohne
                                      // exakten Standort, serverseitig
                                      // berechnet).
                                      if (current.distanceKm > 0)
                                        Text(
                                          current.distanceLabel,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.photo_size_select_small,
                                    color: Colors.grey),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ohne Foto: Diese Person stellt sich mit '
                              'Worten vor. Hör rein oder lies ihre '
                              'Vorstellung.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            if (current.introAudioPath != null) ...[
                              IntroAudioPlayer(targetUserId: current.id),
                              const SizedBox(height: 12),
                            ],
                            if (current.introText.isNotEmpty) ...[
                              Text(
                                L10n.t(context, 'match.introTitle'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                current.introText,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge,
                              ),
                            ],
                            if (current.introAudioPath == null &&
                                current.introText.isEmpty)
                              Text(
                                L10n.t(context, 'match.noIntro'),
                                style: const TextStyle(color: Colors.grey),
                              ),
                            const SizedBox(height: 16),
                            if (current.interests.isNotEmpty) ...[
                              Text(
                                L10n.t(context, 'match.interestsTitle'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: current.interests
                                    .map((i) => Chip(
                                          label: Text(i),
                                          visualDensity: VisualDensity.compact,
                                        ))
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        iconSize: 32,
                        onPressed: _liking ? null : notifier.skip,
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFEF5350),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(72, 72),
                        ),
                      ),
                      const SizedBox(width: 32),
                      IconButton.filled(
                        iconSize: 32,
                        onPressed: _liking ? null : () => _like(current),
                        icon: _liking
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.favorite),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF82),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(72, 72),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
    );
  }
}
