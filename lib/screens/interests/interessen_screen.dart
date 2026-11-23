import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/chat/find_match_models.dart';
import 'package:thestia/models/chat/match.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/dating_hour/find_your_match_provider.dart';
import 'package:thestia/providers/profile/pinned_matches_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/dating_hour/find_your_match_service.dart';
import 'package:thestia/services/profile/report_service.dart';
import 'package:thestia/services/chat/relay_service.dart';
import 'package:thestia/services/chat/seen_service.dart';
import 'package:thestia/services/server/supabase_database_service.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/widgets/chat/end_spark_dialog.dart';
import 'package:thestia/widgets/chat/funke_overlay.dart';
import 'package:thestia/widgets/profile/intro_audio_player.dart';
import 'package:thestia/widgets/common/states.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/common/calm_loading.dart';
import 'package:thestia/utils/common/best_effort.dart';

part 'parts/personenmenue.dart';
part 'parts/ownlikestab.dart';
part 'parts/ownlikestabstate.dart';
part 'parts/receivedlikestab.dart';
part 'parts/receivedlikestabstate.dart';
part 'parts/matchestab.dart';
part 'parts/matchestabstate.dart';
part 'parts/matchestabauswahl.dart';
part 'parts/cooledmatchtile.dart';
part 'parts/busyicon.dart';
part 'parts/busyiconstate.dart';
part 'parts/interestpanelbutton.dart';
part 'parts/panelbubble.dart';
part 'parts/funkenheader.dart';
part 'parts/sectionheader.dart';
part 'parts/automatchbadge.dart';
part 'parts/matchtile.dart';

/// Automatisches Nachladen eines Tabs (v0.9.1): bei Rückkehr von einem
/// gepushten Screen (RouteObserver.didPopNext, z. B. aus dem Chat) und
/// bei App-Resume (anderes Gerät könnte Likes/Funken geändert haben).
/// Einbindung: `with RouteAware, WidgetsBindingObserver, _AutoReloadTab`
/// und [reloadTab] implementieren.
mixin _AutoReloadTab<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, RouteAware, WidgetsBindingObserver {
  /// Lädt den Tab-Inhalt neu (wird von den Observer-Callbacks aufgerufen).
  Future<void> reloadTab();

  @override
  void didPopNext() {
    if (mounted) unawaited(reloadTab());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(reloadTab());
    }
  }

  /// In initState aufrufen.
  void autoReloadInit() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// In didChangeDependencies aufrufen.
  void autoReloadSubscribe(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  /// In dispose aufrufen.
  void autoReloadDispose() {
    WidgetsBinding.instance.removeObserver(this);
    bestEffortSync('unsubscribe', () {
      routeObserver.unsubscribe(this);
    });
  }
}

/// Gewünschter Start-Tab für den Interessen-Reiter (v0.9.1): Aktionen wie
/// "Funke kühlen" navigieren hierher und wollen direkt den Funken-Tab (2)
/// zeigen - sonst wirkt der gekühlte Funke als "komplett weg". Wird beim
/// Öffnen genau einmal verbraucht und auf 0 zurückgesetzt.
final interessenInitialTabProvider = StateProvider<int>((ref) => 0);

/// Verwalten-Modus der Funken-Liste (NUTZERWUNSCH: Ein-/Ausgang über das
/// AppBar-Icon, Zustand wird zwischen den Tabs geteilt - die AppBar
/// gehört zum Screen, die Liste zum Tab).
final matchSelectModeProvider = StateProvider<bool>((ref) => false);

/// Reiter "Interessen" mit drei Bereichen:
///   1. Eigene Likes (noch kein Match)
///   2. Erhaltene Likes (Vorstellung ansehen/anhören, Match bestätigen/ablehnen)
///   3. Matches (Quiz-Zugang, danach Chat)
class InteressenScreen extends ConsumerStatefulWidget {
  const InteressenScreen({super.key});

  @override
  ConsumerState<InteressenScreen> createState() => _InteressenScreenState();
}

class _InteressenScreenState extends ConsumerState<InteressenScreen> {
  /// Welches Panel ist offen? 0 = Gesendet, 1 = Erhalten, null = zu.
  ///
  /// NUTZERWUNSCH (30.10.2026): Beide Listen starten ZUGEKLAPPT. Erst ein
  /// Tipp auf den Reiter öffnet die Blase darunter; ein zweiter Tipp
  /// schließt sie wieder. Die Funken stehen immer darunter und werden
  /// durch das Öffnen nach unten geschoben.
  int? _openPanel;

  /// Schluessel fuer die Abschnitte - sie muessen ueberleben, wenn
  /// der Reiter wechselt (sonst waere die Liste bei jedem Wechsel
  /// neu geladen und der Pull-to-Refresh waere hin).
  final _sentKey = GlobalKey<_OwnLikesTabState>();
  final _receivedKey = GlobalKey<_ReceivedLikesTabState>();
  final _matchesKey = GlobalKey<_MatchesTabState>();

  /// Anker des Funken-Abschnitts (fuer den Sprung aus dem Chat).
  final _funkenAnker = GlobalKey();

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Der Initial-Reiter aus dem Aufrufer:
    //   1 = "Erhalten" (z. B. aus "Neue Likes" auf der Startseite),
    //   2 = "Funken" (z. B. nach einem Match) - der ist kein Reiter mehr,
    //       sondern ein Sprung zum Funken-Abschnitt,
    //   0 = "Gesendet" (Standard: zugeklappt).
    final gewaehlt = ref.read(interessenInitialTabProvider);
    if (gewaehlt == 1) _openPanel = 1;
    if (gewaehlt == 1) {
      // Einmal-Auftrag: beim naechsten ├ûffnen startet die Seite wieder
      // zugeklappt, nicht dauerhaft auf "Erhalten".
      ref.read(interessenInitialTabProvider.notifier).state = 0;
    }
    // Der alte Initial-Reiter "2" war der Funken-Tab. Funken sind
    // jetzt immer sichtbar - deshalb springt die Seite dorthin,
    // statt einen Reiter zu waehlen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (gewaehlt == 2) {
        _scrollToFunken();
        ref.read(interessenInitialTabProvider.notifier).state = 0;
      }
    });
  }

  /// Springt zum Funken-Abschnitt.
  ///
  /// Von dort aus wird der "Funke kühlen"-Weg geoeffnet (Chat-Screens
  /// setzen den Initial-Reiter auf 2 und navigieren dann hierher).
  void _scrollToFunken() {
    final ziel = _funkenAnker.currentContext;
    if (ziel == null) return;
    Scrollable.ensureVisible(
      ziel,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
  }

  /// Aktualisiert alle drei Abschnitte (Pull-to-Refresh der Seite).
  Future<void> _refreshAlle() async {
    await Future.wait(<Future<void>>[
      if (_sentKey.currentState != null) _sentKey.currentState!.refresh(),
      if (_receivedKey.currentState != null)
        _receivedKey.currentState!.refresh(),
      if (_matchesKey.currentState != null) _matchesKey.currentState!.refresh(),
    ]);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// ├ûffnet ein Panel oder schlie├ƒt es, wenn es bereits offen ist.
  void _togglePanel(int index) {
    setState(() => _openPanel = _openPanel == index ? null : index);
  }

  @override
  Widget build(BuildContext context) {
    // Der Stift gehoert zum Verwalten der Funken - also nur, wenn es
    // Funken gibt. Auf "Gesendet" und "Erhalten" tut er nichts, und
    // genau das war der Befund: "Der Stift funktioniert nicht, wenn
    // keine Daten dort vorhanden sind."
    final funkenVorhanden =
        (ref.watch(serverMatchesProvider).valueOrNull?.length ?? 0) > 0;
    final stiftSichtbar = funkenVorhanden;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(L10n.t(context, 'interests.title')),
        // NUTZERWUNSCH: "Verwalten" als Icon statt Textbutton in der
        // Funken-Liste (sparte Platz; der Ein-/Ausgang des Auswähl-Modus
        // bleibt in der Liste selbst).
        actions: [
          // Der Stift erscheint nur, wenn er etwas zu tun hat: wenn es
          // Funken gibt. Ein Knopf, der nichts bewirkt, ist schlechter
          // als kein Knopf.
          if (stiftSichtbar)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: L10n.t(context, 'interests.manage'),
              onPressed: () =>
                  ref.read(matchSelectModeProvider.notifier).state = true,
            ),
        ],
      ),
      // NUTZERWUNSCH (30.10.2026): "Gesendet" und "Erhalten" sind
      // zugeklappte Blasen. Ein Tipp öffnet die Liste direkt unter dem
      // Reiter (die Blase wächst nach unten), ein zweiter Tipp schließt
      // sie. Die Funken stehen IMMER darunter und werden beim Öffnen
      // nach unten geschoben.
      // Die Reiter stehen VOR dem aufgeklappten Bereich, nicht in ihm.
      //
      // NUTZERWUNSCH (01.11.2026), zweimal: "die buttons ... ganz
      // bisschen im aufgeklappten fenster drin und nicht nur dran" und
      // danach "sind Gesendet und Erhalten in dem Aufgeklappten noch
      // immer drinnen".
      //
      // Ein Reiter, der in den Bereich hineinragt, IST in ihm - egal,
      // ob er ueberlappt oder sich nur beruehrt. Der Bereich ist ein
      // eigenes Fenster, die Reiter gehoeren davor. Deshalb liegt
      // der Bereich jetzt unter ihnen (mit einem kleinen Abstand), und
      // die Reiter werden nach der Liste gemalt.
      body: Stack(
        children: [
          // NUTZERWUNSCH (03.11.2026), erneut: "Bei Interessen sind die
          // Buttons Gesendet und Erhalten noch immer in dem Fenster, was
          // aufploppt".
          //
          // DER BEFUND: Die Reiter sind fixiert (Positioned), die Liste
          // war es auch (Positioned.fill) - aber sie hatte den Platz der
          // Reiter nur als INNEREN Abstand (padding). Sobald man in der
          // Liste scrollte, wanderte der Inhalt UNTER den fixierten
          // Reitern hindurch und die Knöpfe lagen optisch IM Panel. Das
          // war der Grund fuer die wiederholte Meldung: die Geometrie
          // war richtig, die Ueberlappung beim Scrollen nicht.
          //
          // Die Loesung: Die Liste beginnt raeumlich UNTER den Reitern
          // (Positioned.top). Ihr Inhalt kann gar nicht mehr unter ihnen
          // durchlaufen - die Reiter stehen immer vor dem Fenster.
          Positioned(
            top:
                _reiterRandOben + _pillenHoehe(context) + _abstandReiterBereich,
            left: 0,
            right: 0,
            bottom: 0,
            child: RefreshIndicator(
              onRefresh: _refreshAlle,
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  // clipBehavior: Clip.hardEdge - OHNE das war die
                  // Blase waehrend des Aufklappens nicht beschnitten:
                  // sie stand in voller Hoehe da, waehrend der Kasten
                  // darunter wuchs. Das sah ruckelig aus (NUTZERWUNSCH
                  // 01.11.2026: "Die Aufklapptanimation ist auch noch
                  // etwas ruckelig").
                  AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.hardEdge,
                    child: _openPanel == null
                        ? const SizedBox.shrink()
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            // Die ausgehenden Panels duerfen die Hoehe
                            // NICHT bestimmen: sonst springt der
                            // Kasten, wenn das neue Panel kuerzer ist.
                            // Sie werden deshalb positioniert - und
                            // zaehlen nicht mit.
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.topCenter,
                              children: [
                                ...previous.map(
                                  (p) => Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: p,
                                  ),
                                ),
                                ?current,
                              ],
                            ),
                            transitionBuilder: (child, animation) {
                              final offset =
                                  Tween<Offset>(
                                    begin: const Offset(0, -0.03),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutCubic,
                                    ),
                                  );
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: offset,
                                  child: child,
                                ),
                              );
                            },
                            child: _PanelBubble(
                              key: ValueKey<int>(_openPanel!),
                              child: _openPanel == 0
                                  ? _OwnLikesTab(key: _sentKey, embedded: true)
                                  : _ReceivedLikesTab(
                                      key: _receivedKey,
                                      embedded: true,
                                    ),
                            ),
                          ),
                  ),
                  // Die Funken stehen immer offen - ohne Text daneben,
                  // mittig unter den beiden Reitern.
                  const SizedBox(height: 20),
                  Padding(
                    key: _funkenAnker,
                    padding: const EdgeInsets.only(bottom: 4),
                    child: const _FunkenHeader(),
                  ),
                  _MatchesTab(key: _matchesKey, embedded: true),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _InterestPanelButton(
                      label: L10n.t(context, 'interests.tabSent'),
                      icon: Icons.outgoing_mail,
                      open: _openPanel == 0,
                      onTap: () => _togglePanel(0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InterestPanelButton(
                      label: L10n.t(context, 'interests.tabReceived'),
                      icon: Icons.call_received,
                      open: _openPanel == 1,
                      onTap: () => _togglePanel(1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Die Hoehe der Reiter-Pille: 40 px im Normalfall.
///
/// Die Pille hat eine FESTE Hoehe - nur so sitzt der aufgeklappte
/// Bereich genau darunter (siehe [_reiterUeberlappung]). Bei grosser
/// Schriftgroesse waere eine feste Hoehe aber zu klein: der Text
/// laege dann ueber (der Render-Test prueft 3,2-fache Schriftgroesse).
///
/// Deshalb waechst die Hoehe mit dem Textfaktor mit.
double _pillenHoehe(BuildContext context) {
  final skala = MediaQuery.textScalerOf(context).scale(1.0);
  return 40 * (skala < 1.0 ? 1.0 : skala);
}

/// Der Rand ueber der Reiter-Zeile.
const double _reiterRandOben = 4;

/// Der Abstand zwischen den Reitern und dem aufgeklappten Bereich.
///
/// NUTZERWUNSCH (01.11.2026), zweimal: "die buttons ... ganz bisschen
/// im aufgeklappten fenster drin und nicht nur dran" und danach
/// "sind Gesendet und Erhalten in dem Aufgeklappten noch immer drinnen".
///
/// Ein Reiter, der in den Bereich hineinragt, IST in ihm - egal, ob
/// er ueberlappt oder sich beruehrt. Der Bereich ist ein eigenes
/// Fenster ("Pop-up"), und die Reiter gehoeren VOR das Fenster.
///
/// Deshalb: der Bereich beginnt unter den Reitern, mit einem kleinen
/// Abstand. Die Reiter stehen dadurch eindeutig ausserhalb.
const double _abstandReiterBereich = 16;

/// Ein Eintrag im Personen-Menü (siehe [_PersonenMenue]).
class _MenueEintrag {
  const _MenueEintrag({
    required this.wert,
    required this.icon,
    required this.label,
    this.rot = false,
  });

  final String wert;
  final IconData icon;
  final String label;

  /// Rote Beschriftung (loeschen, blockieren).
  final bool rot;
}

/// Blockieren mit Bestaetigung - fuer jede Person, nicht nur fuer
/// Funken.
///
/// Der Dialog und der Ablauf sind derselbe wie im Chat: erst fragen,
/// dann blockieren, dann melden. Zwei getrennte Funktionen gab es bis
/// hierher - die eine konnte nur einen Funke blockieren, und genau
/// deshalb war das Blockieren bei einem blossen Like nicht erreichbar.
Future<void> bestaetigeBlockieren(
  BuildContext context,
  WidgetRef ref,
  String personId,
  String personName,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.block, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(L10n.t(ctx, 'chat.blockTitle'))),
        ],
      ),
      content: Text(L10n.tf(ctx, 'chat.blockBody', {'name': personName})),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(L10n.t(ctx, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: Text(L10n.t(ctx, 'chat.blockAction')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await SupabaseDatabaseService(SupabaseService.client).blockUser(personId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          L10n.tf(context, 'chat.blockedDone', {'name': personName}),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t(context, 'chat.blockFailed')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Eigene Likes
// ---------------------------------------------------------------------------

/// Formatiert das Datum, an dem ein Like rausging.
///
/// NUTZERWUNSCH (28.10.2026): "kann ... auch sehen, an welchem Tag
/// man den Like gesendet hat".
///
/// Angezeigt wird das KALENDERDATUM (12.10.2026) - bei einem Like ist
/// das eindeutiger als "vor 3 Tagen" (das wandert mit der Zeit).
String _likeDatum(BuildContext context, DateTime zeit) {
  final lokal = zeit.toLocal();
  final jetzt = DateTime.now();
  final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
  final tag = DateTime(lokal.year, lokal.month, lokal.day);
  final tage = heute.difference(tag).inDays;

  if (tage == 0) return L10n.t(context, 'interests.likeToday');
  if (tage == 1) return L10n.t(context, 'interests.likeYesterday');
  if (tage < 7) {
    return L10n.tf(context, 'interests.likeDaysAgo', {'days': '$tage'});
  }
  return L10n.tf(context, 'interests.likeOn', {
    'date': '${lokal.day}.${lokal.month}.${lokal.year}',
  });
}

// ---------------------------------------------------------------------------
// Tab 2: Erhaltene Likes
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Tab 3: Matches
// ---------------------------------------------------------------------------
