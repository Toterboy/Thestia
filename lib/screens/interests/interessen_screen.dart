import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/models/match.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/find_your_match_provider.dart';
import 'package:thestia/providers/pinned_matches_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/find_your_match_service.dart';
import 'package:thestia/services/report_service.dart';
import 'package:thestia/services/relay_service.dart';
import 'package:thestia/services/seen_service.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/widgets/end_spark_dialog.dart';
import 'package:thestia/widgets/funke_overlay.dart';
import 'package:thestia/widgets/intro_audio_player.dart';
import 'package:thestia/widgets/states.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/calm_loading.dart';
import 'package:thestia/utils/best_effort.dart';

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

/// Die Werkzeuge fuer eine Person in einer Liste.
///
/// NUTZERWUNSCH (01.11.2026): "Die Bearbeitungstools auf der Interessen
/// Seite sehe ich auch nicht. Wenn sie mit Funken erst sichtbar werden
/// ist okay, aber sonst noch ergaenzen, also entfernen, blockieren,
/// melden, anpinnen, archivieren usw."
///
/// Bei den FUNKEN gab es diese Werkzeuge schon (das Drei-Punkte-Menue
/// der Funken-Kachel). Bei den LIKES fehlten sie - und die waren nur
/// erreichbar, wenn ueberhaupt ein Funke existierte. Wer nur geliked
/// hat, konnte nichts machen.
///
/// Das Menue haengt deshalb die allgemeinen Aktionen (Profil,
/// Blockieren, Melden) an die aktionsspezifischen (entfernen,
/// ignorieren, zurueck liken) an - und wird von beiden Kachelarten
/// benutzt, damit es an beiden gleich aussieht.
class _PersonenMenue extends ConsumerWidget {
  const _PersonenMenue({
    required this.personId,
    required this.personName,
    this.aktionen = const [],
    this.onAktion,
    this.aktiv = true,
  });

  final String personId;
  final String personName;

  /// Die aktionsspezifischen Eintraege.
  final List<_MenueEintrag> aktionen;

  /// Aufruf fuer einen aktionsspezifischen Eintrag.
  final void Function(String wert)? onAktion;

  /// Bei einem laufenden Vorgang ist das Menue gesperrt.
  final bool aktiv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: L10n.t(context, 'chat.more'),
      enabled: aktiv,
      onSelected: (wert) => _ausfuehren(context, ref, wert),
      itemBuilder: (ctx) => [
        for (final a in aktionen)
          PopupMenuItem(
            value: a.wert,
            child: ListTile(
              leading: Icon(a.icon, color: a.rot ? Colors.red : null),
              title: Text(a.label),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (aktionen.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem(
          value: 'profil',
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(L10n.t(context, 'profile.detail.aboutMe')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'melden',
          child: ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(L10n.t(context, 'profile.detail.reportUser')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'blockieren',
          child: ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: Text(L10n.t(context, 'profile.detail.blockUser')),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  void _ausfuehren(BuildContext context, WidgetRef ref, String wert) {
    switch (wert) {
      case 'profil':
        context.push(AppRoutes.profileDetailPath(personId));
      case 'melden':
        showReportUserDialog(
          context: context,
          ref: ref,
          reportedUserId: personId,
          reportedUserName: personName,
        );
      case 'blockieren':
        unawaited(bestaetigeBlockieren(context, ref, personId, personName));
      default:
        onAktion?.call(wert);
    }
  }
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

class _OwnLikesTab extends ConsumerStatefulWidget {
  const _OwnLikesTab({this.embedded = false, super.key});

  /// Eingebettet: Der Abschnitt steht in einem fremden Scrollbereich
  /// (der Seite) und scrollt deshalb NICHT selbst.
  ///
  /// NUTZERWUNSCH (28.10.2026): die Funken stehen immer unter dem
  /// Inhalt - dafuer braucht es EINEN Scrollbereich fuer die ganze
  /// Seite. Ohne dieses Flag haette jeder Abschnitt einen eigenen,
  /// und die Seite waere zweimal scrollbar.
  final bool embedded;

  @override
  ConsumerState<_OwnLikesTab> createState() => _OwnLikesTabState();
}

class _OwnLikesTabState extends ConsumerState<_OwnLikesTab>
    with RouteAware, WidgetsBindingObserver, _AutoReloadTab {
  List<ReceivedLike> _likes = [];
  bool _loading = true;

  /// Wurde die Liste mindestens einmal geladen?
  ///
  /// NUTZERWUNSCH (31.10.2026): "der kurze Ladekreis ist stoerend fuer
  /// die Animation dort". Der Kreis ersetzte beim Nachladen den GANZEN
  /// Inhalt - die Liste verschwand fuer einen Moment und kam als
  /// Kreis zurueck. Das ist kein Warten, das ist ein Schnitt.
  ///
  /// Deshalb gilt: der Platzhalter steht nur beim ERSTEN Laden, wenn
  /// es noch nichts zu zeigen gibt. Ab dann bleibt der Inhalt
  /// stehen und aktualisiert sich still im Hintergrund.
  bool _everLoaded = false;

  @override
  void initState() {
    super.initState();
    autoReloadInit();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    autoReloadSubscribe(context);
  }

  @override
  void dispose() {
    autoReloadDispose();
    super.dispose();
  }

  @override
  Future<void> reloadTab() => _load();

  /// Laedt neu - vom Pull-to-Refresh der Seite aufgerufen.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      _likes = await service.listMyLikes();
    } catch (e) {
      debugPrint('[Interessen] Eigene Likes fehlgeschlagen: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _everLoaded = true;
        });
      }
    }
  }

  Future<void> _removeLike(ReceivedLike like) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      await Supabase.instance.client
          .from('likes')
          .delete()
          .eq('user_id', userId)
          .eq('liked_user_id', like.profile.id);
      if (mounted) {
        setState(() => _likes.removeWhere((l) => l.likeId == like.likeId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'interests.likeWithdrawn'))),
        );
      }
    } catch (e) {
      debugPrint('[Interessen] Like entfernen fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nur beim ersten Laden: ein ruhiger Platzhalter statt eines
    // kreisenden Rings. Beim Nachladen bleibt der Inhalt stehen -
    // das Aufblitzen des Rings unterbrach die Animation, in der das
    // Panel gerade aufgeht (NUTZERWUNSCH 31.10.2026).
    if (_loading && !_everLoaded) {
      return const CalmLoading();
    }
    if (_likes.isEmpty) {
      // v0.9.1-Fix (Android 16): Auch im Leerzustand pull-to-refresh
      // ermöglichen - RefreshIndicator braucht ein scrollbares Child mit
      // AlwaysScrollableScrollPhysics (sonst löst Pull bei kurzer/leerer
      // Liste nie aus, auf Android 16 mit enforced edge-to-edge fiel das
      // besonders auf).
      //
      // Eingebettet scrollt die SEITE - der Leerzustand braucht dann
      // keine eigene RefreshIndicator und keine 60 %-Bildschirmhoehe
      // (das waere ein riesiger Leerraum in der Mitte).
      if (widget.embedded) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: EmptyState(
            icon: Icons.favorite_border,
            title: L10n.t(context, 'interests.emptySentTitle'),
            message: L10n.t(context, 'interests.emptySentBody'),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: EmptyState(
              icon: Icons.favorite_border,
              title: L10n.t(context, 'interests.emptySentTitle'),
              message: L10n.t(context, 'interests.emptySentBody'),
            ),
          ),
        ),
      );
    }
    final liste = ListView.separated(
      // Eingebettet scrollt die SEITE - der Abschnitt selbst darf nicht
      // scrollen, sonst haette man zwei Scrollbereiche ineinander.
      shrinkWrap: widget.embedded,
      physics: widget.embedded
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: widget.embedded ? EdgeInsets.zero : const EdgeInsets.all(16),
      itemCount: _likes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final like = _likes[i];
        final profile = like.profile;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  // NUTZERWUNSCH (31.10.2026): "Verifizierung soll
                  // fuer alle Personen sichtbar sein" - auch in der
                  // Liste, nicht nur im Profil.
                  title: Row(
                    children: [
                      Flexible(child: Text(profile.name)),
                      if (profile.isVerified) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: L10n.t(context, 'verify.badge'),
                          child: Icon(
                            Icons.verified,
                            size: 18,
                            color: Colors.lightBlue.shade400,
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    [
                      '${profile.age ?? '?'} Jahre',
                      // Serverseitig berechnet, angezeigt als
                      // 10-km-Stufe (v0.10.0).
                      if (profile.distanceKm > 0)
                        profile.distanceLabel((key) => L10n.t(context, key)),
                      // WANN der Like rausging (NUTZERWUNSCH,
                      // 28.10.2026: "kann ... auch sehen, an welchem
                      // Tag man den Like gesendet hat").
                      if (like.createdAt != null)
                        _likeDatum(context, like.createdAt!),
                    ].join(' · '),
                  ),
                  // Die Werkzeuge fuer die Person (NUTZERWUNSCH
                  // 01.11.2026): "Die Bearbeitungstools auf der
                  // Interessen Seite sehe ich auch nicht ... entfernen,
                  // blockieren, melden ... usw."
                  //
                  // Vorher stand hier nur ein X (Like zuruecknehmen).
                  // Blockieren und Melden waren ausschliesslich bei
                  // den FUNKEN erreichbar - wer nur geliked hatte,
                  // konnte nichts machen.
                  trailing: _PersonenMenue(
                    personId: profile.id,
                    personName: profile.name,
                    aktionen: [
                      _MenueEintrag(
                        wert: 'entfernen',
                        icon: Icons.close,
                        label: L10n.t(context, 'interests.likeWithdrawTooltip'),
                        rot: true,
                      ),
                    ],
                    onAktion: (wert) {
                      if (wert == 'entfernen') _removeLike(like);
                    },
                  ),
                ),
                if (profile.introAudioPath != null) ...[
                  const SizedBox(height: 4),
                  IntroAudioPlayer(targetUserId: profile.id),
                ],
              ],
            ),
          ),
        );
      },
    );

    // Eingebettet zieht die Seite den RefreshIndicator - ein zweiter
    // darin waere wirkungslos (und wuerde beim Ziehen kämpfen).
    if (widget.embedded) return liste;
    return RefreshIndicator(onRefresh: _load, child: liste);
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Erhaltene Likes
// ---------------------------------------------------------------------------

class _ReceivedLikesTab extends ConsumerStatefulWidget {
  const _ReceivedLikesTab({this.embedded = false, super.key});

  /// Eingebettet: Der Abschnitt steht im Scrollbereich der Seite und
  /// scrollt deshalb nicht selbst (siehe [_OwnLikesTab.embedded]).
  final bool embedded;

  @override
  ConsumerState<_ReceivedLikesTab> createState() => _ReceivedLikesTabState();
}

class _ReceivedLikesTabState extends ConsumerState<_ReceivedLikesTab>
    with RouteAware, WidgetsBindingObserver, _AutoReloadTab {
  List<ReceivedLike> _likes = [];
  bool _loading = true;

  /// Wurde die Liste mindestens einmal geladen?
  ///
  /// NUTZERWUNSCH (31.10.2026): "der kurze Ladekreis ist stoerend fuer
  /// die Animation dort". Der Kreis ersetzte beim Nachladen den GANZEN
  /// Inhalt - die Liste verschwand fuer einen Moment und kam als
  /// Kreis zurueck. Das ist kein Warten, das ist ein Schnitt.
  ///
  /// Deshalb gilt: der Platzhalter steht nur beim ERSTEN Laden, wenn
  /// es noch nichts zu zeigen gibt. Ab dann bleibt der Inhalt
  /// stehen und aktualisiert sich still im Hintergrund.
  bool _everLoaded = false;
  int? _busyLikeId;

  @override
  void initState() {
    super.initState();
    autoReloadInit();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    autoReloadSubscribe(context);
  }

  @override
  void dispose() {
    autoReloadDispose();
    super.dispose();
  }

  @override
  Future<void> reloadTab() => _load();

  /// Laedt neu - vom Pull-to-Refresh der Seite aufgerufen.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      _likes = await service.listReceivedLikes();
      // Angesehen = Badge auf Aktuelles weg (v0.9.1, Seen-Tracking).
      unawaited(
        ref
            .read(seenProvider.notifier)
            .markLikesSeen(_likes.map((l) => l.likeId)),
      );
      ref.invalidate(receivedLikesProvider);
    } catch (e) {
      debugPrint('[Interessen] Erhaltene Likes fehlgeschlagen: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _everLoaded = true;
        });
      }
    }
  }

  /// Blendet einen erhaltenen Like aus - ohne ihn abzulehnen.
  ///
  /// BEFUND (07.11.2026, Betreiber): Das Auge mit dem Strich soll
  /// "ausblenden" bedeuten, nicht "ablehnen". Die Gegenseite bekommt
  /// bei einem Ausblenden nichts zu sehen - ein Ablehnen waere eine
  /// Zurueckweisung, und genau das war die Missdeutung des Symbols.
  Future<void> _ignoreLike(ReceivedLike like) async {
    if (_busyLikeId != null) return;
    setState(() => _busyLikeId = like.likeId);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      await service.ignoreLike(like.likeId);
      if (!mounted) return;
      setState(() => _likes.removeWhere((l) => l.likeId == like.likeId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.tf(context, 'interests.likeIgnored', {
              'name': like.profile.name,
            }),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[Interessen] Like ausblenden fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'common.errorWith', {'error': '$e'}),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyLikeId = null);
    }
  }

  Future<void> _respond(ReceivedLike like, {required bool accept}) async {
    if (_busyLikeId != null) return;
    setState(() => _busyLikeId = like.likeId);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      await service.respondToLike(like.likeId, accept: accept);
      if (!mounted) return;
      setState(() => _likes.removeWhere((l) => l.likeId == like.likeId));
      if (accept) {
        await FunkeOverlay.show(context);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? L10n.tf(context, 'interests.sparkAccepted', {
                    'name': like.profile.name,
                  })
                : L10n.tf(context, 'interests.likeDeclined', {
                    'name': like.profile.name,
                  }),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[Interessen] Antwort fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'common.errorWith', {'error': '$e'}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyLikeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nur beim ersten Laden: ein ruhiger Platzhalter statt eines
    // kreisenden Rings. Beim Nachladen bleibt der Inhalt stehen -
    // das Aufblitzen des Rings unterbrach die Animation, in der das
    // Panel gerade aufgeht (NUTZERWUNSCH 31.10.2026).
    if (_loading && !_everLoaded) {
      return const CalmLoading();
    }
    if (_likes.isEmpty) {
      // Eingebettet scrollt die SEITE - kein eigener Leerraum von
      // 60 % Bildschirmhoehe (der waere ein Loch in der Seite).
      if (widget.embedded) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: EmptyState(
            icon: Icons.favorite_border,
            title: L10n.t(context, 'interests.emptyReceivedTitle'),
            message: L10n.t(context, 'interests.emptyReceivedBody'),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: EmptyState(
              icon: Icons.favorite_border,
              title: L10n.t(context, 'interests.emptyReceivedTitle'),
              message: L10n.t(context, 'interests.emptyReceivedBody'),
            ),
          ),
        ),
      );
    }
    final liste = ListView.separated(
      shrinkWrap: widget.embedded,
      physics: widget.embedded
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: widget.embedded ? EdgeInsets.zero : const EdgeInsets.all(16),
      itemCount: _likes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final like = _likes[i];
        final profile = like.profile;
        final busy = _busyLikeId == like.likeId;
        // Gibt es mit dieser Person schon einen Funke? Dann gibt es
        // nichts zu bestaetigen (BEFUND 09.11.2026).
        final serverFunken =
            ref.watch(serverMatchesProvider).valueOrNull ?? const [];
        final hatFunke = serverFunken.any((m) => m.partner.id == profile.id);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: const Icon(
                      Icons.visibility_off,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    [
                      '${profile.name}, ${profile.age ?? '?'}',
                      if (profile.distanceKm > 0)
                        profile.distanceLabel((key) => L10n.t(context, key)),
                    ].join(' · '),
                  ),
                  subtitle: Text(
                    profile.introText.isNotEmpty
                        ? profile.introText
                        : L10n.t(context, 'interests.likedYou'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () =>
                      context.go(AppRoutes.profileDetailPath(profile.id)),
                  // Die Werkzeuge fuer die Person (NUTZERWUNSCH
                  // 01.11.2026). Die aktionsspezifischen Knöpfe
                  // stehen gleich darunter - hier kommen die
                  // allgemeinen (Profil, Melden, Blockieren), die es
                  // vorher nur bei den Funken gab.
                  trailing: _PersonenMenue(
                    personId: profile.id,
                    personName: profile.name,
                    aktiv: !busy,
                  ),
                ),
                if (profile.introAudioPath != null) ...[
                  const SizedBox(height: 8),
                  IntroAudioPlayer(targetUserId: profile.id),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    // AUSBLENDEN (BEFUND 07.11.2026: "Das Auge mit dem
                    // Strich ist like abgelehnt, aber man wuerde eher
                    // sowas wie ausblenden oder ignorieren darunter
                    // verstehen.").
                    //
                    // Das Auge hat IMMER "ausblenden" bedeutet - es rief
                    // aber das ABLEHNEN auf: die andere Person sah die
                    // Ablehnung. Jetzt blendet es nur aus (ignore_like,
                    // Migration 198) und laesst die andere Person in
                    // Ruhe.
                    IconButton(
                      icon: const Icon(Icons.visibility_off_outlined),
                      tooltip: L10n.t(context, 'interests.decline'),
                      onPressed: busy ? null : () => _ignoreLike(like),
                    ),
                    const SizedBox(width: 8),
                    // FUNKE BESTAETIGEN.
                    //
                    // BEFUND (09.11.2026, Betreiber): "Zurueck liken und
                    // Funke bestaetigen laeuft doch aufs selbe hinaus."
                    // **Das stimmt - und die Reihenfolge war es, die den
                    // Fehler verstaendlich machte.** Es gab hier zwei
                    // Knöpfe fuer dieselbe Person: "Zurueck liken" und
                    // "Funke bestaetigen".
                    //
                    // "Zurueck liken" rief `like_user` auf. Und diese
                    // Serverfunktion macht bei einem BEIDSEITIGEN Like
                    // SOFORT einen Funke (Migration 197, Zeile 127-136:
                    // "BEIDSEITIGER LIKE: jetzt entsteht der Funke"). Auf
                    // dieser Karte hat die andere Seite aber IMMER schon
                    // geliked - ein "Zurueck liken" erzeugte hier also
                    // immer genau denselben Funke wie der Knopf daneben.
                    //
                    // Der Kommentar an dem Knopf behauptete das Gegenteil
                    // ("ohne sofort einen Funken daraus zu machen") - der
                    // Server kann das gar nicht: bei einem beidseitigen
                    // Like gibt es nichts zu entscheiden.
                    //
                    // Der Knopf ist deshalb weg. Zwei Knöpfe, die dasselbe
                    // tun, sind schlimmer als einer: der Nutzer muss
                    // raten, welcher der richtige ist.
                    // BEFUND (09.11.2026, Betreiber): "Man kann nicht bei
                    // der selben Person einen Funken haben und ihn dann
                    // noch bestaetigen koennen."
                    //
                    // Wenn es den Funke schon gibt, gibt es nichts zu
                    // bestaetigen - der Knopf wuerde den Server nur
                    // erneut das Gleiche tun lassen. Stattdessen steht
                    // der Hinweis da.
                    if (hatFunke)
                      Expanded(
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            L10n.t(context, 'interests.alreadySpark'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () => _respond(like, accept: true),
                          // Kein Ladekreis im Knopf (NUTZERWUNSCH,
                          // 31.10.2026): der Ring war 16 px breit
                          // statt 24 px - die Knopfbreite sprang
                          // damit hin und her, und bei einem kurzen
                          // Vorgang war der Ring nur ein Blitzer.
                          //
                          // Das Symbol bleibt an seiner Stelle und
                          // atmet nur leiser. Die Breite bleibt
                          // konstant.
                          icon: _BusyIcon(
                            busy: busy,
                            child: const Icon(Icons.favorite),
                          ),
                          label: Text(
                            L10n.t(context, 'interests.sparkConfirmBtn'),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    // Eingebettet zieht die Seite den RefreshIndicator - ein zweiter
    // darin waere wirkungslos.
    if (widget.embedded) return liste;
    return RefreshIndicator(onRefresh: _load, child: liste);
  }
}

// ---------------------------------------------------------------------------
// Tab 3: Matches
// ---------------------------------------------------------------------------

class _MatchesTab extends ConsumerStatefulWidget {
  const _MatchesTab({this.embedded = false, super.key});

  /// Eingebettet: Der Abschnitt steht im Scrollbereich der Seite und
  /// scrollt deshalb nicht selbst (siehe [_OwnLikesTab.embedded]).
  final bool embedded;

  @override
  ConsumerState<_MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends ConsumerState<_MatchesTab>
    with RouteAware, WidgetsBindingObserver, _AutoReloadTab {
  List<MatchWithState> _serverMatches = [];
  bool _loading = true;

  /// Wurde die Liste mindestens einmal geladen?
  ///
  /// NUTZERWUNSCH (31.10.2026): "der kurze Ladekreis ist stoerend fuer
  /// die Animation dort". Der Kreis ersetzte beim Nachladen den GANZEN
  /// Inhalt - die Liste verschwand fuer einen Moment und kam als
  /// Kreis zurueck. Das ist kein Warten, das ist ein Schnitt.
  ///
  /// Deshalb gilt: der Platzhalter steht nur beim ERSTEN Laden, wenn
  /// es noch nichts zu zeigen gibt. Ab dann bleibt der Inhalt
  /// stehen und aktualisiert sich still im Hintergrund.
  bool _everLoaded = false;

  /// Chats verwalten (v0.8.0): Mehrfachauswahl + "Aus Liste entfernen".
  /// Ein-/Ausgang über das AppBar-Icon (NUTZERWUNSCH: weniger Platz);
  /// der Zustand lebt im [matchSelectModeProvider] (AppBar <-> Tab).
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    autoReloadInit();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    autoReloadSubscribe(context);
  }

  @override
  void dispose() {
    autoReloadDispose();
    super.dispose();
  }

  @override
  Future<void> reloadTab() => _load();

  /// Laedt neu - vom Pull-to-Refresh der Seite aufgerufen.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      _serverMatches = await service.listMatchesWithState();
      // 72-Stunden-Regel (Betreiber-Entscheidung): Aktive Funken, in denen
      // 72 h niemand geschrieben hat, wandern RUHIG unter "Erschlossene
      // Funken" - die App räumt auf, gibt die Verbindung aber nie ganz auf
      // (Re-Funke jederzeit möglich). Frisch entstandene Funken (z. B. aus
      // einem Zufallschat, der "nicht so gut lief") bleiben mindestens
      // 3 Tage aktiv - niemand soll zu schnell aufgeben.
      await _autoCoolStaleSparks();
      // Angesehen = Badge auf Aktuelles weg (v0.9.1, Seen-Tracking).
      final seenBox = ref.read(seenProvider.notifier);
      unawaited(seenBox.markMatchesSeen(_serverMatches.map((m) => m.matchId)));
      unawaited(
        seenBox.markQrSeen(
          ref.read(chatProvider).where((m) => m.isQrContact).map((m) => m.id),
        ),
      );
      ref.invalidate(serverMatchesProvider);
    } catch (e) {
      debugPrint('[Interessen] Matches laden fehlgeschlagen: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _everLoaded = true;
        });
      }
    }
  }

  /// Schwelle für die automatische Kühlung inaktiver Funken.
  static const Duration _autoCoolAfter = Duration(hours: 72);

  /// Kühlt aktive Funken ohne letzte Aktivität älter als [_autoCoolAfter]
  /// automatisch (status -> cooled via cool_match-RPC). Letzte Aktivität =
  /// letzte LOCALE Nachricht (E2E: der Server kennt Inhalte nie) oder,
  /// falls kein Verlauf existiert, die Match-Erstellung.
  Future<void> _autoCoolStaleSparks() async {
    if (!SupabaseService.isInitialized) return;
    final cutoff = DateTime.now().subtract(_autoCoolAfter);
    final stale = <MatchWithState>[];
    for (final m in _serverMatches) {
      if (m.status != 'active') continue;
      if (_lastSparkActivity(m).isBefore(cutoff)) stale.add(m);
    }
    if (stale.isEmpty) return;
    final staleIds = stale.map((m) => m.matchId).toSet();
    var cooledAny = false;
    for (final m in stale) {
      // Bereits gekühlt (Gegenseite war schneller) oder Netzwerkfehler:
      // ignorieren, beim nächsten Laden wird erneut geprüft.
      await bestEffort('findYourMatchServiceProvider.coolMatch', () async {
        await ref.read(findYourMatchServiceProvider).coolMatch(m.matchId);
        cooledAny = true;
      });
    }
    if (cooledAny && mounted) {
      // Lokal sofort umziehen (ohne erneuten Server-Roundtrip).
      _serverMatches = _serverMatches
          .where((m) => !staleIds.contains(m.matchId))
          .followedBy(
            stale.map(
              (m) => MatchWithState(
                matchId: m.matchId,
                partner: m.partner,
                unlockLevel: m.unlockLevel,
                failedAttempts: m.failedAttempts,
                createdVia: m.createdVia,
                status: 'cooled',
                createdAt: m.createdAt,
                resparkedAt: m.resparkedAt,
                passedAt: m.passedAt,
                lastAttemptAt: m.lastAttemptAt,
                autoMatch: m.autoMatch,
              ),
            ),
          )
          .toList();
    }
  }

  /// Zeitpunkt der letzten Aktivität eines Funkens: letzte lokale
  /// Nachricht, sonst der letzte RE-FUNKE (Karenzzeit, Migration 101 -
  /// ohne sie hätte die Auto-Kühlung jeden frisch entfachten Funken beim
  /// nächsten Laden sofort wieder gekühlt), sonst die Match-Erstellung.
  DateTime _lastSparkActivity(MatchWithState m) {
    final msgs = ref.read(chatProvider.notifier).messagesFor('${m.matchId}');
    var last = m.createdAt ?? DateTime.now();
    final resparked = m.resparkedAt;
    if (resparked != null && resparked.isAfter(last)) last = resparked;
    if (msgs.isNotEmpty && msgs.last.timestamp.isAfter(last)) {
      last = msgs.last.timestamp;
    }
    return last;
  }

  void _toggleSelect(int matchId) {
    setState(() {
      if (!_selected.add(matchId)) {
        _selected.remove(matchId);
      }
      if (_selected.isEmpty) {
        ref.read(matchSelectModeProvider.notifier).state = false;
      }
    });
  }

  Future<void> _hideSelected() async {
    final service = ref.read(findYourMatchServiceProvider);
    var failed = 0;
    for (final id in _selected) {
      try {
        await service.hideMatch(id);
      } catch (e) {
        debugPrint('[Interessen] hide fehlgeschlagen ($id): $e');
        failed++;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? L10n.tf(context, 'interests.hiddenCount', {
                    'n': '${_selected.length}',
                  })
                : L10n.tf(context, 'interests.hideFailed', {
                    'failed': '$failed',
                    'total': '${_selected.length}',
                  }),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    setState(() {
      _selected.clear();
    });
    ref.read(matchSelectModeProvider.notifier).state = false;
    _load();
  }

  /// Funke direkt in der Liste kühlen (v0.9.1): active -> cooled.
  ///
  /// Mit dem gleichen Ehrlich-Dialog wie im Chat (ruhig vs. Absage-Text).
  /// Ein gewählter Absage-Text geht E2E-verschlüsselt über das Relay raus
  /// (kein Chat nötig). Optimistisch SOFORT lokal auf "cooled" setzen (die
  /// App "merkt" es dadurch direkt, kein doppeltes Kühlen möglich);
  /// "bereits gekühlt" vom Server zählt als Erfolg statt Fehler.
  Future<void> _cool(MatchWithState match) async {
    if (match.cooled) {
      _load();
      return;
    }
    final choice = await showEndSparkDialog(context);
    if (choice == null || !mounted) return;
    final goodbye = goodbyeTextForChoice(context, choice);
    if (goodbye != null) {
      // Absage-Text ohne geöffneten Chat zustellen (Relay, best-effort).
      await bestEffort('relayServiceProvider.storeText', () async {
        await ref
            .read(relayServiceProvider)
            .storeText(peerId: match.partner.id, text: goodbye);
        if (SupabaseService.isInitialized) {
          await SupabaseService.client.functions.invoke(
            'notify-user',
            body: {'kind': 'messages', 'target_user_id': match.partner.id},
          );
        }
      });
      if (!mounted) return;
    }
    setState(() {
      _serverMatches = _serverMatches
          .map(
            (m) => m.matchId == match.matchId
                ? MatchWithState(
                    matchId: m.matchId,
                    partner: m.partner,
                    unlockLevel: m.unlockLevel,
                    failedAttempts: m.failedAttempts,
                    createdVia: m.createdVia,
                    status: 'cooled',
                    createdAt: m.createdAt,
                    resparkedAt: m.resparkedAt,
                    passedAt: m.passedAt,
                    lastAttemptAt: m.lastAttemptAt,
                    autoMatch: m.autoMatch,
                  )
                : m,
          )
          .toList();
    });
    try {
      await ref.read(findYourMatchServiceProvider).coolMatch(match.matchId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'interests.cooledDone', {
                'name': match.partner.name,
              }),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Bereits gekühlt (z. B. Doppel-Tap): kein Fehler, nur neu laden.
      if (e.toString().toLowerCase().contains('bereits gekuehlt')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                L10n.tf(context, 'interests.cooledDone', {
                  'name': match.partner.name,
                }),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'common.errorWith', {'error': '$e'}),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    _load();
  }

  /// Funke direkt in der Liste entfernen (ausblenden, nur für mich).
  /// Oeffnet den Chat zu einem Funken.
  ///
  /// Eigene Methode, weil der Ablauf jetzt an zwei Stellen gebraucht
  /// wird (fixierte Funken und die uebrigen): als gelesen markieren,
  /// als gesehen markieren, dann den Chat oeffnen. Push: Zurueck landet
  /// wieder exakt hier (gleicher Tab).
  void _openMatch(BuildContext context, WidgetRef ref, MatchWithState m) {
    ref.read(chatProvider.notifier).markRead(m.matchId.toString());
    unawaited(ref.read(seenProvider.notifier).markMatchesSeen([m.matchId]));
    context.push(AppRoutes.chatDetailPath(m.matchId.toString()));
  }

  /// Oeffnet einen Funken - bei einem automatisch entstandenen erst die
  /// EINMALIGE Rueckfrage (Migration 177).
  ///
  /// Der automatische Funke (Dating Hour nach 10 Minuten) ist nicht von
  /// beiden Seiten bestaetigt worden. Bevor der Chat aufgeht, fragt die
  /// App deshalb einmal nach: behalten oder Person entfernen.
  ///
  /// Die "einmalig" merkt sich die DATENBANK (matches.auto_match): nach
  /// "Behalten" setzt die RPC das Flag zurueck, nach "Person entfernen"
  /// ist der Funke geloescht. Beides wird hier nur noch lokal
  /// nachgezogen und beim naechsten Laden bestaetigt - eine zweite
  /// (lokale) Wahrheit gibt es nicht.
  Future<void> _openFunke(
    BuildContext context,
    WidgetRef ref,
    MatchWithState m,
  ) async {
    if (!m.autoMatch) {
      _openMatch(context, ref, m);
      return;
    }

    final antwort = await _frageAutoMatch(context);
    // Abgebrochen: weder der Chat geht auf noch aendert sich etwas.
    if (antwort == null || !context.mounted) return;

    if (antwort) {
      // BEHALTEN: der Hinweis verschwindet, der Chat geht danach auf.
      final ok = await _loeseAutoMatch(context, m, behalten: true);
      if (!context.mounted) return;
      if (ok) {
        _setzeAutoMatch(m, false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'dh.autoMatch.done')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      // Auch bei einem Fehler geht der Chat auf - die Frage soll den
      // Nutzer nicht blockieren.
      _openMatch(context, ref, m);
      return;
    }

    // PERSON ENTFERNEN: der Funke wird geloescht, der Chat bleibt zu.
    final ok = await _loeseAutoMatch(context, m, behalten: false);
    if (!context.mounted) return;
    if (ok) {
      setState(() {
        _serverMatches = _serverMatches
            .where((x) => x.matchId != m.matchId)
            .toList();
      });
      await _load();
      return;
    }
    // Fehler: die Person ist noch da. Der Chat geht trotzdem auf.
    _openMatch(context, ref, m);
  }

  /// Die einmalige Rueckfrage zum automatischen Funke (Migration 177).
  ///
  /// true = behalten, false = Person entfernen, null = abgebrochen.
  Future<bool?> _frageAutoMatch(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.auto_awesome,
          color: Theme.of(ctx).colorScheme.primary,
        ),
        title: Text(L10n.t(ctx, 'dh.autoMatch.title')),
        content: Text(L10n.t(ctx, 'dh.autoMatch.body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(L10n.t(ctx, 'dh.autoMatch.remove')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'dh.autoMatch.keep')),
          ),
        ],
      ),
    );
  }

  /// Loest die Rueckfrage zum automatischen Funke auf (Migration 177).
  ///
  /// p_keep = true: der Hinweis verschwindet, der Funke bleibt.
  /// p_keep = false: der Funke wird geloescht, die Person verschwindet.
  ///
  /// Rueckgabe: true = die Datenbank hat es angenommen.
  Future<bool> _loeseAutoMatch(
    BuildContext context,
    MatchWithState m, {
    required bool behalten,
  }) async {
    try {
      await SupabaseService.client.rpc(
        'resolve_dating_hour_auto_match',
        params: {
          // Die UUID der ANDEREN Person (nicht die eigene).
          'p_partner_id': m.partner.id,
          'p_keep': behalten,
        },
      );
      return true;
    } catch (e) {
      debugPrint('[Interessen] Auto-Funke aufloesen fehlgeschlagen: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'dh.autoMatch.failed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  /// Traegt die Entscheidung lokal nach (die Datenbank ist die Wahrheit).
  ///
  /// Ohne das bliebe das Sternchen bis zum naechsten Laden stehen.
  void _setzeAutoMatch(MatchWithState m, bool wert) {
    if (!mounted) return;
    setState(() {
      _serverMatches = _serverMatches
          .map(
            (x) => x.matchId == m.matchId
                ? MatchWithState(
                    matchId: x.matchId,
                    partner: x.partner,
                    unlockLevel: x.unlockLevel,
                    failedAttempts: x.failedAttempts,
                    createdVia: x.createdVia,
                    status: x.status,
                    createdAt: x.createdAt,
                    resparkedAt: x.resparkedAt,
                    passedAt: x.passedAt,
                    lastAttemptAt: x.lastAttemptAt,
                    kind: x.kind,
                    autoMatch: wert,
                  )
                : x,
          )
          .toList();
    });
  }

  /// Fixiert einen Funken (NUTZERWUNSCH, 28.10.2026: "fixieren").
  ///
  /// Lokal, nicht serverseitig: eine Fixierung ist eine Anordnung,
  /// keine Beziehung. Sie gehört dem Geraet, auf dem man sie macht.
  Future<void> _pin(MatchWithState match) async {
    final an = await ref
        .read(pinnedMatchesProvider.notifier)
        .umschalten(match.matchId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          L10n.t(
            context,
            an ? 'interests.pinSparkOn' : 'interests.pinSparkOff',
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Löscht einen Funken endgültig (NUTZERWUNSCH, 28.10.2026:
  /// "Funke löschen").
  ///
  /// Anders als "Archivieren" (kühlen) ist das endgültig: der
  /// Funke kann nicht wieder entzündet werden. Der Chat bleibt
  /// erhalten - es geht nur die Verbindung weg.
  Future<void> _delete(MatchWithState match) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'interests.deleteSparkTitle')),
        content: Text(L10n.t(ctx, 'interests.deleteSparkBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'interests.deleteSpark')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(findYourMatchServiceProvider).endMatch(match.matchId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'interests.deleteSparkDone')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.tf(context, 'common.errorWith', {'error': '$e'})),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _hide(MatchWithState match) async {
    try {
      await ref.read(findYourMatchServiceProvider).hideMatch(match.matchId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'interests.hiddenOne', {
                'name': match.partner.name,
              }),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'common.errorWith', {'error': '$e'}),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// "Re-Funke ohne Druck": gekühlte Verbindung mit einem Tap reaktivieren.
  Future<void> _respark(MatchWithState match) async {
    try {
      await ref.read(findYourMatchServiceProvider).resparkMatch(match.matchId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'interests.resparkDone', {
                'name': match.partner.name,
              }),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'interests.resparkFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Gespeichertes Profil (persistenter QR-Kontakt) entfernen - mit
  /// Bestätigung, da der zugehörige Chat/Verlauf mit verloren geht.
  Future<void> _deleteSavedProfile(
    BuildContext context,
    WidgetRef ref,
    Match contact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'interests.deleteSavedTitle')),
        content: Text(
          L10n.tf(ctx, 'interests.deleteSavedBody', {
            'name': contact.partner.name,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'intro.discardKeep')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(L10n.t(ctx, 'intro.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !ref.context.mounted) return;
    ref.read(chatProvider.notifier).deleteQrContact(contact.id);
    if (ref.context.mounted) {
      ScaffoldMessenger.of(ref.context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.tf(ref.context, 'profile.detail.savedRemoved', {
              'name': contact.partner.name,
            }),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // NUTZERWUNSCH "Verwalten funktioniert nicht richtig": Der Modus lebt
    // im Provider - der Tab muss ihn WATCHEN (sonst reagierte der
    // AppBar-Button nicht sichtbar) und bei Wechsel das Auswahl-Set
    // leeren.
    ref.listen<bool>(matchSelectModeProvider, (prev, next) {
      if (prev != next) setState(() => _selected.clear());
    });
    // QR-Kontakte sind nur lokal gespeichert (kein DB-Match).
    final qrContacts = ref
        .watch(chatProvider)
        .where((m) => m.isQrContact)
        .toList();
    final selectMode = ref.watch(matchSelectModeProvider);

    // v0.8.0: aktive Funken oben, gekühlte ("Erschlossene Funken") unten -
    // ohne Countdown, ohne Ablauf-Benachrichtigung, ohne Verlängerungsdruck.
    final activeMatches = _serverMatches
        .where((m) => m.status == 'active')
        .toList();
    final cooledMatches = _serverMatches
        .where((m) => m.status == 'cooled')
        .toList();

    // Fixierte Funken stehen oben (NUTZERWUNSCH, 28.10.2026:
    // "sowie Einstellungen haben, wie Funke löschen, fixieren,
    // archivieren"). Die Fixierung ist lokal - sie gehört dem
    // Geraet, nicht dem Konto.
    final gepinnt = ref.watch(pinnedMatchesProvider);
    final fixierteFunken = activeMatches
        .where((m) => gepinnt.contains(m.matchId))
        .toList();
    final uebrigeFunken = activeMatches
        .where((m) => !gepinnt.contains(m.matchId))
        .toList();
    // BEFUND (09.11.2026, Betreiber): "Zudem sollen Chats mit
    // ungelesenen Nachrichten hervorgehoben und oben in der Liste sein."
    //
    // Die ungelesenen Nachrichten stehen in der Chatliste (Match), nicht
    // in der Serverliste der Funken (MatchWithState) - der Abgleich
    // laeuft deshalb ueber die Partner-ID.
    final chatListe = ref.watch(chatProvider);
    int ungelesenVon(String partnerId) {
      for (final c in chatListe) {
        if (c.partner.id == partnerId) return c.unreadCount;
      }
      return 0;
    }

    // Die Fixierten stehen ohnehin in ihrem eigenen Abschnitt ganz oben
    // (NUTZERWUNSCH 28.10.2026). Innerhalb des uebrigen Abschnitts
    // kommen jetzt die Chats mit ungelesenen Nachrichten nach oben -
    // bei gleichem Stand der neueste zuerst.
    uebrigeFunken.sort((a, b) {
      final ua = ungelesenVon(a.partner.id);
      final ub = ungelesenVon(b.partner.id);
      if (ua != ub) return ub.compareTo(ua);
      final da = a.createdAt;
      final db = b.createdAt;
      if (da == null || db == null) return 0;
      return db.compareTo(da);
    });

    // Nur beim ersten Laden: ein ruhiger Platzhalter statt eines
    // kreisenden Rings. Beim Nachladen bleibt der Inhalt stehen -
    // das Aufblitzen des Rings unterbrach die Animation, in der das
    // Panel gerade aufgeht (NUTZERWUNSCH 31.10.2026).
    if (_loading && !_everLoaded) {
      return const CalmLoading();
    }
    if (_serverMatches.isEmpty && qrContacts.isEmpty) {
      if (widget.embedded) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: EmptyState(
            icon: Icons.auto_awesome,
            title: L10n.t(context, 'interests.emptySparksTitle'),
            message: L10n.t(context, 'interests.emptySparksBody'),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: EmptyState(
              icon: Icons.auto_awesome,
              title: L10n.t(context, 'interests.emptySparksTitle'),
              message: L10n.t(context, 'interests.emptySparksBody'),
            ),
          ),
        ),
      );
    }

    final liste = ListView(
      // v0.9.1-Fix (Android 16): Ohne AlwaysScrollable löst Pull bei
      // kurzer Liste nie aus - Tab 1/2 hatten die Physics, Tab 3 nicht.
      shrinkWrap: widget.embedded,
      physics: widget.embedded
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (_serverMatches.isNotEmpty) ...[
          // NUTZERWUNSCH: Der "Verwalten"-Textbutton nahm zu viel Platz
          // ein. Er lebt jetzt als Icon-Button in der AppBar (aktiver
          // Modus: Abbrechen + Zähler bleiben hier in der Zeile).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                if (selectMode) ...[
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _selected.clear();
                      });
                      ref.read(matchSelectModeProvider.notifier).state = false;
                    },
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(L10n.t(context, 'common.cancel')),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _selected.isEmpty ? null : _hideSelected,
                    icon: const Icon(Icons.visibility_off, size: 18),
                    label: Text(
                      L10n.tf(context, 'interests.hideSelected', {
                        'n': '${_selected.length}',
                      }),
                    ),
                  ),
                ] else ...[
                  const Spacer(),
                ],
              ],
            ),
          ),
        ],
        if (qrContacts.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.bookmark,
            title: L10n.t(context, 'interests.savedTitle'),
            subtitle: L10n.t(context, 'interests.savedSub'),
          ),
          ...qrContacts.map(
            (m) => ListTile(
              leading: GestureDetector(
                onTap: () =>
                    context.push(AppRoutes.profileDetailPath(m.partner.id)),
                child: const CircleAvatar(child: Icon(Icons.person)),
              ),
              title: Text('${m.partner.name}, ${m.partner.age}'),
              subtitle: Text(L10n.t(context, 'interests.savedTileSub')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.unreadCount > 0) Badge.count(count: m.unreadCount),
                  IconButton(
                    icon: const Icon(Icons.person_outline),
                    tooltip: L10n.t(context, 'profile.detail.aboutMe'),
                    onPressed: () =>
                        context.push(AppRoutes.profileDetailPath(m.partner.id)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: L10n.t(context, 'qr.savedDeleteTooltip'),
                    onPressed: () => _deleteSavedProfile(context, ref, m),
                  ),
                ],
              ),
              onTap: () {
                ref.read(chatProvider.notifier).markRead(m.id);
                // Gelesen + gesehen (Badges weg, v0.9.1).
                unawaited(ref.read(seenProvider.notifier).markQrSeen([m.id]));
                // Push: Zurück landet wieder exakt hier (gleicher Tab).
                context.push(AppRoutes.chatDetailPath(m.id));
              },
            ),
          ),
          const SizedBox(height: 8),
          const Divider(indent: 16, endIndent: 16),
        ],
        // Fixierte Funken stehen in ihrem eigenen Abschnitt ganz oben
        // (NUTZERWUNSCH, 28.10.2026: "fixieren").
        if (fixierteFunken.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.push_pin,
            title: L10n.t(context, 'interests.pinnedSection'),
            subtitle: L10n.t(context, 'interests.pinnedSub'),
          ),
          ...fixierteFunken.map(
            (m) => _MatchTile(
              match: m,
              pinned: true,
              onTap: () => _openFunke(context, ref, m),
              onProfile: () =>
                  context.push(AppRoutes.profileDetailPath(m.partner.id)),
              onCool: () => _cool(m),
              onHide: () => _hide(m),
              onPin: () => _pin(m),
              onDelete: () => _delete(m),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(indent: 16, endIndent: 16),
        ],
        if (uebrigeFunken.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.favorite,
            title: L10n.t(context, 'interests.sparksTitle'),
            subtitle: L10n.t(context, 'interests.matchesSub'),
          ),
          ...uebrigeFunken.map((m) {
            if (selectMode) {
              return CheckboxListTile(
                value: _selected.contains(m.matchId),
                onChanged: (_) => _toggleSelect(m.matchId),
                title: Text('${m.partner.name}, ${m.partner.age ?? '?'}'),
                secondary: const Icon(Icons.chat_bubble_outline),
              );
            }
            return _MatchTile(
              match: m,
              pinned: gepinnt.contains(m.matchId),
              // BEFUND (09.11.2026): Chats mit ungelesenen Nachrichten
              // sollen hervorgehoben sein.
              unreadCount: ungelesenVon(m.partner.id),
              // v0.9.0-Feedback: "Auf die Person klicken -> kommt direkt
              // das Kennenlern-Quiz" - jetzt öffnet die Kachel IMMER den
              // Chat; das Quiz ist als Button im Chat erreichbar (es
              // schaltet nur das Foto frei). Das Profil (inkl.
              // Vorstellung) ist über den Personen-Button erreichbar.
              // Kühlen/Entfernen geht direkt über das Menü (v0.9.1).
              // Push: Zurück landet wieder exakt hier (gleicher Tab).
              //
              // Bei einem automatisch entstandenen Funke kommt vorher
              // die einmalige Rueckfrage (Migration 177).
              onTap: () => _openFunke(context, ref, m),
              onProfile: () =>
                  context.push(AppRoutes.profileDetailPath(m.partner.id)),
              onCool: () => _cool(m),
              onHide: () => _hide(m),
              onPin: () => _pin(m),
              onDelete: () => _delete(m),
            );
          }),
        ],
        // "Erschlossene Funken" (v0.8.0): gekühlte Verbindungen, ganz
        // unten. KEIN Countdown, KEINE Ablauf-Benachrichtigung, KEINE
        // "jetzt verlängern!"-Aktion - nur der freiwillige Re-Funke.
        if (cooledMatches.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(indent: 16, endIndent: 16),
          _SectionHeader(
            icon: Icons.archive_outlined,
            title: L10n.t(context, 'interests.cooledTitle'),
            subtitle: L10n.t(context, 'interests.cooledSub'),
          ),
          ...cooledMatches.map(
            (m) => _CooledMatchTile(
              match: m,
              onOpen: () => _openFunke(context, ref, m),
              onProfile: () =>
                  context.push(AppRoutes.profileDetailPath(m.partner.id)),
              onRespark: () => _respark(m),
              onDelete: () => _delete(m),
            ),
          ),
        ],
      ],
    );

    // Eingebettet zieht die Seite den RefreshIndicator - ein zweiter
    // darin waere wirkungslos.
    if (widget.embedded) return liste;
    return RefreshIndicator(onRefresh: _load, child: liste);
  }
}

/// Kachel für "Erschlossene Funken" (status = cooled): gedimmt, mit
/// Re-Funke-Button (ein Tap, ohne Frist, ohne Benachrichtigung).
class _CooledMatchTile extends StatelessWidget {
  const _CooledMatchTile({
    required this.match,
    required this.onOpen,
    required this.onProfile,
    required this.onRespark,
    required this.onDelete,
  });

  final MatchWithState match;
  final VoidCallback onOpen;
  final VoidCallback onProfile;
  final VoidCallback onRespark;

  /// Endgültig löschen (NUTZERWUNSCH, 28.10.2026: "Funke
  /// löschen"). Bei einem archivierten Funke ist das die einzige
  /// Möglichkeit, ihn wegzuräumen - "Archivieren" waere
  /// sinnlos, er ist ja schon archiviert.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = match.partner;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: ListTile(
        onTap: onOpen,
        leading: GestureDetector(
          onTap: onProfile,
          child: const CircleAvatar(child: Icon(Icons.person_outline)),
        ),
        // NUTZERWUNSCH (31.10.2026): "Verifizierung soll fuer alle
        // Personen sichtbar sein" - auch in der Funken-Liste.
        title: Row(
          children: [
            Flexible(child: Text('${p.name}, ${p.age ?? '?'}')),
            if (p.isVerified) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: L10n.t(context, 'verify.badge'),
                child: Icon(
                  Icons.verified,
                  size: 18,
                  color: Colors.lightBlue.shade400,
                ),
              ),
            ],
            // Der automatische Funke (Migration 177) - auch hier sichtbar,
            // die Rueckfrage kommt beim Antippen.
            if (match.autoMatch) ...[
              const SizedBox(width: 6),
              const _AutoMatchBadge(),
            ],
          ],
        ),
        subtitle: Text(
          p.bio.isNotEmpty ? p.bio : L10n.t(context, 'interests.noBio'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: L10n.t(context, 'profile.detail.aboutMe'),
              onPressed: onProfile,
            ),
            FilledButton.tonalIcon(
              onPressed: onRespark,
              icon: const Icon(Icons.local_fire_department, size: 18),
              label: Text(L10n.t(context, 'interests.resparkBtn')),
            ),
            // Endgueltig loeschen (NUTZERWUNSCH, 28.10.2026).
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: L10n.t(context, 'interests.deleteSpark'),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Reiter ├╝ber einer aufklappbaren Blase.
///
/// Der Reiter bleibt beim ├ûffnen an seinem Platz, der Inhalt w├ñchst
/// darunter nach unten. Deshalb gibt es hier keinen TabController und
/// keine TabBarView - nur einen Zustand.
///
/// FORM (NUTZERWUNSCH 31.10.2026): "die beiden Buttons oben sollen
/// auch unten abgerundet bleiben und nicht unten eckig oben rund
/// sein". Vorher war der Reiter oben eine runde Kapuze und unten fast
/// eckig (Radius 14) - er sollte sich an die Blase anschliessen. Mit
/// der runden Blase darunter sah das aber nach zwei getrennten
/// Teilen aus, und der Reiter wirkte wie eine Haube.
///
/// Jetzt ist der Reiter eine Pille: oben UND unten gleich gerundet.
/// Die Blase darunter ist ebenfalls oben gerundet - die beiden Teile
/// lesen sich als ein Paar, nicht als Kappe plus Kasten.
/// Symbol, das bei einem laufenden Vorgang leise atmet.
///
/// Kein Ladekreis im Knopf (NUTZERWUNSCH 31.10.2026): der Ring war
/// 16 px breit statt 24 px - die Breite des Knopfes sprang damit
/// hin und her, und bei einem kurzen Vorgang (das Antworten auf einen
/// Like ist genau das) war der Ring nur ein Blitzer.
///
/// Das Symbol bleibt an seiner Stelle und wird nur etwas leiser. Die
/// Knopfbreite bleibt dadurch stabil, und die Bewegung ist ruhig.
class _BusyIcon extends StatefulWidget {
  const _BusyIcon({required this.busy, required this.child});

  final bool busy;
  final Widget child;

  @override
  State<_BusyIcon> createState() => _BusyIconState();
}

class _BusyIconState extends State<_BusyIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _BusyIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.busy && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    return AnimatedBuilder(
      animation: anim,
      child: widget.child,
      builder: (context, child) => Opacity(
        // Der Wert bleibt immer ueber 0 - ein ganz verschwindendes
        // Symbol wuerde wie ein Fehler aussehen.
        opacity: widget.busy ? 0.45 + 0.4 * anim.value : 1.0,
        child: child,
      ),
    );
  }
}

class _InterestPanelButton extends StatelessWidget {
  const _InterestPanelButton({
    required this.label,
    required this.icon,
    required this.open,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = open ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    // Feste Hoehe (siehe [_pillenHoehe]): der aufgeklappte Bereich
    // rueckt genau um _reiterUeberlappung darunter. Ohne feste Hoehe
    // waere die Ueberlappung von der Schriftgroesse abhaengig.
    return SizedBox(
      height: _pillenHoehe(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: open
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              // Pille: oben und unten gleich gerundet
              // (NUTZERWUNSCH 31.10.2026).
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: open
                    ? scheme.primary.withValues(alpha: 0.35)
                    : scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: open ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(Icons.keyboard_arrow_down, size: 18, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Blase unter den Reitern.
///
/// Der Inhalt startet direkt unter dem Reiter und schiebt die Funken
/// beim Aufklappen nach unten.
///
/// Die Ecken sind oben wie unten gerundet (NUTZERWUNSCH 31.10.2026):
/// Der Reiter ist jetzt eine Pille, und eine flach angeschlossene
/// Blase darunter passte nicht mehr dazu - die gerundete Unterseite
/// des Reiters stiesse auf die eckige Oberseite der Blase.
class _PanelBubble extends StatelessWidget {
  const _PanelBubble({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(20),
          bottom: Radius.circular(24),
        ),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      // GLEICHE HOEHE (NUTZERWUNSCH 01.11.2026: "Gesendet und
      // Erhalten sind die Pop up maessigen Fenster nicht gleich gross
      // nach unten").
      //
      // Die beiden Leertexte haben verschiedene Laenge, dadurch waren
      // die Fenster unterschiedlich hoch - und beim Wechsel ruckte
      // alles darunter nach. Die Mindesthoehe macht beide gleich
      // hoch, solange der Inhalt nicht ueber sie hinaus waechst.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 236),
        child: child,
      ),
    );
  }
}

/// Zentrierter Funken-Kopf: Symbol und Titel, kein Text daneben.
class _FunkenHeader extends StatelessWidget {
  const _FunkenHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // NEBENEINANDER statt untereinander (NUTZERWUNSCH 01.11.2026: "das
    // Funken Symbol und Funken zusammen untereinander etwas gross. Also
    // entweder irgendwie nebeneinander oder etwas kleiner machen").
    //
    // Beides: nebeneinander UND kleiner. Untereinander brauchte der
    // Kopf fast 100 px Hoehe - die Ueberschrift des Abschnitts war
    // groesser als die Ueberschriften der Listen darunter.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primaryContainer.withValues(alpha: 0.7),
          ),
          child: Icon(Icons.auto_awesome, size: 22, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        // Flexible: bei grosser Schriftgroesse waechst die Ueberschrift
        // ueber die Zeile hinaus (der Render-Test prueft 3,2-fache
        // Schriftgroesse) - ohne Flexible laeuft das Row ueber.
        Flexible(
          child: Text(
            L10n.t(context, 'interests.tabSparks'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dezentes Kennzeichen fuer einen automatisch entstandenen Funke
/// (Migration 177).
///
/// Der Funke kam nach 10 Minuten Dating Hour zustande, nicht durch ein
/// beidseitiges "Ja". Das Sternchen macht das kenntlich - der Tooltip
/// sagt, was es ist.
class _AutoMatchBadge extends StatelessWidget {
  const _AutoMatchBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: L10n.t(context, 'dh.autoMatch.badge'),
      child: Icon(
        Icons.auto_awesome,
        size: 16,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
      ),
    );
  }
}

class _MatchTile extends ConsumerWidget {
  const _MatchTile({
    required this.match,
    required this.onTap,
    required this.onProfile,
    required this.onCool,
    required this.onHide,
    required this.onPin,
    required this.onDelete,
    this.pinned = false,
    this.unreadCount = 0,
  });

  /// Wie viele Nachrichten von dieser Person ungelesen sind.
  ///
  /// BEFUND (09.11.2026): "Zudem sollen Chats mit ungelesenen
  /// Nachrichten hervorgehoben ... sein."
  final int unreadCount;

  final MatchWithState match;
  final VoidCallback onTap;
  final VoidCallback onProfile;
  final VoidCallback onCool;
  final VoidCallback onHide;

  /// Fixiert (NUTZERWUNSCH, 28.10.2026: "fixieren").
  final VoidCallback onPin;

  /// Endgültig löschen (NUTZERWUNSCH, 28.10.2026: "Funke
  /// löschen").
  final VoidCallback onDelete;

  /// Ist der Funke fixiert? Dann steht er oben und traegt eine Nadel.
  final bool pinned;

  /// Blockieren aus dem Funken-Menü (NUTZERWUNSCH): Gleicher Dialog und
  /// Ablauf wie im Chat (Bestätigung -> blockUser -> Funken-Tab).
  ///
  /// Die Arbeit macht [bestaetigeBlockieren] - die kann jede Person,
  /// nicht nur einen Funke. Vorher gab es diese Trennung, und genau
  /// deshalb war das Blockieren bei einem blossen Like nicht
  /// erreichbar (NUTZERWUNSCH 01.11.2026).
  Future<void> _confirmBlockTile(
    BuildContext context,
    WidgetRef ref,
    MatchWithState m,
  ) async {
    await bestaetigeBlockieren(context, ref, m.partner.id, m.partner.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = match.partner;
    // Quiz-Hinweis erst nach 50-70 Nachrichten (pro Chat deterministisch,
    // gleiche Schwelle wie im Chat-Screen).
    final threshold = 50 + (match.matchId.toString().hashCode.abs() % 21);
    final msgCount = ref
        .watch(chatProvider.notifier)
        .messagesFor(match.matchId.toString())
        .length;
    final showQuizHint =
        !match.quizPassed &&
        match.createdVia == 'find_match' &&
        msgCount >= threshold;
    final scheme = Theme.of(context).colorScheme;
    final ungelesen = unreadCount > 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      // BEFUND (09.11.2026, Betreiber): "Zudem sollen Chats mit
      // ungelesenen Nachrichten hervorgehoben ... sein." Der Rand und
      // die Flaeche faellen auf, solange ungelesene Nachrichten da sind.
      color: ungelesen ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      shape: ungelesen
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary, width: 1.5),
            )
          : null,
      child: ListTile(
        onTap: onTap,
        leading: GestureDetector(
          onTap: onProfile,
          child: CircleAvatar(
            radius: 28,
            child: match.quizPassed
                ? const Icon(Icons.person)
                : const Icon(Icons.visibility_off),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                [
                  '${p.name}, ${p.age ?? '?'}',
                  if (p.distanceKm > 0)
                    p.distanceLabel((key) => L10n.t(context, key)),
                ].join(' · '),
              ),
            ),
            // Die kleine Zahl der Nachrichten dieser Person.
            //
            // BEFUND (09.11.2026, Betreiber): "Außerdem soll mit einer
            // kleinen Zahl gekennzeichnet werden, wie viele Nachrichten
            // die Person geschrieben hat."
            if (msgCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$msgCount',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
            // Der automatische Funke (Migration 177): er kam nicht von
            // beiden Seiten zustande. Das Sternchen weist darauf hin -
            // die Rueckfrage kommt beim Antippen.
            if (match.autoMatch) ...[
              const SizedBox(width: 6),
              const _AutoMatchBadge(),
            ],
            // Die Nadel: der Funke ist fixiert und steht deshalb oben.
            if (pinned)
              Icon(
                Icons.push_pin,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            // KEINE Streaks/Flammen-Zählung (v0.9.0-Feedback).
          ],
        ),
        subtitle: Text(
          match.quizPassed
              ? L10n.t(context, 'interests.photoUnlocked')
              : showQuizHint
              ? L10n.t(context, 'interests.quizPending')
              : p.bio.isNotEmpty
              ? p.bio
              : L10n.t(context, 'interests.noBio'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // v0.9.1: Kein Bild-/Status-Icon mehr; die 3 Punkte stehen ganz
        // rechts.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: L10n.t(context, 'profile.detail.aboutMe'),
              onPressed: onProfile,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: L10n.t(context, 'chat.more'),
              onSelected: (value) {
                switch (value) {
                  case 'pin':
                    onPin();
                  case 'cool':
                    onCool();
                  case 'delete':
                    onDelete();
                  case 'hide':
                    onHide();
                  case 'report':
                    showReportUserDialog(
                      context: context,
                      ref: ref,
                      reportedUserId: p.id,
                      reportedUserName: p.name,
                    );
                  case 'block':
                    _confirmBlockTile(context, ref, match);
                }
              },
              itemBuilder: (ctx) => [
                // Fixieren (NUTZERWUNSCH, 28.10.2026: "fixieren").
                PopupMenuItem(
                  value: 'pin',
                  child: ListTile(
                    leading: Icon(
                      pinned ? Icons.push_pin_outlined : Icons.push_pin,
                    ),
                    title: Text(L10n.t(context, 'interests.pinSpark')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                // Archivieren (frueher "kühlen" - der Name war
                // missverstaendlich, der Funke wird ja nicht geloescht).
                PopupMenuItem(
                  value: 'cool',
                  child: ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: Text(L10n.t(context, 'interests.archiveSpark')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                // Endgueltig loeschen.
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    title: Text(L10n.t(context, 'interests.deleteSpark')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'hide',
                  child: ListTile(
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: Text(L10n.t(context, 'interests.hideOneBtn')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                // NUTZERWUNSCH: Melden/Blockieren auch im Funken-Menü.
                PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(L10n.t(context, 'profile.detail.reportUser')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: ListTile(
                    leading: const Icon(Icons.block, color: Colors.red),
                    title: Text(L10n.t(context, 'profile.detail.blockUser')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
