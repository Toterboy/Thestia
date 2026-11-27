// Die Methoden '_ChatEisbrecher'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unverändert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

extension _ChatEisbrecher on _ChatDetailScreenState {
  /// Gemeinsame Interessen mit dem Chat-Partner (für den
  /// Kontext-Icebreaker-Chip, v0.8.0).
  List<String> _commonInterests() {
    final match = _match;
    if (match == null) return const [];
    final mine = ref.read(profileProvider).interests.toSet();
    return match.partner.interests.where(mine.contains).toList();
  }

  /// Die Ideen des Rads (mit den Sync-Ideen).
  ///
  /// DER SYNC-TEIL (Plan 0.11.0, "Begegnung statt Bildschirm"): Die
  /// Sync-Ideen kommen IMMER mit - unabhängig von der Distanz. Wer
  /// 400 km entfernt wohnt, kann kein "Koch-Duell" am selben Tisch
  /// machen - aber beide kochen zur selben Zeit.
  List<({String text, SyncDateIdee? syncIdee})> _localizedMeetIdeas(
    BuildContext context,
  ) => [
    for (final key in _ChatDetailScreenState._meetIdeaCategories)
      (text: L10n.t(context, key), syncIdee: null),
    for (final idee in SyncDateIdee.values)
      (text: L10n.t(context, idee.textKey), syncIdee: idee),
  ];

  /// 5-Minuten-Stille-Vorschlag (Nutzerwunsch "Icebreaker-Vorschlag an
  /// beide nach 5 Minuten ohne Nachricht"): Hat der Nutzer in diesem
  /// frischen Funken-Chat nach 5 Minuten noch nichts geschrieben, wird
  /// EINMALIG eine zufällige Eisbrecher-Frage zum Senden angeboten.
  /// Die Gegenseite bekommt denselben Vorschlag lokal, sobald sie den
  /// Chat mit ebenfalls leerem Verlauf öffnet (beide Geräte werten
  /// dieselbe Regel aus - kein Server nötig).
  Future<void> _maybeSuggestIcebreaker() async {
    final match = _match;
    final myId = _myUserId;
    if (match == null || myId == null || !mounted) return;
    // Nur wenn ICH noch nichts geschrieben habe (empfangene zählen
    // nicht - dann läuft das Gespräch bereits).
    final sent = ref
        .read(chatProvider.notifier)
        .messagesFor(match.id)
        .any((m) => m.isFrom(myId));
    if (sent) return;
    // Einmalig je Match (Prefs).
    final schonVorgeschlagen = await bestEffortOr(
      'localStorageProvider.getString',
      () async {
        final storage = ref.read(localStorageProvider);
        final raw = await storage.getString(
          _ChatDetailScreenState._icebreakerSuggestedKey,
        );
        final done = (jsonDecode(raw ?? '[]') as List).map((e) => '$e').toSet();
        return done.contains(match.id);
      },
      false,
    );
    if (schonVorgeschlagen) return;
    _icebreakerSuggestTimer?.cancel();
    _icebreakerSuggestTimer = Timer(const Duration(minutes: 5), () async {
      if (!mounted) return;
      final current = _match;
      final myIdNow = _myUserId;
      if (current == null || myIdNow == null) return;
      if (ref
          .read(chatProvider.notifier)
          .messagesFor(current.id)
          .any((m) => m.isFrom(myIdNow))) {
        return; // Inzwischen geschrieben - kein Vorschlag nötig.
      }
      // Als gezeigt vermerken (auch bei "Später" - kein Nerven).
      await bestEffort('toList', () async {
        final storage = ref.read(localStorageProvider);
        final raw = await storage.getString(
          _ChatDetailScreenState._icebreakerSuggestedKey,
        );
        final done = (jsonDecode(raw ?? '[]') as List).map((e) => '$e').toSet();
        done.add(current.id);
        await storage.saveString(
          _ChatDetailScreenState._icebreakerSuggestedKey,
          jsonEncode(done.toList()),
        );
      });
      if (!mounted) return;
      // Zufällige Frage aus dem Katalog (Sprache des Geräts).
      final lang = Localizations.localeOf(context).languageCode;
      final all = [for (final c in icebreakerCatalog) ...c.questions];
      if (all.isEmpty) return;
      all.shuffle();
      final question = all.first.textFor(lang);
      final send = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.lightbulb_outline, size: 40),
          title: Text(L10n.t(ctx, 'chat.icebreakerSuggestTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.t(ctx, 'chat.icebreakerSuggestBody')),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '„$question"',
                  style: Theme.of(
                    ctx,
                  ).textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(L10n.t(ctx, 'chat.icebreakerSuggestLater')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(L10n.t(ctx, 'chat.icebreakerSuggestSend')),
            ),
          ],
        ),
      );
      if (send == true && mounted) {
        await _sendIcebreakerQuestion(question);
      }
    });
  }

  /// Eisbrecher-Sammlung im Chat (vom "mehr"-Menü, NUTZERWUNSCH): Frage
  /// auswählen -> direkt als gemeinsame mittige Bubble senden. Für
  /// QR-Kontakte (keine Server-ID) mit Hinweis statt tot aufhören.
  Future<void> _openIcebreakerCollection() async {
    final serverId = int.tryParse(widget.matchId);
    if (serverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.spiceUnavailable')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final picked = await context.push<String>(
      AppRoutes.spiceQuestionsPath(serverId),
    );
    if (picked != null && picked.trim().isNotEmpty && mounted) {
      _sendIcebreakerQuestion(picked);
    }
  }

  /// Sendet eine E2E-Nachricht auf Basis der gemeinsamen Interessen.
  ///
  /// v0.9.1-Fix ("Icebreaker Button geht nicht"): Vorher stilles return,
  /// wenn [_myUserId] noch null war (P2P-Init läuft asynchron) oder [_p2p]
  /// null - ohne Feedback wirkte der Button funktionslos. Jetzt Fallback-ID,
  /// fehlender P2P-Hinweis und Queue-Hinweis bei offline Partner.
  Future<void> _sendContextIcebreaker(String interest) async {
    final match = _match;
    if (match == null) return;
    final myId = _myUserId ?? AppConstants.currentUserId;
    final text = L10n.tf(context, 'chat.icebreakerText', {
      'interest': interest,
    });
    final localMsg = Message(
      id: Message.newId('local'),
      senderId: myId,
      receiverId: match.partner.id,
      text: text,
      timestamp: DateTime.now(),
    );
    ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
    await _transmitText(match, text);
    if (mounted) _setzeState(() {});
  }

  /// Sendet eine Eisbrecher-Frage als GEMEINSAME mittige Bubble (v0.9.1):
  /// Beide Seiten sehen dieselbe Frage in der Chat-Mitte; sie wandert wie
  /// jede Nachricht mit.
  Future<void> _sendIcebreakerQuestion(String question) async {
    final match = _match;
    final text = question.trim();
    if (match == null || text.isEmpty) return;
    final myId = _myUserId ?? AppConstants.currentUserId;
    final localMsg = Message(
      id: Message.newId('local_ice'),
      senderId: myId,
      receiverId: match.partner.id,
      text: text,
      timestamp: DateTime.now(),
      type: MessageType.icebreaker,
    );
    ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
    await _transmitText(match, text, kind: 'icebreaker');
    if (mounted) _setzeState(() {});
  }

  // Ideen-Rad (v0.8.0): die bestehenden Date-Kategorien des Meet-Intents,
  // lokalisiert (l10n-Keys 'chat.idea.*').
  /// Herzensstärken (Idee 5): Gemeinsame Erinnerungsliste (Bucket List)
  /// als Bottom Sheet - beide Seiten können Einträge hinzufügen, abhaken
  /// und eigene löschen. Bei Stillstand (14 Tage) erscheint ein sanfter
  /// Hinweis oben im Sheet.
  Future<void> _showBucketListSheet() async {
    final serverId = int.tryParse(widget.matchId);
    if (serverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.spiceUnavailable')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final partnerName = _match?.partner.name ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => BucketListSheet(
        matchId: serverId,
        partnerName: partnerName,
        myId: _myUserId ?? AppConstants.currentUserId,
      ),
    );
  }

  /// "Ehrliches Beenden" (v0.8.0) statt hartem Auflösen: Entweder den
  /// Funken RUHIG enden lassen (status -> cooled, landet bei beiden unter
  /// "Erschlossene Funken", Re-Funke jederzeit) oder vorher einen der
  /// vorbereiteten, freundlichen Absage-Texte senden (Dialog geteilt mit
  /// der Interessen-Liste, siehe [showEndSparkDialog]).
  Future<void> _showEndSparkDialog() async {
    final choice = await showEndSparkDialog(context);

    if (choice == null || !mounted) return;

    // Optional: gewählten Absage-Text zuerst senden (P2P, sonst Relay).
    final goodbye = goodbyeTextForChoice(context, choice);
    if (goodbye != null) {
      final match = _match;
      if (match != null) {
        final localMsg = Message(
          id: Message.newId('local'),
          senderId: _myUserId ?? AppConstants.currentUserId,
          receiverId: match.partner.id,
          text: goodbye,
          timestamp: DateTime.now(),
        );
        ref
            .read(chatProvider.notifier)
            .addMessage(match.id, localMsg, ref: ref);
        // Best-Effort: Die Verbindung kühlt trotzdem.
        await bestEffort('_transmitText', () async {
          await _transmitText(match, goodbye);
        });
      }
    }

    // Serverseitig kühlen (Migration 090, BIGINT): status -> cooled.
    // Die Match-ID kommt aus der Route als String.
    //
    // Wichtig: `match` einmal am Anfang lesen. Zwischen dem await oben und
    // hier kann ein Rebuild `_match` leeren (z. B. Chat-Verlauf lädt neu);
    // ein späteres `_match!` wäre dann ein Null-Check-Crash.
    final match = _match;
    if (match == null) return;
    final matchId = int.tryParse(match.id);
    if (matchId == null) {
      // Lokaler Kontakt (QR): kein Server-Funke - nur lokal entfernen.
      ref.read(chatProvider.notifier).dissolveMatch(match.id);
      if (mounted) {
        ref.read(interessenInitialTabProvider.notifier).state = 2;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'chat.coolSparkDone')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go(AppRoutes.interessen);
      }
      return;
    }
    try {
      await ref.read(findYourMatchServiceProvider).coolMatch(matchId);
    } catch (e) {
      // Bereits gekühlt (z. B. aus der Liste): kein Fehler, weiter zum
      // Funken-Tab statt Fehlermeldung.
      final alreadyCooled = e.toString().toLowerCase().contains(
        'bereits gekuehlt',
      );
      if (!alreadyCooled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                L10n.tf(context, 'chat.coolSparkError', {
                  'error': e.toString(),
                }),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }
    }

    if (mounted) {
      // Direkt auf den Funken-Tab (v0.9.1): sonst landet man auf
      // "Gesendet" und der gekühlte Funke wirkt "komplett weg".
      ref.read(interessenInitialTabProvider.notifier).state = 2;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.coolSparkDone')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go(AppRoutes.interessen);
    }
  }

  /// Ideen-Rad: dreht (animiert über abnehmende Zyklen), landet auf einer
  /// Kategorie und bietet an, den Vorschlag als E2E-Nachricht zu senden.
  Future<void> _showMeetIdeaWheel() async {
    final match = _match;
    if (match == null) return;

    final picked = await showDialog<({String text, SyncDateIdee? syncIdee})>(
      context: context,
      builder: (ctx) =>
          _MeetIdeaWheelDialog(categories: _localizedMeetIdeas(ctx)),
    );
    if (picked == null || !mounted) return;

    // EINE SYNC-IDEE: Das wird kein Text, sondern ein Date - der
    // Zeitpunkt wird geklaert und der Vorschlag geht an den Server
    // (Plan 0.11.0, "Begegnung statt Bildschirm").
    final syncIdee = picked.syncIdee;
    if (syncIdee != null) {
      await _schlageSyncDateVor(match, syncIdee);
      return;
    }

    // Vorschlag als E2E-Nachricht senden (gleicher Weg wie _send()).
    final text = L10n.tf(context, 'chat.dateIdea', {'idea': picked.text});
    final localMsg = Message(
      id: Message.newId('local'),
      senderId: _myUserId ?? AppConstants.currentUserId,
      receiverId: match.partner.id,
      text: text,
      timestamp: DateTime.now(),
    );
    ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
    await _transmitText(match, text);
  }

  /// Schlägt ein Sync-Date vor: erst der Zeitpunkt, dann der Server.
  ///
  /// DER WEG (Betreiber, 27.11.2026): "Die annehmende Person oder die,
  /// die das Date vorschlägt, kann auch direkt einen Zeitvorschlag
  /// machen." Der Zeitpunkt kommt deshalb aus einer kurzen Liste
  /// (heute 20 Uhr, morgen 18 Uhr, selbst wählen) - und steht dann
  /// serverseitig, damit beide Seiten denselben Termin sehen.
  Future<void> _schlageSyncDateVor(Match match, SyncDateIdee idee) async {
    final zeit = await zeigeSyncDateZeitwahl(context);
    if (zeit == null || !mounted) return;
    await ref
        .read(syncDateProvider(match.id).notifier)
        .propose(idee: idee, startAt: zeit);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t(context, 'sync.proposedOwn')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
