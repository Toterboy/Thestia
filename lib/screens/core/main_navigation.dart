import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/routing/route_restore.dart';
import 'package:thestia/screens/profile/profile_edit_screen.dart'
    show profileEditDirtyProvider, profileEditNavigateAfterSaveProvider;
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
    ref.read(currentNavIndexProvider.notifier).state = i;
    context.go(_tabs[i].route);
  }

  /// Zuletzt gesicherte Route (schreibt Prefs nur bei Wechsel, v0.9.1).
  static String? _lastSavedRoute;

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

    final navBar = NavigationBar(
      selectedIndex: index,
      // Hintergrund + Schatten kommen vom schwebenden Container unten;
      // die Bar selbst ist transparent (kein Doppel-Rand).
      backgroundColor: Colors.transparent,
      elevation: 0,
      onDestinationSelected: (i) => _goToTab(context, ref, i),
      destinations: _tabs
          .map(
            (t) => NavigationDestination(
              icon: Icon(t.icon),
              label: L10n.t(context, t.label),
            ),
          )
          .toList(),
    );

    return Scaffold(
      body: useRail && !hideNav
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

