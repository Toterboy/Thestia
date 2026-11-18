// Die Methoden '_ChatDialoge'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

extension _ChatDialoge on _ChatDetailScreenState {
  /// F: Startet einen Audio-Anruf. Öffnet den Anruf-Screen (Signaling + Audio
  /// laufen E2E-verschlüsselt über den bestehenden P2P-DataChannel).
  Future<void> _call() async {
    final match = _match;
    if (match == null) return;
    if (!mounted) return;
    if (ref.read(activeCallIdProvider) != null) return;
    // callId synchron reservieren (v0.9.1-Fix: sonst öffnet ein exakt
    // gleichzeitig eingehendes Invite einen zweiten Screen darüber).
    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    ref.read(activeCallIdProvider.notifier).state = callId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          partnerName: match.partner.name,
          peerId: match.partner.id,
          isIncoming: false,
          incomingCallId: callId,
        ),
      ),
    );
  }

  /// Zeigt vor der ersten Sprachnachricht die prominente Offenlegung.
  ///
  /// Google Play verlangt fuer RECORD_AUDIO, dass die App sichtbar
  /// erklaert, warum aufgenommen wird, BEVOR der Systemdialog erscheint.
  /// Ein Aufruf von `hasPermission()` mit anschliessendem Start reicht
  /// nicht: das Plugin fragt an, ohne dass vorher etwas gesagt wurde.
  ///
  /// `true` heisst: weitermachen darf. `false` heisst: nichts aufnehmen.
  /// Ein Nein wird nicht erinnert - wer zweimal ablehnt, wird nicht
  /// weiter gefragt.
  Future<bool> _ensureMicDisclosure() async {
    final settings = ref.read(settingsProvider);
    if (settings.micDisclosureAccepted) return true;
    if (!mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.t(context, 'chat.micDisclosureTitle')),
        content: Text(L10n.t(context, 'chat.micDisclosureBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(L10n.t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(L10n.t(context, 'chat.micDisclosureAccept')),
          ),
        ],
      ),
    );

    if (accepted != true) return false;
    await ref.read(settingsProvider.notifier).setMicDisclosureAccepted(true);
    return true;
  }

  /// Blendet das Date-Rad für diesen Chat dauerhaft aus.
  Future<void> _hideIdeaWheel() async {
    _setzeState(() => _ideaWheelHidden = true);
    await bestEffort('toList', () async {
      final storage = ref.read(localStorageProvider);
      final raw = await storage.getString(
        _ChatDetailScreenState._ideaWheelHiddenKey,
      );
      final hidden = <String>{
        if (raw != null && raw.isNotEmpty)
          ...(jsonDecode(raw) as List).map((e) => '$e'),
        widget.matchId,
      };
      await storage.saveString(
        _ChatDetailScreenState._ideaWheelHiddenKey,
        jsonEncode(hidden.toList()),
      );
    });
  }

  /// Lädt Server-Match + dismissed-Momente für die Herzensstärken.
  Future<void> _loadHeartState() async {
    final serverId = int.tryParse(widget.matchId);
    if (serverId == null || !SupabaseService.isInitialized) return;
    await bestEffort(
      'findYourMatchServiceProvider.listMatchesWithState',
      () async {
        final all = await ref
            .read(findYourMatchServiceProvider)
            .listMatchesWithState();
        _serverMatch = all.where((m) => m.matchId == serverId).firstOrNull;
      },
    );
    await bestEffort('toSet', () async {
      final storage = ref.read(localStorageProvider);
      final raw = await storage.getString(
        _ChatDetailScreenState._milestoneDismissedKey,
      );
      _milestoneDismissed = (jsonDecode(raw ?? '[]') as List)
          .map((e) => '$e')
          .toSet();
    });
    if (mounted) _setzeState(() {});
  }

  /// Lädt, ob das Date-Rad für diesen Chat ausgeblendet wurde.
  Future<void> _loadIdeaWheelHidden() async {
    await bestEffort('localStorageProvider.getString', () async {
      final raw = await ref
          .read(localStorageProvider)
          .getString(_ChatDetailScreenState._ideaWheelHiddenKey);
      if (raw == null || raw.isEmpty || !mounted) return;
      final hidden = (jsonDecode(raw) as List).map((e) => '$e').toSet();
      if (mounted && hidden.contains(widget.matchId)) {
        _setzeState(() => _ideaWheelHidden = true);
      }
    });
  }

  /// Prüft serverseitig, ob dieses Match noch quiz-gesperrt ist.
  Future<void> _loadQuizGate() async {
    final matchId = int.tryParse(widget.matchId);
    if (matchId == null) return; // Lokaler Kontakt (QR etc.): keine Sperre.
    try {
      final state = await ref.read(quizServiceProvider).getState(matchId);
      if (!mounted || state == null) return;
      if (state.quizGated != _quizGated) {
        _setzeState(() => _quizGated = state.quizGated);
      }
    } catch (e) {
      // Kein DB-Match (lokaler Kontakt) -> keine Sperre.
      debugPrint('[ChatDetail] Quiz-Gate prüfen fehlgeschlagen: $e');
    }
  }

  /// Bietet den Vergleich der Sicherheitsnummer aktiv an.
  ///
  /// DER GRUND (Audit 16.11.2026): Die Safety-Number-Pruefung gab es,
  /// sie war aber nur im Menue "Sicherheit" versteckt. Beim ersten
  /// Kontakt vertraut die App dem Identity-Key, den der Server
  /// ausliefert (TOFU) - ein kompromittierter Server kann ihn
  /// einschleusen, und ohne Hinweis faellt das niemandem auf. Der
  /// Hinweis bietet den Vergleich an (einmal je Kontakt).
  Future<void> _maybeOfferSafetyNumber() async {
    if (!mounted) return;
    // Der Partner kommt aus dem Provider (der Match wird beim Bauen
    // gesetzt - hier nicht ueber _match, das erst im Build gefuellt wird).
    final match = ref.read(chatProvider.notifier).getMatchById(widget.matchId);
    final partnerId = match?.partner.id;
    if (partnerId == null || partnerId.isEmpty) return;

    final encryption = ref.read(encryptionServiceProvider);
    // Ohne Schluessel (z. B. weil der Keystore nicht offen ist) gibt es
    // keine Sicherheitsnummer - dann gibt es auch keinen Hinweis.
    if (!encryption.bereit) return;
    if (!mounted) return;
    // Nur wenn es eine Sicherheitsnummer gibt (die Session steht) und
    // der Kontakt noch nicht bestaetigt ist.
    if (encryption.safetyNumberFor(partnerId) == null) return;
    if (encryption.isPeerIdentityVerified(partnerId)) return;
    if (encryption.safetyHintShown(partnerId)) return;
    await encryption.markSafetyHintShown(partnerId);
    if (!mounted) return;

    final name = match?.partner.name ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          L10n.tf(context, 'chat.safetyNumberHint', {'name': name}),
        ),
        action: SnackBarAction(
          label: L10n.t(context, 'chat.safetyNumberTooltip'),
          onPressed: () => _showSafetyNumberDialog(partnerId, name),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
      ),
    );
  }

  /// Zeigt beim ersten Chat einmalig den Hinweis auf den Hintergrund.
  ///
  /// v0.10.0: Der Hintergrund liess sich bisher nur ueber die Einstellungen
  /// oder die Einrichtung setzen. Wer direkt in einen Chat tappt, sah
  /// nie, dass es die Option gibt.
  ///
  /// Bewusst ein Dialog mit dem Picker statt eines Snackbars: die Auswahl
  /// braucht Platz, und ein Snackbar waere nach einer Sekunde weg, bevor
  /// jemand entschieden hat. "Spaeter" ist ein gleichwertiger Weg
  /// raus - der Hinweis kommt beim naechsten Chat wieder, aber erst,
  /// wenn jemand ihn wegklickt.
  Future<void> _maybeShowBackgroundHint() async {
    // Warten, bis die Einstellungen wirklich geladen sind. Sie kommen
    // asynchron aus dem Speicher - ohne dieses Warten sieht der Screen
    // nur die Vorgabewerte und zeigt den Dialog auch dann, wenn die
    // Person den Hintergrund schon gewaehlt und weggedrueckt hat.
    final settings = await ref.read(settingsProvider.notifier).whenLoaded();
    if (!mounted) return;
    if (settings.chatBackgroundSeen) return;

    // Der Dialog darf nicht im Dialog landen, wenn zwischen den Frames
    // schon einer aufgegangen ist (Schnelltippen durch die Liste).
    if (!mounted) return;

    final settingsNotifier = ref.read(settingsProvider.notifier);

    final gewaehlt = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        // scrollable: Der Inhalt (Text + Hintergrund-Auswahl) ist bei
        // grosser Systemschrift hoeher als der Dialog. Ohne
        // Scrollview laeuft die Column unten ueber (RenderFlex-Overflow).
        scrollable: true,
        title: Text(L10n.t(ctx, 'chatbg.hintTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(L10n.t(ctx, 'chatbg.hintBody')),
            const SizedBox(height: 16),
            // Feste Breite: der AlertDialog fragt sonst die intrinsische
            // Breite der Liste ab - und Flutter kann die nicht liefern
            // ("RenderViewport does not support returning intrinsic
            // dimensions"). Live im Emulator gesehen: der Dialog blieb
            // leer und der Chat-Bildschirm war unbrauchbar.
            const ChatBackgroundPicker(festeBreite: 260),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.later')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'common.done')),
          ),
        ],
      ),
    );

    // Auch bei "Spaeter" merken: sonst kommt derselbe Dialog bei jedem
    // Chat erneut, und das nervt schneller als der Hinweis selbst.
    await settingsNotifier.markChatBackgroundSeen();
    if (gewaehlt == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chatbg.hintDone')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Zeigt den Bestätigungsdialog zum Blockieren eines Nutzers
  /// (Bot-/Spam-Schutz, Migration 043).
  ///
  /// Serverseitig werden Likes in beide Richtungen und der Match gelöscht;
  /// künftige Interaktionen werden dauerhaft verhindert (bis zum Unblock).
  Future<void> _showBlockUserDialog(String peerId, String peerName) async {
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
        content: Text(L10n.tf(context, 'chat.blockBody', {'name': peerName})),
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

    if (confirmed != true || !mounted) return;

    try {
      await SupabaseDatabaseService(SupabaseService.client).blockUser(peerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'chat.blockedDone', {'name': peerName}),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Match wurde serverseitig gelöscht -> zurück zur Match-Liste
        // (Funken-Tab, v0.9.1).
        ref.read(interessenInitialTabProvider.notifier).state = 2;
        context.go(AppRoutes.interessen);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatDetail] Blockieren fehlgeschlagen: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'chat.blockFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Zeigt den Safety-Number-Dialog (E2E-Identitätsverifikation, Audit B2).
  ///
  /// Beide Chat-Partner sehen für ihre Session dieselbe Nummer. Sie wird
  /// out-of-band (persönlich/telefonisch) verglichen; stimmt sie überein,
  /// kann die Identität hier bestätigt werden. Ein unterschobenes PreKey-
  /// Bundle (kompromittierter Server) führt zu abweichenden Nummern.
  Future<void> _showSafetyNumberDialog(String peerId, String peerName) async {
    final encryption = ref.read(encryptionServiceProvider);
    await encryption.initialized;

    var verified = encryption.isPeerIdentityVerified(peerId);
    final safetyNumber = encryption.safetyNumberFor(peerId);
    // SECURITY (Audit 2026-09-26): Das `verified`-Flag wurde vorher nur
    // angezeigt, aber NIRGENDS ausgewertet. Der Schalter macht die
    // Out-of-Band-Bestaetigung praktisch erzwingbar.
    var requireVerified = encryption.requiresPeerVerification(peerId);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.verified_user_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(L10n.t(context, 'chat.safetyNumber'))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                safetyNumber == null
                    ? L10n.tf(context, 'chat.safetyNotConnected', {
                        'name': peerName,
                      })
                    : L10n.tf(context, 'chat.safetyCompare', {
                        'name': peerName,
                      }),
              ),
              if (safetyNumber != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    safetyNumber,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(L10n.t(context, 'chat.identityVerifiedTitle')),
                  subtitle: Text(L10n.t(context, 'chat.identityVerifiedHint')),
                  value: verified,
                  onChanged: (value) async {
                    await encryption.setPeerIdentityVerified(peerId, value);
                    setDialogState(() => verified = value);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(L10n.t(context, 'chat.requireVerifiedTitle')),
                  subtitle: Text(L10n.t(context, 'chat.requireVerifiedHint')),
                  value: requireVerified,
                  onChanged: (value) async {
                    await encryption.setRequiresPeerVerification(peerId, value);
                    if (ctx.mounted) {
                      setDialogState(() => requireVerified = value);
                    }
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L10n.t(context, 'chat.close')),
            ),
          ],
        ),
      ),
    );
  }
}
