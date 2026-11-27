// Die Antizipation in der Chat-Kopfzeile.
//
// ANLASS (27.11.2026): Der Plan für 0.11.0 ("Begegnung statt
// Bildschirm"): "Sobald der Meet-Intent terminiert ist, zeigt der
// Chat-Header die Vorfreude ('Treffen am Samstag!') statt
// Chat-Metriken."
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne Termin steht keine Vorfreude in der Kopfzeile,
//   * mit einem Termin steht sie da (mit der Zeit),
//   * läuft das Date gerade, steht es da, dass es läuft.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/dating_hour/sync_date.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/services/dating_hour/sync_date_service.dart';

import '../support/plugin_mocks.dart';

import 'hilfen.dart';

/// Der Dienst als Ersatz (er liefert den Termin, den der Test will).
class _FakeService implements SyncDateService {
  _FakeService(this.stand);

  final SyncDate? stand;

  @override
  Future<SyncDate?> get(String matchId) async => stand;

  @override
  Future<SyncDate?> propose(
    String matchId, {
    required SyncDateIdee idee,
    required DateTime startAt,
  }) async => stand;

  @override
  Future<SyncDate?> accept(String matchId) async => stand;

  @override
  Future<void> decline(String matchId) async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // HIVE: der Verschlüsselungs-Dienst öffnet seine Boxen - ohne
    // initialisiertes Hive schlägt der Aufbau fehl.
    await mockHive();
    // Der Client: die Stimmungs-Karte des Chats braucht ihn.
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() {
    moodClient = supabase.SupabaseClient(
      'https://example.supabase.co',
      'test-key',
    );
  });

  tearDown(() async {
    // Sonst bleibt der Auto-Refresh-Timer des Clients stehen.
    await moodClient.dispose();
  });

  /// Das Sync-Date (so sieht der Serverstand aus).
  SyncDate date({Duration inFuture = const Duration(hours: 2)}) => SyncDate(
    matchId: '7',
    idea: SyncDateIdee.kochDuell,
    startAt: DateTime.now().add(inFuture),
    proposedByMe: true,
    acceptedByMe: true,
    acceptedByPartner: true,
  );

  group('Die Vorfreude in der Kopfzeile', () {
    testWidgets('ohne Termin steht keine da', (tester) async {
      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        overrides: [
          syncDateServiceProvider.overrideWithValue(_FakeService(null)),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Termin:'),
        findsNothing,
        reason: 'Ohne Termin gibt es keine Vorfreude.',
      );
    });

    testWidgets('mit einem Termin steht sie da', (tester) async {
      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        overrides: [
          syncDateServiceProvider.overrideWithValue(_FakeService(date())),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Termin:'),
        findsOneWidget,
        reason:
            'Der Termin ist das, worauf man sich freut - er gehoert in die '
            'Kopfzeile.',
      );
    });

    testWidgets('laeuft das Date, steht das da', (tester) async {
      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        overrides: [
          syncDateServiceProvider.overrideWithValue(
            _FakeService(date(inFuture: const Duration(minutes: -5))),
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('sync.anticipationNow')),
        findsOneWidget,
      );
    });
  });
}
