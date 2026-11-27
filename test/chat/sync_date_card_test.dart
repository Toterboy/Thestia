// Die Karte des Sync-Dates im Chat.
//
// ANLASS (27.11.2026): Der Plan für 0.11.0 ("Begegnung statt
// Bildschirm"): Zwei Menschen, die weit auseinander wohnen, treffen sich
// zur selben Zeit an verschiedenen Orten.
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne Date steht die Karte nicht da (sie stört den Chat nicht),
//   * der Vorschlag bringt die zwei Knöpfe (Bin dabei / Lieber nicht),
//   * nach der eigenen Annahme wartet die Karte auf den Partner,
//   * wenn beide angenommen haben, steht der Countdown und der
//     Anruf-Knopf da.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/dating_hour/sync_date.dart';
import 'package:thestia/services/dating_hour/sync_date_service.dart';
import 'package:thestia/widgets/chat/sync_date_card.dart';

/// Der Dienst als Ersatz (er liefert den Stand, den der Test will).
class _FakeService implements SyncDateService {
  _FakeService(this.stand);

  final SyncDate? stand;
  bool angenommen = false;
  bool abgesagt = false;

  @override
  Future<SyncDate?> get(String matchId) async => stand;

  @override
  Future<SyncDate?> propose(
    String matchId, {
    required SyncDateIdee idee,
    required DateTime startAt,
  }) async => stand;

  @override
  Future<SyncDate?> accept(String matchId) async {
    angenommen = true;
    return stand;
  }

  @override
  Future<void> decline(String matchId) async {
    abgesagt = true;
  }
}

void main() {
  /// Das Date (so sieht der Serverstand aus).
  SyncDate date({
    bool proposedByMe = false,
    bool acceptedByMe = false,
    bool acceptedByPartner = false,
    Duration inFuture = const Duration(hours: 2),
  }) => SyncDate(
    matchId: '7',
    idea: SyncDateIdee.kochDuell,
    startAt: DateTime.now().add(inFuture),
    proposedByMe: proposedByMe,
    acceptedByMe: acceptedByMe,
    acceptedByPartner: acceptedByPartner,
  );

  /// Baut die Karte.
  Future<_FakeService> zeige(WidgetTester tester, {SyncDate? stand}) async {
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeService(stand);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          syncDateServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SyncDateCard(
              matchId: '7',
              partnerName: 'Mira',
              onCall: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return service;
  }

  group('Die Sync-Date-Karte', () {
    testWidgets('ohne Date steht sie nicht da', (tester) async {
      await zeige(tester);

      expect(find.byType(SyncDateCard), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('sync.cardTitle')),
        findsNothing,
        reason: 'Ohne Date darf die Karte den Chat nicht stoeren.',
      );
    });

    testWidgets('der Vorschlag bringt die zwei Knöpfe', (tester) async {
      await zeige(tester, stand: date(proposedByMe: false));

      expect(find.text(L10n.tWithoutContext('sync.cardTitle')), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('sync.accept')),
        findsOneWidget,
        reason: 'Der Partner muss annehmen koennen.',
      );
      expect(find.text(L10n.tWithoutContext('sync.decline')), findsOneWidget);
    });

    testWidgets('"Bin dabei" nimmt an', (tester) async {
      final service = await zeige(tester, stand: date());

      await tester.tap(find.text(L10n.tWithoutContext('sync.accept')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(service.angenommen, isTrue);
    });

    testWidgets('nach der Annahme wartet die Karte auf den Partner', (
      tester,
    ) async {
      await zeige(
        tester,
        stand: date(acceptedByMe: true, acceptedByPartner: false),
      );

      expect(
        find.textContaining('Mira'),
        findsWidgets,
        reason: 'Die Karte muss sagen, auf wen sie wartet.',
      );
      expect(
        find.text(L10n.tWithoutContext('sync.accept')),
        findsNothing,
        reason: 'Die eigene Annahme steht schon.',
      );
    });

    testWidgets('wenn beide angenommen haben, kommt der Anruf-Knopf', (
      tester,
    ) async {
      await zeige(
        tester,
        stand: date(acceptedByMe: true, acceptedByPartner: true),
      );

      expect(
        find.text(L10n.tWithoutContext('sync.startNow')),
        findsWidgets,
        reason:
            'Das Date steht - der Anruf-Knopf ist der ganze Zweck des '
            'Sync-Dates.',
      );
    });

    testWidgets('der Anruf-Knopf ruft den Aufrufer', (tester) async {
      var angerufen = false;
      await tester.binding.setSurfaceSize(const Size(600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            syncDateServiceProvider.overrideWithValue(
              _FakeService(date(acceptedByMe: true, acceptedByPartner: true)),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SyncDateCard(
                matchId: '7',
                partnerName: 'Mira',
                onCall: () => angerufen = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text(L10n.tWithoutContext('sync.startNow')));
      await tester.pump();

      expect(angerufen, isTrue);
    });
  });
}
