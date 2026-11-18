// Die Methoden '_TransitRadarVorbereitung'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

extension _TransitRadarVorbereitung on _TransitRadarScreenState {
  /// Die Namens-Entscheidung - genau einmal, solange der Nutzer nicht
  /// selbst entschieden hat.
  ///
  /// BEFUND (10.11.2026, Betreiber): "Die Abfrage über die Entscheidung
  /// Name an oder aus soll beim ersten öffnen des Transit Spark screens
  /// kommen und dann nachträglich noch änderbar sein. So ist die
  /// Entscheidung beim User und er kann bewusst entscheiden."
  Future<void> _askNameDecisionOnce() async {
    if (!mounted) return;
    // Nur Volljaehrige - fuer sie ist Transit Spark ueberhaupt frei.
    final myAge = ref.read(profileProvider).age;
    if (myAge == null || myAge < 18) return;
    // Schon entschieden? Dann kein Dialog.
    if (ref.read(settingsProvider).transitShowNameSet) return;
    // Ein zweiter Aufruf, waehrend der Dialog offen ist, soll ihn nicht
    // verdoppeln.
    if (_nameDecisionOpen) return;
    _nameDecisionOpen = true;
    try {
      final choice = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(L10n.t(ctx, 'transit.nameDecisionTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.t(ctx, 'transit.nameDecisionBody')),
              const SizedBox(height: 12),
              Text(
                L10n.t(ctx, 'transit.nameDecisionBoundary'),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(L10n.t(ctx, 'transit.nameDecisionHide')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(L10n.t(ctx, 'transit.nameDecisionShow')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      // Egal, was gewaehlt wurde: die Entscheidung ist damit gefallen.
      // `setTransitShowName` setzt das Flag mit - der Dialog kommt nicht
      // wieder.
      await ref
          .read(settingsProvider.notifier)
          .setTransitShowName(choice ?? false);
    } finally {
      _nameDecisionOpen = false;
    }
  }

  Future<void> _loadRadioCleanup() async {
    await bestEffort('localStorageProvider.getBool', () async {
      final v = await ref
          .read(localStorageProvider)
          .getBool(kTransitRadioCleanupKey);
      // DER VORGABE-WERT (BEFUND 18.11.2026, gefunden von einem Test):
      // "Nach Radar erinnern" ist AN - so wollte es der Nutzerwunsch
      // ("Standard AN statt AUS (opt-out) - der Toggle war standardmaessig
      // deaktiviert und die Erinnerung kam deshalb nie").
      //
      // DER FEHLER: Hier stand "v ?? false" - ohne gespeicherten Wert
      // war der Schalter also AUS und die Erinnerung kam nie. Genau das
      // hatte der Nutzer gemeldet.
      if (mounted) _setzeState(() => _radioCleanupEnabled = v ?? true);
    });
  }

  /// Nach Radar-Ende (wenn Opt-in aktiv): Hinweis zum manuellen
  /// Ausschalten von Bluetooth/Standort anbieten. Echte Funk-Stille
  /// (Scan + Werbung) ist bereits durch deactivate() erreicht; die
  /// System-Radios kann nur der Nutzer selbst deaktivieren.
  ///
  /// NUTZERWUNSCH ("Erinnerung fehlt"): Standard AN statt AUS (opt-out) -
  /// der Toggle war standardmäßig deaktiviert und die Erinnerung kam
  /// deshalb nie. Zusätzlich Bluetooth-Button (nur Standort half nicht).
  Future<void> _maybeOfferRadioCleanup() async {
    if (!_radioCleanupEnabled || !mounted) return;
    final open = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.signal_cellular_off, size: 40),
        title: Text(L10n.t(ctx, 'transit.cleanupTitle')),
        content: Text(L10n.t(ctx, 'transit.cleanupBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('later'),
            child: Text(L10n.t(ctx, 'transit.cleanupLater')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('bluetooth'),
            child: Text(L10n.t(ctx, 'transit.cleanupOpenBluetooth')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('location'),
            child: Text(L10n.t(ctx, 'transit.cleanupOpenLocation')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (open == 'bluetooth') {
      // Direktes Ausschalten ist auf Android 13+ meist privilegiert
      // (SDK 33+ deprecated, kein unprivilegierter Ersatz); try/catch
      // mit Fallback auf die App-Einstellungen.
      // ignore: deprecated_member_use, deprecated_member_use_from_same_package
      try {
        // ignore: deprecated_member_use
        await FlutterBluePlus.turnOff();
      } catch (_) {
        await bestEffort('openAppSettings', () async {
          await openAppSettings();
        });
      }
      if (mounted) {
        // Danach noch den Standort-Hinweis anbieten.
        final loc = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.location_off, size: 40),
            content: Text(L10n.t(ctx, 'transit.cleanupBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'transit.cleanupLater')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'transit.cleanupOpenLocation')),
              ),
            ],
          ),
        );
        if (loc == true && mounted) {
          await bestEffort('openLocationSettings', () async {
            await Geolocator.openLocationSettings();
          });
        }
      }
      return;
    }
    if (open == 'location' && mounted) {
      await bestEffort('openLocationSettings', () async {
        await Geolocator.openLocationSettings();
      });
    }
  }

  Future<void> _setRadioCleanup(bool value) async {
    _setzeState(() => _radioCleanupEnabled = value);
    await bestEffort('localStorageProvider.saveBool', () async {
      await ref
          .read(localStorageProvider)
          .saveBool(kTransitRadioCleanupKey, value);
    });
  }
}
