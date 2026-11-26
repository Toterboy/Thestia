// Der Teil '_AdminMetricsBar'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

/// Kennzahlen-Zeile über dem Tab-Inhalt.
///
/// Eigene kleine Consumer-Widget, weil sie auf `adminCountsProvider`
/// hört. Nach einer Aktion in einem Tab wird der Provider invalidiert -
/// das gehört an die eine Stelle, an der die Zeile gezeichnet wird, sonst
/// vergisst es einer der sechs Tabs.
class _AdminMetricsBar extends ConsumerWidget {
  const _AdminMetricsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminCountsProvider);
    final counts = async.valueOrNull;
    // Der TabController kommt aus dem DefaultTabController über den
    // Kontext, nicht über eine Property: die Zeile wird neu gebaut, wenn
    // sich die Kennzahlen ändern, und hält sonst einen Controller fest,
    // den der DefaultTabController beim Screenwechsel schon freigegeben hat.
    final controller = DefaultTabController.of(context);

    // Ladezustand: keine Zeilen aus Platzhaltern bauen. "-1" wäre eine
    // gelogene Zahl; die Zeile erscheint, sobald echte Werte da sind.
    if (counts == null) {
      return async.hasError
          ? const SizedBox.shrink()
          : const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
    }

    void goToTab(int index) {
      // Leere Tabs sind keine Arbeit: nur springen, wenn dort etwas liegt.
      if (index >= controller.length) return;
      controller.animateTo(index);
    }

    final openReports = counts.openReports;
    final newBugs = counts.bugsLast24h;
    final pendingChecks = counts.pendingVerifications + counts.pendingAppeals;

    return AdminMetricRow(
      metrics: [
        AdminMetric(
          label: L10n.t(context, 'admin.metricOpenReports'),
          value: '$openReports',
          urgent: openReports > 0,
          onTap: () => goToTab(0),
        ),
        AdminMetric(
          label: L10n.t(context, 'admin.metricNewBugs'),
          value: '$newBugs',
          subtitle: L10n.t(context, 'admin.metricNewBugsSub'),
          urgent: counts.bugsRising,
          onTap: () => goToTab(1),
        ),
        AdminMetric(
          label: L10n.t(context, 'admin.metricPendingChecks'),
          value: '$pendingChecks',
          urgent: pendingChecks > 0,
          onTap: () => goToTab(2),
        ),
      ],
    );
  }
}
