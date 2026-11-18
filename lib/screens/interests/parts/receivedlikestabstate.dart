// Der Teil '_ReceivedLikesTabState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

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
