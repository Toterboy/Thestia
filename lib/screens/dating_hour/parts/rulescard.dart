// Der Teil '_RulesCard'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_event_screen.dart';

/// Regeln-Karte.
class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.t(context, 'dh.event.rulesTitle'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _RuleItem('1', L10n.t(context, 'dh.event.rule.1')),
            _RuleItem('2', L10n.t(context, 'dh.event.rule.2')),
            _RuleItem('3', L10n.t(context, 'dh.event.rule.3')),
            _RuleItem('4', L10n.t(context, 'dh.event.rule.4')),
            _RuleItem('5', L10n.t(context, 'dh.event.rule.5')),
            _RuleItem('6', L10n.t(context, 'dh.event.rule.6')),
            _RuleItem('7', L10n.t(context, 'dh.event.rule.7')),
            _RuleItem('8', L10n.t(context, 'dh.event.rule.8')),
            _RuleItem('9', L10n.t(context, 'dh.event.rule.9')),
          ],
        ),
      ),
    );
  }
}
