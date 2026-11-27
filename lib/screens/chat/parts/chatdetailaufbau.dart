// Der Aufbau des Bildschirms '_ChatDetailScreenState'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Der Aufbau
// liegt in einer ERWEITERUNG auf dieselbe Klasse - die lokalen
// Variablen des Aufbaus wandern mit, das Verhalten bleibt also
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

extension _ChatDetailScreenBuild on _ChatDetailScreenState {
  Widget _baueChat(BuildContext context) {
    // Kontext-Icebreaker ein-/ausschaltbar (v0.8.0).
    final icebreakerEnabled = ref
        .watch(settingsProvider)
        .contextIcebreakerEnabled;
    // v0.9.0-Nutzerwunsch: Wer NACH FREUNDEN sucht, bekommt keine
    // Date-Vorschläge (Meet-Intent + Ideen-Rad ausgeblendet). Der
    // Friends-Filter (Migration 088) stellt sicher, dass der Partner
    // ebenfalls "Freunde" sucht - die eigene Einstellung genügt als
    // Umschalter.
    final noDates =
        ref.watch(userPreferencesProvider).relationshipType ==
        RelationshipType.friends;
    _match = ref.watch(chatProvider.notifier).getMatchById(widget.matchId);
    final settings = ref.watch(settingsProvider);

    void goToSparks() {
      // Zurück IMMER auf die Seite davor (v0.9.1): per Push geöffnet ->
      // pop zum exakten Vorzustand (z. B. Funken-Tab). Nur ohne Stack
      // (Deep-Link) auf den Funken-Tab navigieren - Chats hängen dort,
      // sonst wirkt der Funke "plötzlich weg".
      if (Navigator.of(context).canPop()) {
        context.pop();
        return;
      }
      ref.read(interessenInitialTabProvider.notifier).state = 2;
      context.go(AppRoutes.interessen);
    }

    if (_match == null) {
      // Match existiert nicht mehr (z. B. aufgelöst) - zurück zur übersicht.
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: L10n.t(context, 'chat.backToSparks'),
            onPressed: goToSparks,
          ),
          title: Text(L10n.t(context, 'chat.title')),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.chat_bubble_outline,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(L10n.t(context, 'chat.gone')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: goToSparks,
                child: Text(L10n.t(context, 'chat.backToSparks')),
              ),
            ],
          ),
        ),
      );
    }

    final partner = _match!.partner;
    final myProfile = ref.watch(profileProvider);
    final messages = ref.watch(chatProvider.notifier).messagesFor(_match!.id);
    final myId = _myUserId ?? AppConstants.currentUserId;
    // Nutzerwunsch Gruppierung: Namens-Header an Gruppenstarts (max. 3
    // Nachrichten / 3 Minuten pro Gruppe), Zeit an jeder Bubble.
    final bubbleGroups = computeBubbleGroups(messages);

    // Gemeinsame Interessen EINMAL pro Build ermitteln. Vorher rief
    // _commonInterests() im Chip-Block bis zu dreimal auf und baute dabei
    // jedes Mal ein neues Set + Liste auf.
    final commonInterests = _commonInterests();
    final sharedInterest = commonInterests.isEmpty
        ? null
        : commonInterests.first;

    // Vorstellung ausblenden, sobald die erste eigene Nachricht raus ist.
    final hasSentMessage = messages.any((m) => m.isFrom(myId));

    // Kennenlern-Quiz erst nach 50-70 Nachrichten vorschlagen. Die Schwelle
    // ist pro Chat deterministisch (Hash der Match-ID) - jeder Chat hat
    // seine eigene, sie gilt nicht global für alle.
    final quizThreshold = 50 + (widget.matchId.hashCode.abs() % 21);
    final showQuizBanner = _quizGated && messages.length >= quizThreshold;

    // Date-Rad erst nach 50-70 Nachrichten (v0.9.1): Eigene Schwelle je
    // Chat (bitversetzt, damit sie nicht mit der Quiz-Schwelle
    // zusammenfällt), pro Chat ausblendbar.
    final ideaThreshold = 50 + ((widget.matchId.hashCode >> 8).abs() % 21);
    final showIdeaWheel =
        !noDates && messages.length >= ideaThreshold && !_ideaWheelHidden;

    // Altersbasierte Sichtbarkeits-Regeln anwenden
    final myAge = myProfile.age ?? 0;
    final partnerAge = partner.age ?? 0;
    final isPhotosVisible = AgeSafetyRules.arePhotosVisible(
      targetAge: partnerAge,
      viewerAge: myAge,
      blindModeEnabled: settings.blindModeEnabled,
      revealPhotosAfterMatch: settings.revealPhotosAfterMatch,
      isMatched: _match!.photosUnlocked,
    );

    // Herzensstärken (v0.9.2): Funken-Typ + Server-Match-Daten (wenn der
    // Server-Match bekannt ist; QR-/Lokal-Chats bleiben 'spark') werden
    // NICHT im Build geladen (Sync-Build!), sondern in _bootstrap
    // vorgeladen und im State gehalten (Dismissed-Set ebenfalls).
    final serverMatch = _serverMatch;
    final serverId = serverMatch?.matchId;
    // Erinnerungs-Moment (Idee 1): EIN Moment pro Chat-Öffnung.
    final milestone = Milestones.currentFor(
      matchId: serverId ?? widget.matchId.hashCode,
      matchedAt: serverMatch?.createdAt,
      quizPassedAt: serverMatch?.passedAt,
      dismissed: _milestoneDismissed,
    );

    // DIE ANTIZIPATION (Plan 0.11.0): Der Termin steht unter der
    // Kopfzeile - statt Chat-Metriken.
    final syncDate = termin;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: L10n.t(context, 'chat.backToSparks'),
          onPressed: goToSparks,
        ),
        // G/H: Tap auf Name/Avatar -> Profil des Gegenübers.
        // Bewusst push() statt go(), damit der "Zurück"-Pfeil im
        // Profil-Screen wieder exakt zu DIESEM Chat zurückkehrt (und nicht
        // zu Matches/Profil). Der aktive Tab bleibt "Matches" (siehe
        // _subRoutePrefixes in main_navigation.dart).
        title: GestureDetector(
          onTap: () => context.push(AppRoutes.profileDetailPath(partner.id)),
          child: Row(
            children: [
              CircleAvatar(
                child: !isPhotosVisible
                    ? const Icon(Icons.visibility_off)
                    : const Icon(Icons.person),
              ),
              const SizedBox(width: 12),
              Expanded(
                // Name und E2E-Badge in EINER zentrierten Zeile (v0.9.2).
                //
                // Vorher stand das Badge in einer eigenen, zentrierten
                // Zeile unter dem Namen. Dadurch war der Name links
                // bündig und die Kopfzeile zweizeilig - bei einem
                // Namen wie "Mara" sah das nach einem Zufall aus und
                // nicht nach einer Absicht.
                //
                // Jetzt bilden Name und Badge eine Einheit und werden
                // gemeinsam zentriert. Der Name bleibt Flexible, damit
                // ein langer Name mit Auslassungspunkten endet, statt
                // das Badge aus dem Titel zu drücken.
                //
                // Bewusst KEIN Online-Status / "schreibt..." /
                // Lesebestätigung - siehe ADR-0007 (Präsenz-frei).
                // KEINE Streaks/Flammen-Zählung (v0.9.0-Feedback:
                // "Es soll keine Streaks geben").
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        partner.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: _p2pConnected
                          ? L10n.t(context, 'chat.e2eReady')
                          : L10n.t(context, 'chat.e2eWaiting'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _p2pConnected
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _p2pConnected ? Icons.lock : Icons.lock_open,
                              size: 13,
                              color: _p2pConnected
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'E2E',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _p2pConnected
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottom: SyncDateAntizipation.unten(syncDate),
        actions: [
          // NUTZERWUNSCH "zu viele Symbole, Name abgeschnitten": Die
          // AppBar-Buttons sind auf ZWEI kompakte reduziert (Anruf +
          // Menü). Alles andere (Eisbrecher, Erinnerungsliste,
          // Sicherheit, Melden, Blockieren, Funke beenden) lebt im
          // "mehr"-Menü bzw. im Chat-Verlauf - der Platz bleibt dem
          // Chat erhalten.
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: L10n.t(context, 'chat.call'),
            onPressed: _call,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: L10n.t(context, 'chat.more'),
            onSelected: (value) {
              switch (value) {
                case 'icebreaker':
                  _openIcebreakerCollection();
                case 'bucket':
                  _showBucketListSheet();
                case 'safety':
                  _showSafetyNumberDialog(partner.id, partner.name);
                case 'report':
                  // Letzte 3 Nachrichten (inkl. Medien) werden automatisch
                  // mit der Meldung an den Support übermittelt – nur so
                  // kann der Support E2E-Chats einsehen. Chronologisch
                  // (älteste zuerst), daher die letzten Elemente nehmen.
                  final lastMessages = messages.length > 3
                      ? messages.sublist(messages.length - 3)
                      : messages;
                  showReportUserDialog(
                    context: context,
                    ref: ref,
                    reportedUserId: partner.id,
                    reportedUserName: partner.name,
                    messages: lastMessages,
                  );
                case 'toggleIcebreaker':
                  final current = ref
                      .read(settingsProvider)
                      .contextIcebreakerEnabled;
                  ref
                      .read(settingsProvider.notifier)
                      .setContextIcebreaker(!current);
                case 'block':
                  _showBlockUserDialog(partner.id, partner.name);
                case 'dissolve':
                  _showEndSparkDialog();
                case 'nachrichtPruef':
                  // Die Nachricht überdenken (26.11.2026): Vor dem
                  // Senden nachfragen, wie der Nutzer die Nachricht
                  // selbst versteht.
                  _zeigeNachrichtPruefEinstellungen();
              }
            },
            itemBuilder: (ctx) => [
              // NUTZERWUNSCH "Menü besser geordnet": Die Punkte laufen in
              // sinngemässen Gruppen - GESPRÄCH (Eisbrecher,
              // Erinnerungsliste) -> SICHERHEIT (Sicherheitsnummer, Melden,
              // Blockieren) -> VERBINDUNG (Kontext-Eisbrecher an/aus,
              // Funke beenden). Jede Gruppe hat eine ÜBERSCHRIFT und ist
              // durch einen Divider getrennt.
              //
              // BEFUND (09.11.2026, Betreiber): "Bei 3 Punkte Menü ist
              // über Eisbrecher Fragen ein Strich einfach so aber keine
              // überschrift oder so." Der Strich war der ERSTE Eintrag
              // des Menüs - er trennte nichts, er stand einfach da. Und
              // die Gruppe "Sicherheit" hatte eine Überschrift, die
              // beiden anderen nicht.
              //
              // Also: Der führende Divider ist weg, und JEDE Gruppe
              // bekommt ihre Überschrift - so wie es die
              // Sicherheits-Gruppe schon hatte.
              PopupMenuItem(
                enabled: false,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                  child: Text(
                    L10n.t(context, 'chat.conversationHeader'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'icebreaker',
                child: ListTile(
                  leading: const Icon(Icons.local_fire_department_outlined),
                  title: Text(L10n.t(context, 'chat.spiceTooltip')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'bucket',
                child: ListTile(
                  leading: const Icon(Icons.checklist),
                  title: Text(L10n.t(context, 'bucket.title')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              // Die Nachricht überdenken (26.11.2026): gehört in die
              // Gruppe "Gespräch" - es geht um das Senden.
              _nachrichtPruefMenueEintrag(),
              const PopupMenuDivider(),
              // Kein 'const': L10n.t braucht den Kontext und ist damit
              // keine konstante Ausdrücksform.
              PopupMenuItem(
                enabled: false,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                  child: Text(
                    L10n.t(context, 'chat.securityHeader'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'safety',
                child: ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(L10n.t(context, 'chat.safetyNumberTooltip')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'report',
                child: ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(L10n.t(context, 'chat.reportTooltip')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: ListTile(
                  leading: const Icon(Icons.block),
                  title: Text(L10n.t(context, 'chat.block')),
                  subtitle: Text(L10n.t(context, 'chat.blockSub')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                enabled: false,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                  child: Text(
                    L10n.t(context, 'chat.connectionHeader'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'toggleIcebreaker',
                child: ListTile(
                  leading: Icon(
                    ref.watch(settingsProvider).contextIcebreakerEnabled
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  title: Text(
                    ref.watch(settingsProvider).contextIcebreakerEnabled
                        ? L10n.t(context, 'chat.icebreakerOff')
                        : L10n.t(context, 'chat.icebreakerOn'),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'dissolve',
                child: ListTile(
                  leading: const Icon(Icons.link_off),
                  title: Text(L10n.t(context, 'chat.end')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // Chat-Hintergrund (v0.9.1): Muster oder eigenes Bild.
          Positioned.fill(
            child: ChatBackgroundView(
              backgroundId: settings.chatBackground,
              customPath: settings.chatBackgroundPath,
            ),
          ),
          Column(
            children: [
              // Verbindungs-Hinweis (v0.9.1): Abgerundete Karte, eingeklappt
              // nur "Keine direkte Verbindung", aufklappbar für Details.
              // Wegtippbar pro Öffnen.
              if (!_p2pConnected && !_relayHintDismissed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () =>
                          _setzeState(() => _relayExpanded = !_relayExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _relayExpanded
                                      ? Icons.expand_less
                                      : Icons.cloud_sync_outlined,
                                  size: 16,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSecondaryContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _relayExpanded
                                        ? L10n.t(context, 'chat.relayBanner')
                                        : L10n.t(
                                            context,
                                            'chat.relayBannerShort',
                                          ),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSecondaryContainer,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close, size: 16),
                                  tooltip: L10n.t(context, 'common.close'),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSecondaryContainer,
                                  onPressed: () => _setzeState(
                                    () => _relayHintDismissed = true,
                                  ),
                                ),
                              ],
                            ),
                            // Technische Diagnose (nur aufgeklappt): hilft zu
                            // erkennen, wo der Aufbau hängt (Signaling vs.
                            // ICE/NAT). Automatischer Neuversuch läuft.
                            if (_relayExpanded)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 24,
                                  top: 2,
                                ),
                                child: StreamBuilder(
                                  stream: _p2p?.iceConnectionState,
                                  builder: (context, snap) {
                                    // Der letzte Zustand wird zusätzlich
                                    // direkt vom Service geholt: der
                                    // Broadcast-Stream wiederholt nichts,
                                    // wer sich erst später anmeldet, sah
                                    // sonst gar nichts (die Zeile stand
                                    // dauerhaft auf "-").
                                    final ice =
                                        (_p2p?.lastIceConnectionState ??
                                                snap.data)
                                            ?.toString()
                                            .split('.')
                                            .last ??
                                        '-';
                                    final err = _lastP2pError;
                                    // Das letzte interne Problem (z. B.
                                    // 'Das Senden der Signaling-Nachricht
                                    // ist fehlgeschlagen'). Es kommt aus
                                    // dem WebRTC-Service und ist im
                                    // Release-Build genauso sichtbar wie
                                    // im Debug-Build.
                                    final problem = _lastP2pProblem;
                                    final zeilen = <String>[
                                      L10n.tf(context, 'chat.connDiag', {
                                        'ice': ice,
                                      }),
                                      if (err != null)
                                        L10n.tf(context, 'chat.connError', {
                                          'error': err,
                                        }),
                                      if (problem != null)
                                        L10n.tf(context, 'chat.connProblem', {
                                          'problem': problem,
                                        }),
                                    ];
                                    return Text(
                                      zeilen.join('\n'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSecondaryContainer,
                                          ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Altersdifferenz-Hinweis (v0.9.1, Jugendschutz): Ab 10 Jahren
              // Unterschied warnen, Profile können falsche Angaben enthalten.
              // Tap führt ins Safety Center.
              if (myAge > 0 &&
                  partnerAge > 0 &&
                  (myAge - partnerAge).abs() >= 10)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Card(
                    color: Colors.orange.shade100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push(AppRoutes.safetyCenter),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 20,
                              color: Colors.orange.shade900,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                L10n.tf(context, 'chat.ageGapHint', {
                                  'my': '$myAge',
                                  'other': '$partnerAge',
                                }),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Herzensstärken (Idee 1): Erinnerungs-Karte (ein Moment pro
              // Chat-Öffnung, wegwischbar).
              if (milestone != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.favorite,
                            size: 20,
                            color: Theme.of(
                              context,
                            ).colorScheme.onTertiaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${L10n.t(context, 'milestone.title')} · '
                                  '${L10n.t(context, milestone.titleKey)}',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onTertiaryContainer,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  L10n.tf(context, milestone.bodyKey, {
                                    'date': milestone.formattedDate(
                                      Localizations.localeOf(
                                        context,
                                      ).languageCode,
                                    ),
                                  }),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onTertiaryContainer,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            tooltip: L10n.t(context, 'milestone.dismiss'),
                            onPressed: () async {
                              // Dismiss je Match+Moment (Prefs).
                              final key =
                                  '${serverId ?? widget.matchId.hashCode}:${milestone.type}';
                              await bestEffort('toList', () async {
                                final storage = ref.read(localStorageProvider);
                                final raw = await storage.getString(
                                  _ChatDetailScreenState._milestoneDismissedKey,
                                );
                                final dismissed =
                                    (jsonDecode(raw ?? '[]') as List)
                                        .map((e) => '$e')
                                        .toSet()
                                      ..add(key);
                                await storage.saveString(
                                  _ChatDetailScreenState._milestoneDismissedKey,
                                  jsonEncode(dismissed.toList()),
                                );
                                _milestoneDismissed = dismissed;
                              });
                              if (mounted) _setzeState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!isPhotosVisible)
                BlindPhotoPlaceholder(
                  label: L10n.t(context, 'chat.photosAfterSpark'),
                ),
              // Freundschafts-Badge + Typ-Umschalter (Idee 3): Dezent als Chip
              // unter dem Verbindungs-Hinweis; Popup zum Umschalten.
              if (serverMatch?.isFriends == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: Icon(
                        Icons.group_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      label: Text(
                        L10n.t(context, 'friends.badge'),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      onPressed: () async {
                        final serverId = int.tryParse(widget.matchId);
                        if (serverId == null) return;
                        final messenger = ScaffoldMessenger.of(context);
                        final l10nHint = L10n.t(context, 'friends.toggleHint');
                        await bestEffort(
                          'findYourMatchServiceProvider.setMatchKind',
                          () async {
                            await ref
                                .read(findYourMatchServiceProvider)
                                .setMatchKind(serverId, friends: false);
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(l10nHint),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            _setzeState(() {});
                          },
                        );
                      },
                    ),
                  ),
                ),
              // Kein Meet-Intent für Freunde-Sucher (v0.9.0: "keine Dates").
              if (!noDates)
                MeetIntentCard(
                  matchId: widget.matchId,
                  partnerName: partner.name,
                ),
              // Das Sync-Date (Plan 0.11.0): die Karte mit dem
              // gemeinsamen Countdown und dem Anruf-Knopf.
              syncDateKarte,
              // Vorstellung des Partners (Text + Audio): Beide Seiten können
              // die Vorstellung im Chat anhören (v0.9.0-Feedback - die Person,
              // die den Funke erhalten hat, hörte sie bisher nur im
              // "Erhalten"-Tab). Blendet sich nach der ersten eigenen
              // Nachricht aus (v0.9.1).
              if (!hasSentMessage &&
                  (partner.introText.isNotEmpty ||
                      partner.introAudioPath != null))
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      // Volle Vorstellung im Profil-Screen (Text + Audio).
                      // Die Karten-Vorschau bleibt kompakt (2 Zeilen), ein Tap
                      // öffnet die ausführliche Ansicht.
                      onTap: () =>
                          context.push(AppRoutes.profileDetailPath(partner.id)),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.record_voice_over_outlined,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                partner.introText.isNotEmpty
                                    ? partner.introText
                                    : L10n.t(context, 'chat.introTitle'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            const Icon(Icons.chevron_right, size: 18),
                            if (partner.introAudioPath != null)
                              IntroAudioPlayer(targetUserId: partner.id),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Ideen-Rad (v0.8.0, Test): wählt aus den bestehenden Date-
              // Kategorien einen Vorschlag, der als Nachricht gesendet wird -
              // beide bestätigt im Chat. Für Freunde-Sucher ausgeblendet
              // (v0.9.0: "keine Dates vorschlagen"). Erst nach 50-70
              // Nachrichten pro Chat sichtbar und ausblendbar (v0.9.1).
              if (showIdeaWheel)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showMeetIdeaWheel,
                          icon: const Icon(Icons.casino_outlined, size: 18),
                          label: Text(L10n.t(context, 'chat.ideaWheelBtn')),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: L10n.t(context, 'chat.ideaHide'),
                        onPressed: _hideIdeaWheel,
                      ),
                    ],
                  ),
                ),
              // Kontext-Icebreaker (v0.8.0): gemeinsame Interessen als
              // Gesprächseinstieg. Im Menü deaktivierbar.
              if (icebreakerEnabled && sharedInterest != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: const Icon(Icons.lightbulb_outline, size: 18),
                      label: Text(
                        'Gemeinsam: $sharedInterest',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () => _sendContextIcebreaker(sharedInterest),
                    ),
                  ),
                ),
              Expanded(
                child: messages.isEmpty
                    ? Center(child: Text(L10n.t(context, 'chat.empty')))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: messages.length,
                        reverse: true,
                        itemBuilder: (context, i) {
                          final idx = messages.length - 1 - i;
                          final msg = messages[idx];
                          final mine = msg.isFrom(
                            _myUserId ?? AppConstants.currentUserId,
                          );
                          final group = idx >= 0 && idx < bubbleGroups.length
                              ? bubbleGroups[idx]
                              : (showName: true, showTime: true);
                          // Geteilte Eisbrecher-Frage: mittige Bubble für BEIDE
                          // Seiten (v0.9.1), wandert wie jede Nachricht mit.
                          if (msg.type == MessageType.icebreaker) {
                            final senderName = mine
                                ? L10n.t(context, 'chat.you')
                                : partner.name;
                            return Center(
                              child: _IcebreakerBubble(
                                text: msg.text,
                                senderName: senderName,
                              ),
                            );
                          }
                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: _MessageBubble(
                              msg: msg,
                              mine: mine,
                              blurEnabled: _blurChatImages,
                              onDelete: _canDeleteMessage(msg)
                                  ? _deleteMessageForAll
                                  : null,
                              onReportImage: _reportImage,
                              showName: group.showName,
                              senderName: mine
                                  ? L10n.t(context, 'chat.you')
                                  : partner.name,
                            ),
                          );
                        },
                      ),
              ),
              // Kennenlern-Quiz: schaltet NUR das Foto frei - chatten ist
              // unabhängig möglich. Vorschlag erst nach 50-70 Nachrichten
              // pro Chat (v0.9.1, Schwelle je Match deterministisch).
              if (showQuizBanner)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.photo_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          L10n.t(context, 'chat.quizBanner'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () {
                          final serverId = int.tryParse(widget.matchId);
                          if (serverId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  L10n.t(context, 'chat.quizUnavailable'),
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          // Push: Zurück landet wieder in DIESEM Chat.
                          context.push(AppRoutes.quizPath(serverId));
                        },
                        child: Text(L10n.t(context, 'chat.quizOpen')),
                      ),
                    ],
                  ),
                ),
              // Neues Aufnahme-Design (v0.9.1, wie IntroEditor): Live-Dauer,
              // Lautstärke-Balken, Pause/Fortsetzen, Verwerfen, Stoppen/Senden
              // in einer Karte OBERHALB der Eingabezeile - statt nur Mic/X und
              // Sekunden im Hint-Text (altes Design).
              if (_recording) _buildVoiceRecordingPanel(context),
              // Die Eingabeleiste bringt ihre eigene Tastatur mit
              // (v0.10.1): die Systemtastatur des Geräts sieht dabei
              // keinen einzelnen Buchstaben.
              SecureComposer(
                // Die Tastatur (0.11.0) holt sich Belegung und Farben
                // selbst aus den Einstellungen - so kann keine Stelle
                // sie vergessen (der Befund vom 27.11.2026).
                controller: _ctrl,
                hintText: _recording
                    ? L10n.tf(context, 'chat.recordingHint', {
                        's': '$_recordSeconds',
                      })
                    : L10n.t(context, 'chat.hint'),
                onSend: _send,
                leading: <Widget>[
                  // Der Extra-Knopf "Nachricht überdenken" (26.11.2026) -
                  // er steht nur da, wenn die Einstellung ihn braucht.
                  ..._nachrichtPruefKnopf(),
                  IconButton(
                    icon: const Icon(Icons.image),
                    tooltip: L10n.t(context, 'chat.imageSend'),
                    // E: Während eines Uploads deaktivieren.
                    onPressed: _uploadingImage ? null : _pickImage,
                  ),
                  IconButton(
                    icon: Icon(_recording ? Icons.stop : Icons.mic),
                    tooltip: _recording
                        ? L10n.t(context, 'chat.voiceStopSend')
                        : L10n.t(context, 'chat.voiceTooltip'),
                    color: _recording ? Colors.red : null,
                    onPressed: _toggleRecord,
                  ),
                  // D: Separater "X"-Abbrechen-Button während der Aufnahme.
                  if (_recording)
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: L10n.t(context, 'chat.voiceCancel'),
                      color: Colors.red,
                      onPressed: _cancelRecording,
                    ),
                ],
                // E: Während des Bild-Uploads Ladeindikator statt Senden.
                showSendSpinner: _uploadingImage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
