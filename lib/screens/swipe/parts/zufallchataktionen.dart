// Die Methoden '_ZufallChatAktionen'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unverändert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../random_chat_screen.dart';

extension _ZufallChatAktionen on _RandomChatScreenState {
  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'random.leaveTitle')),
        content: Text(L10n.t(ctx, 'random.leaveBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(L10n.t(ctx, 'random.leaveConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _leaving = true;
    final service = ref.read(randomChatServiceProvider);
    final sessionId = _sessionId;
    if (service != null && sessionId != null) {
      await service.leave(sessionId);
    }
    await _p2p?.disconnect();
    ref.read(chatProvider.notifier).dissolveMatch(sessionId ?? 'random');
    if (mounted) {
      context.go(AppRoutes.swipeModeSelection);
    }
  }

  /// Liken: markiert den Zufallspartner als gefallen.
  ///
  /// NUTZERWUNSCH "Doppelte Funken / einseitiger Funke": Der lokale
  /// Match-Eintrag entstand NUR auf der Likenden-Seite (einseitiger
  /// Funke) und bei gegenseitigem Liken sogar ZWEIMAL (lokal + Server-
  /// Pipeline). Jetzt: NUR der serverseitige Like - der Funke entsteht
  /// serverseitig in der Bestandspipeline, sobald BEIDE geliked haben
  /// (kanonisches Match für beide), nie einseitig und nie doppelt.
  Future<void> _likePartner() async {
    final partner = _partner;
    if (partner == null) return;
    if (SupabaseService.isInitialized) {
      try {
        await ref.read(findYourMatchServiceProvider).likeUser(partner.id);
      } catch (e) {
        debugPrint('[RandomChat] Server-Like fehlgeschlagen: $e');
      }
      // BEFUND (08.11.2026, Betreiber): "Keine doppelten Benachrichtigungen
      // für das Selbe." Der Push an die Person kommt vom DB-Trigger
      // (notify_push_trigger) - der Server-Like oben löst ihn aus. Ein
      // eigener Aufruf von notify-user erzeugte die ZWEITE Meldung.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'random.likeSentWaiting')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Push an die Gegenseite: es wartet eine Nachricht.
  ///
  /// Der Text wird serverseitig erzeugt - übertragen wird nur, dass
  /// etwas wartet (keine Inhalte).
  Future<void> _notifyPeerAboutMessage() async {
    final partnerId = _partnerId;
    if (partnerId == null) return;
    await bestEffort('invoke', () async {
      // MIT ZEITLIMIT (15.11.2026): ohne Grenze blieb der Aufruf
      // stehen und das Senden wartete auf ihn.
      await SupabaseService.rufeEdgeFunktion(
        'notify-user',
        body: {'kind': 'messages', 'target_user_id': partnerId},
      );
    });
  }

  // ------------------------------------------------------------- Relay --
  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    if (_partnerId == null || _myUserId == null) {
      // Allein in der Warteschlange (Test mit nur einem Konto) oder ohne
      // Session: still verwerfen statt irreführendem Sende-Fehler.
      return;
    }
    _ctrl.clear();

    final local = _localMessage(text, senderId: _myUserId!);
    ref
        .read(chatProvider.notifier)
        .addMessage(_sessionId ?? 'random', local, ref: ref);

    // Relay-Modus (kein direkter Kanal, z. B. Mobilfunk): E2E-verschlüsselt
    // über den Server-Relay zustellen statt über den DataChannel. Danach
    // Wake-up-Ping an den Partner (sofortige Zustellung statt Polling).
    if (_relayMode) {
      try {
        await ref
            .read(relayServiceProvider)
            .storeText(peerId: _partnerId!, text: text);
        unawaited(_p2p?.sendRelayPing());
        // NUTZERWUNSCH "Nachrichten ohne Chat-Screen": Push an die Person,
        // dass eine Nachricht wartet (serverseitig generierter Text, nur
        // Metadaten; Beziehung = aktive Zufallschat-Session, Migration im
        // notify-user-Update).
        unawaited(_notifyPeerAboutMessage());
      } catch (e) {
        debugPrint('[RandomChat] Relay-Send fehlgeschlagen: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'random.sendFailed')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      return;
    }

    // BEFUND (07.11.2026, Betreiber): Im Zufallschat kam keine
    // Nachricht an ("Zufallschat ohne Nachrichten").
    //
    // DER GRUND: Der Zufallschat sendete AUSSCHLIESSLICH über den
    // P2P-DataChannel. Der Relay-Fallback gab es nur, wenn der Bildschirm
    // schon im Relay-Modus war - der wird aber erst eingeschaltet, wenn
    // ICE DEFINITIV gescheitert ist. In der Zeit davor (der Handshake
    // dauert, und ohne TURN-Server kommt er oft nicht zustande) landete
    // die Nachricht in der Outbox: der Absender sah sein Echo, der
    // Partner nichts.
    //
    // Jetzt derselbe Dreistufen-Weg wie im normalen Chat:
    //   1. P2P-DataChannel (wenn offen),
    //   2. E2E-verschlüsselter Server-Relay,
    //   3. lokale Outbox als letzte Reserve.
    final p2p = _p2p;
    if (p2p != null) {
      final ueberP2p = await bestEffortOr(
        'p2p.trySendText',
        () async => await p2p.trySendText(text),
        false,
      );
      if (ueberP2p) {
        unawaited(_notifyPeerAboutMessage());
        return;
      }
    }

    // Kanal zu: über den E2E-Relay zustellen.
    final ueberRelay = await bestEffortOr(
      'relayServiceProvider.storeText',
      () async {
        await ref
            .read(relayServiceProvider)
            .storeText(peerId: _partnerId!, text: text);
        // Dual-Delivery-Schutz: trySendText hat die Nachricht bei
        // geschlossenem Kanal bereits eingereiht - nach erfolgreichem
        // Relay-Store muss der Eintrag raus, sonst kommt sie bei einer
        // späteren Kanalöffnung doppelt.
        p2p?.dequeueText(text);
        unawaited(p2p?.sendRelayPing());
        unawaited(_notifyPeerAboutMessage());
        return true;
      },
      false,
    );
    if (ueberRelay) return;

    // Letzte Reserve: die Outbox. Die Nachricht geht raus, sobald der
    // Kanal steht.
    await bestEffort('sendText', () async {
      await p2p?.sendText(text);
    });
    unawaited(_notifyPeerAboutMessage());
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

  void _showPartnerLeftDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'random.endedTitle')),
        content: Text(L10n.t(context, 'random.partnerLeft')),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) context.go(AppRoutes.swipeModeSelection);
            },
            child: Text(L10n.t(context, 'random.backToDiscover')),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- UI --
}
