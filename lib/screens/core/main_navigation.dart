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
import 'package:thestia/widgets/dock_tab_bar.dart';

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
    DockTab(
        route: AppRoutes.home, icon: Icons.newspaper, labelKey: 'nav.home'),
    DockTab(
        route: AppRoutes.swipeModeSelection,
        icon: Icons.favorite,
        labelKey: 'nav.discover'),
    DockTab(
        route: AppRoutes.interessen, icon: Icons.people, labelKey: 'nav.interests'),
    DockTab(
        route: AppRoutes.profile, icon: Icons.person, labelKey: 'nav.profile'),
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
    final navBar = DockTabBar(
      index: index,
      tabs: _tabs,
      onSelected: (i) => _goToTab(context, ref, i),
    );

    // Wischen zwischen den Haupt-Reitern (NUTZERWUNSCH 28.10.2026).
    // Nur wenn die Leiste sichtbar ist - im Chat wuerde ein Wischen
    // sonst unerwartet den Reiter wechseln.
    final swipeAktiv = !hideNav && !useRail;

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
                            label: Text(L10n.t(context, t.labelKey)),
                          ),
                        )
                        .toList(),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(child: child),
                ],
              )
            : _TabSwipe(
                enabled: swipeAktiv,
                index: index,
                onSwipe: (richtung) {
                  final ziel = index + richtung;
                  if (ziel < 0 || ziel >= _tabs.length) return;
                  _goToTab(context, ref, ziel);
                },
                child: child,
              ),
      ),
      bottomNavigationBar: (hideNav || useRail)
          ? null
          // Schwebende Reiter-Leiste (Nutzerwunsch): abgerundeter
          // Container mit Schatten statt kantiger Vollbreite - passt zu
          // Cards (24) und Dialogen im Rest der App.
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                // Der Schatten ist ausdruecklich ein BoxShadow und NICHT
                // die Elevation des Material: die Material-Elevation
                // zeichnet ihren Schatten je nach Geraet unterschiedlich
                // (manchmal als harter Ring). Ein BoxShadow sieht
                // ueberall gleich aus - und das Dock soll auf jedem
                // Geraet dasselbe schwebende Objekt sein.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(32),
                    // Eine feine Lichtkante: sie hebt das Dock vom
                    // Hintergrund ab, ohne die Kanten zu ueberzeichnen.
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .shadow
                            .withValues(alpha: 0.20),
                        blurRadius: 26,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    // MaterialType.transparency: nur fuer die
                    // Farb-Pinsel des InkWell - der Schatten kommt von
                    // aussen.
                    child: Material(
                      type: MaterialType.transparency,
                      child: navBar,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
/// Wischen zwischen den Haupt-Reitern der App.
///
/// NUTZERWUNSCH (28.10.2026): das Wischen soll NICHT mehr zwischen den
/// Unterreitern der Interessen-Seite gehen, sondern zwischen den vier
/// grossen Reitern der App (Aktuelles, Entdecken, Interessen, Profil).
/// NUTZERWUNSCH (30.10.2026): "die Wisch-Animation soll fluessiger
/// werden" - die Seite folgt dem Finger jetzt mit einer gedaempften
/// Bewegung, federt beim Loslassen weich zurueck und der neue Reiter
/// gleitet von der passenden Seite herein.
///
/// Umsetzung: ein waagerechter Geste-Erkner ueber dem Seiteninhalt.
/// Er wird nur aktiv, wenn die Reiterleiste sichtbar ist - im Chat oder
/// im Quiz wuerde ein Wischen sonst unerwartet den Reiter wechseln.
class _TabSwipe extends StatefulWidget {
  const _TabSwipe({
    required this.child,
    required this.onSwipe,
    required this.enabled,
    required this.index,
  });

  final Widget child;

  /// Richtung: -1 = zurueck (nach rechts wischen), +1 = vor.
  final ValueChanged<int> onSwipe;

  final bool enabled;

  /// Aktueller Reiter. Aendert er sich, gleitet der neue Inhalt herein.
  final int index;

  @override
  State<_TabSwipe> createState() => _TabSwipeState();
}

class _TabSwipeState extends State<_TabSwipe>
    with TickerProviderStateMixin {
  /// Weg der aktuellen Geste in Pixeln (mit Widerstand gedaempft).
  double _weg = 0;

  /// Startwert der Rueckfeder-Animation.
  double _federStart = 0;

  /// Ob die Reitergrenze in dieser Geste schon ueberschritten wurde.
  bool _geTickt = false;

  /// Richtung des hereingleitenden Reiters: +1 von rechts, -1 von links.
  int _enterRichtung = 1;

  /// Ab dieser Wegerstrecke wird gewechselt.
  static const double _schwelle = 64;

  /// Anteil des Fingerwegs, den die Seite sichtbar mitgeht.
  static const double _folge = 0.42;

  /// Breite des Hereingleitens (Anteil der Bildschirmbreite).
  static const double _einflug = 0.10;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );

  late final AnimationController _feder = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  )..addListener(_onFederTick);

  void _onFederTick() {
    if (!mounted) return;
    if (_feder.isCompleted) {
      setState(() => _weg = 0);
    } else {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant _TabSwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      // Der Inhalt wurde vom Router ausgetauscht: von der Seite
      // hereinholen, in deren Richtung gewischt wurde.
      _enterRichtung = widget.index > oldWidget.index ? 1 : -1;
      _weg = 0;
      _feder.stop();
      _enter.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _feder.dispose();
    super.dispose();
  }

  /// Sichtbarer Versatz durch die laufende Rueckfeder.
  double get _federWeg {
    if (!_feder.isAnimating) return _weg;
    final t = Curves.easeOutCubic.transform(_feder.value);
    return _federStart * (1 - t);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final breite = MediaQuery.sizeOf(context).width;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _feder.stop();
        _weg = 0;
        _geTickt = false;
      },
      onHorizontalDragUpdate: (details) {
        // Widerstand ab der halben Strecke: die Seite laesst sich
        // ziehen, laeuft aber nicht unbegrenzt mit.
        final daempfung = _weg.abs() > _schwelle * 0.75 ? 0.35 : 1.0;
        final next = (_weg + details.delta.dx * daempfung).clamp(
          -breite * 0.28,
          breite * 0.28,
        );
        setState(() => _weg = next);
        if (!_geTickt && _weg.abs() >= _schwelle) {
          _geTickt = true;
          HapticFeedback.selectionClick();
        }
      },
      onHorizontalDragEnd: (_) {
        final gewickt = _weg.abs() >= _schwelle;
        // RICHTUNG (NUTZERWUNSCH 28.10.2026): Nach links wischen
        // schiebt die Seite nach links - man kommt zum naechsten
        // Reiter. Nach rechts waere es der vorherige.
        final richtung = _weg < 0 ? 1 : -1;
        if (gewickt) {
          setState(() => _weg = 0);
          widget.onSwipe(richtung);
        } else {
          // Nicht weit genug: weich in die Ausgangslage zurueck.
          _federStart = _weg;
          _feder.forward(from: 0);
        }
      },
      onHorizontalDragCancel: () {
        _federStart = _weg;
        _feder.forward(from: 0);
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _feder]),
        builder: (context, child) {
          final einflug =
              (1 - Curves.easeOutCubic.transform(_enter.value)) *
                  breite *
                  _einflug *
                  _enterRichtung;
          final x = _federWeg * _folge + einflug;
          return Transform.translate(offset: Offset(x, 0), child: child);
        },
        child: widget.child,
      ),
    );
  }
}
