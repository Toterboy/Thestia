// Die Methoden '_ZufallChatVerbindung'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../random_chat_screen.dart';

extension _ZufallChatVerbindung on _RandomChatScreenState {
  /// Schaltet in den Relay-Fallback-Modus (kein direkter Kanal, z. B.
  /// Mobilfunk/CGNAT): Chat läuft E2E-verschlüsselt über den Server-Relay
  /// weiter. Vorher geschriebene Nachrichten (Outbox) werden nachgeliefert.
  void _enterRelayMode() {
    if (_leaving || !mounted || _sessionId == null || _partnerId == null) {
      return;
    }
    if (_relayMode) return;
    _statusTimer?.cancel();
    _setzeState(() {
      _relayMode = true;
      _state = _RandomChatState.chat;
    });
    // Diagnose sichtbar machen: Der Nutzer soll WISSEN, dass der Router
    // (AP-Isolation) oder das Mobilfunknetz die Direktverbindung blockiert.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'random.relayNoDirect')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
    final relayPeer = _partnerId!;
    final p2p = _p2p;
    if (p2p != null) {
      unawaited(
        p2p
            .drainOutboxViaRelay(
              (text) => ref
                  .read(relayServiceProvider)
                  .storeText(peerId: relayPeer, text: text),
            )
            .then((_) => unawaited(p2p.sendRelayPing())),
      );
    }
    _startRelayPolling();
  }

  Future<void> _fetchRelay() async {
    final peerId = _partnerId;
    if (peerId == null || !SupabaseService.isInitialized) return;
    // Netzwerkfehler: nächster Poll-Takt versucht es erneut.
    await bestEffort('relayServiceProvider.fetchPending', () async {
      // Nur Zeilen des AKTUELLEN Partners abholen/bestätigen.
      final pending = await ref
          .read(relayServiceProvider)
          .fetchPending(from: peerId);
      if (!mounted || pending.isEmpty) return;
      if (_relayBackoffStep != 0) {
        // Zustellung lief -> wieder schnell pollen.
        _relayBackoffStep = 0;
      }
      for (final r in pending) {
        final msgId = 'relay_${r.id}';
        if (_seenRelayIds.contains(msgId)) continue;
        _seenRelayIds.add(msgId);
        final msg = _localMessage(r.text, senderId: peerId);
        ref
            .read(chatProvider.notifier)
            .addMessage(_sessionId ?? 'random', msg, ref: ref);
      }
    });
  }

  /// Baut die E2E-P2P-Verbindung zum gematchten Partner auf.
  Future<void> _initP2P() async {
    final p2p = ref.read(p2pChatServiceProvider);
    _p2p = p2p;

    // Eigene ID strikt aus der Supabase-Session (Fix): Stale Secure-Store-
    // Werte (alter Account, Demo-'me') erzeugen ein Signaling-Topic, das
    // die echte auth.uid() nicht enthaelt -> Realtime-RLS verweigert den
    // Join und das Peer-Pinning verwirft jede Nachricht. Ohne Session
    // gibt es hier bewusst KEINEN Fallback mehr, sondern einen Fehler.
    final myId = SupabaseService.currentUser?.id;
    if (myId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'random.notLoggedIn')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    _myUserId = myId;
    final peerId = _partnerId!;

    _msgSub = p2p.incomingMessages.listen((text) {
      if (!mounted) return;
      final msg = _localMessage(text, senderId: peerId);
      ref
          .read(chatProvider.notifier)
          .addMessage(_sessionId ?? 'random', msg, ref: ref);
    });

    // Ehrlicher Verbindungsstatus: den echten DataChannel-Zustand
    // abbilden statt des Screen-States.
    _dcSub?.cancel();
    _dcSub = p2p.connectionState.listen((state) {
      if (!mounted) return;
      final open = state == RTCDataChannelState.RTCDataChannelOpen;
      if (open) {
        _handshakeDeadline = null; // Verbunden: Deadline obsolet.
        _rejoinCount = 0; // ECHT verbunden: Rejoin-Budget zurücksetzen.
        if (_relayMode) {
          // Upgrade: Direkter Kanal kam doch noch zustande (Partner
          // hat erneut verbunden) - zurück auf P2P, Relay-Polling stoppen,
          // Status-Polling neu starten (Fix: Partner-Left-Erkennung und
          // Retry liefen nach dem Upgrade sonst nie wieder).
          _relayMode = false;
          _relayTimer?.cancel();
          _relayTimer = null;
          _startStatusPolling();
        }
      }
      if (open != _dataChannelOpen) {
        _setzeState(() => _dataChannelOpen = open);
      }
    });

    // Sofort-Fallback: Meldet ICE definitives Scheitern (Failed), nicht
    // erst auf die ganze Deadline warten - Mobilfunk-Nutzer chatten
    // dann über den E2E-Relay, ohne die Wartezeit.
    _iceSub?.cancel();
    _iceSub = p2p.iceConnectionState.listen((state) {
      if (!mounted || _leaving) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _handshakeDeadline = null;
        _enterRelayMode();
      }
    });

    // Relay-Wake-up: Der Partner hat eine Relay-Nachricht hinterlegt -
    // sofort abholen statt auf den nächsten Poll-Takt zu warten.
    // LATENZ-FIX: Reaktion auch außerhalb des Relay-Modus - wer zuerst
    // in den Relay-Modus wechselt, muss nicht auf den ersten Poll des
    // Partners warten; der fetch ist mit from-Filter harmlos.
    _pingSub?.cancel();
    _pingSub = p2p.relayPing.listen((_) {
      if (mounted && !_leaving) {
        unawaited(_fetchRelay());
      }
    });

    try {
      await p2p.connect(myUserId: _myUserId!, peerId: peerId);
    } catch (e) {
      debugPrint('[RandomChat] P2P Verbindung fehlgeschlagen: $e');
      if (mounted) {
        // 404 = Partner-Gerät hat noch kein Schlüssel-Bundle veröffentlicht
        // (startet gerade erst die neue App-Version). KEIN harter Fehler:
        // freundlicher Wartezustand, die 25-s-Wiederholung verbindet
        // automatisch, sobald das Bundle da ist.
        final waitingForPartner = e.toString().contains('404');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              waitingForPartner
                  ? L10n.t(context, 'random.waitingForPartner')
                  : L10n.tf(context, 'random.connectFailed', {'error': '$e'}),
            ),
            behavior: SnackBarBehavior.floating,
            duration: waitingForPartner
                ? const Duration(seconds: 6)
                : const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Handshake-Retry, gedrosselt auf max. einen Versuch alle 25 Sekunden
  /// (nur im geöffneten Chat im Vordergrund). Im Relay-Modus aus: Der
  /// Chat läuft ohnehin, erneute P2P-Versuche kosten nur Akku/Requests.
  Future<void> _retryHandshakeThrottled() async {
    final p2p = _p2p;
    if (_relayMode) return;
    if (_state != _RandomChatState.chat || p2p == null || !mounted) return;
    if (p2p.isConnected) return;
    if (!SupabaseService.isInitialized) return;
    final myId = _myUserId;
    final peerId = _partnerId;
    if (myId == null || peerId == null) return;
    final now = DateTime.now();
    if (_lastHandshakeRetry != null &&
        now.difference(_lastHandshakeRetry!) < const Duration(seconds: 25)) {
      return;
    }
    _lastHandshakeRetry = now;
    try {
      await p2p.ensureConnected(myUserId: myId, peerId: peerId);
    } catch (e) {
      debugPrint('[RandomChat] Handshake-Retry fehlgeschlagen: $e');
    }
  }

  // ------------------------------------------------------------------ Chat --
  /// Läuft nur bei offenem Chat im Vordergrund.
  void _startRelayPolling() {
    _relayTimer?.cancel();
    _relayTimer = null;
    if (!mounted) return;
    final step = _relayBackoffStep.clamp(
      0,
      _RandomChatScreenState._relayIntervals.length - 1,
    );
    _relayTimer = Timer(_RandomChatScreenState._relayIntervals[step], () async {
      if (!mounted || _leaving || !_relayMode) return;
      final before = _relayBackoffStep;
      await _fetchRelay();
      if (!mounted || _leaving || !_relayMode) return;
      if (_relayBackoffStep == before &&
          _relayBackoffStep <
              _RandomChatScreenState._relayIntervals.length - 1) {
        _relayBackoffStep++;
      }
      _startRelayPolling();
    });
    unawaited(_fetchRelay());
  }
}
