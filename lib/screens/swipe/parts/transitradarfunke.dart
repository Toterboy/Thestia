// Die Methoden '_TransitRadarFunke'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

extension _TransitRadarFunke on _TransitRadarScreenState {
  /// "Blicke getauscht": Tag-Auswahl (1-3 Merkmale, Farben optional)
  /// im Bottom Sheet, dann Versand.
  Future<void> _sendSpark() async {
    final picked = await _showTagPickerSheet(
      titleKey: 'transit.sheetTitle',
      hintKey: 'transit.sheetHint',
      requireSelection: true,
    );
    if (picked == null || picked.tags.isEmpty || !mounted) return;

    final result = await ref
        .read(transitProvider.notifier)
        .sendSpark(picked.tags);
    if (!mounted) return;
    if (result == null) {
      final reason = ref.read(transitProvider).lastError;
      // Eigene Lage statt Rohfehler: "kein Geraet in Reichweite" ist
      // kein Fehler, sondern der Normalfall, wenn niemand nearby ist.
      // Der Serverfehler dazu war "Bad request" (400) - fuer den
      // Nutzer eine tote Meldung (BEFUND 06.11.2026).
      //
      // Und: der eigene Token fehlt (v0.10.0, Migration 185) - das
      // heisst, das Radar sendet noch kein Signal. Ohne ihn kann der
      // Server keinen Match finden; das wird gesagt statt still
      // nichts zu tun.
      final text = reason == 'no_devices'
          ? L10n.t(context, 'transit.noDevices')
          : (reason == 'own_token_missing'
                ? L10n.t(context, 'transit.ownTokenMissing')
                : (reason == 'transit_server_too_old'
                      ? L10n.t(context, 'transit.serverTooOld')
                      : (reason == null
                            ? L10n.t(context, 'transit.sendFailed')
                            : '${L10n.t(context, 'transit.sendFailed')} ($reason)')));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
        ),
      );
      return;
    }
    if (result.matched && result.partnerId != null) {
      // BEFUND (09.11.2026, Betreiber): "Wenn man bei Transit Spark schon
      // die Person als Funken hat, soll darauf hingewiesen werden."
      //
      // DER GRUND: Der Server legt bei jedem Transit-Treffer Likes in
      // beide Richtungen an. Existiert mit der Person SCHON ein Funke,
      // bleibt es bei diesem einen (ON CONFLICT DO NOTHING) - der
      // Nutzer sah aber trotzdem den Erfolgs-Dialog. Das war
      // irrefuehrend.
      //
      // JETZT: Der Server teilt mit, ob der Match NEU war. Wenn nicht,
      // wird das gesagt (mit Weg in den bestehenden Chat) statt des
      // Freude-Dialogs.
      if (result.alreadySpark) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(
              Icons.favorite,
              color: Theme.of(ctx).colorScheme.primary,
              size: 40,
            ),
            title: Text(L10n.t(ctx, 'transit.alreadySparkTitle')),
            content: Text(L10n.t(ctx, 'transit.alreadySparkBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(L10n.t(ctx, 'transit.later')),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push(AppRoutes.interessen);
                },
                child: Text(L10n.t(ctx, 'transit.openSparks')),
              ),
            ],
          ),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            Icons.auto_awesome,
            color: Theme.of(ctx).colorScheme.primary,
            size: 40,
          ),
          title: Text(L10n.t(ctx, 'transit.matchTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.t(ctx, 'transit.matchBody')),
              if (result.partnerNote != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    result.partnerNote!,
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L10n.t(ctx, 'transit.later')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.push(AppRoutes.interessen);
              },
              child: Text(L10n.t(ctx, 'transit.openSparks')),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'transit.stored')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // NUTZERWUNSCH "gleichzeitig Blicke getauscht": Der Partner kann
      // MILLISEKUNDEN später drücken - sein Signal-Match erzeugt den
      // Funke serverseitig für BEIDE, aber mein erster Call erfuhr es
      // nicht mehr. Deshalb: nach einem "Signal gespeichert" für ~45 s
      // auf einen NEU entstehenden Funken lauschen (der 2-Minuten-Rate-
      // Limit des erneuten Drückens wartet sonst vergeblich).
      _watchForLateSpark();
      // BEFUND (11.11.2026): Die Kandidatenliste - alle Personen in der
      // Naehe, deren Beschreibung passt. Wer mehrere sind, bekommt sie
      // alle vorgeschlagen und kann mehreren zuwinken.
      unawaited(_showCandidates(picked.tags));
    }
  }

  Future<void> _toggle() async {
    final transit = ref.read(transitProvider.notifier);
    if (ref.read(transitProvider).active) {
      await transit.deactivate();
      await _maybeOfferRadioCleanup();
      return;
    }

    // NUTZERWUNSCH (Build 30): Transit Spark nur ab 18. build() blendet
    // den Start-Button fuer Minderjaehrige bereits aus, diese Pruefung
    // ist die zweite Verteidigungslinie fuer den Fall, dass ein bereits
    // gestarteter Radar nach einer Profilaenderung weiterlaeuft - der
    // Server wuerde den Heartbeat ohnehin mit transit_age_restricted
    // ablehnen, dann waere der Fehler aber erst nach dem BLE-Start
    // sichtbar.
    final age = ref.read(profileProvider).age;
    if (age == null || age < 18) return;

    // Der Server kann Transit Spark abschalten (Migration 159 - die
    // Notbremse fuer den Fall, dass der BLE-Gerätetest nicht besteht).
    // Dann wird nicht nur der Funk unterlassen: der Nutzer bekommt
    // eine klare Begruendung statt einer Alters-Meldung, die nicht
    // zutrifft.
    if (ref.read(transitProvider).featureDisabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'transit.featureDisabled')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Taegliche Selbst-Angaben (v0.9.0): Pflicht vor dem Start - andere
    // koennen dich nur darueber finden. Jeden Tag neu angeben. Plus
    // optionale freie Ergänzung (v0.9.1, eigenes Textfeld).
    final self = await _showTagPickerSheet(
      titleKey: 'transit.self.title',
      hintKey: 'transit.self.hint',
      requireSelection: true,
      customHintKey: 'transit.self.noteHint',
      initialCustomText: ref.read(transitProvider).selfNote,
    );
    if (self == null || !mounted) return;
    transit.setSelfTags(self.tags);
    transit.setSelfNote(self.note);

    // BEFUND (06.11.2026): Auf Android 11 und aelter fragt der
    // BLE-Scan den genauen Standort an - Google Play verlangt dafuer
    // eine prominente Begruendung IN DER APP, bevor der Systemdialog
    // erscheint. Ab Android 12 reicht Bluetooth, da wird gar nicht
    // erst nach dem Standort gefragt.
    if (await TransitBleService.brauchtStandort() && mounted) {
      final zugestimmt = await ensureLocationDisclosure(context, ref);
      if (!zugestimmt || !mounted) return;
    }

    var ok = await transit.activate();
    // v0.9.1: Gezielte Fehlerbehandlung statt generischem startFailed.
    // TransitBleService.lastError unterscheidet Standort-Dienst (Android 11
    // braucht GPS AN für BLE-Scan), fehlende Berechtigungen und BT aus.
    var attempts = 0;
    while (!ok && mounted && attempts < 2) {
      attempts++;
      final reason = TransitBleService.instance.lastError;
      if (reason == 'location_service') {
        if (!mounted) break;
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.location_off, size: 40),
            title: Text(L10n.t(ctx, 'transit.locationTitle')),
            content: Text(L10n.t(ctx, 'transit.locationBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'transit.locationOpen')),
              ),
            ],
          ),
        );
        if (open == true) {
          await bestEffort('openLocationSettings', () async {
            await Geolocator.openLocationSettings();
          });
          // Fix: Nach Rückkehr aus den Einstellungen einen Bestätigungs-
          // Dialog zeigen ("Standort ist jetzt aktiv"), damit der Nutzer
          // nicht alles neu eingeben muss - ein Tap startet das Radar
          // direkt mit den bereits gewählten Tags.
          if (!mounted) break;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(
                Icons.location_on,
                size: 40,
                color: Colors.green,
              ),
              title: Text(L10n.t(ctx, 'transit.locationActiveTitle')),
              content: Text(L10n.t(ctx, 'transit.locationActiveBody')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(L10n.t(ctx, 'common.cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(L10n.t(ctx, 'transit.locationActiveBtn')),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            ok = await transit.activate();
            continue;
          }
          break;
        }
        break;
      }
      if (reason == 'location_permission' ||
          reason == 'bluetooth_scan' ||
          reason == 'bluetooth_connect' ||
          reason == 'bluetooth_advertise') {
        final isAdvertise = reason == 'bluetooth_advertise';
        if (!mounted) break;
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.lock_outline, size: 40),
            title: Text(L10n.t(ctx, 'transit.permissionTitle')),
            content: Text(
              isAdvertise
                  ? L10n.t(ctx, 'transit.advertiseBody')
                  : L10n.t(ctx, 'transit.permissionBody'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'transit.permissionOpen')),
              ),
            ],
          ),
        );
        if (open == true) {
          await bestEffort('openAppSettings', () async {
            await openAppSettings();
          });
          ok = await transit.activate();
          continue;
        }
        break;
      }
      // Natives Advertising abgelehnt (z. B. DATA_TOO_LARGE, zu viele
      // Advertiser, Chipsatz-Limit): Kein BT-Dialog, direkt zur
      // generischen Fehlermeldung (Snackbar unten).
      if (reason == 'advertise_failed') break;
      // Bluetooth-Prompt (v0.9.0): direkt aus der App aktivieren.
      // Fix: 'bluetooth_off' wird jetzt VOR der Berechtigungsprüfung
      // erkannt (Adapter aus, Permissions trotzdem erteilt) - vorher
      // schlug das Advertising mit 'advertise_failed' fehl und der
      // Dialog kam nie.
      if (!mounted) break;
      final enable = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.bluetooth_disabled, size: 40),
          title: Text(L10n.t(ctx, 'transit.btTitle')),
          content: Text(L10n.t(ctx, 'transit.btBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(L10n.t(ctx, 'common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(L10n.t(ctx, 'transit.btEnable')),
            ),
          ],
        ),
      );
      if (enable == true) {
        await bestEffort('turnOn', () async {
          await FlutterBluePlus.turnOn();
        });
        ok = await transit.activate();
      } else {
        break;
      }
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'transit.startFailed')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// Lauscht nach einem "Signal gespeichert" (45 s) auf einen Funken, der
  /// durch das GEGENSEITIGE Drücken des Partners entsteht (Race-Fix:
  /// beide drücken quasi gleichzeitig -> nur die Seite, die zufällig
  /// zuletzt drückte, sah den Match-Dialog).
  void _watchForLateSpark() {
    _lateSparkTimer?.cancel();
    final pressTime = DateTime.now().subtract(const Duration(seconds: 2));
    var checks = 0;
    _lateSparkTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      checks++;
      if (!mounted || checks > 15) {
        _lateSparkTimer?.cancel();
        _lateSparkTimer = null;
        return;
      }
      // Netzwerkfehler: nächster Tick versucht es erneut.
      await bestEffort('findYourMatchService.listMatchesWithState', () async {
        final matches = await ref
            .read(findYourMatchServiceProvider)
            .listMatchesWithState();
        final fresh = matches.where(
          (m) =>
              m.status == 'active' &&
              m.createdAt != null &&
              m.createdAt!.isAfter(pressTime),
        );
        if (fresh.isNotEmpty) {
          _lateSparkTimer?.cancel();
          _lateSparkTimer = null;
          if (!mounted) return;
          await FunkeOverlay.show(context);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'transit.matchTitle')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    });
  }
}
