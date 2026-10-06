import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/widgets/admin_metric_row.dart';
import 'package:thestia/widgets/pill_tab_bar.dart';

/// Tests fuer die beiden neuen Bausteine des Admin-Screens
/// (ROADMAP Zeile 807): Pillen-Tab-Indikator und Kennzahlen-Zeile.
///
/// Beide zeigen Arbeitsstand an. Ein Fehler dort faellt nicht als Absturz
/// auf, sondern als falsche Zahl an der falschen Stelle - deshalb sind das
/// Tests gegen den sichtbaren Zustand und nicht nur gegen den Aufbau.
void main() {
  group('PillTabBar', () {
    Future<void> pumpTabs(
      WidgetTester tester,
      TabController controller,
      List<PillTab> tabs,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultTabController(
              length: tabs.length,
              child: Builder(
                builder: (context) => Column(
                  children: [
                    PillTabBar(controller: controller, tabs: tabs),
                    Expanded(
                      child: TabBarView(
                        children: [
                          for (final _ in tabs) const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('zeigt alle Labels und Symbole', (tester) async {
      final controller = TabController(length: 2, vsync: tester);
      addTearDown(controller.dispose);
      await pumpTabs(tester, controller, const [
        PillTab(label: 'Meldungen', icon: Icons.flag),
        PillTab(label: 'Sperren', icon: Icons.block),
      ]);

      expect(find.text('Meldungen'), findsOneWidget);
      expect(find.text('Sperren'), findsOneWidget);
      expect(find.byIcon(Icons.flag), findsOneWidget);
      expect(find.byIcon(Icons.block), findsOneWidget);
    });

    testWidgets('der erste Tab ist ausgewählt, nicht der letzte',
        (tester) async {
      // Der Fehler, den die Material-TabBar-Indikation erzeugte: der
      // Indikator stand zwischen den Labels und war nicht eindeutig.
      final controller = TabController(length: 3, vsync: tester);
      addTearDown(controller.dispose);
      await pumpTabs(tester, controller, const [
        PillTab(label: 'A', icon: Icons.looks_one),
        PillTab(label: 'B', icon: Icons.looks_two),
        PillTab(label: 'C', icon: Icons.looks_3),
      ]);

      final semantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('pill_tab_A')),
      );
      expect(semantics.properties.selected, isTrue);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('pill_tab_B')))
            .properties
            .selected,
        isFalse,
      );
    });

    testWidgets('Tipp auf die zweite Pille wechselt den Tab',
        (tester) async {
      final controller = TabController(length: 3, vsync: tester);
      addTearDown(controller.dispose);
      await pumpTabs(tester, controller, const [
        PillTab(label: 'A', icon: Icons.looks_one),
        PillTab(label: 'B', icon: Icons.looks_two),
        PillTab(label: 'C', icon: Icons.looks_3),
      ]);

      await tester.tap(find.byKey(const ValueKey('pill_tab_B')));
      await tester.pumpAndSettle();

      expect(controller.index, 1);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('pill_tab_B')))
            .properties
            .selected,
        isTrue,
      );
    });

    testWidgets('die Auswahl wandert mit (kein Zurueckspringen)',
        (tester) async {
      // Ohne AnimatedBuilder um den Controller waere die Pille beim
      // Wischen stehen geblieben und erst nach dem Loslassen gewandert.
      final controller = TabController(length: 3, vsync: tester);
      addTearDown(controller.dispose);
      await pumpTabs(tester, controller, const [
        PillTab(label: 'A', icon: Icons.looks_one),
        PillTab(label: 'B', icon: Icons.looks_two),
        PillTab(label: 'C', icon: Icons.looks_3),
      ]);

      controller.animateTo(2);
      await tester.pumpAndSettle();

      expect(controller.index, 2);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('pill_tab_C')))
            .properties
            .selected,
        isTrue,
      );
    });

    testWidgets('eine Kennzahl wird angezeigt, eine Null nicht',
        (tester) async {
      // Null heisst "nichts offen" und darf keinen Platz beanspruchen:
      // sonst stuende eine leere Kachel neben jeder geschlossenen Queue.
      final controller = TabController(length: 2, vsync: tester);
      addTearDown(controller.dispose);
      await pumpTabs(tester, controller, const [
        PillTab(label: 'Meldungen', icon: Icons.flag, count: 7),
        PillTab(label: 'Bugs', icon: Icons.bug_report, count: 0),
      ]);

      expect(find.text('7'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pill_tab_count_Bugs')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pill_tab_count_Meldungen')),
        findsOneWidget,
      );
    });

    testWidgets('count null verhaelt sich wie 0', (tester) async {
      final controller = TabController(length: 2, vsync: tester);
      addTearDown(controller.dispose);
      await pumpTabs(tester, controller, const [
        PillTab(label: 'A', icon: Icons.looks_one, count: null),
        PillTab(label: 'B', icon: Icons.looks_two),
      ]);

      expect(find.byKey(const ValueKey('pill_tab_count_A')), findsNothing);
      expect(find.byKey(const ValueKey('pill_tab_count_B')), findsNothing);
    });

    testWidgets('Semantik nennt Label und Kennzahl', (tester) async {
      // Screenreader: "Meldungen" allein waere falsch, es sind 7.
      final controller = TabController(length: 1, vsync: tester);
      addTearDown(controller.dispose);
      await pumpTabs(tester, controller, const [
        PillTab(label: 'Meldungen', icon: Icons.flag, count: 7),
      ]);

      final semantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('pill_tab_Meldungen')),
      );
      expect(semantics.properties.label, 'Meldungen. 7');
    });

    testWidgets('Tipp auf einen ausgewaehlten Tab bleibt dort',
        (tester) async {
      final controller = TabController(length: 2, vsync: tester);
      addTearDown(controller.dispose);
      await pumpTabs(tester, controller, const [
        PillTab(label: 'A', icon: Icons.looks_one),
        PillTab(label: 'B', icon: Icons.looks_two),
      ]);

      await tester.tap(find.byKey(const ValueKey('pill_tab_A')));
      await tester.pumpAndSettle();

      expect(controller.index, 0);
    });

    testWidgets('Gegenprobe: die Pille ist wirklich die Auswahl',
        (tester) async {
      // Ohne Auswahl waere jede Pille gleich aussehend und der Test
      // "der erste Tab ist ausgewaehlt" koennte nie fallen. Geprueft wird
      // die gezeichnete Hintergrundfarbe, nicht nur das Semantics-Flag.
      final controller = TabController(length: 2, vsync: tester);
      addTearDown(controller.dispose);
      await pumpTabs(tester, controller, const [
        PillTab(label: 'A', icon: Icons.looks_one),
        PillTab(label: 'B', icon: Icons.looks_two),
      ]);

      Color? fillOf(String label) {
        final box = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byKey(ValueKey('pill_tab_$label')),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).color;
      }

      final active = fillOf('A');
      final inactive = fillOf('B');
      expect(active, isNotNull);
      expect(active, isNot(inactive));

      await tester.tap(find.byKey(const ValueKey('pill_tab_B')));
      await tester.pumpAndSettle();
      // Jetzt ist B die gefuellte Pille - die Farbe ist mitgewandert.
      expect(fillOf('B'), isNot(inactive));
      expect(fillOf('A'), isNot(active));
    });

    testWidgets('überlebt grosse Schrift ohne Overflow', (tester) async {
      // Barrierefreiheit: bei 1,5-facher Schrift sind die Labels länger
      // als die Pille. Die Liste muss waechseln statt abzuschneiden.
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final controller = TabController(length: 3, vsync: tester);
      addTearDown(controller.dispose);
      await pumpTabs(tester, controller, const [
        PillTab(label: 'Verifizierung', icon: Icons.verified),
        PillTab(label: 'Bild-Prüfung', icon: Icons.image_search),
        PillTab(label: 'Sperren', icon: Icons.block),
      ]);

      expect(tester.takeException(), isNull);
    });
  });

  group('AdminMetricRow', () {
    Future<void> pumpMetrics(
      WidgetTester tester,
      List<AdminMetric> metrics,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminMetricRow(metrics: metrics)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('zeigt Wert, Label und Zusatzzeile', (tester) async {
      await pumpMetrics(tester, const [
        AdminMetric(
          label: 'Neue Bugs',
          value: '6',
          subtitle: 'letzte 24 Stunden',
        ),
      ]);

      expect(find.text('6'), findsOneWidget);
      expect(find.text('Neue Bugs'), findsOneWidget);
      expect(find.text('letzte 24 Stunden'), findsOneWidget);
    });

    testWidgets('zeigt einen Wert, der keine Zahl ist', (tester) async {
      // "> 99" ist der Grund, warum [AdminMetric.value] ein String ist.
      await pumpMetrics(tester, const [
        AdminMetric(label: 'Meldungen', value: '> 99'),
      ]);
      expect(find.text('> 99'), findsOneWidget);
    });

    testWidgets('tippbare Kachel meldet den Tipp', (tester) async {
      var taps = 0;
      await pumpMetrics(tester, [
        AdminMetric(
          label: 'Offene Meldungen',
          value: '3',
          onTap: () => taps++,
        ),
      ]);

      await tester.tap(find.text('Offene Meldungen'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('eine reine Anzeige-Kachel ist nicht als Schaltflaeche '
        'ausgezeichnet', (tester) async {
      // Sonst waere die Zeile fuer Screenreader eine Schaltflaeche, die
      // nichts tut. Geprueft wird die ausgezeichnete Rolle am
      // Semantics-Knoten, den das Widget selbst setzt - nicht ein Tipp.
      final handle = tester.ensureSemantics();
      await pumpMetrics(tester, const [
        AdminMetric(label: 'Nur Anzeige', value: '0'),
      ]);

      final node = tester.getSemantics(find.bySemanticsLabel(
        'Nur Anzeige: 0',
      ));
      expect(node.flagsCollection.isButton, isFalse);

      handle.dispose();
    });

    testWidgets('null-Kennzahl braucht keinen Absender', (tester) async {
      await pumpMetrics(tester, const [
        AdminMetric(label: 'Nur Anzeige', value: '0'),
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('drei Kacheln teilen sich die Breite ohne Overflow',
        (tester) async {
      await pumpMetrics(tester, const [
        AdminMetric(label: 'Offene Meldungen', value: '12'),
        AdminMetric(label: 'Neue Bugs', value: '6', subtitle: 'letzte 24 h'),
        AdminMetric(label: 'Offene Prüfungen', value: '3'),
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('überlebt grosse Schrift ohne Overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpMetrics(tester, const [
        AdminMetric(label: 'Offene Meldungen', value: '120'),
        AdminMetric(label: 'Neue Bugs', value: '42', subtitle: 'letzte 24 h'),
        AdminMetric(label: 'Offene Prüfungen', value: '7'),
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Semantik nennt Label und Wert als Satz', (tester) async {
      // "Offene Meldungen: 3, letzte 24 Stunden" statt drei Fragmenten.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdminMetricRow(
              metrics: [
                AdminMetric(
                  label: 'Neue Bugs',
                  value: '6',
                  subtitle: 'letzte 24 Stunden',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Neue Bugs: 6, letzte 24 Stunden'),
        findsOneWidget,
      );
    });

    testWidgets('eigene Semantik gewinnt gegen die automatische',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdminMetricRow(
              metrics: [
                AdminMetric(
                  label: 'Meldungen',
                  value: '> 99',
                  semanticsLabel: 'Meldungen: mehr als 99',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Meldungen: mehr als 99'),
        findsOneWidget,
      );
    });
  });
}
