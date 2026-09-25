import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/widgets/app_logo.dart';

/// Willkommens-/Erklärungsscreen VOR dem Anmelde-Screen.
///
/// Begrüßt den Nutzer, erklärt das Grundprinzip (Persönlichkeit vor
/// Aussehen, Blind Mode, Matching, Ende-zu-Ende-Verschlüsselung) und
/// führt mit Swipe-Seiten durch die wichtigsten Funktionen.
/// Wird nur beim allerersten App-Start gezeigt
/// (Flag [AppSettings.introSeen]) und ist überspringbar.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  /// Future, das abschließt, sobald das Logo im Bild-Cache liegt.
  /// Erst danach werden Logo UND Text gleichzeitig sichtbar.
  late Future<void> _logoReady;

  @override
  void initState() {
    super.initState();
    // Einführung gilt ab dem Moment als gesehen, in dem sie ANGEZEIGT wird –
    // nicht erst beim Verlassen. So erscheint sie garantiert nur beim
    // allerersten App-Start: Auch wenn der Nutzer die App mitten auf der
    // Seite beendet oder im Anschluss der Router-Redirect greift (z. B.
    // nach dem CAPTCHA bei der Registrierung), wird der Welcome-Screen
    // nie wieder angezeigt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(settingsProvider.notifier).markIntroSeen();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Wichtig: exakt DIESELBE Datei precachen, die AppLogo auch anzeigt
    // (assets/images/thestia_icon_base.png) - sonst erscheinen Logo und
    // Text nicht gleichzeitig.
    final imageProvider =
        const AssetImage('assets/images/thestia_icon_base.png');
    _logoReady = precacheImage(imageProvider, context);
  }

  /// Seiten lokalisiert aufbauen (kein static const: Texte kommen aus L10n).
  List<_PageData> _pages(BuildContext context) => [
        _PageData(
          title: L10n.t(context, 'welcome.t1'),
          body: L10n.t(context, 'welcome.b1'),
        ),
        _PageData(
          title: L10n.t(context, 'welcome.t2'),
          body: L10n.t(context, 'welcome.b2'),
        ),
        _PageData(
          title: L10n.t(context, 'welcome.t3'),
          body: L10n.t(context, 'welcome.b3'),
        ),
      ];

  Future<void> _leave() async {
    // introSeen wird bereits beim Anzeigen gesetzt (initState) – hier nur
    // weiter zur Anmeldung navigieren.
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildContent(bool isLast) {
    final pages = _pages(context);
    return Column(
      children: [
        Expanded(
          // KEIN Scrollbar-Wrapper um das PageView!
          // Der Scrollbar zeichnet eine zusätzliche Linie oberhalb der
          // Punkte-Indikatoren, die nicht gewünscht ist. Ein PageView
          // braucht keinen Scrollbar, da es intern horizontal scrollt.
          child: PageView.builder(
            controller: _pageController,
            itemCount: pages.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final page = pages[index];
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppLogo(size: 120),
                    const SizedBox(height: 32),
                    Text(
                      page.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      page.body,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pages.length, (i) {
            final active = i == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 24 : 10,
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            );
          }),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              if (_currentPage > 0)
                TextButton(
                  onPressed: () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  child: Text(L10n.t(context, 'common.back')),
                )
              else
                const SizedBox.shrink(),
              const Spacer(),
              FilledButton(
                onPressed: isLast
                    ? _leave
                    : () => _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        ),
                child: Text(isLast
                    ? L10n.t(context, 'welcome.start')
                    : L10n.t(context, 'common.continue')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _pages(context).length - 1;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _leave,
            child: Text(L10n.t(context, 'common.skip')),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _logoReady,
          builder: (context, snapshot) {
            // Solange das Logo noch nicht im Cache ist, KEINEN Inhalt
            // anzeigen – so erscheinen Logo und Text immer gleichzeitig.
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            return _buildContent(isLast);
          },
        ),
      ),
    );
  }
}

class _PageData {
  const _PageData({
    required this.title,
    required this.body,
  });
  final String title;
  final String body;
}
