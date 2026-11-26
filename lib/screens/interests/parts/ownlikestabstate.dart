// Der Teil '_OwnLikesTabState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

class _OwnLikesTabState extends ConsumerState<_OwnLikesTab>
    with RouteAware, WidgetsBindingObserver, _AutoReloadTab {
  List<ReceivedLike> _likes = [];
  bool _loading = true;

  /// Wurde die Liste mindestens einmal geladen?
  ///
  /// NUTZERWUNSCH (31.10.2026): "der kurze Ladekreis ist störend für
  /// die Animation dort". Der Kreis ersetzte beim Nachladen den GANZEN
  /// Inhalt - die Liste verschwand für einen Moment und kam als
  /// Kreis zurück. Das ist kein Warten, das ist ein Schnitt.
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

  /// Lädt neu - vom Pull-to-Refresh der Seite aufgerufen.
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
      // keine eigene RefreshIndicator und keine 60 %-Bildschirmhöhe
      // (das wäre ein riesiger Leerraum in der Mitte).
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
      // scrollen, sonst hätte man zwei Scrollbereiche ineinander.
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
                  // für alle Personen sichtbar sein" - auch in der
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
                  // Die Werkzeuge für die Person (NUTZERWUNSCH
                  // 01.11.2026): "Die Bearbeitungstools auf der
                  // Interessen Seite sehe ich auch nicht ... entfernen,
                  // blockieren, melden ... usw."
                  //
                  // Vorher stand hier nur ein X (Like zurücknehmen).
                  // Blockieren und Melden waren ausschließlich bei
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
    // darin wäre wirkungslos (und würde beim Ziehen kämpfen).
    if (widget.embedded) return liste;
    return RefreshIndicator(onRefresh: _load, child: liste);
  }
}
