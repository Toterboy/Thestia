// Die Erinnerungsliste im Chat (bisher ungetestet - 0 %).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/chat/bucket_list_sheet.dart 0 % - die gemeinsame
// Wunschliste, die im Chat-Menue liegt.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Eintraege stehen da (mit der Angabe, wer sie geschrieben hat),
//   * ein Haken wird abgehakt und dem Server gemeldet,
//   * einen eigenen Eintrag kann man loeschen - einen fremden nicht,
//   * ein neuer Eintrag wird dem Server gemeldet,
//   * ohne Eintraege steht der Leerzustand da.
//
// OHNE SERVER: Der Dienst ist ein Hand-Fake - es geht KEINE Anfrage raus.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/find_match_models.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/screens/chat/bucket_list_sheet.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/dating_hour/find_your_match_service.dart';

/// Hand-Fake des Dienstes fuer die Erinnerungsliste.
///
/// Der echte Dienst spricht mit der Datenbank (RPCs). Der Fake antwortet
/// aus dem RAM und merkt sich die Schreibvorgaenge - so ist sichtbar, OB
/// die App wirklich etwas beim Server ausgeloest hat.
class _FakeBucketService extends FindYourMatchService {
  _FakeBucketService(super.client);

  /// Die Eintraege, die der Server liefert.
  List<BucketItem> eintraege = const [];

  /// Die Texte, die hinzugefuegt wurden.
  final List<String> hinzugefuegt = [];

  /// Die IDs, die abgehakt wurden.
  final List<int> abgehakt = [];

  /// Die IDs, die geloescht wurden.
  final List<int> geloescht = [];

  @override
  Future<List<BucketItem>> bucketItems(int matchId) async => eintraege;

  @override
  Future<int?> bucketAdd(int matchId, String text) async {
    hinzugefuegt.add(text);
    return 1;
  }

  @override
  Future<bool> bucketToggle(int itemId) async {
    abgehakt.add(itemId);
    return true;
  }

  @override
  Future<bool> bucketDelete(int itemId) async {
    geloescht.add(itemId);
    return true;
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// Baut das Blatt mit dem Fake.
  ///
  /// [eintraege] stehen dem Server VOR dem Aufbau zur Verfuegung - das
  /// Blatt laedt seine Liste beim ersten Aufbau.
  Future<_FakeBucketService> zeigeBlatt(
    WidgetTester tester, {
    List<BucketItem> eintraege = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeBucketService(
      // DER CLIENT: Der Fake beantwortet alles selbst - der Client wird
      // nie benutzt. `autoRefreshToken: false`, weil der Client sonst
      // einen periodischen Timer startet (den der Test am Ende als
      // "Timer is still pending" melden wuerde).
      supabase.SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        authOptions: const supabase.AuthClientOptions(autoRefreshToken: false),
      ),
    );

    service.eintraege = eintraege;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          findYourMatchServiceProvider.overrideWithValue(service),
          chatProvider.overrideWith((ref) => ChatNotifier(ChatService())),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: BucketListSheet(
              matchId: 42,
              partnerName: 'Mira',
              myId: 'ich',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  group('Die Erinnerungsliste', () {
    testWidgets('die Eintraege stehen da', (tester) async {
      await zeigeBlatt(
        tester,
        eintraege: const [
          BucketItem(
            id: 1,
            text: 'Sonnenaufgang auf dem Deich',
            createdBy: 'ich',
            done: false,
          ),
          BucketItem(
            id: 2,
            text: 'Kaffee im Café',
            createdBy: 'partnerin',
            done: true,
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Sonnenaufgang auf dem Deich'), findsOneWidget);
      expect(find.text('Kaffee im Café'), findsOneWidget);
      // Wer hat es geschrieben - das steht dabei.
      expect(find.text(L10n.tWithoutContext('bucket.mine')), findsOneWidget);
      expect(
        find.textContaining('Mira'),
        findsOneWidget,
        reason: 'Der Eintrag der Partnerin muss ihr zugeordnet sein.',
      );
    });

    testWidgets('ein Haken wird dem Server gemeldet', (tester) async {
      final service = await zeigeBlatt(
        tester,
        eintraege: const [
          BucketItem(
            id: 1,
            text: 'Sonnenaufgang auf dem Deich',
            createdBy: 'ich',
            done: false,
          ),
        ],
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(service.abgehakt, contains(1));
    });

    testWidgets('einen eigenen Eintrag kann man loeschen', (tester) async {
      final service = await zeigeBlatt(
        tester,
        eintraege: const [
          BucketItem(
            id: 1,
            text: 'Sonnenaufgang auf dem Deich',
            createdBy: 'ich',
            done: false,
          ),
        ],
      );

      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('common.discard')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(service.geloescht, contains(1));
    });

    testWidgets('einen fremden Eintrag kann man nicht loeschen', (
      tester,
    ) async {
      await zeigeBlatt(
        tester,
        eintraege: const [
          BucketItem(
            id: 2,
            text: 'Kaffee im Café',
            createdBy: 'partnerin',
            done: false,
          ),
        ],
      );

      // Kein Loesch-Knopf bei einem fremden Eintrag - sonst koennte
      // jeder die Liste der anderen leeren.
      expect(
        find.byTooltip(L10n.tWithoutContext('common.discard')),
        findsNothing,
      );
    });

    testWidgets('ein neuer Eintrag wird dem Server gemeldet', (tester) async {
      final service = await zeigeBlatt(tester);

      await tester.enterText(find.byType(TextField), 'Fahrrad fahren');
      await tester.pumpAndSettle();
      await tester.tap(find.text(L10n.tWithoutContext('bucket.add')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(service.hinzugefuegt, contains('Fahrrad fahren'));
    });

    testWidgets('ohne Eintraege steht der Leerzustand da', (tester) async {
      await zeigeBlatt(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('bucket.empty')),
        findsOneWidget,
        reason:
            'Eine leere Liste muss es sagen - ein leeres Blatt sieht wie ein '
            'Fehler aus.',
      );
    });
  });
}
