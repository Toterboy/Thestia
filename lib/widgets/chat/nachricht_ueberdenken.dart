import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/settings/nachricht_ueberdenken.dart';
import 'package:thestia/providers/settings/settings_provider.dart';

/// Der Dialog "Nachricht überdenken" (NUTZERWUNSCH 26.11.2026).
///
/// DER WEG: Der Nutzer tippt eine Nachricht und drückt auf "Senden". Der
/// Dialog zeigt die Nachricht und fragt, wie er sie selbst versteht.
/// Erst wenn er seine Deutung eintippt, wird der Senden-Knopf aktiv.
///
/// DIE DEUTUNG BLEIBT LOKAL: Sie wird nirgends gespeichert und nirgends
/// gesendet - sie ist ein Spiegel, kein Bericht.
class NachrichtPruefDialog extends StatefulWidget {
  const NachrichtPruefDialog({required this.text, super.key});

  /// Die Nachricht, die geprüft wird.
  final String text;

  @override
  State<NachrichtPruefDialog> createState() => _NachrichtPruefDialogState();
}

class _NachrichtPruefDialogState extends State<NachrichtPruefDialog> {
  final TextEditingController _feld = TextEditingController();

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // scrollable: Bei großer Systemschrift ist der Dialog (Text +
      // Feld + Knöpfe) höher als der Bildschirm. Ohne Scrollview läuft
      // die Column unten über und die Knöpfe sind nicht erreichbar.
      scrollable: true,
      title: Text(L10n.t(context, 'chat.nachrichtPruefTitle')),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Die Nachricht selbst - sie muss sichtbar sein, sonst
            // beantwortet der Nutzer eine Frage, die er nicht liest.
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                widget.text,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              L10n.t(context, 'chat.nachrichtPruefFrage'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _feld,
              maxLines: 3,
              minLines: 1,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: L10n.t(context, 'chat.nachrichtPruefFeld'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              L10n.t(context, 'chat.nachrichtPruefHinweis'),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(L10n.t(context, 'chat.nachrichtPruefZurueck')),
        ),
        FilledButton(
          // DER KERN: Ohne Deutung geht die Nachricht nicht raus. Das ist
          // der Punkt der Funktion - deshalb ist der Knopf erst dann
          // aktiv, wenn etwas im Feld steht.
          onPressed: _feld.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(true),
          child: Text(L10n.t(context, 'chat.nachrichtPruefSenden')),
        ),
      ],
    );
  }
}

/// Fragt nach, ob die Nachricht so gesendet werden soll.
///
/// Rückgabe: true, wenn der Nutzer bestätigt hat (die Nachricht darf
/// raus), false, wenn er zurück zum Text will.
Future<bool> frageNachrichtNach(
  BuildContext context, {
  required String text,
}) async {
  final antwort = await showDialog<bool>(
    context: context,
    builder: (ctx) => NachrichtPruefDialog(text: text),
  );
  return antwort == true;
}

/// Die Einstellungen "Nachricht überdenken" (der Bogen im Drei-Punkte-Menü
/// des Chats).
///
/// DER WEG: Der Nutzer entscheidet zweimal - WANN geprüft wird und FÜR
/// WEN. "Für alle Kontakte" ist die globale Einstellung; "Nur für
/// diesen Kontakt" legt eine Ausnahme fest, die den globalen Wert für
/// genau diesen einen Chat überstimmt.
///
/// Beides ist möglich: Der globale Wert bleibt stehen, während die
/// Ausnahme nur diesen einen Chat betrifft.
Future<void> zeigeNachrichtPruefEinstellungen(
  BuildContext context,
  WidgetRef ref, {
  required String kontaktId,
  required String kontaktName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) =>
        _NachrichtPruefBogen(kontaktId: kontaktId, kontaktName: kontaktName),
  );
}

class _NachrichtPruefBogen extends ConsumerStatefulWidget {
  const _NachrichtPruefBogen({
    required this.kontaktId,
    required this.kontaktName,
  });

  final String kontaktId;
  final String kontaktName;

  @override
  ConsumerState<_NachrichtPruefBogen> createState() =>
      _NachrichtPruefBogenState();
}

class _NachrichtPruefBogenState extends ConsumerState<_NachrichtPruefBogen> {
  /// Gilt die Einstellung für alle Kontakte (true) oder nur für diesen?
  bool _global = true;

  /// Der gewählte Modus (beim globalen Werten der globale, sonst die
  /// Ausnahme für diesen Kontakt).
  NachrichtPruefModus _modus = NachrichtPruefModus.aus;

  /// Die Schwelle in Zeichen.
  int _schwelle = 250;

  @override
  void initState() {
    super.initState();
    final einstellung = ref.read(settingsProvider).nachrichtPruef;
    _schwelle = einstellung.schwelle;
    // DER KONTAKT HAT EINE AUSNAHME? Dann startet der Bogen bei ihr -
    // sonst würde der Nutzer beim Öffnen etwas anderes sehen als das,
    // was tatsächlich gilt.
    final ausnahme = einstellung.ausnahmen[widget.kontaktId];
    if (ausnahme != null) {
      _global = false;
      _modus = ausnahme;
    } else {
      _global = true;
      _modus = einstellung.modus;
    }
  }

  /// Speichert den gewählten Modus (global oder als Ausnahme).
  Future<void> _speichere(NachrichtPruefModus modus) async {
    setState(() => _modus = modus);
    final notifier = ref.read(settingsProvider.notifier);
    if (_global) {
      await notifier.setNachrichtPruefModus(modus);
    } else {
      await notifier.setNachrichtPruefAusnahme(widget.kontaktId, modus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.t(context, 'chat.nachrichtPruefTitle'),
                style: text.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                L10n.t(context, 'chat.nachrichtPruefBogen'),
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              // DIE GELTUNG: für alle oder nur für diesen Kontakt.
              RadioGroup<bool>(
                groupValue: _global,
                onChanged: (v) {
                  if (v == null) return;
                  // DER MODUS FOLGT DER GELTUNG: bei einem Kontakt die
                  // Ausnahme, sonst der globale Wert. Sonst zeigte der
                  // Bogen etwas anderes als das, was tatsächlich gilt.
                  final einstellung = ref.read(settingsProvider).nachrichtPruef;
                  setState(() {
                    _global = v;
                    _modus = v
                        ? einstellung.modus
                        : (einstellung.ausnahmen[widget.kontaktId] ??
                              einstellung.modus);
                  });
                },
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      value: true,
                      title: Text(L10n.t(context, 'chat.nachrichtPruefGlobal')),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<bool>(
                      value: false,
                      title: Text(
                        L10n.tf(context, 'chat.nachrichtPruefNurKontakt', {
                          'name': widget.kontaktName,
                        }),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              // DER MODUS: wann geprüft wird.
              RadioGroup<NachrichtPruefModus>(
                groupValue: _modus,
                onChanged: (v) {
                  if (v != null) _speichere(v);
                },
                child: Column(
                  children: [
                    RadioListTile<NachrichtPruefModus>(
                      value: NachrichtPruefModus.aus,
                      title: Text(L10n.t(context, 'chat.nachrichtPruefAus')),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<NachrichtPruefModus>(
                      value: NachrichtPruefModus.immer,
                      title: Text(L10n.t(context, 'chat.nachrichtPruefImmer')),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<NachrichtPruefModus>(
                      value: NachrichtPruefModus.abZeichen,
                      title: Text(
                        L10n.tf(context, 'chat.nachrichtPruefAbZeichen', {
                          'n': '$_schwelle',
                        }),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<NachrichtPruefModus>(
                      value: NachrichtPruefModus.manuell,
                      title: Text(
                        L10n.t(context, 'chat.nachrichtPruefManuell'),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              // DIE SCHWELLE: nur im Modus "ab Zeichen" sinnvoll.
              if (_modus == NachrichtPruefModus.abZeichen) ...[
                const SizedBox(height: 8),
                Text(
                  L10n.t(context, 'chat.nachrichtPruefSchwelle'),
                  style: text.bodySmall,
                ),
                Slider(
                  value: _schwelle.toDouble().clamp(50, 1000),
                  min: 50,
                  max: 1000,
                  divisions: 95,
                  label: '$_schwelle',
                  onChanged: (w) {
                    setState(() => _schwelle = w.round());
                  },
                  onChangeEnd: (w) {
                    ref
                        .read(settingsProvider.notifier)
                        .setNachrichtPruefSchwelle(w.round());
                  },
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(L10n.t(context, 'common.done')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
