// Der Teil '_MatchesTabState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

class _MatchesTabState extends ConsumerState<_MatchesTab>
    with RouteAware, WidgetsBindingObserver, _AutoReloadTab {
  List<MatchWithState> _serverMatches = [];
  bool _loading = true;

  /// Der Fehler des LETZTEN Ladevorgangs (null = alles in Ordnung).
  ///
  /// BEFUND (13.11.2026): Ohne diesen Zustand sah ein fehlgeschlagener
  /// Abruf aus wie "du hast keine Funken" - der Nutzer dachte, sein
  /// Funke sei verschwunden. Siehe [_load].
  Object? _loadError;

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
      // Der Abruf war erfolgreich - ein alter Fehler darf nicht stehen bleiben.
      _loadError = null;
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
      // BEFUND (13.11.2026, Betreiber: "Außerdem ist mein Funke
      // verschwunden"): Der Fehler wurde geschluckt, die Liste blieb
      // leer - und die App zeigte den LEERZUSTAND ("Noch keine
      // Funken"). Ein fehlgeschlagener Abruf sah damit genau aus wie
      // "dein Funke ist weg". Im Release-Build stand der Fehler nur im
      // Log (das debugPrint ist dort stumm).
      //
      // JETZT: Der Fehler wird sichtbar. Die Liste bleibt, wie sie war
      // (sie wird nicht geleert), und der Nutzer bekommt einen Hinweis
      // mit dem Knopf zum Wiederholen.
      debugPrint('[Interessen] Matches laden fehlgeschlagen: $e');
      _loadError = e;
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
          // MIT ZEITLIMIT (15.11.2026): ohne Grenze blieb der Aufruf
          // stehen - und der "Funke beenden"-Weg wartete darauf.
          await SupabaseService.rufeEdgeFunktion(
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
    // BEFUND (13.11.2026): Ein fehlgeschlagener Abruf sah aus wie
    // "du hast keine Funken" - der Nutzer dachte, sein Funke sei weg.
    // Der Fehler wird jetzt gezeigt (mit dem Knopf zum Wiederholen),
    // statt die Leere zu behaupten.
    if (_loadError != null && _serverMatches.isEmpty && qrContacts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: ErrorState(
              message: L10n.t(context, 'interests.sparksLoadFailed'),
              onRetry: _load,
            ),
          ),
        ),
      );
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
        // BEFUND (13.11.2026): Der Fehler bleibt auch sichtbar, wenn die
        // Liste noch Inhalt hat - der Nutzer soll wissen, dass der Stand
        // veraltet ist (und nicht nur, dass etwas fehlt).
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: 18,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        L10n.t(context, 'interests.sparksLoadFailed'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: Text(L10n.t(context, 'common.retry')),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
