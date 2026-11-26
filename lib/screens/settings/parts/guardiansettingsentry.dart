// Der Teil '_GuardianSettingsEntry'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_screen.dart';

/// Der Eintrag "Kinderschutz & Elternzugriff" in den Einstellungen.
///
/// Zeigt den aktuellen Stand in einem Satz und öffnet den Eltern-
/// bereich (eigener Screen). Der Inhalt dort ist das gemeinsame Widget
/// `GuardianSection` - es gibt keine zweite, abweichende Darstellung.
class _GuardianSettingsEntry extends ConsumerWidget {
  const _GuardianSettingsEntry();

  /// Der Stand in einem Satz - ohne Zahlen, ohne Geheimnis.
  String _status(BuildContext context, GuardianStatus status) {
    // Der Abruf ist gescheitert: nicht "lädt" sagen (das stimmt nicht
    // mehr) und nicht "keine Aufsicht" (das wäre eine falsche Aussage
    // über die Aufsicht). BEFUND 06.11.2026.
    if (status.isError) return L10n.t(context, 'guardian.loadErrorTitle');
    if (status.isUnknown) return L10n.t(context, 'common.loading');
    if (!status.hasConsent) return L10n.t(context, 'guardian.noConsentTitle');
    if (status.isPending) return L10n.t(context, 'guardian.pendingTitle');
    return L10n.t(context, 'guardian.activeTitle');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(guardianProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PrivacySectionTitle(L10n.t(context, 'guardian.sectionTitle')),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.family_restroom),
            title: Text(L10n.t(context, 'guardian.pinTitle')),
            subtitle: Text(_status(context, status)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.guardianSettings),
          ),
        ),
      ],
    );
  }
}
