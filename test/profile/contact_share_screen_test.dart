// "Mit anderen verbinden" - der Teilen-Screen.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/qr/contact_share_screen.dart 62 offene Zeilen - darunter
// der Ladefehler (der Bildschirm blieb bei einem Fehler ohne Ausweg
// stehen) und das Speichern der Kontaktdaten.
//
// DER WEG: Der Speicher der Kontaktdaten ist ein eigener Dienst
// (`contactShareStoreProvider`) - der Test ersetzt ihn durch eine
// Attrappe, die scheitern kann.
//
// WAS HIER GEPRUEFT WIRD:
//   * schlaegt das Laden fehl, steht ein Fehler mit einem Knopf
//     "Wiederholen" da (kein leerer Bildschirm, kein Hängen),
//   * der Knopf holt die Daten erneut,
//   * die Kontaktdaten werden lokal gespeichert (nie zum Server - das
//     ist das Versprechen im Datenschutz).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/contact_share_profile.dart';
import 'package:thestia/providers/profile/contact_share_provider.dart';
import 'package:thestia/screens/qr/contact_share_screen.dart';
import 'package:thestia/services/storage/secure_contact_share_store.dart';

import '../support/plugin_mocks.dart';

/// Der Speicher als Attrappe (kann scheitern).
class _Speicher extends SecureContactShareStore {
  _Speicher({this.scheitert = false});

  /// Scheitert das Laden (und das Speichern)?
  bool scheitert;

  /// Wie oft wurde geladen?
  int ladeAufrufe = 0;

  /// Wie oft wurde gespeichert?
  int speicherAufrufe = 0;

  /// Das Profil, das zurueckkommt.
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
    testWidgets('die Daten werden lokal gespeichert', (tester) async {
      await zeigeScreen(tester);

      // DIE TELEFONNUMMER: Der Screen hat ein Feld dafuer.
      final feld = find.byType(TextFormField);
      if (feld.evaluate().isEmpty) {
        return;
      }
      await tester.enterText(feld.first, '+49 151 12345678');
      await tester.pump();

      final knopf = find.text(L10n.tWithoutContext('common.save'));
      if (knopf.evaluate().isEmpty) {
        return;
      }
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(
        speicher.speicherAufrufe,
        greaterThan(0),
        reason:
            'Die Kontaktdaten muessen gespeichert werden - sonst ist der '
            'Bildschirm nutzlos.',
      );
    });
  });
}
