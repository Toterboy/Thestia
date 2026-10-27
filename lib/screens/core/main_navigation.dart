import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/routing/route_restore.dart';
import 'package:thestia/screens/profile/profile_edit_screen.dart'
    show profileEditDirtyProvider, profileEditNavigateAfterSaveProvider;
import 'package:thestia/screens/swipe/transit_radar_screen.dart'
    show confirmTransitExit;
import 'package:thestia/services/local_storage.dart';

/// Sichert die Route für die Wiederherstellung nach Prozesstod (v0.9.1).
Future<void> _saveLastRoute(WidgetRef ref, String path) async {
  try {
    await ref.read(localStorageProvider).saveString(lastRoutePrefsKey, path);
  } catch (_) {}
}

/// Hält den aktuell aktiven Tab der Bottom-Navigation.
///
/// Wird zentral über Riverpod geführt, damit der visuell hervorgehobene
/// Tab IMMER exakt mit der angezeigten Seite übereinstimmt - unabhängig
/// davon, ob die Navigation über die Bottom-Navigation oder per go()/
/// push() erfolgt.
final currentNavIndexProvider = StateProvider<int>((ref) => 0);

/// Bottom-Navigation als Shell für die Hauptbereiche der App.
class MainNavigation extends ConsumerWidget {
  const MainNavigation({required this.child, super.key});

  final Widget child;

  static const _tabs = [
    _NavItem(AppRoutes.home, Icons.newspaper, 'nav.home'),
    _NavItem(AppRoutes.swipeModeSelection, Icons.favorite, 'nav.discover'),
    _NavItem(AppRoutes.interessen, Icons.people, 'nav.interests'),
    _NavItem(AppRoutes.profile, Icons.person, 'nav.profile'),
  ];

  static const _routes = [
    AppRoutes.home,
    AppRoutes.swipeModeSelection,
    AppRoutes.interessen,
    AppRoutes.profile,
  ];

  /// Unterrouten, die (unabhängig davon, von welchem Tab aus man sie
  /// erreicht hat) einem bestimmten Haupt-Tab zugeordnet werden. So bleibt
  /// der hervorgehobene Tab stets zum angezeigten Screen passend.
  ///
  /// Reihenfolge: [prefix] -> Tab-Index (siehe [_routes]).
  static const _subRoutePrefixes = <String, int>{
    '/chat/': 2,
    '/quiz/': 2,
    '/random-chat': 1,
    '/find-your-match': 1,
    '/dating-hour': 1,
    '/qr/': 1,
    // Transit Spark (vom Modi-Screen gestartet): vorher Fallback 0 =
    // "Aktuelles" war hervorgehoben statt "Entdecken" (Nutzer-Feedback).
    '/transit/radar': 1,
    '/profile/edit': 3,
    '/profile/': 2,
  };

  /// Routen, auf denen die Bottom-Navigation ausgeblendet wird.
  ///
  /// Chat (v0.9.0-Feedback): Im Chat sollen die Reiter unten nicht mehr
  /// sichtbar sein - das Gespraech hat den vollen Bildschirm. v0.9.1: ALLE
  /// Fenster innerhalb des Chats (Quiz, Eisbrecher, Profil-Detail) ebenfalls
  /// ohne Reiter.
  static const _hideBottomNavRoutes = {
    AppRoutes.personalityTest,
    AppRoutes.emailVerification,
    AppRoutes.chatDetail,
    AppRoutes.randomChat,
    AppRoutes.quiz,
    AppRoutes.spiceQuestions,
    AppRoutes.profileDetail,
  };

  /// Entscheidet anhand Muster UND konkretem Pfad, ob die Reiter
  /// ausgeblendet werden.
  ///
  /// Robust gegen beide GoRouter-Verhaltensweisen: [matchedLocation] liefert
  /// je nach Version das Muster ("/chat/:matchId") oder den konkreten Pfad
  /// ("/chat/123"). Der reine [contains]-Vergleich schlug deshalb auf
  /// manchen Versionen fehl und die Reiter blieben im Chat sichtbar.
  /// Der konkrete Pfad wird explizit geprüft - dabei bleibt "/profile/edit"
  /// (Profil BEARBEITEN, mit Reitern) ausgenommen.
  static bool _hideForLocation(String matchedLocation, String uriPath) {
    if (_hideBottomNavRoutes.contains(matchedLocation)) return true;
    if (uriPath.startsWith('/chat/')) return true;
    if (uriPath == AppRoutes.randomChat) return true;
    if (uriPath.startsWith('/dating-hour/chat/')) return true;
    if (uriPath.startsWith('/quiz/')) return true;
    if (uriPath.startsWith('/spice/')) return true;
    if (uriPath.startsWith('/profile/') && uriPath != AppRoutes.profileEdit) {
      return true;
    }
    return false;
  }

  int _index(String location) {
    // 1) Exakte übereinstimmung mit einem Haupt-Tab hat Vorrang.
    for (var i = 0; i < _routes.length; i++) {
      if (location == _routes[i]) return i;
    }
    // 2) Bekannte Unterrouten-Prefixe dem passenden Haupt-Tab zuordnen.
    for (final entry in _subRoutePrefixes.entries) {
      if (location == entry.key || location.startsWith('${entry.key}/')) {
        return entry.value;
      }
    }
    // 3) Generischer Prefix-Fallback (z. B. /settings, /profile/edit).
    for (var i = 0; i < _routes.length; i++) {
      if (location.startsWith('${_routes[i]}/')) return i;
    }
    return 0;
  }

  /// Tab-Wechsel mit Schutz für ungespeicherte Profil-Änderungen
  /// (Nutzerwunsch): Wird "Profil bearbeiten" mit Änderungen verlassen,
  /// fragt die Navigation nach Speichern / Verwerfen / Abbrechen.
  ///
  /// Bewusst OHNE Router-URI-Prüfung: Der Dirty-Flag ist genau dann true,
  /// wenn der Profil-Editor offen ist und ungespeicherte Änderungen hat -
  /// der Screen setzt ihn beim Verlassen (dispose) zurück. Die frühere
  /// URI-Ermittlung über den Router-Delegate war fehleranfällig (der
  /// Kontext der Bottom-Nav sah die Unter-Route je nach Zeitpunkt nicht),
  /// wodurch die Nachfrage stil blieb.
  Future<void> _goToTab(
    BuildContext context,
    WidgetRef ref,
    int i,
  ) async {
    final dirty = ref.read(profileEditDirtyProvider);
    if (dirty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(L10n.t(ctx, 'nav.unsavedTitle')),
          content: Text(L10n.t(ctx, 'nav.unsavedBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: Text(L10n.t(ctx, 'common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('discard'),
              child: Text(L10n.t(ctx, 'common.discard')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: Text(L10n.t(ctx, 'common.save')),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      if (choice == 'discard') {
        ref.read(profileEditDirtyProvider.notifier).state = false;
      } else {
        // Speichern: Der Edit-Screen speichert und navigiert danach selbst
        // zur Ziel-Route (bei Validierungsfehlern bleibt er im Formular).
        ref.read(profileEditNavigateAfterSaveProvider.notifier).state =
            _tabs[i].route;
        return;
      }
    }
    if (!context.mounted) return;
    // Radar laeuft und der Wechsel verlaesst den Transit-Tab: gleiche
    // Rueckfrage wie beim Screen-Pop. Ohne diesen Haken blieb der Scan
    // beim Tabsprung still im Hintergrund aktiv und adressierbar.
    if (GoRouterState.of(context).uri.path.startsWith('/transit')) {
      final mayLeave = await confirmTransitExit(context, ref);
      if (!mayLeave) return;
    }
    if (!context.mounted) return;
    ref.read(currentNavIndexProvider.notifier).state = i;
    if (!context.mounted) return;
    context.go(_tabs[i].route);
  }

  /// Zuletzt gesicherte Route (schreibt Prefs nur bei Wechsel, v0.9.1).
  static String? _lastSavedRoute;

  /// System-Overlay passend zur Helligkeit (Nutzerwunsch, 27.10.2026).
  ///
  /// Die Statusleiste wird nur dann richtig, wenn die Icon-Helligkeit
  /// zum Theme passt: dunkle Icons auf hellem Grund, helle auf dunklem.
  /// Ohne diese Angabe bleiben sie in Flutter weiss - im Light-Mode
  /// unlesbar.
  static SystemUiOverlayStyle _overlayStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Theme.of(context).colorScheme.surface,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routerState = GoRouterState.of(context);
    final location = routerState.matchedLocation;
    // Letzte wiederherstellbare Route für Kaltstarts nach Prozesstod
    // sichern (v0.9.1) - nur bei Wechsel, kein Schreiben pro Build.
    final concretePath = routerState.uri.path;
    if (concretePath != _lastSavedRoute) {
      _lastSavedRoute = concretePath;
      if (isRestorableRoute(concretePath)) {
        unawaited(_saveLastRoute(ref, concretePath));
      }
    }
    final computedIndex = _index(location);
    // Zentralen State synchronisieren, damit er überall konsistent ist.
    final stateIndex = ref.watch(currentNavIndexProvider);
    final index = stateIndex == computedIndex ? stateIndex : computedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(currentNavIndexProvider) != computedIndex) {
        ref.read(currentNavIndexProvider.notifier).state = computedIndex;
      }
    });

    final hideNav = _hideForLocation(location, routerState.uri.path);
    // Desktop/Web: ab 1000 px logischer Breite NavigationRail statt
    // Bottom-Bar (Touch-Targets bleiben, Maus-Nutzung wird natürlicher).
    final useRail = MediaQuery.sizeOf(context).width >= 1000;

    // Eigene Reiter-Leiste statt Material-NavigationBar.
    //
    // NUTZERWUNSCH (27.10.2026): "der aktuell ausgewählte Reiter soll
    // besser aussehen, als nur das Logo farblich wie aktuell
    // hervorzuheben. Das soll ein besseres und ikonisches Design
    // haben."
    //
    // Die Material-NavigationBar hebt den aktiven Reiter nur farblich
    // hervor - auf dem schwebenden, fast durchsichtigen Container der
    // App geht das unter: man sieht nicht, wo man ist.
    //
    // Die eigene Leiste gibt dem aktiven Reiter eine GEFUELLTE PILLE
    // um das Symbol, plus die Label-Farbe und eine fette Schrift. Das ist
    // dieselbe Sprache wie die Pillen-Leiste im Admin-Screen und im
    // Interessen-Screen - eine Form, ein Material.
    final navBar = _BottomTabBar(
      index: index,
      tabs: _tabs,
      onSelected: (i) => _goToTab(context, ref, i),
    );

    return Scaffold(
      // STATUSLEISTE (Nutzerwunsch, 27.10.2026).
      //
      // Die AppBar setzt die Icon-Helligkeit ueber das Theme - aber
      // nicht jeder Screen hat eine AppBar (Startseite, Profil). Ohne
      // diese Angabe bleiben die System-Icons dann weiss, auch im
      // Light-Mode, und Akkustand, Uhrzeit und Empfangsanzeige sind
      // auf hellem Grund unlesbar.
      //
      // AnnotatedRegion schlaegt die AppBar-Angabe fuer die Bildschirm-
      // Flaeche, in der sie sitzt - deshalb steht sie HIER, einmal fuer
      // die ganze App, statt in jedem Screen einzeln.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _overlayStyle(context),
        child: useRail && !hideNav
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: index,
                    onDestinationSelected: (i) => _goToTab(context, ref, i),
                    labelType: NavigationRailLabelType.all,
                    destinations: _tabs
                        .map(
                          (t) => NavigationRailDestination(
                            icon: Icon(t.icon),
                            label: Text(L10n.t(context, t.label)),
                          ),
                        )
                        .toList(),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(child: child),
                ],
              )
            : child,
      ),
      bottomNavigationBar: (hideNav || useRail)
          ? null
          // Schwebende Reiter-Leiste (Nutzerwunsch): abgerundeter
          // Container mit Schatten statt kantiger Vollbreite - passt zu
          // Cards (24) und Dialogen im Rest der App.
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Material(
                  elevation: 8,
                  shadowColor: Theme.of(context)
                      .colorScheme
                      .shadow
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(28),
                  color:
                      Theme.of(context).colorScheme.surfaceContainer,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: navBar,
                  ),
                ),
              ),
            ),
    );
  }
}

class _NavItem {
  const _NavItem(this.route, this.icon, this.label);
  final String route;
  final IconData icon;
  final String label;
}

/// Die Reiter-Leiste unten (v0.10.0, NUTZERWUNSCH 27.10.2026).
///
/// EIGENE Zeichnung statt Material-`NavigationBar`.
///
/// Grund: die Material-Leiste hebt den aktiven Reiter nur farblich
/// hervor. Auf dem schwebenden, fast durchsichtigen Container der App
/// geht das unter - man sieht nicht mehr, wo man ist. Der Nutzerwunsch
/// war ausdruecklich: der aktive Reiter soll "besseres und ikonisches
/// Design" haben, nicht nur ein farbiges Logo.
///
/// Was diese Leiste anders macht:
///   * eine GEFUELLTE Pille hinter dem aktiven Symbol (nicht nur eine
///     Farbaenderung am Icon),
///   * das Label des aktiven Reiters in der Akzentfarbe und fett,
///   * die Pille waechst sanft mit (AnimatedContainer), statt hart
///     umzuschalten.
///
/// Die Pille hat dieselbe Form wie die Pillen-Leiste im Admin-Screen
/// und im Interessen-Screen (Radius 999 = vollstaendig rund).
class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({
    required this.index,
    required this.tabs,
    required this.onSelected,
  });

  final int index;
  final List<_NavItem> tabs;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < tabs.length; i++)
          Expanded(
            child: _BottomTabItem(
              tab: tabs[i],
              selected: i == index,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(i);
              },
            ),
          ),
      ],
    );
  }
}

class _BottomTabItem extends StatelessWidget {
  const _BottomTabItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _NavItem tab;
  final bool selected;
  final VoidCallback onTap;

  /// Radius der Pille. 999 macht aus jedem Rechteck eine Pille
  /// unabhaengig von der Hoehe.
  static const double _pilleRadius = 999;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final symbolFarbe = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    final textFarbe = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: L10n.t(context, tab.label),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_pilleRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Die Pille: gefuellt beim aktiven Reiter, transparent
                // sonst. AnimatedContainer faehrt die Farbe weich.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(_pilleRadius),
                  ),
                  child: Icon(tab.icon, size: 22, color: symbolFarbe),
                ),
                const SizedBox(height: 4),
                Text(
                  L10n.t(context, tab.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: textFarbe,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

