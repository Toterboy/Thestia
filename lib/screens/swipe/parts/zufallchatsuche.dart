// Die Methoden '_ZufallChatSuche'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../random_chat_screen.dart';

extension _ZufallChatSuche on _RandomChatScreenState {
  Future<void> _join() async {
    final service = ref.read(randomChatServiceProvider);
    if (service == null) {
      if (mounted) {
        _setzeState(() {
          _state = _RandomChatState.error;
          _errorKey = 'random.errorOffline';
        });
      }
      return;
    }

    // Ein Retry bei transientem RPC-Fehler, bevor die Fehlermeldung kommt
    // (z. B. Netzwerkwechsel kurz nach dem Screen-Öffnen).
    var session = await service.join();
    if (session == null) {
      await Future.delayed(const Duration(milliseconds: 1500));
      session = await service.join();
    }
    if (!mounted) return;

    if (session == null || session.sessionId == null) {
      _setzeState(() {
        _state = _RandomChatState.error;
        _errorKey = 'random.errorNoPartner';
      });
      return;
    }

    _sessionId = session.sessionId;
    if (session.isMatched) {
      _instantReconnect = true; // Reconnect auf (Alt-)Session.
      await _onMatched(session);
    } else {
      _instantReconnect = false;
      if (mounted) _setzeState(() => _state = _RandomChatState.searching);
      _startSearchPolling();
    }
  }

  Future<void> _onMatched(RandomChatSession session) async {
    _sessionId = session.sessionId;
    _partnerId = session.partnerId;
    if (mounted) _setzeState(() => _state = _RandomChatState.matched);

    // Partner-Profil laden (Name/Alter für die Anzeige). Best effort.
    if (_partnerId != null && SupabaseService.isInitialized) {
      try {
        final row = await SupabaseDatabaseService(
          SupabaseService.client,
        ).fetchPublicProfile(_partnerId!);
        if (row != null && mounted) {
          _setzeState(() {
            _partner = UserProfile(
              id: _partnerId!,
              name:
                  (row['name'] as String?) ??
                  L10n.t(context, 'random.fallbackPartnerName'),
              bio: '',
              interests: const [],
            );
          });
        }
      } catch (e) {
        debugPrint('[RandomChat] Profil laden fehlgeschlagen: $e');
      }
    }
    if (_partner == null && mounted) {
      _setzeState(() {
        _partner = UserProfile(
          id: _partnerId!,
          name: L10n.t(context, 'random.fallbackPartnerName'),
          bio: '',
        );
      });
    }

    await _initP2P();
    // Verbindungs-Deadline (Backstop - das ECHTE Scheitern meldet der
    // ICE-Listener früher): Instant-Reconnects (Match stand schon beim
    // join() fest) bekommen eine kürzere Frist.
    _handshakeDeadline = DateTime.now().add(
      Duration(seconds: _instantReconnect ? 15 : 25),
    );
    if (mounted) _setzeState(() => _state = _RandomChatState.chat);
    _startStatusPolling();
    // NUTZERWUNSCH: Keine Benachrichtigung, solange dieser Chat sichtbar
    // ist (Nachrichten erscheinen direkt auf dem Bildschirm). Die
    // Partner-ID dient dem Server-Push-Handler (Metadaten enthalten den
    // Absender), die Session-ID dem lokalen Nachrichtenpfad.
    _aktiveChatId.state = _sessionId ?? 'random';
    _aktiveChatPeerId.state = _partnerId;
  }

  void _startSearchPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final service = ref.read(randomChatServiceProvider);
      final sessionId = _sessionId;
      if (service == null || sessionId == null || !mounted) return;
      // Jeder Netzwerkfehler wuerde sonst als unhandled Async-Error aus
      // dem Timer-Callback herausfliegen - alle 2 s erneut, ohne Stopp.
      RandomChatSession? session;
      try {
        session = await service.getSession(sessionId);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[RandomChat] Such-Poll fehlgeschlagen: $e');
        }
        return;
      }
      if (!mounted || session == null) return;
      if (session.status == RandomChatStatus.ended) {
        _pollTimer?.cancel();
        if (_state != _RandomChatState.chat) {
          if (!_leaving && mounted && _rejoinCount < 5) {
            // Partner hat kurz gematcht und ist sofort wieder gegangen:
            // weitersuchen statt abbrechen (begrenzt gegen Loop).
            _rejoinCount++;
            _setzeState(() => _state = _RandomChatState.searching);
            await _join();
            return;
          }
          _setzeState(() => _state = _RandomChatState.error);
          _errorKey = 'random.errorUnavailable';
        }
        return;
      }
      if (session.isMatched) {
        _pollTimer?.cancel();
        await _onMatched(session);
      }
    });
  }

  /// Prüft regelmäßig, ob der Partner die Session verlassen hat - und
  /// versucht nebenbei den P2P-Handshake erneut, solange kein direkter
  /// Kanal steht (erstes Offer geht leicht ins Leere, wenn der Peer noch
  /// nicht subscribed ist). Läuft der Handshake trotz Retries in die
  /// Verbindungs-Deadline, wird ein sichtbarer Fehler gemeldet.
  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final service = ref.read(randomChatServiceProvider);
      final sessionId = _sessionId;
      if (service == null || sessionId == null || !mounted) return;
      RandomChatSession? session;
      try {
        session = await service.getSession(sessionId);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[RandomChat] Status-Poll fehlgeschlagen: $e');
        }
        return;
      }
      if (!mounted || session == null) return;
      if (session.status == RandomChatStatus.ended && !_leaving) {
        _statusTimer?.cancel();
        _showPartnerLeftDialog();
        return;
      }
      // Verbindungs-Timeout: DataChannel nie offen geworden. Der Chat wird
      // NICHT verlassen (Betreiber-Entscheidung) - stattdessen
      // RELAY-FALLBACK mit dem AKTUELLEN Partner: Nachrichten laufen
      // E2E-verschlüsselt über den Server (Mobilfunk/CGNAT ohne TURN).
      // Kommt der direkte Kanal später doch zustande, schaltet der Chat
      // automatisch zurück.
      final p2p = _p2p;
      if (p2p != null &&
          !p2p.isDataChannelOpen &&
          _handshakeDeadline != null &&
          DateTime.now().isAfter(_handshakeDeadline!)) {
        _handshakeDeadline = null;
        _enterRelayMode();
        return;
      }
      if (!_relayMode) {
        await _retryHandshakeThrottled();
      }
    });
  }
}
