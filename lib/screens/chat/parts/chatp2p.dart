// Die Methoden '_ChatP2p'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unverändert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

extension _ChatP2p on _ChatDetailScreenState {
  /// Bootstrapping in richtiger Reihenfolge:
  ///   1. Lokales Match sicherstellen (Server-Matches aus dem Funken-Tab
  ///      existieren sonst NUR serverseitig -> "Dieser Chat existiert
  ///      nicht mehr", v0.9.0-Fix).
  ///   2. P2P-Verbindung aufbauen (braucht das lokale Match).
  ///   3. Partner-Profil nachladen (QR-Kontakte: Name "Unbekannt").
  ///   4. Offline gescannter Kontakt: Like nachholen (der QR-Scan erzeugt
  ///      nur bei Online den Like - beim späteren Öffnen nachholen).
  Future<void> _bootstrap() async {
    // Opt-in-Verlauf ZUERST laden (Fix "Verlauf wird nicht direkt
    // geladen"): lokal & sofort. Vorher lief die Hydration ganz am ENDE -
    // hinter dem (ggf. Sekunden dauernden oder scheiternden) P2P-Connect
    // und dem Relay-Fetch, der Chat blieb entsprechend lange leer.
    await ref.read(chatProvider.notifier).hydrateHistory(widget.matchId);
    await _ensureLocalMatch();
    // BEFUND (09.11.2026): Der Ungelesen-Zähler wird jetzt geführt
    // (vorher NIE erhöht). Beim Öffnen des Chats wird er zurückgesetzt
    // - die Nachrichten im Chat sind ja gelesen.
    ref.read(chatProvider.notifier).markRead(widget.matchId);
    // BEFUND (15.11.2026, gefunden von einem Test): Der P2P-Aufbau darf
    // die RUHE-Schritte nicht blockieren. Ein hängender Connect (z. B.
    // ein HTTP-Aufruf ohne Antwort im Mobilfunk) ließ den ganzen
    // Bootstrap stehen - damit kamen die RELAY-Nachrichten nicht an,
    // das Partnerprofil wurde nicht nachgeladen und der
    // Eisbrecher-Vorschlag startete nie.
    //
    // DER WEG: Der P2P-Aufbau bekommt eine Grenze. Nach 20 Sekunden
    // geht es ohne Direktverbindung weiter - der Chat läuft dann über
    // das Relay, und der Handshake wird später nachgezogen
    // (_retryHandshakeThrottled).
    await _initP2P().timeout(
      const Duration(seconds: 20),
      onTimeout: () => debugPrint(
        '[ChatDetail] P2P-Aufbau hat nicht geantwortet - weiter ueber Relay.',
      ),
    );
    await _loadPartnerProfileIfNeeded();
    await _ensureLikeForSavedContact();
    // Relay-Nachrichten sofort abholen (Partner hat ggf. bei fehlendem
    // P2P-Kanal zwischengespeichert).
    await _fetchRelay();
    // Die "für alle gelöscht"-Hinweise holen (BEFUND 11.11.2026).
    await _applyMessageDeletions(widget.matchId);
    // Herzensstärken: Server-Match-Daten (Freundschafts-Badge,
    // Erinnerungs-Momente) im Hintergrund laden.
    unawaited(_loadHeartState());
    // 5-Minuten-Stille-Vorschlag starten (nur frischer Chat ohne eigene
    // Nachricht, siehe _maybeSuggestIcebreaker).
    unawaited(_maybeSuggestIcebreaker());
    // Der Hinweis auf die Sicherheitsnummer (Audit 16.11.2026) - erst
    // jetzt: der Partner ist bekannt.
    unawaited(_maybeOfferSafetyNumber());
  }

  /// Hebt die Markierungen "dieser Chat ist gerade sichtbar" auf.
  ///
  /// Getrennt von [dispose], weil dort `ref` nicht mehr benutzt werden
  /// darf. Vor super.dispose() aufgerufen ist es erlaubt.
  void _clearActiveChatFlags() {
    // Über die Notifier (im initState geholt): im dispose() ist `ref`
    // nicht mehr benutzbar - der Aufruf würfe sonst.
    //
    // DER WEG (18.11.2026, gefunden von einem Test): Das Rücksetzen muss
    // einen Frame warten. Wird der Bildschirm während eines
    // Routenwechsels abgeräumt (der Nutzer geht in den Chat eines
    // anderen), passiert das dispose() MITTEN IM AUFBAU - und Riverpod
    // verbietet das Ändern eines Providers während des Aufbaus ("Tried
    // to modify a provider while the widget tree was building"). Die
    // Markierung blieb dann stehen: die Meldungen des Partners kamen
    // nicht an.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bestEffortSync('aktiven Chat freigeben', () {
        if (_aktiveChatId.state == widget.matchId) {
          _aktiveChatId.state = null;
        }
        if (_aktiveChatPeerId.state == _activePeerId) {
          _aktiveChatPeerId.state = null;
        }
      });
    });
  }

  /// Offline gescannter Kontakt (gespeichertes Profil): Beim späteren
  /// Öffnen des Chats holen wir das versäumte Like nach - der Funke
  /// entsteht, sobald die Person annimmt. Best-Effort, mehrfach-fähig
  /// (like_user ist idempotent).
  Future<void> _ensureLikeForSavedContact() async {
    final match = ref.read(chatProvider.notifier).getMatchById(widget.matchId);
    if (match == null || !match.isQrContact) return;
    if (!SupabaseService.isInitialized) return;
    try {
      // BEFUND (08.11.2026, Betreiber): "Keine doppelten Benachrichtigungen
      // für das Selbe." Der Push kommt vom DB-Trigger
      // (notify_push_trigger) - der Like-Insert löst ihn aus. Ein eigener
      // Aufruf von notify-user erzeugte die ZWEITE Meldung.
      await ref.read(findYourMatchServiceProvider).likeUser(match.partner.id);
    } catch (e) {
      debugPrint('[ChatDetail] Nachträgliches Like fehlgeschlagen: $e');
    }
  }

  /// Auflösung von Matches, die es lokal noch nicht gibt: Bei einer
  /// numerischen Match-ID (Server-Match) wird list_my_matches_with_state
  /// geladen und das Match lokal mit derselben ID wiederhergestellt.
  Future<void> _ensureLocalMatch() async {
    final notifier = ref.read(chatProvider.notifier);
    if (notifier.getMatchById(widget.matchId) != null) return;
    final id = int.tryParse(widget.matchId);
    if (id == null || !SupabaseService.isInitialized) return;
    try {
      final service = ref.read(findYourMatchServiceProvider);
      final matches = await service.listMatchesWithState();
      final server = matches.where((x) => x.matchId == id).firstOrNull;
      if (server == null || !mounted) return;
      notifier.restoreServerMatch(
        widget.matchId,
        server.partner,
        server.createdAt ?? DateTime.now(),
      );
      if (mounted) _setzeState(() {});
    } catch (e) {
      debugPrint('[ChatDetail] Server-Match laden fehlgeschlagen: $e');
    }
  }

  /// Baut die echte P2P-Verbindung zum Partner auf und leitet eingehende
  /// (bereits entschlüsselte) Nachrichten in den lokalen Chat-Verlauf.
  Future<void> _initP2P() async {
    final match = ref.read(chatProvider.notifier).getMatchById(widget.matchId);
    if (match == null) return;
    _p2p = ref.read(p2pChatServiceProvider);
    // NUTZERWUNSCH: Notification-Unterdrückung braucht die Partner-ID
    // (Server-Push-Metadaten enthalten den Absender, nicht die Match-ID).
    _activePeerId = match.partner.id;
    _aktiveChatPeerId.state = _activePeerId;
    // Eigene ID strikt aus der Supabase-Session (Fix): Stale Secure-Store-
    // Werte (alter Account, Demo-'me') erzeugen ein Signaling-Topic, das
    // die echte auth.uid() nicht enthält -> Realtime-RLS verweigert den
    // Join und das Peer-Pinning verwirft jede Nachricht.
    _myUserId = SupabaseService.isInitialized
        ? SupabaseService.currentUser?.id
        : null;
    if (_myUserId == null || _myUserId!.isEmpty) {
      debugPrint('[ChatDetail] Keine Supabase-Session - P2P übersprungen.');
      return;
    }

    // Verbindungsstatus LIVE spiegeln (v0.9.1-Fix): Bisher wurde
    // _p2pConnected nur EINMAL direkt nach connect() gelesen - zu dem
    // Zeitpunkt ist ICE praktisch nie fertig, sodass Badge und
    // Relay-Karte dauerhaft "keine direkte Verbindung" zeigten, obwohl
    // der Kanal Sekunden später aufging.
    _connSub?.cancel();
    _connSub = _p2p!.connectionState.listen((_) {
      if (!mounted) return;
      final open = _p2p?.isConnected ?? false;
      if (open != _p2pConnected) {
        _setzeState(() => _p2pConnected = open);
      }
    });

    // Relay-Wake-up: Der Partner hat eine Relay-Nachricht hinterlegt -
    // sofort abholen statt auf den 5-s-Poll-Takt zu warten.
    _relayPingSub?.cancel();
    _relayPingSub = _p2p!.relayPing.listen((_) {
      if (mounted) unawaited(_fetchRelay());
    });

    // Probleme beim Verbindungsaufbau (06.11.2026): Die internen
    // Meldungen des WebRTC-Service gingen nur in den Debug-Log - im
    // Store-Build war damit nicht zu sehen, WORAN der Aufbau
    // scheiterte. Der letzte Eintrag steht jetzt in der Diagnosezeile.
    _problemSub?.cancel();
    _problemSub = _p2p!.problems.listen((problem) {
      if (!mounted) return;
      _setzeState(() => _lastP2pProblem = problem);
    });

    // Textnachrichten abonnieren. Nachrichten mit Eisbrecher-Präfix werden
    // als gemeinsame mittige Bubble dargestellt (v0.9.1, beide Seiten).
    _msgSub = _p2p!.incomingMessages.listen((text) {
      if (!mounted) return;
      // DIE HULLE auspacken (BEFUND 11.11.2026): Die ID kommt vom
      // SENDER. Damit ist dieselbe Nachricht über P2P und Relay erkennbar
      // (kein Doppel-Eintrag) und "für alle löschen" erreicht auch die
      // andere Seite.
      final draht = parseEnvelope(text);
      final msgId = draht.fromNewFormat ? draht.id : Message.newId('p2p');
      if (_seenMessageIds.contains(msgId)) return;
      _seenMessageIds.add(msgId);
      final msg = Message(
        id: msgId,
        senderId: match.partner.id,
        receiverId: _myUserId ?? AppConstants.currentUserId,
        text: draht.text,
        timestamp: DateTime.now(),
        type: draht.kind == WireKind.icebreaker
            ? MessageType.icebreaker
            : MessageType.text,
      );
      ref.read(chatProvider.notifier).addMessage(match.id, msg, ref: ref);
    });

    // Binärdaten (Bilder, Audio) abonnieren.
    _binarySub = _p2p!.incomingBinary.listen((record) {
      final data = record.data;
      final contentType = record.contentType;
      final metadata = record.metadata;
      if (!mounted) return;
      final msgId = Message.newId('p2p_bin');
      if (_seenMessageIds.contains(msgId)) return;
      _seenMessageIds.add(msgId);

      final isVoice = contentType.startsWith('audio/');
      if (isVoice) {
        final duration = (metadata?['durationSeconds'] as int?) ?? 0;
        _writeVoiceFile(msgId, data).then((path) {
          if (!mounted || path == null) return;
          final msg = Message(
            id: msgId,
            senderId: match.partner.id,
            receiverId: _myUserId!,
            text: '',
            timestamp: DateTime.now(),
            mediaUrl: path,
            durationSeconds: duration,
            type: MessageType.voice,
          );
          ref.read(chatProvider.notifier).addMessage(match.id, msg, ref: ref);
        });
      } else {
        // Image: base64-data-URI.
        final mediaUrl = 'data:image/jpeg;base64,${base64Encode(data)}';
        final msg = Message(
          id: msgId,
          senderId: match.partner.id,
          receiverId: _myUserId!,
          text: '',
          timestamp: DateTime.now(),
          mediaUrl: mediaUrl,
          type: MessageType.image,
        );
        ref.read(chatProvider.notifier).addMessage(match.id, msg, ref: ref);
      }
    });

    try {
      await _p2p!.connect(myUserId: _myUserId!, peerId: match.partner.id);
      if (mounted) _setzeState(() => _p2pConnected = _p2p!.isConnected);
    } catch (e) {
      // Audit H-7/E-4: Der Peer hat einen ANDEREN Identity-Key als beim
      // ersten Kontakt -> Session wird blockiert statt still aufgebaut.
      if (e.toString().contains('peer_identity_changed')) {
        await _showIdentityChangedDialog(match.partner.id);
        return;
      }
      // v0.9.0-Feedback ("es gab einen P2P Fehler"): Wenn die andere Seite
      // (noch) nicht im Chat ist, scheitert das Signal-Setup - das ist
      // NORMAL und kein Fehler. Der orange E2E-Badge zeigt den Zustand;
      // die Verbindung kommt zustande, sobald beide gleichzeitig online
      // sind. Nur ein ruhiger Hinweis, keine Fehlermeldung.
      // Der Kurz-Fehler landet zusätzlich in der aufgeklappten
      // Relay-Karte (Diagnose statt Logcat-Suche).
      debugPrint('[ChatDetail] P2P-Verbindung noch nicht offen: $e');
      if (mounted) {
        _setzeState(() {
          _p2pConnected = false;
          _lastP2pError = _ChatDetailScreenState._shortError(e);
        });
      }
    }

    // Eingehende Anrufe (invite) abonnieren. Der Anruf-Screen wird nur
    // geöffnet, wenn gerade kein anderer Anruf aktiv ist.
    _callControlSub = _p2p!.callControl.listen((payload) {
      if (!mounted) return;
      final type = payload['type'] as String?;
      if (type != 'invite') return;
      // Leere/fremde callIds verwerfen (keine Ghost-Calls).
      final callId = payload['callId'] as String?;
      if (callId == null || callId.isEmpty) return;
      if (ref.read(activeCallIdProvider) != null) {
        // Bereits im Anruf: ablehnen statt zweiten Screen zu öffnen.
        _p2p?.sendCallControl({'type': 'decline', 'callId': callId});
        return;
      }
      // Synchron reservieren, damit keine zweite Einladung dazwischenfunkt.
      ref.read(activeCallIdProvider.notifier).state = callId;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            partnerName: match.partner.name,
            peerId: match.partner.id,
            isIncoming: true,
            incomingCallId: callId,
          ),
        ),
      );
    });
  }

  /// Das Partner-Profil wird IMMER vom Server nachgeladen (v0.9.1-Fix:
  /// vorher nur bei "Unbekannt" - dadurch fehlten bei bestehenden Kontakten
  /// Vorstellungstext und Audio-Pfad und die Vorstellung war weder sichtbar
  /// noch anhörbar). Lokale Daten bleiben Fallback bei Fehlschlag.
  Future<void> _loadPartnerProfileIfNeeded() async {
    final match = ref.read(chatProvider.notifier).getMatchById(widget.matchId);
    if (match == null) return;
    if (!SupabaseService.isInitialized) return;
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final row = await db.fetchPublicProfile(match.partner.id);
      if (row == null || !mounted) return;
      final real = UserProfile.fromPublicView(
        Map<String, dynamic>.from(row as Map),
      );
      ref.read(chatProvider.notifier).updatePartner(widget.matchId, real);
      if (mounted) _setzeState(() {});
    } catch (e) {
      debugPrint('[ChatDetail] Partner-Profil-Refresh fehlgeschlagen: $e');
    }
  }

  /// Audit H-7/E-4: Dialog bei Peer-Identity-Wechsel. Der Nutzer muss dem
  /// neuen Schlüssel explizit zustimmen (Safety-Number-Vergleich), bevor
  /// die Session neu aufgebaut wird - kein stiller MITM-Accept mehr.
  Future<void> _showIdentityChangedDialog(String partnerId) async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'chat.safetyChangedTitle')),
        content: Text(L10n.t(context, 'chat.safetyChangedBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(context, 'chat.safetyChangedCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(context, 'chat.safetyChangedAccept')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      // Alten Trust + Session-Cache verwerfen, dann erneut verbinden.
      await ref.read(encryptionServiceProvider).resetPeerTrust(partnerId);
      ref.read(preKeyServiceProvider).forget(partnerId);
      await _p2p?.connect(myUserId: _myUserId!, peerId: partnerId);
      if (mounted) _setzeState(() => _p2pConnected = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'chat.reconnectStillFailing')),
          ),
        );
      }
    }
  }
}
