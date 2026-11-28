// Der Nudge Richtung Anruf (Plan 0.11.0, "Begegnung statt Bildschirm").
//
// ANLASS (27.11.2026): Der Plan für 0.11.0: "Bei Distanz-Funken den
// Chat sanft Richtung Anruf/Sprachnachricht nudge ('Stimmen verbinden
// mehr als Texte')."
//
// WAS HIER GEPRÜFT WIRD:
//   * bei großer Entfernung steht der Nudge da ("Stimmen verbinden
//     mehr als Texte"),
//   * bei kleiner Entfernung steht er nicht da (da ist ein Anruf
//     unnötig),
//   * er kommt nur einmal je Chat (der Merker liegt im lokalen
//     Speicher),
//   * der Anruf-Knopf ruft den Aufrufer.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/widgets/chat/stimmen_nudge.dart';

/// Der Speicher im RAM (der Merker des Nudges liegt dort).
class _Speicher implements LocalStorage {
  _Speicher([this.gemerkt = '']);

  /// Der Merker (so steht er im Speicher).
  String gemerkt;

  final Map<String, String> _daten = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async {
    _daten[key] = value;
    if (key == StimmenNudge.merkerKey) gemerkt = value;
  }

  @override
  Future<String?> getString(String key) async =>
      key == StimmenNudge.merkerKey ? gemerkt : _daten[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _daten[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _daten[key] == null ? null : _daten[key] == 'true';

  @override
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
  });

  /// Baut den Nudge.
  Future<_Speicher> zeige(
    WidgetTester tester, {
    required double entfernungKm,
    String gemerkt = '',
    VoidCallback? onCall,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final speicher = _Speicher(gemerkt);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[localStorageProvider.overrideWithValue(speicher)],
        child: MaterialApp(
          home: Scaffold(
            body: StimmenNudge(
              matchId: '7',
              entfernungKm: entfernungKm,
              onCall: onCall ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return speicher;
  }

  group('Der Nudge', () {
    testWidgets('steht da, wenn die Distanz groß ist', (tester) async {
      await zeige(tester, entfernungKm: 300);

      expect(
        find.text(L10n.tWithoutContext('chat.stimmenNudge')),
        findsOneWidget,
        reason:
            'Bei 300 Kilometern ist ein Anruf sinnvoller als Text - das '
            'sagt der Nudge.',
      );
    });

    testWidgets('steht nicht da, wenn die Distanz klein ist', (tester) async {
      await zeige(tester, entfernungKm: 12);

      expect(
        find.text(L10n.tWithoutContext('chat.stimmenNudge')),
        findsNothing,
        reason: 'Zwanzig Kilometer sind ein Anruf nicht wert.',
      );
    });

    testWidgets('kommt nur einmal je Chat', (tester) async {
      // Der Merker sagt: der Nudge war schon da.
      await zeige(tester, entfernungKm: 300, gemerkt: '["7"]');

      expect(
        find.text(L10n.tWithoutContext('chat.stimmenNudge')),
        findsNothing,
        reason: 'Der Nudge ist sanft - er kommt nicht in jedem Chat.',
      );
    });

    testWidgets('merkt sich den Chat', (tester) async {
      final speicher = await zeige(tester, entfernungKm: 300);

      // Der Merker wird geschrieben, sobald der Nudge dasteht.
      expect(
        speicher.gemerkt.contains('7'),
        isTrue,
        reason:
            'Der Chat muss gemerkt werden - sonst kommt der Nudge '
            'bei jedem Oeffnen wieder.',
      );
    });

    testWidgets('der Anruf-Knopf ruft den Aufrufer', (tester) async {
      var angerufen = false;
      await zeige(tester, entfernungKm: 300, onCall: () => angerufen = true);

      await tester.tap(
        find.text(L10n.tWithoutContext('chat.stimmenNudgeCall')),
      );
      await tester.pump();

      expect(angerufen, isTrue);
    });

    testWidgets('der Nudge lässt sich wegwischen', (tester) async {
      await zeige(tester, entfernungKm: 300);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text(L10n.tWithoutContext('chat.stimmenNudge')),
        findsNothing,
        reason: 'Wer ihn wegwischt, soll ihn nicht wieder sehen.',
      );
    });
  });
}
