import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/transit_models.dart';
import 'package:thestia/providers/transit_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/find_your_match_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/services/transit_ble_service.dart';
import 'package:thestia/widgets/funke_overlay.dart';
import 'package:thestia/widgets/location_disclosure.dart';
import 'package:thestia/widgets/transit_mode_selector.dart';
import 'package:thestia/utils/best_effort.dart';

part 'parts/transitradarkandidaten.dart';

part 'parts/transitradarfunke.dart';

part 'parts/transitradarvorbereitung.dart';

part 'parts/pulsecircle.dart';
part 'parts/countdowntext.dart';
part 'parts/countdowntextstate.dart';
part 'parts/encountergreetlist.dart';
part 'parts/encountergreetliststate.dart';
part 'parts/candidatesheet.dart';
part 'parts/softpingsheet.dart';
part 'parts/softpingsheetstate.dart';
part 'parts/softpinginbox.dart';
part 'parts/softpinginboxstate.dart';
part 'parts/transittagpickersheet.dart';
part 'parts/transittagpickersheetstate.dart';

/// Lokale Speicher-Stelle für die gemerkte Radar-Exit-Entscheidung
/// ('stop' | 'keep' | null = immer fragen).
const String kTransitExitPolicyKey = 'transit_exit_policy';

/// Opt-in (v0.9.1, standardmäßig DEAKTIVIERT): Nach Radar-Ende an das
/// manuelle Ausschalten von Bluetooth/Standort erinnern. Android erlaubt
/// Apps NICHT, diese Funkgeräte selbst auszuschalten (BT-Disable ist
/// deprecated/privilegiert, Location gar nicht möglich) - die App stoppt
/// Scan + Werbung (echtes Funk-Aus) und bietet danach nur die
/// Systemeinstellungen zum manuellen Deaktivieren an.
const String kTransitRadioCleanupKey = 'transit_radio_cleanup';

/// Transit-Radar (v0.9.0): "Blicke getauscht, sich nicht getraut?"
/// Aktiviert BLE-Nähe-Erkennung (Vordergrund), zeigt live, wie viele
/// Thestia-Geräte in Reichweite gesehen wurden, und funkt bei beidseitigem
/// Signal über die Bestandspipeline einen Funken.
class TransitRadarScreen extends ConsumerStatefulWidget {
  const TransitRadarScreen({super.key});

  @override
  ConsumerState<TransitRadarScreen> createState() => _TransitRadarScreenState();
}

class _TransitRadarScreenState extends ConsumerState<TransitRadarScreen> {
  /// NUTZERWUNSCH: Erinnerung Standardmäßig AN (opt-out statt opt-in) -
  /// der Toggle war standardmäßig AUS und die Erinnerung kam deshalb nie.
  bool _radioCleanupEnabled = true;

  /// Lauscher für einen Funken, der durch das GEGENSEITIGE Drücken des
  /// Partners entsteht (Nutzerwunsch "gleichzeitig drücken", siehe
  /// [_watchForLateSpark]).
  Timer? _lateSparkTimer;

  /// Läuft der Namens-Dialog gerade? (verhindert ein zweites Fenster)
  bool _nameDecisionOpen = false;

  @override
  void initState() {
    super.initState();
    _loadRadioCleanup();
    // Die Namens-Entscheidung (BEFUND 10.11.2026): Beim ersten Oeffnen
    // des Transit-Radars fragen, ob der Name sichtbar sein soll. Der
    // Dialog kommt erst, wenn der Bildschirm steht (showDialog braucht
    // einen Kontext im Baum).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_askNameDecisionOnce());
    });
  }

  @override
  void dispose() {
    // Lauscher für nachgelieferte Funken (gleichzeitiges Drücken) stoppen.
    _lateSparkTimer?.cancel();
    // Bewusst KEIN deactivate im dispose: Das 45-Minuten-Fenster soll
    // weiterlaufen (asynchrones Funken ist der Kern des Features) und
    // endet von selbst. Nutzer beenden aktiv über den Stop-Button.
    super.dispose();
  }

  /// Universeller Tag-Picker (v0.9.0): 1-3 Basis-Merkmale; fuer farbige
  /// Merkmale folgt OPTIONAL eine Farbwahl (überspringbar, wenn man die
  /// Farbe vergessen hat). Rueckgabe: Slugs (mit ':farbe' wenn gewaehlt)
  /// plus optionale freie Ergänzung, oder null (Abbruch).
  /// [requireSelection] = min. 1 Merkmal Pflicht. Mit [customHintKey] wird
  /// zusätzlich ein eigenes Textfeld (max. 140 Zeichen) angeboten (v0.9.1:
  /// Selbstbeschreibung ergänzen).
  Future<({List<String> tags, String note})?> _showTagPickerSheet({
    required String titleKey,
    required String hintKey,
    required bool requireSelection,
    String? customHintKey,
    String initialCustomText = '',
  }) {
    return showTransitTagPickerSheet(
      context,
      titleKey: titleKey,
      hintKey: hintKey,
      requireSelection: requireSelection,
      customHintKey: customHintKey,
      initialCustomText: initialCustomText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final transit = ref.watch(transitProvider);
    final myAge = ref.watch(profileProvider).age;

    // NUTZERWUNSCH (Build 30): Transit Spark ausschliesslich ab 18.
    // Das ist bewusst ein Fail-closed-Gate: kein Geburtsdatum bedeutet
    // "nicht nachgewiesen volljaehrig" und wird genauso gesperrt wie
    // ein Minderjaehriger-Alter. Genau so arbeitet auch die Datenbank
    // (transit_spark_adult() in Migration 131) - sonst waere die
    // Server-Sperrе allein nicht ausreichend, weil das Profil sonst
    // bis zum naechsten Laden lokal "volljaehrig" aussaehe.
    if (myAge == null || myAge < 18) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.t(context, 'transit.title'))),
        body: _adultOnlyNotice(missingBirthDate: myAge == null),
      );
    }

    // v0.9.0-Feedback: Beim Verlassen der Radar-Seite fragen, ob das Radar
    // gestoppt werden soll - mit Merk-Checkbox ("zukünftig automatisch so
    // beibehalten"). Gespeicherte Entscheidungen werden ohne Nachfrage
    // angewendet.
    return PopScope(
      canPop: !transit.active,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmExitWhileActive();
        if (leave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(L10n.t(context, 'transit.title'))),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Radar-Grafik / Status.
              Center(
                child: SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (transit.active) ..._radarPulse(context),
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: transit.active
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                        ),
                        child: Icon(
                          transit.active ? Icons.radar : Icons.radar_outlined,
                          size: 56,
                          color: transit.active
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  transit.active
                      ? L10n.t(context, 'transit.active')
                      : L10n.t(context, 'transit.inactive'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (transit.active && transit.endsAt != null) ...[
                const SizedBox(height: 4),
                Center(child: _CountdownText(endsAt: transit.endsAt!)),
              ],
              if (transit.active) ...[
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.battery_charging_full_outlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            L10n.t(context, 'transit.batteryHint'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    L10n.tf(context, 'transit.seenCount', {
                      'count': '${transit.encounterCount}',
                    }),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // Der ungefaehre Ort (v0.10.1, Betreiber).
              _placePicker(context),
              const SizedBox(height: 16),
              // Modus-Auswahl (v0.9.0): Bahn/Café vs. Messe/Event - der
              // Messe-Modus nimmt nur starke BLE-Signale auf (echter
              // Sichtkontakt in dichten Umgebungen). Nur inaktiv umschaltbar.
              if (!transit.active) ...[
                Text(
                  L10n.t(context, 'transit.modeLabel'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                TransitModeSelector(
                  value: transit.mode,
                  onChanged: (mode) =>
                      ref.read(transitProvider.notifier).setMode(mode),
                ),
                const SizedBox(height: 16),
              ],
              // Aktivieren/Deaktivieren.
              FilledButton.tonalIcon(
                onPressed: _toggle,
                icon: Icon(transit.active ? Icons.stop : Icons.play_arrow),
                label: Text(
                  transit.active
                      ? L10n.t(context, 'transit.stop')
                      : L10n.t(context, 'transit.start'),
                ),
              ),
              const SizedBox(height: 12),
              // "Blicke getauscht".
              FilledButton.icon(
                onPressed: transit.active && !transit.busy ? _sendSpark : null,
                icon: transit.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(L10n.t(context, 'transit.exchanged')),
              ),
              const SizedBox(height: 12),
              // ---- Die beiden Optionen des Radars: Erinnerung und
              // Namensfreigabe. Zusammen in einer Karte.
              //
              // BEFUND (14.11.2026, Betreiber): "Transit Spark Screen sieht
              // überfüllt und durcheinander aus. Bitte anders anordnen
              // z.B. Name anzeigen zu nach Radar erinnern hinpacken."
              //
              // Die beiden Schalter sagen beide, wie sich der Radar
              // verhält - sie gehören zusammen. Vorher stand der
              // Namens-Schalter weit oben zwischen Ort und Start, der
              // Erinnerungs-Schalter weit unten: die Seite sah dadurch
              // ungeordnet aus. Jetzt stehen beide in einer Karte unter
              // den Knöpfen.
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Opt-in (v0.9.1, Standard AUS): Nach Radar-Ende an
                      // das manuelle Ausschalten von Bluetooth/Standort
                      // erinnern.
                      SwitchListTile(
                        value: _radioCleanupEnabled,
                        onChanged: _setRadioCleanup,
                        title: Text(L10n.t(context, 'transit.cleanupToggle')),
                        subtitle: Text(
                          L10n.t(context, 'transit.cleanupToggleSub'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        secondary: const Icon(
                          Icons.signal_cellular_off_outlined,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        dense: true,
                      ),
                      const Divider(height: 1),
                      // Der Name beim Zuwinken (v0.10.1).
                      //
                      // BEFUND (10.11.2026, Betreiber): "Ich finde aber,
                      // dass man bei Transit Spark einstellen können
                      // soll, ob der Name für andere sichtbar sein soll
                      // oder nicht."
                      _showNameSwitch(context),
                    ],
                  ),
                ),
              ),
              // Eigene Ergänzung zur Selbstbeschreibung (v0.9.1).
              if (transit.selfNote.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.edit_note_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            transit.selfNote,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (transit.active) ...[
                const SizedBox(height: 20),
                Text(
                  L10n.t(context, 'transit.greetSection'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const _EncounterGreetList(),
              ],
              // v0.9.0-Nutzerwunsch: Nach dem Radar-Ende bleiben gesehene
              // Personen 2 Stunden - Bottom-Button öffnet die Liste ("in
              // Ruhe finden"). WATCH statt READ (Fix "Button verschwindet
              // plötzlich"): das Reaktivieren nach neuen Encounters läuft
              // sonst nie, weil der Build nie neu lief.
              if (!transit.active &&
                  ref.watch(transitProvider).encounterCount > 0) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _showRetainedEncounters(),
                  icon: const Icon(Icons.history, size: 18),
                  label: Text(L10n.t(context, 'transit.retainedBtn')),
                ),
              ],
              const SizedBox(height: 20),
              const _SoftPingInbox(),
              const SizedBox(height: 24),
              // Erklärung.
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L10n.t(context, 'transit.howTitle'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        L10n.t(context, 'transit.howBody'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        L10n.t(context, 'transit.privacyNote'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  /// Die Orte, die man nennen kann (frei gewaehlt - kein Standort).
  static const List<String> _placeArten = [
    'zug',
    'messe',
    'veranstaltung',
    'bar',
    'sonstiges',
  ];

  /// Setzt den Zustand - aufrufbar auch aus den Erweiterungen.
  ///
  /// DER GRUND: In einer Erweiterung darf `setState` nicht aufgerufen
  /// werden (der Analyser erlaubt es nur in Instanzmitgliedern einer
  /// State-Klasse). Diese Methode gehoert zur Klasse - die Erweiterung
  /// ruft sie auf.
  void _setzeState(VoidCallback fn) => setState(fn);
}

/// Radar laeuft und der Nutzer verlaesst die Seite: nachfragen, ob der
/// Scan gestoppt oder weiterlaufen soll - mit Merk-Checkbox ("zukuenftig
/// automatisch so beibehalten"). Eine gespeicherte Entscheidung wird ohne
/// Dialog angewendet; Abbrechen liefert `false` und der Aufrufer bleibt.
///
/// Bewusst eine Top-Level-Funktion und keine Screen-Methode: derselbe
/// Dialog muss auch greifen, wenn der Wechsel ueber die Bottom-Navigation
/// laeuft. Dort wird der Radar-Screen nicht disposed, sein `dispose()`
/// also nicht aufgerufen - vorher lief der Presence-Leave beim Tabsprung
/// deshalb am vorbei und das Token blieb serverseitig liegen.
Future<bool> confirmTransitExit(
  BuildContext context,
  WidgetRef ref, {
  Future<void> Function()? onStopped,
}) async {
  if (!ref.read(transitProvider).active) return true;

  final storage = ref.read(localStorageProvider);
  // Kein Storage -> immer fragen.
  final behalten = await bestEffortOr('localStorage.getString', () async {
    final saved = await storage.getString(kTransitExitPolicyKey);
    if (saved == 'stop') {
      await ref.read(transitProvider.notifier).deactivate();
      await onStopped?.call();
      return true;
    }
    if (saved == 'keep') return true;
    return false;
  }, false);
  if (behalten) return true;
  if (!context.mounted) return false;

  var remember = false;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        icon: Icon(
          Icons.radar,
          color: Theme.of(ctx).colorScheme.primary,
          size: 40,
        ),
        title: Text(L10n.t(ctx, 'transit.exitTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.t(ctx, 'transit.exitBody')),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: remember,
              onChanged: (v) => setDialogState(() => remember = v ?? false),
              title: Text(L10n.t(ctx, 'transit.exitRemember')),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('keep'),
            child: Text(L10n.t(ctx, 'transit.exitKeep')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('stop'),
            child: Text(L10n.t(ctx, 'transit.exitStop')),
          ),
        ],
      ),
    ),
  );
  if (choice == null) return false; // Bleiben.
  if (remember && context.mounted) {
    await bestEffort('localStorageProvider.saveString', () async {
      await ref
          .read(localStorageProvider)
          .saveString(kTransitExitPolicyKey, choice);
    });
  }
  if (choice == 'stop') {
    await ref.read(transitProvider.notifier).deactivate();
    await onStopped?.call();
  }
  return true; // 'keep' oder 'stop': Seite verlassen.
}

// ===========================================================================
// Merkmalsauswahl mit Kategorien und Suche (v0.10.0)
// ===========================================================================
//
// BISHER: eine flache Liste von 15 Chips, ohne Suche und ohne
// Kategorien. "T-Shirt", "Hoodie" und "Oberteil" standen gleichrangig
// nebeneinander, ohne erkennbar zu sein, dass drei davon Oberteile sind.
// Wer "Hemd" suchte, musste alles durchsehen.
//
// JETZT:
//   * Suche ueber Slug, Schreibweise und Uebersetzung
//   * Filter je Kategorie
//   * Anzeige gruppiert nach Kategorie
//   * hoechstens EIN Wert je Kategorie - "Hemd" und "Bluse" gleichzeitig
//     waere keine Angabe, sondern Unsinn. Die Server-Regel (Migration
//     149) sagt dasselbe, sonst lehnt die RPC ab.
//   * eigene Farbpaletten fuer Haar und Augen
/// Oeffnet die Merkmals-Auswahl von Transit Spark (der Tag-Picker).
///
/// v0.10.0: Die Auswahl ist in einen eigenen Widget gezogen. Sie
/// braucht Suchfeld, Kategoriefilter und einen Zaehler - das passt
/// nicht mehr in einen StatefulBuilder-Block.
///
/// BEFUND (06.11.2026, Betreiber): "Bei Transit Spark mit 'Wie siehst
/// du aus' hat die Ueberschrift in der Statusleiste gesteckt." Das
/// Sheet ist hoeher als der Bildschirm (Suchfeld, Kategoriefilter,
/// Merkmale, Freitextfeld) und reicht deshalb bis an den oberen Rand -
/// ohne SafeArea liegt die Ueberschrift unter der Statusleiste des
/// Systems.
///
/// `useSafeArea: true` rueckt den Inhalt des Sheets unterhalb der
/// Systemleiste ein. Ohne das ragt der Titel in die Statusleiste.
///
/// BEFUND (07.11.2026): Der Betreiber meldete danach erneut, die
/// Ueberschrift liege noch immer in der Statusleiste. Die Ursache war
/// nicht der Code, sondern die getestete Datei: die Admin-APKs waren
/// noch Build 33 vom 06.11. 19:00 - also VOR diesem Fix (das Gate
/// `tool/check_release_artifacts.py` meldet es heute).
///
/// Oeffentlich, damit der Test den WEG geht, den die App geht - mit
/// demselben `useSafeArea`. Eine Nachbildung im Test wuerde nur pruefen,
/// dass Flutter das kann, nicht dass die App es tut.
@visibleForTesting
Future<({List<String> tags, String note})?> showTransitTagPickerSheet(
  BuildContext context, {
  required String titleKey,
  required String hintKey,
  required bool requireSelection,
  String? customHintKey,
  String initialCustomText = '',
}) {
  return showModalBottomSheet<({List<String> tags, String note})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _TransitTagPickerSheet(
      titleKey: titleKey,
      hintKey: hintKey,
      requireSelection: requireSelection,
      customHintKey: customHintKey,
      initialCustomText: initialCustomText,
    ),
  );
}
