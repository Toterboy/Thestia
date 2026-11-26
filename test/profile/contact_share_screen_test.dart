// "Mit anderen verbinden" - der Teilen-Screen.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte für
// lib/screens/qr/contact_share_screen.dart 62 offene Zeilen - darunter
// der Ladefehler (der Bildschirm blieb bei einem Fehler ohne Ausweg
// stehen) und das Speichern der Kontaktdaten.
//
// DER WEG: Der Speicher der Kontaktdaten ist ein eigener Dienst
// (`contactShareStoreProvider`) - der Test ersetzt ihn durch eine
// Attrappe, die scheitern kann.
//
// WAS HIER GEPRÜFT WIRD:
//   * schlägt das Laden fehl, steht ein Fehler mit einem Knopf
//     "Wiederholen" da (kein leerer Bildschirm, kein Hängen),
//   * der Knopf holt die Daten erneut,
//   * die Kontaktdaten werden lokal gespeichert (nie zum Server - das
//     ist das Versprechen im Datenschutz).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/contact_share_profile.dart';
import 'package:thestia/providers/profile/contact_share_provider.dart';
import 'package:thestia/screens/qr/contact_share_screen.dart';
import 'package:thestia/services/storage/secure_contact_share_store.dart';

import '../support/plugin_mocks.dart';

/// Der Kanal des Teilens (das Plugin gibt es auf dem Testrechner nicht).
const MethodChannel shareKanal = MethodChannel(
  'dev.fluttercommunity.plus/share',
);

/// Der Speicher als Attrappe (kann scheitern).
class _Speicher extends SecureContactShareStore {
  _Speicher();

  /// Scheitert das Laden (und das Speichern)?
  bool scheitert = false;

  /// Wie oft wurde geladen?
  int ladeAufrufe = 0;

  /// Wie oft wurde gespeichert?
  int speicherAufrufe = 0;

  /// Das Profil, das zurückkommt.
  ContactShareProfile profil = const ContactShareProfile();

  @override
  Future<ContactShareProfile> load() async {
    ladeAufrufe++;
    if (scheitert) throw StateError('Der Speicher ist nicht erreichbar.');
    return profil;
  }

  @override
  Future<void> save(ContactShareProfile profil) async {
    speicherAufrufe++;
    if (scheitert) throw StateError('Der Speicher ist nicht erreichbar.');
    this.profil = profil;
  }
}

void main() {
  late _Speicher speicher;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    mockKeystore();

    // DIE ZWISCHENABLAGE: Ohne den Ersatz wartet der Aufruf im Test
    // endlos (es gibt keine Zwischenablage auf dem Testrechner).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (anfrage) async {
          return null;
        });

    // DAS TEILEN: Das Plugin gibt es auf dem Testrechner nicht. Der
    // Ersatz meldet einen Fehler - so sieht man, was der Bildschirm dem
    // Nutzer sagt, wenn das Teilen nicht klappt.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareKanal, (anfrage) async {
          throw PlatformException(code: 'kein-plugin');
        });
  });

  setUp(() {
    speicher = _Speicher();
  });

  /// Baut den Screen.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          contactShareStoreProvider.overrideWithValue(speicher),
        ],
        child: const MaterialApp(home: ContactShareScreen()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Tippt auf den Speichern-Knopf.
  Future<void> speichern(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('contactShare.save'));
    expect(knopf, findsOneWidget, reason: 'Der Speichern-Knopf muss da sein.');
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Schaltet Signal ein (der erste Schalter der Liste).
  Future<void> signalEinschalten(WidgetTester tester) async {
    final schalter = find.ancestor(
      of: find.text(L10n.tWithoutContext('contactShare.signal')),
      matching: find.byType(SwitchListTile),
    );
    expect(schalter, findsOneWidget, reason: 'Signal muss da sein.');
    await tester.ensureVisible(schalter);
    await tester.pump();
    final knopf = find.descendant(of: schalter, matching: find.byType(Switch));
    await tester.tap(knopf);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Der Ladefehler', () {
    testWidgets('er wird mit einem Knopf "Wiederholen" gezeigt', (
      tester,
    ) async {
      speicher.scheitert = true;

      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('contactShare.loadFailed')),
        findsOneWidget,
        reason:
            'Der Nutzer muss sehen, WAS nicht geklappt hat - ein leerer '
            'Bildschirm sieht wie ein Absturz aus.',
      );
      expect(
        find.text(L10n.tWithoutContext('common.retry')),
        findsOneWidget,
        reason:
            'Es muss einen Ausweg geben - sonst ist der Bildschirm fuer '
            'immer blockiert.',
      );
    });

    testWidgets('der Knopf holt die Daten erneut', (tester) async {
      speicher.scheitert = true;
      await zeigeScreen(tester);
      final aufrufeVorher = speicher.ladeAufrufe;

      // DAS SCHEITERN VERGEHT: Der zweite Versuch klappt.
      speicher.scheitert = false;
      await tester.tap(find.text(L10n.tWithoutContext('common.retry')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(
        speicher.ladeAufrufe,
        greaterThan(aufrufeVorher),
        reason: 'Der Knopf muss das Laden wiederholen.',
      );
      expect(
        find.text(L10n.tWithoutContext('contactShare.loadFailed')),
        findsNothing,
      );
    });
  });

  group('Das Speichern', () {
    testWidgets('die Telefonnummer wird lokal gespeichert', (tester) async {
      await zeigeScreen(tester);

      // DIE TELEFONNUMMER: Das Feld des Bildschirms (es ist ein
      // TextField, kein TextFormField).
      final feld = find.byType(TextField).first;
      await tester.ensureVisible(feld);
      await tester.pump();
      await tester.enterText(feld, '+49 151 12345678');
      await tester.pump();

      await speichern(tester);

      expect(tester.takeException(), isNull);
      expect(
        speicher.speicherAufrufe,
        greaterThan(0),
        reason:
            'Die Kontaktdaten muessen gespeichert werden - sonst ist der '
            'Bildschirm nutzlos.',
      );
      expect(
        speicher.profil.phone,
        contains('151'),
        reason: 'Die Telefonnummer muss im Speicher landen.',
      );
      expect(
        find.text(L10n.tWithoutContext('contactShare.saved')),
        findsOneWidget,
        reason: 'Der Nutzer muss sehen, dass es geklappt hat.',
      );
    });

    testWidgets('eine ungueltige Telefonnummer wird abgewiesen', (
      tester,
    ) async {
      await zeigeScreen(tester);

      final feld = find.byType(TextField).first;
      await tester.ensureVisible(feld);
      await tester.pump();
      await tester.enterText(feld, 'keine Nummer');
      await tester.pump();

      await speichern(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('contactShare.invalidPhone')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass die Nummer nicht geht - sonst '
            'teilt er eine kaputte Nummer.',
      );
      expect(
        speicher.speicherAufrufe,
        0,
        reason: 'Eine kaputte Nummer darf nicht gespeichert werden.',
      );
    });
  });

  group('Die Apps', () {
    testWidgets('eine App ohne Handle wird abgewiesen', (tester) async {
      await zeigeScreen(tester);

      // DER SCHALTER: Signal einschalten, aber kein Handle eintragen.
      await signalEinschalten(tester);
      await speichern(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('contactShare.handleMissing')),
        findsOneWidget,
        reason:
            'Eine App ohne Handle ist nicht teilbar - der Nutzer muss es '
            'wissen.',
      );
      expect(speicher.speicherAufrufe, 0);
    });

    testWidgets('eine App mit Handle wird gespeichert', (tester) async {
      await zeigeScreen(tester);

      await signalEinschalten(tester);

      // DAS HANDLE-FELD: Es erscheint, sobald die App eingeschaltet ist.
      final handle = find.byType(TextField).last;
      await tester.ensureVisible(handle);
      await tester.pump();
      await tester.enterText(handle, 'lena.er');
      await tester.pump();

      await speichern(tester);

      expect(tester.takeException(), isNull);
      expect(
        speicher.speicherAufrufe,
        greaterThan(0),
        reason: 'Die App muss gespeichert werden.',
      );
      expect(
        speicher.profil.entries.map((e) => e.handle),
        contains('lena.er'),
        reason: 'Das Handle muss im Speicher landen.',
      );
    });

    testWidgets('eine eigene App wird angelegt und wieder entfernt', (
      tester,
    ) async {
      await zeigeScreen(tester);

      // DIE EIGENE APP: Der Knopf legt eine Zeile an.
      final knopf = find.text(L10n.tWithoutContext('contactShare.addCustom'));
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('contactShare.customEntry')),
        findsOneWidget,
        reason: 'Die eigene App muss erscheinen.',
      );

      // WIEDER ENTFERNEN: Der Knopf am Rand der Zeile.
      final entfernen = find.byTooltip(
        L10n.tWithoutContext('contactShare.remove'),
      );
      expect(entfernen, findsOneWidget);
      await tester.tap(entfernen);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('contactShare.customEntry')),
        findsNothing,
        reason: 'Die eigene App muss wieder weg sein.',
      );
    });
  });

  group('Das Kopieren und das Teilen', () {
    testWidgets('die Daten lassen sich kopieren', (tester) async {
      await zeigeScreen(tester);

      final feld = find.byType(TextField).first;
      await tester.ensureVisible(feld);
      await tester.pump();
      await tester.enterText(feld, '+49 151 12345678');
      await tester.pump();

      final knopf = find.text(L10n.tWithoutContext('contactShare.copy'));
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('contactShare.copied')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass die Daten in der Zwischenablage sind.',
      );
    });

    testWidgets('schlaegt das Teilen fehl, wird es gesagt', (tester) async {
      await zeigeScreen(tester);

      final feld = find.byType(TextField).first;
      await tester.ensureVisible(feld);
      await tester.pump();
      await tester.enterText(feld, '+49 151 12345678');
      await tester.pump();

      // DAS TEILEN: Das Plugin gibt es im Test nicht - der Bildschirm
      // muss das sagen, statt still zu scheitern.
      final knopf = find.text(L10n.tWithoutContext('contactShare.share'));
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('contactShare.shareFailed')),
        findsOneWidget,
        reason:
            'Wenn das Teilen nicht klappt, muss der Nutzer es erfahren - '
            'sonst denkt er, die Daten waeren raus.',
      );
    });
  });
}
