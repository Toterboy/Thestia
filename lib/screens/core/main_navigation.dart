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
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/widgets/chat/dock_tab_bar.dart';
import 'package:thestia/utils/common/best_effort.dart';

/// Sichert die Route für die Wiederherstellung nach Prozesstod (v0.9.1).
Future<void> _saveLastRoute(WidgetRef ref, String path) async {
  await bestEffort('localStorageProvider.saveString', () async {
    await ref.read(localStorageProvider).saveString(lastRoutePrefsKey, path);
  });
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
    DockTab(route: AppRoutes.home, icon: Icons.newspaper, labelKey: 'nav.home'),
    DockTab(
      route: AppRoutes.swipeModeSelection,
      icon: Icons.favorite,
      labelKey: 'nav.discover',
    ),
    DockTab(
      route: AppRoutes.interessen,
      icon: Icons.people,
      labelKey: 'nav.interests',
    ),
    DockTab(
      route: AppRoutes.profile,
      icon: Icons.person,
      labelKey: 'nav.profile',
    ),
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
  /// sichtbar sein - das Gespräch hat den vollen Bildschirm. v0.9.1: ALLE
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
  Future<void> _goToTab(BuildContext context, WidgetRef ref, int i) async {
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
    // Radar läuft und der Wechsel verlässt den Transit-Tab: gleiche
    // Rückfrage wie beim Screen-Pop. Ohne diesen Haken blieb der Scan
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
  /// Ohne diese Angabe bleiben sie in Flutter weiß - im Light-Mode
  /// unlesbar.
  static SystemUiOverlayStyle _overlayStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Theme.of(context).colorScheme.surface,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
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
    // Die eigene Leiste gibt dem aktiven Reiter eine GEFÜLLTE PILLE
    // um das Symbol, plus die Label-Farbe und eine fette Schrift. Das ist
    // dieselbe Sprache wie die Pillen-Leiste im Admin-Screen und im
    // Interessen-Screen - eine Form, ein Material.
    final navBar = DockTabBar(
      index: index,
      tabs: _tabs,
      onSelected: (i) => _goToTab(context, ref, i),
    );

    // Wischen zwischen den HAUPT-Reitern (NUTZERWUNSCH 28.10.2026).
    // Nur wenn die Leiste sichtbar ist - im Chat würde ein Wischen
    // sonst unerwartet den Reiter wechseln.
    //
    // BEFUND (09.11.2026, Betreiber): "Das Swipen zwischen den Reitern
    // soll bei Entdecken aber nicht in den Unterscreens davon
    // funktionieren (selbes gilt auch für die anderen Reiter)."
    //
    // Das Wischen ist damit ein REITER-Wechsel und kein Screen-Wechsel:
    // In jedem Unterscreen (Find your Spark, Profil bearbeiten,
    // Einstellungen, die Kategorie-Sicht, ...) würde es den Reiter
    // wechseln, während man gerade in etwas anderem ist - und der
    // Bildschirm, aus dem man wegwischt, käme nicht zurück.
    //
    // Deshalb: das Wischen gibt es NUR auf den vier Haupt-Reitern
    // (_routes). In allen Unterscreens ist es aus.
    final swipeAktiv =
        !hideNav && !useRail && _routes.contains(routerState.uri.path);

    return Scaffold(
      // STATUSLEISTE (Nutzerwunsch, 27.10.2026).
      //
      // Die AppBar setzt die Icon-Helligkeit über das Theme - aber
      // nicht jeder Screen hat eine AppBar (Startseite, Profil). Ohne
      // diese Angabe bleiben die System-Icons dann weiß, auch im
      // Light-Mode, und Akkustand, Uhrzeit und Empfangsanzeige sind
      // auf hellem Grund unlesbar.
      //
      // AnnotatedRegion schlägt die AppBar-Angabe für die Bildschirm-
      // Fläche, in der sie sitzt - deshalb steht sie HIER, einmal für
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
                // Der Schatten ist ausdrücklich ein BoxShadow und NICHT
                // die Elevation des Material: die Material-Elevation
                // zeichnet ihren Schatten je nach Gerät unterschiedlich
                // (manchmal als harter Ring). Ein BoxShadow sieht
                // überall gleich aus - und das Dock soll auf jedem
                // Gerät dasselbe schwebende Objekt sein.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(32),
                    // Eine feine Lichtkante: sie hebt das Dock vom
                    // Hintergrund ab, ohne die Kanten zu überzeichnen.
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.shadow.withValues(alpha: 0.20),
                        blurRadius: 26,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    // MaterialType.transparency: nur für die
                    // Farb-Pinsel des InkWell - der Schatten kommt von
                    // außen.
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
/// großen Reitern der App (Aktuelles, Entdecken, Interessen, Profil).
/// NUTZERWUNSCH (30.10.2026): "die Wisch-Animation soll flüssiger
/// werden" - die Seite folgt dem Finger jetzt mit einer gedämpften
/// Bewegung, federt beim Loslassen weich zurück und der neue Reiter
/// gleitet von der passenden Seite herein.
///
/// Umsetzung: ein waagerechter Geste-Erkner über dem Seiteninhalt.
/// Er wird nur aktiv, wenn die Reiterleiste sichtbar ist - im Chat oder
/// im Quiz würde ein Wischen sonst unerwartet den Reiter wechseln.
class _TabSwipe extends StatefulWidget {
  const _TabSwipe({
    required this.child,
    required this.onSwipe,
    required this.enabled,
    required this.index,
  });

  final Widget child;

  /// Richtung: -1 = zurück (nach rechts wischen), +1 = vor.
  final ValueChanged<int> onSwipe;

  final bool enabled;

  /// Aktueller Reiter. Ändert er sich, gleitet der neue Inhalt herein.
  final int index;

  @override
  State<_TabSwipe> createState() => _TabSwipeState();
}

class _TabSwipeState extends State<_TabSwipe> with TickerProviderStateMixin {
  /// Weg der aktuellen Geste in Pixeln (mit Widerstand gedämpft).
  double _weg = 0;

  /// Startwert der Rückfeder-Animation.
  double _federStart = 0;

  /// Ob die Reitergrenze in dieser Geste schon überschritten wurde.
  bool _geTickt = false;

  /// Richtung des hereingleitenden Reiters: +1 von rechts, -1 von links.
  int _enterRichtung = 1;

  /// Der Inhalt, der gerade ANGEZEIGT wird.
  ///
  /// NUTZERWUNSCH (01.11.2026): "Das swipen in der App zwischen den
  /// Reitern ist noch immer nicht flüssig."
  ///
  /// Der Grund war nicht die Animation, sondern dass die alte Seite
  /// SOFORT verschwand: der Router tauschte sie aus, und die neue
  /// Seite fuhr von der Seite herein. Zwischen "alt" und "neu" gab es
  /// keinen Übergang - das ist ein Schnitt, und ein Schnitt wirkt
  /// immer abrupt, egal wie schön die Bewegung danach aussieht.
  ///
  /// Deshalb hält dieser State den Inhalt selbst. Der Wechsel wird
  /// hier zu Ende geführt: die alte Seite bleibt eingebaut und
  /// blendet aus, die neue blendet ein und gleitet herein.
  ///
  /// Wichtig: Die alte Seite wird hier NICHT neu eingebaut. Sie war
  /// vorher ein Kind dieses Staates und bleibt es - ein erneutes
  /// Einbauen würde ihren State neu aufsetzen und zurückflackern.
  late Widget _angezeigt;

  /// Der vorherige Inhalt, der beim Wechsel ausblendet.
  Widget? _ausblendend;

  /// Der Weg, den der Finger beim Wechsel zurückgelegt hatte.
  ///
  /// Die alte Seite startet dort - sie springt nicht auf 0 zurück und
  /// fährt dann weiter. Ohne das wirkt der Wechsel wie ein Schnitt mit
  /// einem verschobenen Bild.
  double _wegBeimWechsel = 0;

  /// Ab dieser Wegerstrecke wird gewechselt.
  static const double _schwelle = 64;

  /// Anteil des Fingerwegs, den die Seite sichtbar mitgeht.
  ///
  /// NUTZERWUNSCH (03.11.2026): "Das Swipen zwischen den Reitern
  /// (links und rechts) sieht nicht nach einem flüssigen Swipe aus."
  ///
  /// DER BEFUND: Die Seite folgte dem Finger nur mit 42 %. Das fühlt
  /// sich an, als hätte die Seite einen Widerstand - der Finger
  /// zieht, die Seite zöodert hinterher. Ein Wischen, das sich
  /// wäch wie ein Wischen anfühlt, geht 1:1 mit dem Finger.
  static const double _folge = 1.0;

  /// Wie weit die Seite beim Ziehen maximal mitwandert (Anteil der
  /// Bildschirmbreite).
  static const double _maxWeg = 0.34;

  /// Dauer des Hereinflugs bei einem Reiterwechsel per Tippen.
  ///
  /// Der Weg, den die neue Seite zurücklegt, ist die Bildschirmbreite
  /// minus dem, was der Finger schon geschafft hat - die Dauer wächst
  /// also mit der Reststrecke. Das ist der Unterschied zwischen
  /// "abrupt" und "flüssig": eine kurze Bewegung wird zügiger
  /// beendet, eine lange braucht ihre Zeit.
  static const int _wechselMs = 300;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  )..addStatusListener(_onEnterStatus);

  /// Nach der Überblendung wird der alte Inhalt freigegeben.
  ///
  /// Bis dahin bleibt er eingebaut (sonst würde er neu eingebaut
  /// und zurückflackern). Danach hat er nichts mehr zu tun - er
  /// würde sonst ewig weiterlaufen (Timer, Streams, Abos).
  void _onEnterStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted) return;
    setState(() => _ausblendend = null);
  }

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
  void initState() {
    super.initState();
    _angezeigt = widget.child;
  }

  @override
  void didUpdateWidget(covariant _TabSwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      // Der Inhalt wurde vom Router ausgetauscht: von der Seite
      // hereinholen, in deren Richtung gewischt wurde.
      _enterRichtung = widget.index > oldWidget.index ? 1 : -1;
      // Die alte Seite bleibt eingebaut und blendet aus. Sie war
      // vorher ein Kind dieses Staates - sie wird hier also NICHT neu
      // eingebaut (kein Zurückflackern).
      _ausblendend = _angezeigt;
      _angezeigt = widget.child;
      // Der Weg, den der Finger zurückgelegt hat, wandert in die alte
      // Seite - sie startet dort, wo der Finger sie verlassen hat.
      _wegBeimWechsel = _weg;
      // Der Weg wird HIER zurückgesetzt - beim Loslassen blieb er
      // stehen, damit die Seite nicht für ein Bild zurücksprang.
      _weg = 0;
      _feder.stop();
      // Die Dauer hängt an der Reststrecke: die neue Seite kommt von
      // neben dem Bildschirm und legt (Bildschirmbreite minus dem
      // Fingerweg) zurück. Ein kurzer Wisch wird also zügiger
      // beendet als ein langer.
      final breite = MediaQuery.sizeOf(context).width;
      final restweg = (breite + _wegBeimWechsel).abs();
      _enter.duration = Duration(
        milliseconds: (140 + (restweg / breite).clamp(0.0, 1.0) * _wechselMs)
            .round(),
      );
      _enter.forward(from: 0);
    } else if (widget.child != oldWidget.child) {
      // Innerhalb des GLEICHEN Reiters (Detailseite, Chat, Profil):
      // der Inhalt wird direkt getauscht.
      //
      // Wichtig: Das Kind des ShellRoute wechselt bei JEDER Navigation
      // - nicht nur beim Reiterwechsel. Ohne diese Unterscheidung
      // würde die Überblendung bei jedem Aufruf einer Detailseite
      // ausgelöst, und die vorige Seite stünde noch 320 ms über
      // der neuen.
      _angezeigt = widget.child;
      _ausblendend = null;
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _feder.dispose();
    super.dispose();
  }

  /// Sichtbarer Versatz durch die laufende Rückfeder.
  double get _federWeg {
    if (!_feder.isAnimating) return _weg;
    // Geklemmt: der Wert eines Controllers kann knapp über 1,0 landen -
    // und Flutter wirft dann die Assertion "parametric value is outside
    // of [0, 1] range" (BEFUND 14.11.2026, gefunden von einem Test in
    // der Funke-Animation).
    final t = Curves.easeOutCubic.transform(_feder.value.clamp(0.0, 1.0));
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
        // Widerstand ab der halben Strecke: die Seite lässt sich
        // ziehen, läuft aber nicht unbegrenzt mit.
        final daempfung = _weg.abs() > _schwelle * 0.75 ? 0.35 : 1.0;
        final next = (_weg + details.delta.dx * daempfung).clamp(
          -breite * _maxWeg,
          breite * _maxWeg,
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
        // schiebt die Seite nach links - man kommt zum nächsten
        // Reiter. Nach rechts wäre es der vorherige.
        final richtung = _weg < 0 ? 1 : -1;
        if (gewickt) {
          // NUTZERWUNSCH (01.11.2026): "die Animation, wenn ich
          // zwischen den Reitern swipe, ist sehr abrupt und unschön".
          //
          // Das Rücksetzen auf 0 war der abrupte Teil: die Seite
          // sprang für ein Bild zurück, während der neue Reiter
          // von der Seite herein kam. Der Weg bleibt deshalb stehen -
          // der neue Inhalt zieht an der Stelle ein, an der der
          // alte gerade lag, und das Wischen läuft durch.
          //
          // Zurückgesetzt wird der Weg in didUpdateWidget, wenn der
          // Reiter tatsächlich wechselt. Passiert das nicht (am
          // Rand gibt es keinen weiteren Reiter), muss die Seite
          // trotzdem zurückfedern - das passiert im
          // Post-Frame-Callback unten.
          widget.onSwipe(richtung);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // Der Wechsel hat den Weg bereits zurückgesetzt.
            if (_weg == 0) return;
            _federStart = _weg;
            _feder.forward(from: 0);
          });
        } else {
          // Nicht weit genug: weich in die Ausgangslage zurück.
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
          final t = Curves.easeOutCubic.transform(_enter.value.clamp(0.0, 1.0));

          // NUTZERWUNSCH (03.11.2026): "Das Swipen ... sieht nicht nach
          // einem flüssigen Swipe aus."
          //
          // DER BEFUND: Die neue Seite kam mit 18 % Hereinflug und der
          // alte Inhalt blendete nur aus. Das ist eine Überblendung mit
          // einem kleinen Rutsch - kein Wischen.
          //
          // JETZT: Die beiden Seiten fahren GLEICHZEITIG und mit
          // derselben Strecke: Die alte fährt vom Fingerweg aus weiter
          // hinaus, die neue kommt von neben dem Bildschirm hinterher.
          // Weil beide dieselbe Strecke zurücklegen, wirkt es wie eine
          // einzige durchgehende Bewegung.
          //
          // Der Weg der neuen Seite ist die Bildschirmbreite minus dem,
          // was der Finger schon geschafft hat - sie setzt also genau
          // dort an, wo die alte Seite gerade ist. Kein Sprung, keine
          // Lücke.
          final alterWeg =
              _wegBeimWechsel * (1 - t) + (-_enterRichtung * breite) * t;
          final neuerWeg =
              (_enterRichtung * (breite + _wegBeimWechsel)) * (1 - t);

          // Beim Ziehen (kein Wechsel) ist t = 1: die neue Seite folgt
          // dem Finger 1:1 (_federWeg ist dann der Fingerweg).
          final x = _federWeg * _folge + neuerWeg;
          return Stack(
            children: [
              if (_ausblendend != null)
                Opacity(
                  // Der alte Inhalt weicht zurück, während er
                  // ausblendet - so bleibt die Bewegung eine
                  // durchgehende.
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(alterWeg, 0),
                    child: _ausblendend,
                  ),
                ),
              Transform.translate(offset: Offset(x, 0), child: _angezeigt),
            ],
          );
        },
      ),
    );
  }
}
