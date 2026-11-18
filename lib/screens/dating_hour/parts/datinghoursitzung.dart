// Die Methoden '_DatingHourSitzung'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_chat_screen.dart';

extension _DatingHourSitzung on _DatingHourChatScreenState {
  Future<void> _createMatchAndNavigate(DatingHourSession session) async {
    // Siehe _handleDecision: ohne eigene User-ID gibt es keine Partner-ID.
    final myId = _currentUserId;
    if (myId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'common.errorOccurred'))),
        );
      }
      return;
    }
    final partnerId = session.getPeerId(myId);

    // v0.9.0-Fix (Gerätetest): Der Funke wurde vorher NUR LOKAL erzeugt
    // (Platzhalter 'Dein Gegenüber') - der Partner sah ihn nie, das Profil
    // war unbekannt und der Funke verschwand nach Neuinstallation. Jetzt:
    // serverseitiger Like -> bestehende Mutual-Like-Pipeline erzeugt das
    // kanonische Match (fuer BEIDE, samt Push), und das ECHTE Profil
    // wird geladen.
    //
    // NUTZERWUNSCH "Doppelte Funken": Der lokale addMatch legte parallel
    // zur Server-Pipeline einen ZWEITEN Funken mit anderer ID an (bei
    // gegenseitigem Liken). Jetzt: lokale Anlage NUR als Offline-Fallback,
    // wenn der Server-Like scheitert.
    var partnerProfile = UserProfile(
      id: partnerId,
      name: 'Dein Gegenüber',
      bio: '',
      interests: [],
    );
    var serverMatchOk = false;
    if (SupabaseService.isInitialized) {
      try {
        final fym = ref.read(findYourMatchServiceProvider);
        await fym.likeUser(partnerId);
        serverMatchOk = true;
        final row = await SupabaseDatabaseService(
          SupabaseService.client,
        ).fetchPublicProfile(partnerId);
        if (row != null) {
          partnerProfile = UserProfile.fromJson({
            'id': row['user_id'],
            'name': row['name'] ?? 'Dein Gegenüber',
            'bio': row['bio'] ?? '',
            'interests': row['interests'] ?? <dynamic>[],
            'photos': row['photos'],
            'gender': row['gender'],
            'birthDate': null,
          });
        }
      } catch (e) {
        debugPrint('[DH-Chat] Funke-Server-Sync fehlgeschlagen: $e');
      }
    }

    if (!serverMatchOk) {
      // Offline: lokaler Funke, damit der Chat nicht leer endet.
      ref.read(chatProvider.notifier).addMatch(partnerProfile, ref: ref);
    }

    if (mounted) {
      await FunkeOverlay.show(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'dh.chat.sparkJumped'))),
        );
      }
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        // Direkt auf den Funken-Tab (v0.9.1): sonst landet man auf
        // "Gesendet" und der neue Funke wirkt unsichtbar.
        bestEffortSync('containerOf.read', () {
          ProviderScope.containerOf(
            context,
          ).read(interessenInitialTabProvider.notifier).state = 2;
        });
        context.go(AppRoutes.interessen);
      }
    }
  }

  /// Beendet das Gespraech - von einer Seite aus, jederzeit.
  ///
  /// NUTZERWUNSCH 04.11.2026: "Wenn man das aber nicht will, kann
  /// die eine Seite ja jederzeit das Gespraech beenden und es gibt
  /// keinen automatischen Funke von beiden Seiten."
  Future<void> _endConversation() async {
    final service = ref.read(datingHourServiceProvider);
    final session = _session;
    if (session == null) return;

    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'dh.chat.endConversationTitle')),
        content: Text(L10n.t(ctx, 'dh.chat.endConversationBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'dh.chat.endConversation')),
          ),
        ],
      ),
    );
    if (bestaetigt != true || !mounted) return;

    try {
      await service.endConversation(widget.sessionId);
      if (!mounted) return;
      // Lokal nachziehen: der Server beendet die Session.
      await _loadSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'dh.chat.endConversationDone')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'common.errorOccurred')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _evaluateSessionOutcome() {
    final session = _session;
    if (session == null || !session.bothDecided) return;

    if (session.isMutualMatch) {
      _createMatchAndNavigate(session);
    } else if (session.isRejected) {
      _showRejectionMessage(_getDefaultRejectionMessage());
    }
  }

  /// Lädt das Alter des Chat-Partners (RPC get_public_profile, Migration
  /// 080 - Nachfolger der public_profiles-View; nur das Alter) und zeigt
  /// bei >= 10 Jahren Differenz einen Hinweis im Chat an.
  Future<void> _loadPartnerAge(DatingHourSession session) async {
    try {
      final myAge = ref.read(profileProvider).age;
      if (myAge == null) return;
      final myId = _currentUserId;
      if (myId == null) return;
      final peerId = session.getPeerId(myId);
      final row = await SupabaseService.client.rpc(
        'get_public_profile',
        params: {'p_user_id': peerId},
      );
      if (row == null) return;
      final partnerAge = ((row as Map)['age'] as num?)?.toInt();
      if (partnerAge == null || !mounted) return;
      _setzeState(() => _partnerAge = partnerAge);
      final diff = (myAge - partnerAge).abs();
      if (diff >= 10) {
        _setzeState(() => _ageWarningShown = true);
      }
    } catch (e) {
      debugPrint(
        '[DatingHourChat] Partner-Alter konnte nicht geladen werden: $e',
      );
    }
  }

  Future<void> _loadSession() async {
    final service = ref.read(datingHourServiceProvider);
    try {
      final session = await service.getSession(widget.sessionId);
      if (mounted) {
        _setzeState(() => _session = session);
      }
      // BEFUND (16.11.2026, gefunden von einem Test): Die eigene
      // User-ID wurde erst in `_initP2P` gesetzt - aber der Alters-
      // hinweis braucht sie VORHER. Er brach deshalb immer ab
      // (`myId == null`) und der RPC wurde nie aufgerufen: Der Hinweis
      // (bei zehn Jahren Unterschied oder mehr) kam **nie**.
      //
      // DER WEG: Die eigene ID wird hier geholt - vor beiden Wegen.
      _currentUserId ??= SupabaseService.currentUser?.id;
      // Partner-Alter laden (für den Altersdifferenz-Hinweis).
      if (session != null) {
        _loadPartnerAge(session);
      }
      // P2P-Verbindung zum Partner aufbauen, sobald die Session bekannt ist.
      if (session != null) {
        await _initP2P(session);
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'common.errorWith', {'error': e.message}),
            ),
          ),
        );
      }
    } catch (e) {
      // _loadSession wird unawaited aufgerufen und laeuft im Timer. Ein
      // Postgrest-/Socket-Fehler ist KEIN DatingHourException und wuerde
      // sonst unhandled aus dem Timer fliegen - alle 10 s erneut.
      debugPrint('[DatingHourChat] Session konnte nicht geladen werden: ');
    }
  }

  bool _shouldPollSession(DatingHourSession session) {
    // Nur pollen, wenn noch nicht final entschieden und der Timer läuft oder
    // gerade abgelaufen ist.
    if (session.isCompleted) return false;
    return true;
  }

  void _startTimer() {
    // V: Countdown basiert auf verifizierter Serverzeit, damit die 5 Minuten
    // manipulationssicher sind. Batterie/Netz schonen: Die Sekunden-Anzeige
    // läuft in eigenen Mini-Widgets (_PerSecond, nur sie rebuilden), dieser
    // Timer feuert die Ablauf-Logik und die Session-Abfrage alle
    // 10 Sekunden (vorher: VOLLER Screen-Rebuild JEDE Sekunde + RPC).
    // Sobald beidseitig entschieden ist, endet der Timer ganz (v0.9.1).
    var ticksSinceSync = 0;
    var slowTicks = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;

      final session = _session;
      if (session == null) return;
      if (session.bothDecided) {
        // Nach beidseitiger Entscheidung: Session-Polls stoppen, aber den
        // Relay-Abruf weiterlaufen lassen (Fix: sonst kommen späte
        // Nachrichten des Partners nie an, solange der Screen offen ist).
        slowTicks++;
        if (slowTicks % 3 == 0) {
          unawaited(_fetchRelay());
        }
        return;
      }

      // Wenn abgelaufen und noch keine Entscheidung angezeigt wird.
      if (session.isExpired && !_showDecision) {
        _showDecisionDialog();
      }

      // Die Fuenf-Minuten-Marke als mittiger Hinweis im Chat
      // (NUTZERWUNSCH 04.11.2026).
      //
      // Sie steht an der Position, an der die Fuenf Minuten
      // vorbeigegangen sind - alles, was danach geschrieben wird,
      // steht darunter. Der Ton ist bewusst sanft: es ist eine
      // Einladung, in Ruhe zu entscheiden, kein Countdown-Druck.
      if (session.isExpired && !_fiveMinuteNoticeShown) {
        _fiveMinuteNoticeShown = true;
        _zeigeFuenfMinutenHinweis(session);
      }

      // Während der Timer läuft, frischen wir den Session-Status im
      // Hintergrund auf, um gegenseitige Entscheidungen zu erkennen.
      // Zusätzlich (Relay-Fallback): Relay-Nachrichten des Partners alle
      // ~3 s abholen (LATENZ: war 5 s) und den P2P-Handshake alle ~25 s
      // erneut versuchen. Der Wake-up-Ping liefert sofort - der Timer
      // fängt nur verlorene Pings ab.
      slowTicks++;
      if (slowTicks % 3 == 0) {
        unawaited(_fetchRelay());
      }
      if (slowTicks % 25 == 0) {
        unawaited(_retryHandshakeThrottled());
      }
      ticksSinceSync++;
      if (ticksSinceSync >= 10 && _shouldPollSession(session)) {
        ticksSinceSync = 0;
        await _loadSession();
        _evaluateSessionOutcome();
      }
    });
  }
}
