import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/guardian_status.dart';
import 'package:thestia/providers/guardian_provider.dart';
import 'package:thestia/widgets/buttons.dart';
import 'package:thestia/widgets/privacy_section.dart';

/// Der Abschnitt "Kinderschutz & Elternzugriff" in den Einstellungen.
///
/// fuer ALLE sichtbar, nicht nur fuer Minderjaehrige: wer mit 18
/// geworden ist, hat die Freigabe aus der Zeit mit 16/17 noch - und
/// entscheidet hier ueber ihr Ende.
///
/// Die Einstellungen der Aufsicht (Rhythmus, Nutzungszeit) aendert der
/// ELTERNTEIL im Portal. Der Jugendliche kann sie nur mit der PIN
/// aendern - und die Pruefung laeuft auf dem Server. Deshalb steht hier
/// die PIN als Weg zur Aenderung, nicht als Schutz vor dem Jugendlichen:
/// er kennt sie nicht, der Elternteil schon.
class GuardianSection extends ConsumerStatefulWidget {
  const GuardianSection({super.key, this.showTitle = true});

  /// Der Titel wird im eigenen Screen in der AppBar gezeigt - dort
  /// waere er doppelt.
  final bool showTitle;

  @override
  ConsumerState<GuardianSection> createState() => _GuardianSectionState();
}

class _GuardianSectionState extends ConsumerState<GuardianSection> {
  bool _entsperrt = false;
  bool _speichert = false;
  String? _frequency;
  bool? _usageAktiv;
  int? _startMin;
  int? _endMin;

  String _zeit(int min) {
    final h = (min ~/ 60).toString().padLeft(2, '0');
    final m = (min % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _datum(DateTime? d) {
    if (d == null) return '';
    try {
      return DateFormat('dd.MM.yyyy').format(d.toLocal());
    } catch (_) {
      return '';
    }
  }

  /// Fragt die PIN ab und schaltet die Bearbeitung frei.
  Future<void> _entsperren() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'guardian.unlockTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.t(ctx, 'guardian.pinText')),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(
                counterText: '',
                hintText: '••••',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(L10n.t(ctx, 'common.ok')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pin == null || !mounted) return;
    if (pin.length != 4) {
      _meldung(L10n.t(context, 'guardian.pinWrong'));
      return;
    }
    final ok = await ref.read(guardianProvider.notifier).verifyPin(pin);
    if (!mounted) return;
    if (!ok) {
      _meldung(L10n.t(context, 'guardian.pinWrong'));
      return;
    }
    // Die PIN wird nur fuer die Dauer der Bearbeitung gehalten und
    // danach verworfen. Sie gehoert dem Elternteil - der Jugendliche
    // soll sie nicht kennen.
    setState(() {
      _entsperrt = true;
      _pinAusDemDialog = pin;
    });
  }

  void _meldung(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _speichern() async {
    final pin = _pinAusDemDialog;
    if (pin == null) {
      _meldung(L10n.t(context, 'guardian.pinWrong'));
      return;
    }
    setState(() => _speichert = true);
    final result = await ref
        .read(guardianProvider.notifier)
        .updateSettingsWithPin(
          pin: pin,
          notifyFrequency: _frequency,
          usageLimitEnabled: _usageAktiv,
          usageStartMin: _startMin,
          usageEndMin: _endMin,
        );
    if (!mounted) return;
    setState(() => _speichert = false);
    if (result.isOk) {
      _meldung(L10n.t(context, 'guardian.saveBtn'));
      setState(() => _entsperrt = false);
      _pinAusDemDialog = null;
    } else {
      _meldung(
        result.code == 'wrong_pin' || result.code == 'rate_limited'
            ? L10n.t(context, 'guardian.pinWrong')
            : L10n.t(context, 'guardian.errorGeneric'),
      );
    }
    // Der Server ist die Quelle der Wahrheit - der lokale Zustand wird
    // danach neu geholt.
    await ref.read(guardianProvider.notifier).load();
  }

  /// Die PIN wird nur fuer die Dauer der Bearbeitung gehalten.
  String? _pinAusDemDialog;

  Future<void> _zeitWaehlen(bool start) async {
    final aktuell = start ? _startMin : _endMin;
    final stunde = aktuell == null ? 12 : aktuell ~/ 60;
    final minute = aktuell == null ? 0 : aktuell % 60;
    final gewaehlt = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: stunde, minute: minute),
    );
    if (gewaehlt == null || !mounted) return;
    final minuten = gewaehlt.hour * 60 + gewaehlt.minute;
    setState(() {
      if (start) {
        _startMin = minuten;
      } else {
        _endMin = minuten;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(guardianProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showTitle)
          PrivacySectionTitle(L10n.t(context, 'guardian.sectionTitle')),
        if (widget.showTitle) const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  L10n.t(context, 'guardian.sectionIntro'),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 16),
                if (status.isUnknown)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  _inhalt(context, status),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _inhalt(BuildContext context, GuardianStatus status) {
    final theme = Theme.of(context);

    // Die Freigabe ist beendet (widerrufen oder abgelaufen).
    //
    // BEFUND 04.11.2026: Bis hierher sah dieser Fall aus wie "es gab
    // nie eine Freigabe". Das war falsch und uninformativ: Der
    // Jugendliche wusste nicht, ob seine Freigabe endete - und erst
    // recht nicht, dass dabei die E-Mail-Adresse des Elternteils
    // geloescht wurde (Migration 179).
    if (status.isEnded) {
      final endgueltigGeloescht = status.isGuardianEmailDeleted;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            L10n.t(context, 'guardian.endedTitle'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.t(
              context,
              endgueltigGeloescht
                  ? 'guardian.endedTextEmailDeleted'
                  : 'guardian.endedTextEmailPending',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          if (status.isMinor) ...[
            const SizedBox(height: 14),
            PrimaryButton(
              label: L10n.t(context, 'guardian.requestBtn'),
              onPressed: () => context.push('/guardian-consent'),
            ),
          ],
        ],
      );
    }

    // Keine Freigabe vorhanden.
    if (!status.hasConsent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            L10n.t(context, 'guardian.noConsentTitle'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.t(context, 'guardian.noConsentText'),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          if (status.isMinor) ...[
            const SizedBox(height: 14),
            PrimaryButton(
              label: L10n.t(context, 'guardian.requestBtn'),
              onPressed: () => context.push('/guardian-consent'),
            ),
          ],
        ],
      );
    }

    // Freigabe wartet auf die Bestaetigung des Elternteils.
    if (status.isPending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            L10n.t(context, 'guardian.pendingTitle'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.tf(context, 'guardian.pendingText', {
              'email': status.guardianEmail ?? status.guardianEmailMasked ?? '',
            }),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => context.push('/guardian-consent'),
                child: Text(L10n.t(context, 'guardian.requestBtn')),
              ),
              TextButton(
                onPressed: () => _beenden(status),
                child: Text(L10n.t(context, 'guardian.endAccessBtn')),
              ),
            ],
          ),
        ],
      );
    }

    // Freigabe aktiv.
    final eintraege = <Widget>[];

    if (status.transitionPending) {
      eintraege.add(
        Card(
          margin: EdgeInsets.zero,
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  L10n.t(context, 'guardian.transitionTitle'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  L10n.t(context, 'guardian.transitionText'),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: L10n.t(context, 'guardian.transitionBtn'),
                  onPressed: () => context.push('/guardian-transition'),
                ),
              ],
            ),
          ),
        ),
      );
      eintraege.add(const SizedBox(height: 12));
    }

    eintraege.add(
      Text(
        L10n.t(context, 'guardian.activeTitle'),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    eintraege.add(const SizedBox(height: 4));
    eintraege.add(
      Text(
        L10n.tf(context, 'guardian.activeText', {
          'email': status.guardianEmail ?? status.guardianEmailMasked ?? '',
        }),
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
      ),
    );
    eintraege.add(const SizedBox(height: 16));

    // Benachrichtigungen
    eintraege.add(
      Text(
        L10n.t(context, 'guardian.notifyTitle'),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    eintraege.add(
      Text(
        L10n.t(context, 'guardian.notifyText'),
        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
      ),
    );
    eintraege.add(const SizedBox(height: 6));
    eintraege.add(
      Text(
        '${L10n.t(context, 'guardian.notifyFrequencyLabel')}: '
            '${_frequenzText(status.notifyFrequency)}',
        style: theme.textTheme.bodyMedium,
      ),
    );
    eintraege.add(const SizedBox(height: 16));

    // Nutzungszeit
    eintraege.add(
      Text(
        L10n.t(context, 'guardian.usageTitle'),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    eintraege.add(
      Text(
        L10n.t(context, 'guardian.usageText'),
        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
      ),
    );
    eintraege.add(const SizedBox(height: 6));

    if (_entsperrt) {
      // Bearbeitbar - die Aenderung geht nur mit der PIN durch.
      final frequenz = _frequency ?? status.notifyFrequency;
      final aktiv = _usageAktiv ?? status.usageLimitEnabled;
      final start = _startMin ?? status.usageStartMin;
      final ende = _endMin ?? status.usageEndMin;
      eintraege.add(
        DropdownButtonFormField<String>(
          initialValue: frequenz,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: L10n.t(context, 'guardian.notifyFrequencyLabel'),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          items: const ['daily', 'weekly', 'monthly', 'none']
              .map(
                (f) => DropdownMenuItem(
                  value: f,
                  child: Text(_frequenzText(f)),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _frequency = v),
        ),
      );
      eintraege.add(const SizedBox(height: 12));
      eintraege.add(
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(L10n.t(context, 'guardian.usageToggleLabel')),
          value: aktiv,
          onChanged: (v) => setState(() => _usageAktiv = v),
        ),
      );
      eintraege.add(
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _zeitWaehlen(true),
                child: Text(
                  '${L10n.t(context, 'guardian.usageFrom')} '
                  '${start == null ? '--:--' : _zeit(start)}',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _zeitWaehlen(false),
                child: Text(
                  '${L10n.t(context, 'guardian.usageTo')} '
                  '${ende == null ? '--:--' : _zeit(ende)}',
                ),
              ),
            ),
          ],
        ),
      );
      eintraege.add(const SizedBox(height: 12));
      eintraege.add(
        PrimaryButton(
          label: L10n.t(context, 'guardian.saveBtn'),
          loading: _speichert,
          onPressed: _speichert ? null : _speichern,
        ),
      );
    } else {
      eintraege.add(
        Text(
          status.usageLimitEnabled &&
                  status.usageStartMin != null &&
                  status.usageEndMin != null
              ? L10n.tf(context, 'guardian.usageWindow', {
                  'from': _zeit(status.usageStartMin!),
                  'to': _zeit(status.usageEndMin!),
                })
              : L10n.t(context, 'guardian.usageNone'),
          style: theme.textTheme.bodyMedium,
        ),
      );
      eintraege.add(const SizedBox(height: 6));
      eintraege.add(
        Text(
          L10n.t(context, 'guardian.usagePinNote'),
          style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
        ),
      );
      if (status.hasPin) {
        eintraege.add(const SizedBox(height: 10));
        eintraege.add(
          OutlinedButton(
            onPressed: _entsperren,
            child: Text(L10n.t(context, 'guardian.pinLocked')),
          ),
        );
      }
    }

    eintraege.add(const SizedBox(height: 16));

    // Wie lange bleibt der Zugriff?
    eintraege.add(
      Text(
        L10n.t(context, 'guardian.accessTitle'),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    eintraege.add(
      Text(
        L10n.t(context, 'guardian.accessText'),
        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
      ),
    );
    eintraege.add(const SizedBox(height: 6));
    eintraege.add(
      Text(
        _zugangText(status),
        style: theme.textTheme.bodyMedium,
      ),
    );

    eintraege.add(const SizedBox(height: 14));
    eintraege.add(
      TextButton(
        onPressed: () => _beenden(status),
        child: Text(L10n.t(context, 'guardian.endAccessBtn')),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: eintraege,
    );
  }

  String _frequenzText(String f) {
    switch (f) {
      case 'daily':
        return L10n.t(context, 'guardian.notifyFrequency.daily');
      case 'weekly':
        return L10n.t(context, 'guardian.notifyFrequency.weekly');
      case 'monthly':
        return L10n.t(context, 'guardian.notifyFrequency.monthly');
      default:
        return L10n.t(context, 'guardian.notifyFrequency.none');
    }
  }

  String _zugangText(GuardianStatus status) {
    switch (status.accessPolicy) {
      case 'grace':
        return L10n.tf(context, 'guardian.accessUntil', {
          'date': _datum(status.accessUntil),
        });
      case 'indefinite':
        return L10n.t(context, 'guardian.accessIndefinite');
      default:
        return L10n.t(context, 'guardian.accessUntil18');
    }
  }

  Future<void> _beenden(GuardianStatus status) async {
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'guardian.confirmEndTitle')),
        content: Text(L10n.t(ctx, 'guardian.confirmEndText')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'guardian.endAccessBtn')),
          ),
        ],
      ),
    );
    if (bestaetigt != true || !mounted) return;
    final result = await ref.read(guardianProvider.notifier).revoke();
    if (!mounted) return;
    if (!result.isOk) {
      _meldung(L10n.t(context, 'guardian.errorGeneric'));
    }
  }
}
