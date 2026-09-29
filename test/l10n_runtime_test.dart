import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/transit_models.dart';
import 'package:thestia/widgets/appearance_selector.dart';
import 'package:thestia/widgets/transit_mode_selector.dart';

/// Laufzeit-Test der Sprachumschaltung.
///
/// l10n_test.dart prueft die TABELLE statisch (Paritaet, Platzhalter).
/// Dieser Test prueft das, was statisch nicht sichtbar ist: dass ein
/// Locale-Wechsel zur Laufzeit tatsaechlich bis in die Oberflaeche
/// durchschlaegt. Ein Fehler wie "L10n.t liest immer _strings['de']"
/// waere in der Tabelle unsichtbar - hier faellt er auf.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host({Locale? initial}) {
    return ProviderScope(
      overrides: [
        if (initial != null) localeProvider.overrideWith((ref) => initial),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: L10nScope(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: TransitModeSelector(
                value: TransitMode.transit,
                onChanged: _noop,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('DE ist Standard und zeigt deutschen Text', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Nur direkt daneben'), findsOneWidget);
    expect(find.text('Only right next to me'), findsNothing);
  });

  testWidgets('Locale-Wechsel auf EN zieht bis zur Oberflaeche durch',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Nur direkt daneben'), findsOneWidget);

    // Umschalten exakt wie die Sprachumschaltung es tut.
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TransitModeSelector)));
    container.read(localeProvider.notifier).state = const Locale('en');
    await tester.pumpAndSettle();

    expect(find.text('Only right next to me'), findsOneWidget,
        reason: 'EN-Text muss erscheinen');
    expect(find.text('Nur direkt daneben'), findsNothing,
        reason: 'DE-Text muss verschwinden');
  });

  testWidgets('zurueck auf DE', (tester) async {
    await tester.pumpWidget(host(initial: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Only right next to me'), findsOneWidget);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(TransitModeSelector)));
    container.read(localeProvider.notifier).state = const Locale('de');
    await tester.pumpAndSettle();

    expect(find.text('Nur direkt daneben'), findsOneWidget);
  });

  group('Transit Spark: beide Sprachen vollstaendig uebersetzt', () {
    // Der Fehler, den man beim manuellen Testen leicht uebersieht: ein
    // Schluessel ist in DE gepflegt, in EN aber leer oder fehlt - der
    // Fallback zeigt dann den SCHLUESSEL statt Text. Beide Sprachbloecke
    // muessen fuer jede angezeigte Zeile echten Text liefern.
    const keys = [
      'transit.modeLabel',
      'transit.mode.transit',
      'transit.mode.convention',
      'transit.modeDesc.transit',
      'transit.modeDesc.convention',
      'transit.rssiValue',
      'transit.adultOnly.title',
      'transit.adultOnly.body',
      'transit.adultOnly.missingAge',
    ];

    for (final locale in ['de', 'en']) {
      testWidgets('$locale: kein Schluessel faellt durch', (tester) async {
        await tester.pumpWidget(host(initial: Locale(locale)));
        await tester.pumpAndSettle();

        for (final key in keys) {
          final txt = L10n.t(
              tester.element(find.byType(TransitModeSelector)), key);
          expect(txt, isNot(key), reason: '$locale: $key nicht uebersetzt');
          expect(txt.trim(), isNotEmpty, reason: '$locale: $key leer');
        }
      });
    }

    testWidgets('EN-Ansicht zeigt keine deutschen Reste', (tester) async {
      await tester.pumpWidget(host(initial: const Locale('en')));
      await tester.pumpAndSettle();

      // Die sichtbaren Labels und Erklaerungen.
      for (final german in [
        'Nur direkt daneben',
        'Übliche Reichweite',
        'Eng begrenzt',
        'Signal ab',
      ]) {
        expect(find.textContaining(german), findsNothing,
            reason: 'deutscher Rest in EN: $german');
      }
    });

    testWidgets('RSSI-Chip wird in beiden Sprachen gefuellt', (tester) async {
      for (final locale in ['de', 'en']) {
        await tester.pumpWidget(host(initial: Locale(locale)));
        await tester.pumpAndSettle();
        // {value} muss ersetzt sein, nicht als Literal dastehen.
        expect(find.textContaining('{value}'), findsNothing,
            reason: '$locale: Platzhalter nicht gefuellt');
        expect(find.textContaining('dBm'), findsNWidgets(2),
            reason: '$locale: beide Schwellen muessen sichtbar sein');
      }
    });
  });

  group('AppearanceSelector: beide Sprachen', () {
    // v0.9.2: Das Widget ersetzt drei SelectableTile-Radiozeilen. Es
    // traegt je Modus eine Erklaerung - die ist der eigentliche Grund
    // fuer den Wechsel, also wird sie hier wie beim Transit geprueft.
    const keys = [
      'appearance.light',
      'appearance.system',
      'appearance.dark',
      'appearanceDesc.light',
      'appearanceDesc.system',
      'appearanceDesc.dark',
    ];

    for (final locale in ['de', 'en']) {
      testWidgets('$locale: Wert und Erklaerung uebersetzt', (tester) async {
        await tester.pumpWidget(_appearanceHost(initial: Locale(locale)));
        await tester.pumpAndSettle();

        final ctx = tester.element(find.byType(AppearanceSelector));
        for (final key in keys) {
          final t = L10n.t(ctx, key);
          expect(t, isNot(key), reason: '$locale: $key fehlt');
          expect(t.trim(), isNotEmpty, reason: '$locale: $key leer');
        }
      });
    }

    testWidgets('DE zeigt deutschen Text', (tester) async {
      await tester.pumpWidget(_appearanceHost());
      await tester.pumpAndSettle();

      expect(find.text('Hell'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Dunkel'), findsOneWidget);
      expect(find.textContaining('Folgt deinem Gerät'), findsOneWidget);
    });

    testWidgets('EN zeigt englischen Text ohne deutsche Reste',
        (tester) async {
      await tester.pumpWidget(_appearanceHost(initial: const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Follows your device'), findsOneWidget);
      expect(find.textContaining('Folgt deinem Gerät'), findsNothing);
    });

    testWidgets('genau eine Option ist als gewählt markiert', (tester) async {
      for (final mode in ['light', 'system', 'dark']) {
        await tester.pumpWidget(_appearanceHost(mode: mode));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check_circle), findsOneWidget,
            reason: 'Modus $mode: Auswahl nicht eindeutig');
      }
    });

    testWidgets('meldet den Wechsel nach außen', (tester) async {
      String? picked;
      await tester.pumpWidget(_appearanceHost(
          mode: 'light', onChanged: (m) => picked = m));

      await tester.tap(find.text('Dunkel'));
      await tester.pumpAndSettle();

      expect(picked, 'dark');
    });
  });

  group('Sperrbildschirm: beide Sprachen', () {
    testWidgets('Alterssperre erscheint auf Deutsch', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [localeProvider.overrideWith((ref) => const Locale('de'))],
          child: const MaterialApp(
            home: Scaffold(body: L10nScope(child: _GateNotice())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transit Spark nur ab 18'), findsOneWidget);
      expect(
          find.textContaining('nur volljährigen Personen'), findsOneWidget);
    });

    testWidgets('Alterssperre erscheint auf Englisch', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [localeProvider.overrideWith((ref) => const Locale('en'))],
          child: const MaterialApp(
            home: Scaffold(body: L10nScope(child: _GateNotice())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transit Spark is 18+ only'), findsOneWidget);
      expect(find.textContaining('only available to adults'), findsOneWidget);
      // Kein deutscher Text in der EN-Fassung.
      expect(find.textContaining('volljährigen'), findsNothing);
    });

    testWidgets('Variante ohne Geburtsdatum ist übersetzt', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [localeProvider.overrideWith((ref) => const Locale('en'))],
          child: const MaterialApp(
            home: Scaffold(
                body: L10nScope(child: _GateNotice(missingAge: true))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('date of birth'), findsOneWidget);
    });
  });
}

void _noop(TransitMode _) {}

Widget _appearanceHost({
  Locale? initial,
  String mode = 'system',
  ValueChanged<String>? onChanged,
}) {
  return ProviderScope(
    overrides: [
      if (initial != null) localeProvider.overrideWith((ref) => initial),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: L10nScope(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AppearanceSelector(
              value: mode,
              onChanged: onChanged ?? (String _) {},
            ),
          ),
        ),
      ),
    ),
  );
}

/// Abbild des Sperrbildschirms - bewusst dupliziert statt die private
/// Methode der Radar-Seite zu testen, damit der Test nicht am
/// Screen-Wiring haengt, sondern an der Uebersetzung.
class _GateNotice extends StatelessWidget {
  const _GateNotice({this.missingAge = false});
  final bool missingAge;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(L10n.t(context, 'transit.adultOnly.title')),
      Text(L10n.t(context, missingAge
          ? 'transit.adultOnly.missingAge'
          : 'transit.adultOnly.body')),
    ]);
  }
}
