// Die Methoden '_ChatNachrichten'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

extension _ChatNachrichten on _ChatDetailScreenState {
  /// Holt die "fuer alle geloescht"-Hinweise des Funkes und wendet sie an.
  ///
  /// BEFUND (11.11.2026): Der Empfaenger ersetzt die geloeschte Nachricht
  /// durch den Hinweis. Das passiert beim Oeffnen des Chats und bei jeder
  /// Relay-Abfrage (damit es auch im laufenden Gespraech ankommt).
  Future<void> _applyMessageDeletions(String matchId) async {
    final serverId = int.tryParse(matchId);
    if (serverId == null) return;
    if (!SupabaseService.isInitialized) return;
    // Der Hinweis-Text wird VOR dem await gelesen (nach dem await darf
    // der Context nicht mehr benutzt werden).
    final hinweis = L10n.t(context, 'chat.deletedNotice');
    try {
      final loeschungen = await ref
          .read(findYourMatchServiceProvider)
          .listMessageDeletions(serverId);
      if (loeschungen.isEmpty) return;
      var geaendert = false;
      for (final l in loeschungen) {
        final ok = ref
            .read(chatProvider.notifier)
            .applyDeletion(
              matchId,
              l.messageId,
              noticeText: hinweis,
              timestamp: l.deletedAt,
            );
        geaendert = geaendert || ok;
      }
      if (geaendert && mounted) _setzeState(() {});
    } catch (e) {
      debugPrint('[ChatDetail] Loeschungen nicht abrufbar: $e');
    }
  }

  /// Zaehlt die gesendete Nachricht serverseitig (BEFUND 11.11.2026).
  ///
  /// Damit die kleine Zahl in der Kachel auf ALLEN Geraeten stimmt und
  /// auch dann da ist, wenn der Chat hier nie geoeffnet wurde.
  ///
  /// Best-Effort: ein Fehler darf das Senden nie stoeren.
  Future<void> _bumpMessageCounter(Match match, String messageId) async {
    final serverId = int.tryParse(match.id);
    if (serverId == null) return;
    if (!SupabaseService.isInitialized) return;
    await bestEffort('findYourMatchService.bumpMessageCount', () async {
      await ref
          .read(findYourMatchServiceProvider)
          .bumpMessageCount(matchId: serverId, messageId: messageId);
    });
  }

  /// Darf diese Nachricht geloescht werden?
  ///
  /// BEFUND (11.11.2026): Nur EIGENE Textnachrichten. Der Server prueft
  /// das auch - aber die Oberflaeche soll es gar nicht erst anbieten.
  bool _canDeleteMessage(Message msg) {
    if (msg.type != MessageType.text) return false;
    final myId = _myUserId ?? AppConstants.currentUserId;
    if (myId.isEmpty) return false;
    return msg.senderId == myId;
  }

  /// Loescht eine Nachricht fuer alle (BEFUND 11.11.2026).
  ///
  /// ABLAUF:
  /// 1. Der Server markiert die Nachricht (er speichert NUR die Tatsache -
  ///    keinen Inhalt).
  /// 2. Lokal wird die Nachricht durch den Hinweis ersetzt.
  /// 3. Beim Empfaenger erscheint derselbe Hinweis, sobald er die
  ///    Loeschungen des Funkes abfragt.
  Future<void> _deleteMessageForAll(Message msg) async {
    final match = _match;
    if (match == null) return;
    final serverId = int.tryParse(match.id);
    if (serverId == null) {
      // QR-Kontakte haben keinen Server-Funke - dort gibt es kein
      // "fuer alle".
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.deleteForAllNotPossible')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // Der Text wird VOR dem await gelesen: nach dem await darf der
    // Context nicht mehr benutzt werden.
    final hinweis = L10n.t(context, 'chat.deletedNotice');
    try {
      await ref
          .read(findYourMatchServiceProvider)
          .deleteMessageForAll(matchId: serverId, messageId: msg.id);
      ref
          .read(chatProvider.notifier)
          .applyDeletion(match.id, msg.id, noticeText: hinweis);
      if (mounted) _setzeState(() {});
    } catch (e) {
      debugPrint('[ChatDetail] Loeschen fehlgeschlagen: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.deleteForAllFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Ruft die notify-user-Edge-Function für den Chat-Partner auf
  /// (nur Metadaten – kein Nachrichteninhalt). Best effort.
  ///
  /// Seit Audit H2 generiert der SERVER Titel/Text (Client kann keine
  /// Push-Inhalte mehr einschleusen – kein Push-Phishing möglich).
  Future<void> _notifyPeerAboutMessage(Match match) async {
    if (!SupabaseService.isInitialized) return;
    try {
      // MIT ZEITLIMIT (15.11.2026): ohne Grenze blieb der Aufruf
      // stehen und das Senden wartete auf ihn.
      await SupabaseService.rufeEdgeFunktion(
        'notify-user',
        body: {'kind': 'messages', 'target_user_id': match.partner.id},
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatDetail] Push-Benachrichtigung fehlgeschlagen: $e');
      }
    }
  }

  Future<void> _send() async {
    final match = _match;
    if (match == null) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final myId = _myUserId ?? AppConstants.currentUserId;
    _ctrl.clear();

    // Die ID kommt vom SENDER - damit kennen beide Seiten dieselbe
    // Nachricht (BEFUND 11.11.2026: "Nachricht fuer alle loeschen" geht
    // nur, wenn die ID auf beiden Seiten gleich ist).
    final msgId = Message.newId('m');
    final localMsg = Message(
      id: msgId,
      senderId: myId,
      receiverId: match.partner.id,
      text: text,
      timestamp: DateTime.now(),
    );
    ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);

    // BEFUND (13.11.2026, Test am Chat-Bildschirm): Der Bildschrim baute
    // erst NACH dem Senden neu - die eigene Nachricht war also erst zu
    // sehen, wenn der Netz-Roundtrip durch war. Bei langsamer Verbindung
    // (oder wenn das Relay haengt) sah der Nutzer seine eigene Nachricht
    // nicht: er dachte, es sei nichts angekommen, und schrieb sie
    // noch einmal.
    //
    // Der Neuaufbau gehoert deshalb direkt hinter das Hinzufuegen - die
    // Nachricht ist lokal da, also gehoert sie auch sofort auf den
    // Bildschirm. Der Versand laeuft danach weiter.
    if (mounted) _setzeState(() {});

    // … und ECHT E2E-verschlüsselt zustellen: direkt per P2P, sonst über
    // das Server-Relay (Partner holt beim Öffnen ab), sonst Outbox.
    await _transmitText(match, text, messageId: msgId);
    // Der Zaehler: die Zahl der gesendeten Nachrichten soll auf ALLEN
    // Geraeten stimmen (BEFUND 11.11.2026). Dazu zaehlt der Server -
    // genau einmal je Nachrichten-ID.
    unawaited(_bumpMessageCounter(match, msgId));
  }

  /// Sendet Text über drei Stufen (v0.9.1):
  ///   1. Direkt per P2P-DataChannel (wenn offen).
  ///   2. E2E-verschlüsselt über das Server-Relay (Partner holt beim
  ///      Öffnen des Chats ab - kein gleichzeitiges Online nötig).
  ///   3. Lokale Outbox (letzte Reserve, braucht später beide online).
  /// Inkl. Push-Metadaten und ehrlichem Zustands-Hinweis.
  Future<void> _transmitText(
    Match match,
    String text, {
    String kind = 'text',
    String? messageId,
  }) async {
    // DIE HULLE (BEFUND 11.11.2026): Die Nachrichten-ID des Senders
    // reist mit - damit kennen beide Seiten dieselbe Nachricht (Grundlage
    // fuer "fuer alle loeschen" und dafuer, dass dieselbe Nachricht
    // ueber P2P und Relay nicht doppelt erscheint).
    //
    // Die Huelle ersetzt den Eisbreker-Praefix: die Art steht jetzt im
    // Feld `art` der Huelle.
    final wireText = buildEnvelope(
      id: messageId ?? Message.newId('m'),
      kind: kind == 'icebreaker' ? WireKind.icebreaker : WireKind.text,
      text: text,
    );
    final p2p = _p2p;
    if (p2p != null) {
      final ueberP2p = await bestEffortOr(
        'p2p.trySendText',
        () async => await p2p.trySendText(wireText),
        false,
      );
      if (ueberP2p) {
        unawaited(_notifyPeerAboutMessage(match));
        return;
      }
    }
    // Kanal zu: Relay-Fallback (nur Ciphertext zum Server, E2E bleibt).
    final ueberRelay = await bestEffortOr(
      'relayServiceProvider.storeText',
      () async {
        // BEFUND (11.11.2026): Ueber das Relay muss DIE HULLE laufen,
        // nicht der blanke Text - sonst verliert der Relay-Weg die
        // Nachrichten-ID des Senders (und damit das "fuer alle
        // loeschen" und die Doppel-Erkennung zwischen P2P und Relay).
        await ref
            .read(relayServiceProvider)
            .storeText(peerId: match.partner.id, text: wireText, kind: kind);
        // Dual-Delivery-Schutz: trySendText oben hat bei geschlossenem Kanal
        // bereits in die Outbox eingereiht (mit icebreaker-Präfix!) - nach
        // erfolgreichem Relay-Store muss der Eintrag raus, sonst kommt die
        // Nachricht bei Kanalöffnung doppelt.
        p2p?.dequeueText(wireText);
        // Wake-up-Ping: Der Partner holt sofort ab statt aufs 5-s-Polling
        // zu warten (gleicher Mechanismus wie im Zufallschat).
        unawaited(p2p?.sendRelayPing());
        unawaited(_notifyPeerAboutMessage(match));
        // KEINE "zwischengespeichert"-SnackBar mehr (Fix: war bei jeder
        // Nachricht störend - die Nachricht kommt zuverlässig an, der
        // Nutzer braucht keinen Hinweis auf den Transportweg).
        return true;
      },
      false,
    );
    if (ueberRelay) return;
    // Letzte Reserve: Outbox (wird bei späterer Direktverbindung geflusht).
    await bestEffort('sendText', () async {
      await p2p?.sendText(wireText);
    });
    unawaited(_notifyPeerAboutMessage(match));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.queuedHint')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
