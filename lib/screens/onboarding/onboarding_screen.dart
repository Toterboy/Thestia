import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/widgets/birthday_style.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/interview_bubble.dart';

/// Onboarding als INTERVIEW (v0.9.0): Wisp stellt Fragen - eine pro
/// Screen, in warmem Ton, alles immer überspringbar. KEINE neuen
/// Datenpunkte und bewusst KEIN Belohnungs-Mechanismus (spielerisch
/// heißt hier: Gesprächston statt Formular, kein Dopamin-Loop).
///
/// Die Daten-Logik (Speichern/Server-Sync) ist identisch zur Vorgänger-
/// version; nur die Präsentation ist das Interview.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  final _songCtrl = TextEditingController();
  final _bandCtrl = TextEditingController();

  final Set<String> _musicGenres = {};

  String _birthdayStyle = 'classic';

  // 7 Seiten: Bio, Interessen und Gewohnheiten fragt die Einrichtung
  // ("Einstellungen & Privatsphäre") bereits vorher ab - hier kämen
  // sie doppelt UND würden beim Abschluss sogar mit leeren Werten
  // überschrieben. Übrig: Begrüßung, Foto-Hinweis, Musik,
  // Geburtstags-Stil, Abschluss.
  static const int _pageCount = 7;

  @override
  void initState() {
    super.initState();
    // Vorbelegen, falls das Interview erneut geöffnet wird (kein
    // Überschreiben mit leeren Werten).
    final profile = ref.read(profileProvider);
    _musicGenres.addAll(profile.musicLiked);
    if (profile.favoriteSong != null) {
      _songCtrl.text = profile.favoriteSong!;
    }
    if (profile.favoriteBand != null) {
      _bandCtrl.text = profile.favoriteBand!;
    }
    _birthdayStyle = BirthdayStyle.orDefault(profile.birthdayStyle);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _songCtrl.dispose();
    _bandCtrl.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (_pageController.page?.round() == 0) return true;
    _prev();
    return false;
  }

  void _prev() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _finish() async {
    final profile = ref.read(profileProvider);
    final song = _songCtrl.text.trim();
    final band = _bandCtrl.text.trim();
    // NUR Interview-eigene Felder schreiben: Bio, Interessen und
    // Gewohnheiten kommen aus "Einstellungen & Privatsphäre" und
    // dürfen hier NICHT mit leeren Werten überschrieben werden.
    await ref
        .read(profileProvider.notifier)
        .update(
          name: profile.name,
          musicLiked: _musicGenres.toList(),
          favoriteSong: song.isEmpty ? null : song,
          favoriteBand: band.isEmpty ? null : band,
          birthdayStyle: _birthdayStyle,
        );
    await _persistMusicToServer();
    await _persistSongToServer(song);
    await _persistBandToServer(band);
    await _persistBirthdayStyleToServer();
    await ref.read(settingsProvider.notifier).completeOnboarding();
    if (mounted) context.go(AppRoutes.home);
  }

  /// Schreibt die Musik-Genres serverseitig (Migration 074, Matching).
  Future<void> _persistMusicToServer() async {
    if (!SupabaseService.isInitialized || _musicGenres.isEmpty) return;
    try {
      await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
        'music_liked': _musicGenres.toList(),
      });
    } catch (e) {
      debugPrint('[Onboarding] Musik-Server-Sync fehlgeschlagen: $e');
    }
  }

  /// Schreibt Lieblingssong/Band serverseitig (Migration 092).
  Future<void> _persistSongToServer(String song) async {
    if (!SupabaseService.isInitialized || song.isEmpty) return;
    try {
      await SupabaseDatabaseService(
        SupabaseService.client,
      ).updateOwnProfile({'favorite_song': song});
    } catch (e) {
      debugPrint('[Onboarding] Song-Server-Sync fehlgeschlagen: $e');
    }
  }

  /// Schreibt den Lieblingsband serverseitig (Migration 119).
  Future<void> _persistBandToServer(String band) async {
    if (!SupabaseService.isInitialized || band.isEmpty) return;
    try {
      await SupabaseDatabaseService(
        SupabaseService.client,
      ).updateOwnProfile({'favorite_band': band});
    } catch (e) {
      debugPrint('[Onboarding] Band-Server-Sync fehlgeschlagen: $e');
    }
  }

  /// Schreibt den Geburtstags-Stil serverseitig (Migration 115).
  Future<void> _persistBirthdayStyleToServer() async {
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseDatabaseService(
        SupabaseService.client,
      ).updateOwnProfile({'birthday_style': _birthdayStyle});
    } catch (e) {
      debugPrint('[Onboarding] Stil-Server-Sync fehlgeschlagen: $e');
    }
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        if (await _onWillPop()) {
          if (mounted) router.go(AppRoutes.home);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.t(context, 'onboarding.appbarTitle')),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: L10n.t(context, 'common.back'),
            onPressed: () async {
              final router = GoRouter.of(context);
              if (await _onWillPop()) {
                if (mounted) router.go(AppRoutes.home);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: _finish,
              child: Text(L10n.t(context, 'onboarding.skipAll')),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Fortschritts-Dots (dezent, kein Belohnungs-Mechanismus).
              _ProgressDots(controller: _pageController, count: _pageCount),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pageCount,
                  itemBuilder: (context, index) {
                    switch (index) {
                      case 0:
                        return const _InfoPage(
                          icon: Icons.waving_hand,
                          titleKey: 'onboarding.hello.title',
                          bodyKey: 'onboarding.hello.body',
                        );
                      case 1:
                        return const _InfoPage(
                          icon: Icons.visibility_off,
                          titleKey: 'onboarding.blind.title',
                          bodyKey: 'onboarding.blind.body',
                        );
                      case 2:
                        return const _InfoPage(
                          icon: Icons.favorite,
                          titleKey: 'onboarding.connections.title',
                          bodyKey: 'onboarding.connections.body',
                        );
                      case 3:
                        return _QuestionStep(
                          questionKey: 'onboarding.q.photo',
                          onSkip: _next,
                          onContinue: _next,
                          onBack: _prev,
                          child: const Center(
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 48,
                                  child: Icon(Icons.person, size: 48),
                                ),
                                SizedBox(height: 8),
                                _PhotoLaterHint(),
                              ],
                            ),
                          ),
                        );
                      case 4:
                        return _QuestionStep(
                          questionKey: 'onboarding.q.music',
                          onSkip: _next,
                          onContinue: _next,
                          onBack: _prev,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                L10n.t(context,
                                    'onboarding.q.musicGenres'),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: AppConstants.presetMusicGenres
                                    .map(
                                      (g) => FilterChip(
                                        label: Text(g),
                                        selected:
                                            _musicGenres.contains(g),
                                        onSelected: (sel) {
                                          setState(() {
                                            if (sel) {
                                              _musicGenres.add(g);
                                            } else {
                                              _musicGenres.remove(g);
                                            }
                                          });
                                        },
                                      ),
                                    )
                                    .toList(),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _songCtrl,
                                maxLines: 1,
                                maxLength: 120,
                                keyboardType: TextInputType.text,
                                decoration: InputDecoration(
                                  hintText: L10n.t(
                                    context,
                                    'onboarding.q.musicHint',
                                  ),
                                  counterText: '',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _bandCtrl,
                                maxLines: 1,
                                maxLength: 120,
                                keyboardType: TextInputType.text,
                                decoration: InputDecoration(
                                  hintText: L10n.t(
                                    context,
                                    'onboarding.q.bandHint',
                                  ),
                                  counterText: '',
                                ),
                              ),
                            ],
                          ),
                        );
                      case 5:
                        return _QuestionStep(
                          questionKey: 'onboarding.q.birthday',
                          onSkip: _next,
                          onContinue: _next,
                          onBack: _prev,
                          child: BirthdayStylePicker(
                            selected: _birthdayStyle,
                            onSelected: (style) =>
                                setState(() => _birthdayStyle = style),
                          ),
                        );
                      case 6:
                        return const _InfoPage(
                          icon: Icons.celebration,
                          titleKey: 'onboarding.done.title',
                          bodyKey: 'onboarding.done.body',
                        );
                      default:
                        return const SizedBox.shrink();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Später hochladen"-Hinweis (eigenes Widget, damit const-fähig).
class _PhotoLaterHint extends StatelessWidget {
  const _PhotoLaterHint();

  @override
  Widget build(BuildContext context) {
    return Text(L10n.t(context, 'onboarding.photoLater'));
  }
}

/// Fortschritts-Dots: dezent, ohne Belohnungs-Animation.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.controller, required this.count});

  final PageController controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients ? (controller.page ?? 0) : 0;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                Container(
                  width: i == page.round() ? 20 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == page.round()
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlpha(70),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// statische Informationsseite (Blind Mode / Privatsphäre) - im Interview-
/// Ton, als Wisp-Bubble statt_INFO-Karte.
class _InfoPage extends StatelessWidget {
  const _InfoPage({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 54,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            L10n.t(context, titleKey),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            L10n.t(context, bodyKey),
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Überspringbarer Interview-Frage-Schritt: Wisp-Bubble + Antwortbereich.
///
/// Tastatur-Disziplin (Nutzer-Regel: "man sieht nicht, was man tippt"):
/// Sobald ein Feld im Antwortbereich den Fokus bekommt, scrollt die
/// Ansicht das fokussierte Feld über die Tastatur ([FocusableAction]-
/// frei, via [Scrollable.ensureVisible]) und hält Tastatur-Platz frei.
class _QuestionStep extends StatefulWidget {
  const _QuestionStep({
    required this.questionKey,
    required this.child,
    required this.onSkip,
    required this.onContinue,
    this.onBack,
  });

  final String questionKey;
  final Widget child;
  final VoidCallback onSkip;
  final VoidCallback onContinue;
  final VoidCallback? onBack;

  @override
  State<_QuestionStep> createState() => _QuestionStepState();
}

class _QuestionStepState extends State<_QuestionStep> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          InterviewBubble(text: L10n.t(context, widget.questionKey)),
          const SizedBox(height: 20),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                // Platz für die Tastatur: Der Inhalt bleibt so über dem
                // Keyboard scrollbar, statt dahinter zu verschwinden.
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  children: [
                    // Sobald ein Eingabefeld Fokus bekommt (Tastatur geht
                    // auf), das Feld sichtbar scrollen - sonst tippt man
                    // blind unterhalb der Tastatur.
                    Focus(
                      onFocusChange: (hasFocus) {
                        if (!hasFocus || !mounted) return;
                        Future.delayed(const Duration(milliseconds: 350), () {
                          if (!mounted) return;
                          final focused =
                              FocusManager.instance.primaryFocus?.context;
                          if (focused != null && focused.mounted) {
                            Scrollable.ensureVisible(
                              focused,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                              alignment: 0.25,
                            );
                          }
                        });
                      },
                      child: widget.child,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: widget.onSkip,
                      child: Text(L10n.t(context, 'onboarding.fillLater')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (widget.onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: Text(L10n.t(context, 'common.back')),
              ),
            ),
          PrimaryButton(
            label: L10n.t(context, 'onboarding.next'),
            onPressed: widget.onContinue,
          ),
        ],
      ),
    );
  }
}
