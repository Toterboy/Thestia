import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/local_storage.dart';

/// Ausführliche Fassung der Sicherheits-Aufklärung (statische Seite).
///
/// Dieselbe Adresse steht in der Datenschutzerklärung und in der
/// Rewrite-Liste von Netlify (/dating-sicherheit -> dating-sicherheit.html).
const String kDatingSafetyUrl = 'https://auth.thestia.de/dating-sicherheit';

/// Schlüssel des lokalen Fortschritts.
///
/// Bewusst NUR der Fortschritt (Seite/Antworten/Startzeit), nicht die
/// Abschluss-Markierung: die liegt als geräteübergreifendes Setup-Flag in
/// [AppSettings.datingSafetyEducationCompleted]. So kann ein kaputter
/// Fortschritt neu beginnen, ohne den Abschluss zu verlieren.
const String _progressKey = 'dating_safety_education_v1';

/// Version des Fortschrittsformats. Ein unbekannter Wert gilt als
/// "nicht wiederherstellbar" und startet die Aufklärung von vorn.
const int _progressVersion = 1;

/// Höchstdauer der Aufklärung (Nutzerwunsch: "max. 5 Minuten").
const Duration _maxEducationDuration = Duration(minutes: 5);

enum _SafetyStep { ack, usedBefore, awareOfDangers, education }

/// Lokal gespeicherter Fortschritt.
///
/// [startedAtMs] ist der Start der Aufklärungsseiten. Beim Wiederöffnen
/// läuft die Uhr weiter, damit die 5-Minuten-Grenze auch nach einem
/// Neustart gilt.
class _SafetyProgress {
  const _SafetyProgress({
    this.step = _SafetyStep.ack,
    this.usedBefore,
    this.awareOfDangers,
    this.page = 0,
    this.startedAtMs,
  });

  final _SafetyStep step;
  final bool? usedBefore;
  final bool? awareOfDangers;
  final int page;
  final int? startedAtMs;

  _SafetyProgress copyWith({
    _SafetyStep? step,
    bool? usedBefore,
    bool? awareOfDangers,
    bool clearAwareOfDangers = false,
    int? page,
    int? startedAtMs,
  }) => _SafetyProgress(
    step: step ?? this.step,
    usedBefore: usedBefore ?? this.usedBefore,
    awareOfDangers: clearAwareOfDangers
        ? null
        : (awareOfDangers ?? this.awareOfDangers),
    page: page ?? this.page,
    startedAtMs: startedAtMs ?? this.startedAtMs,
  );

  Map<String, dynamic> toJson() => {
    'version': _progressVersion,
    'step': step.name,
    'usedBefore': usedBefore,
    'awareOfDangers': awareOfDangers,
    'page': page,
    'startedAtMs': startedAtMs,
  };

  /// Liest den Fortschritt. Wirft bei unbekannten/ungültigen Daten -
  /// der Aufrufer startet dann von vorn.
  factory _SafetyProgress.fromJson(Map<String, dynamic> json) {
    if (json['version'] != _progressVersion) {
      throw const FormatException('Unbekannte Version');
    }
    final stepName = json['step'];
    final step = _SafetyStep.values.firstWhere(
      (s) => s.name == stepName,
      orElse: () => throw const FormatException('Unbekannter Schritt'),
    );
    final page = json['page'] is int ? json['page'] as int : 0;
    final started = json['startedAtMs'] is int
        ? json['startedAtMs'] as int
        : null;
    if (page < 0 || page >= _educationPageCount) {
      throw const FormatException('Ungültige Seite');
    }
    if (step == _SafetyStep.education && started == null) {
      throw const FormatException('Startzeit fehlt');
    }
    return _SafetyProgress(
      step: step,
      usedBefore: json['usedBefore'] as bool?,
      awareOfDangers: json['awareOfDangers'] as bool?,
      page: page,
      startedAtMs: started,
    );
  }
}

const int _educationPageCount = 5;

/// Sicherheits-Aufklärung nach der E-Mail-Bestätigung und VOR dem Setup.
///
/// Ablauf:
///  1. Bestätigungsseite (kein Weg daran vorbei, aber ohne Häkchen-Zwang).
///  2. Frage: schon einmal eine Dating-App benutzt?
///     - Nein -> Aufklärung.
///     - Ja -> Frage: Gefahren bewusst?
///       - Ja -> weiter zum Setup.
///       - Nein -> Aufklärung.
///  3. Aufklärung: fünf horizontal wischbare Seiten, höchstens 5 Minuten.
///
/// Der Fortschritt liegt lokal und wird bei jedem Schritt gespeichert.
/// Lässt er sich nicht wiederherstellen, beginnt der Ablauf von vorn.
class DatingSafetyEducationScreen extends ConsumerStatefulWidget {
  const DatingSafetyEducationScreen({super.key});

  @override
  ConsumerState<DatingSafetyEducationScreen> createState() =>
      _DatingSafetyEducationScreenState();
}

class _DatingSafetyEducationScreenState
    extends ConsumerState<DatingSafetyEducationScreen> {
  _SafetyProgress _progress = const _SafetyProgress();
  bool _restored = false;
  bool _finishing = false;
  Timer? _ticker;
  Duration _remaining = _maxEducationDuration;

  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final raw = await ref.read(localStorageProvider).getString(_progressKey);
      if (raw == null || raw.isEmpty) {
        if (mounted) setState(() => _restored = true);
        return;
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final restored = _SafetyProgress.fromJson(map);
      if (!mounted) return;
      setState(() {
        _progress = restored;
        _restored = true;
      });
      if (restored.step == _SafetyStep.education) {
        _beginEducationClock(restored);
      }
    } catch (_) {
      // Wiederherstellung fehlgeschlagen (kaputter/alter Eintrag,
      // Storage-Fehler): von vorn beginnen.
      try {
        await ref.read(localStorageProvider).remove(_progressKey);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _progress = const _SafetyProgress();
        _restored = true;
      });
    }
  }

  Future<void> _save() async {
    try {
      await ref
          .read(localStorageProvider)
          .saveString(_progressKey, jsonEncode(_progress.toJson()));
    } catch (_) {
      // Speichern ist Komfort, kein Gate: der Abschluss wird am Ende
      // separat und dauerhaft gesetzt.
    }
  }

  void _setStep(_SafetyStep step) {
    setState(() => _progress = _progress.copyWith(step: step));
    unawaited(_save());
  }

  void _answerUsedBefore(bool value) {
    setState(() {
      _progress = _progress.copyWith(
        usedBefore: value,
        clearAwareOfDangers: !value,
      );
    });
    unawaited(_save());
    if (value) {
      _setStep(_SafetyStep.awareOfDangers);
    } else {
      _startEducation();
    }
  }

  void _answerAware(bool value) {
    setState(() {
      _progress = _progress.copyWith(awareOfDangers: value);
    });
    unawaited(_save());
    if (value) {
      unawaited(_finish());
    } else {
      _startEducation();
    }
  }

  void _startEducation() {
    final started =
        _progress.startedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _progress = _progress.copyWith(
        step: _SafetyStep.education,
        page: 0,
        startedAtMs: started,
      );
    });
    unawaited(_save());
    _beginEducationClock(_progress);
  }

  /// Startet bzw. setzt die 5-Minuten-Uhr fort.
  ///
  /// Die Uhr läuft ab [startedAtMs] weiter - auch nach einem Neustart.
  /// Ist die Zeit bereits abgelaufen, wird sofort abgeschlossen.
  void _beginEducationClock(_SafetyProgress progress) {
    _ticker?.cancel();
    final started = progress.startedAtMs;
    if (started == null) return;
    final elapsed = DateTime.now().millisecondsSinceEpoch - started;
    final left = _maxEducationDuration - Duration(milliseconds: elapsed);
    // Eine zurückgestellte Geräteuhr darf die Aufklärung nicht über die
    // zugesagten fünf Minuten hinaus verlängern.
    _remaining = left.isNegative
        ? Duration.zero
        : (left > _maxEducationDuration ? _maxEducationDuration : left);
    if (_remaining == Duration.zero) {
      unawaited(_finish());
      return;
    }
    setState(() {});
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final rest =
          _maxEducationDuration -
          Duration(
            milliseconds: DateTime.now().millisecondsSinceEpoch - started,
          );
      if (rest.isNegative || rest == Duration.zero) {
        timer.cancel();
        setState(() => _remaining = Duration.zero);
        unawaited(_finish());
        return;
      }
      setState(() => _remaining = rest);
    });
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _ticker?.cancel();
    await ref.read(settingsProvider.notifier).completeDatingSafetyEducation();
    try {
      await ref.read(localStorageProvider).remove(_progressKey);
    } catch (_) {}
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'safetyOnboarding.title')),
        automaticallyImplyLeading: false,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.35),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: !_restored
              ? const Center(child: CircularProgressIndicator())
              : switch (_progress.step) {
                  _SafetyStep.ack => _buildAck(context),
                  _SafetyStep.usedBefore => _buildQuestion(
                    context,
                    titleKey: 'safetyOnboarding.q1Title',
                    bodyKey: 'safetyOnboarding.q1Body',
                    onAnswer: _answerUsedBefore,
                    selected: _progress.usedBefore,
                    onBack: null,
                  ),
                  _SafetyStep.awareOfDangers => _buildQuestion(
                    context,
                    titleKey: 'safetyOnboarding.q2Title',
                    bodyKey: 'safetyOnboarding.q2Body',
                    onAnswer: _answerAware,
                    selected: _progress.awareOfDangers,
                    onBack: () => _setStep(_SafetyStep.usedBefore),
                  ),
                  _SafetyStep.education => _buildEducation(context),
                },
        ),
      ),
    );
  }

  /// Bestaetigungsseite: Der Text scrollt, der Knopf bleibt unten stehen.
  ///
  /// NUTZERWUNSCH (31.10.2026, gefunden beim Rendern): Der Knopf lag auf
  /// einem 390x844-Telefon 108 Pixel UNTERhalb des Bildschirmrands - man
  /// musste scrollen, um weiterzukommen. Bei grosser Schrift (die App
  /// erlaubt bis 3,2x) waere das noch schlimmer. Deshalb liegt die
  /// Hauptaktion fest am unteren Rand und nur der Text scrollt.
  /// Bestaetigungsseite: Der Text scrollt, der Knopf bleibt unten stehen.
  ///
  /// NUTZERWUNSCH (31.10.2026, gefunden beim Rendern): Der Knopf lag auf
  /// einem 390x844-Telefon 108 Pixel UNTERhalb des Bildschirmrands - man
  /// musste scrollen, um weiterzukommen. Bei grosser Schrift (die App
  /// erlaubt bis 3,2x) waere das noch schlimmer. Deshalb liegt die
  /// Hauptaktion fest am unteren Rand und nur der Text scrollt.
  ///
  /// Der Zeit-Hinweis gehoert in den scrollenden Teil: Bei 3,2x Schrift
  /// waere er rund 840 Pixel hoch und wuerde den festen Bereich
  /// sprengen (RenderFlex-Overflow). Fest unten steht nur der Knopf.
  Widget _buildAck(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _CircleIcon(icon: Icons.shield_outlined),
                        const SizedBox(height: 20),
                        Text(
                          L10n.t(context, 'safetyOnboarding.ackTitle'),
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          L10n.t(context, 'safetyOnboarding.ackBody'),
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        _Bullet(text: L10n.t(context, 'safetyOnboarding.ack1')),
                        _Bullet(text: L10n.t(context, 'safetyOnboarding.ack2')),
                        _Bullet(text: L10n.t(context, 'safetyOnboarding.ack3')),
                        const SizedBox(height: 16),
                        Text(
                          L10n.t(context, 'safetyOnboarding.timeHint'),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _setStep(_SafetyStep.usedBefore),
                child: Text(
                  L10n.t(context, 'safetyOnboarding.ackButton'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
  Widget _buildQuestion(
    BuildContext context, {
    required String titleKey,
    required String bodyKey,
    required ValueChanged<bool> onAnswer,
    required bool? selected,
    required VoidCallback? onBack,
  }) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (onBack != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: onBack,
                              icon: const Icon(Icons.arrow_back, size: 18),
                              label: Text(
                                L10n.t(context, 'safetyOnboarding.back'),
                              ),
                            ),
                          ),
                        const _CircleIcon(icon: Icons.psychology_alt_outlined),
                        const SizedBox(height: 18),
                        Text(
                          L10n.t(context, titleKey),
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          L10n.t(context, bodyKey),
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onAnswer(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                        color: selected == false
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(L10n.t(context, 'safetyOnboarding.no')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => onAnswer(true),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(L10n.t(context, 'safetyOnboarding.yes')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEducation(BuildContext context) {
    final controller = _pageController ??= PageController(
      initialPage: _progress.page.clamp(0, _educationPageCount - 1),
    );
    final minutes = (_remaining.inSeconds / 60).ceil();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  L10n.t(context, 'safetyOnboarding.educationTitle'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, size: 15),
                    const SizedBox(width: 5),
                    Text(
                      L10n.tf(context, 'safetyOnboarding.timer', {
                        'min': '$minutes',
                      }),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            L10n.tf(context, 'safetyOnboarding.progress', {
              'current': '${_progress.page + 1}',
              'total': '$_educationPageCount',
            }),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: PageView.builder(
            controller: controller,
            itemCount: _educationPageCount,
            onPageChanged: (page) {
              setState(() => _progress = _progress.copyWith(page: page));
              unawaited(_save());
            },
            itemBuilder: (context, index) => _EducationPage(index: index),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(
            children: [
              for (var i = 0; i < _educationPageCount; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 6),
                  width: i == _progress.page ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _progress.page
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              const Spacer(),
              if (_progress.page > 0)
                TextButton(
                  onPressed: () => controller.previousPage(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                  ),
                  child: Text(L10n.t(context, 'safetyOnboarding.back')),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _progress.page < _educationPageCount - 1
                    ? () => controller.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      )
                    : () => unawaited(_finish()),
                child: Text(
                  L10n.t(
                    context,
                    _progress.page < _educationPageCount - 1
                        ? 'safetyOnboarding.next'
                        : 'safetyOnboarding.finish',
                  ),
                ),
              ),
            ],
          ),
        ),
        // Ausführliche Fassung zum Nachlesen und Weitergeben.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Center(
            child: TextButton.icon(
              onPressed: () => unawaited(_openWebsite()),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(L10n.t(context, 'safetyOnboarding.moreInfo')),
            ),
          ),
        ),
      ],
    );
  }

  /// Öffnet die öffentliche Seite "Sicher daten".
  ///
  /// Die App übergibt dabei nichts - es wird nur die Seite geöffnet
  /// (url_launcher, externer Browser). Keine Nutzungsdaten, keine
  /// Parameter.
  Future<void> _openWebsite() async {
    try {
      await launchUrl(
        Uri.parse(kDatingSafetyUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Kein Browser oder kein Netz: die Aufklärung läuft ohnehin
      // weiter, der Link ist nur ein Extra.
    }
  }
}

class _EducationPage extends StatelessWidget {
  const _EducationPage({required this.index});

  final int index;

  static const _icons = [
    Icons.person_search_outlined,
    Icons.lock_outline,
    Icons.location_on_outlined,
    Icons.favorite_border,
    Icons.support_agent,
  ];

  @override
  Widget build(BuildContext context) {
    final n = index + 1;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CircleIcon(icon: _icons[index], small: true),
              const SizedBox(height: 16),
              Text(
                L10n.t(context, 'safetyOnboarding.edu${n}Title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                L10n.t(context, 'safetyOnboarding.edu${n}Body'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 14),
              Text(
                L10n.t(context, 'safetyOnboarding.edu${n}Hint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, this.small = false});

  final IconData icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = small ? 46.0 : 72.0;
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primaryContainer,
        ),
        child: Icon(
          icon,
          size: small ? 24 : 36,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(
              Icons.check_circle_outline,
              size: 18,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
