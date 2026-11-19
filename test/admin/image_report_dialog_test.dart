// Der Melde-Dialog fuer Chat-Bilder - bisher ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/profile/image_report_service.dart 230 offene Zeilen (9 %).
// Der Dialog ist der einzige Weg, ueber den ein Nutzer ein Bild im Chat
// meldet - und dort steht die Zusage, dass NUR das gemeldete Bild und
// NICHTS aus dem Verlauf an den Server geht.
//
// WAS HIER GEPRUEFT WIRD:
//   * ohne Bild gibt es keine Meldung (der Nutzer bekommt einen Hinweis),
//   * der Grund muss gewaehlt werden (der Knopf ist sonst gesperrt),
//   * mit Grund geht genau das gemeldete Bild an den Server,
//   * beim Abbrechen geht NICHTS raus.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/verification/report_models.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/services/profile/image_report_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/profile/report_service.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Meldungs-Dienst als Ersatz.
///
/// DER GRUND: Der echte Dienst legt die Meldung in einer verschluesselten
/// Hive-Box ab - die laesst sich im Widget-Test nicht oeffnen (das ist
/// echte Datei-Arbeit). Fuer den Dialog reicht der Ersatz.
class _FakeReportService extends ReportService {
  /// Die Meldungen, die erstellt wurden.
  final List<String> beschreibungen = [];

  @override
  Future<ReportSubmission> createReport({
    required String reporterId,
    required String reporterUserName,
    required String reportedUserId,
    required String reportedUserName,
    required ReportType type,
    String? description,
    List<Message>? messages,
  }) async {
    beschreibungen.add(description ?? '');
    return ReportSubmission(
      report: UserReport(
        id: 'report-1',
        reporterId: reporterId,
        reportedUserId: reportedUserId,
        type: type,
        description: description,
        createdAt: DateTime.now(),
      ),
      serverAccepted: true,
    );
  }
}

/// Der Speicher im RAM.
class _Speicher implements LocalStorage {
  final Map<String, String> _daten = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async =>
      _daten[key] = value;

  @override
  Future<String?> getString(String key) async => _daten[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _daten[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _daten[key] == null ? null : _daten[key] == 'true';

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);

  @override
  Future<void> remove(String key) async => _daten.remove(key);
}

/// Der Keystore ohne Plugin.
class _Keystore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {
    // Der Test speichert kein Profil im Keystore.
  }

  @override
  Future<void> delete() async {
    // Der Test loescht kein Profil im Keystore.
  }
}

/// Der Knopf, der den Melde-Dialog oeffnet.
class _Aufrufer extends ConsumerWidget {
  const _Aufrufer({required this.nachricht});

  final Message nachricht;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showImageReportDialog(
            context: context,
            ref: ref,
            message: nachricht,
            reportedUserId: 'user-42',
            reportedUserName: 'Mira',
          ),
          child: const Text('Bild melden'),
        ),
      ),
    );
  }
}

void main() {
  /// Der Ersatz-Server.
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();

    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() {
    server.funktionsAufrufe.clear();
    server.funktionsAntworten.clear();
  });

  /// Baut den Dialog.
  Future<_FakeReportService> zeigeDialog(
    WidgetTester tester, {
    required Message nachricht,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final meldedienst = _FakeReportService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(_Speicher()),
          secureProfileStoreProvider.overrideWithValue(_Keystore()),
          reportServiceProvider.overrideWithValue(meldedienst),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(_Speicher(), _Keystore());
            notifier.setProfile(
              const UserProfile(id: 'ich', name: 'Lena', bio: ''),
            );
            return notifier;
          }),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: _Aufrufer(nachricht: nachricht),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Bild melden'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return meldedienst;
  }

  /// Eine Nachricht mit einem Bild.
  Message nachrichtMitBild() => Message(
    id: 'm1',
    senderId: 'partner-1',
    receiverId: 'ich',
    text: 'Schau mal',
    mediaUrl: 'data:image/png;base64,iVBORw0KGgo=',
    timestamp: DateTime.now(),
  );

  group('Der Bild-Melde-Dialog', () {
    testWidgets('ohne Bild gibt es keine Meldung', (tester) async {
      final nachricht = Message(
        id: 'm1',
        senderId: 'partner-1',
        receiverId: 'ich',
        text: 'Nur Text',
        timestamp: DateTime.now(),
      );

      await zeigeDialog(tester, nachricht: nachricht);

      expect(tester.takeException(), isNull);
      // Der Nutzer wird informiert - und es geht NICHTS raus.
      expect(
        find.text(L10n.tWithoutContext('report.imageUnavailable')),
        findsOneWidget,
      );
      expect(server.funktionsAufrufe, isEmpty);
    });

    testWidgets('der Grund muss gewaehlt werden', (tester) async {
      await zeigeDialog(tester, nachricht: nachrichtMitBild());

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);

      // Ohne Grund ist der Knopf gesperrt.
      final knopf = tester.widget<FilledButton>(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('report.sendReport'),
        ),
      );
      expect(
        knopf.onPressed,
        isNull,
        reason:
            'Ohne Grund darf der Nutzer nicht senden - sonst waere die '
            'Meldung fuer das Team unbrauchbar.',
      );

      // Und es ist auch nichts rausgegangen.
      expect(server.funktionsAufrufe, isEmpty);
    });

    testWidgets('mit Grund geht genau das gemeldete Bild raus', (tester) async {
      await zeigeDialog(tester, nachricht: nachrichtMitBild());

      // Den ersten Grund waehlen.
      final grund = find.byType(RadioListTile<ReportType>).first;
      await tester.ensureVisible(grund);
      await tester.tap(grund);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Und absenden.
      final senden = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('report.sendReport'),
      );
      await tester.ensureVisible(senden);
      await tester.tap(senden);
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(
        server.funktionsAufrufe,
        hasLength(1),
        reason: 'Die Meldung muss beim Server ankommen.',
      );
      final aufruf = server.funktionsAufrufe.first;
      expect(aufruf['funktion'], 'report-image');
      expect(
        aufruf['imageBase64'],
        'iVBORw0KGgo=',
        reason:
            'Es geht NUR das gemeldete Bild raus - nicht irgendein Bild '
            'aus dem Verlauf.',
      );
      expect(aufruf['reportedUserId'], 'user-42');
    });

    testWidgets('beim Abbrechen geht nichts raus', (tester) async {
      await zeigeDialog(tester, nachricht: nachrichtMitBild());

      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        server.funktionsAufrufe,
        isEmpty,
        reason:
            'Bricht der Nutzer ab, wird das Bild sofort verworfen und '
            'nichts gesendet.',
      );
    });
  });
}
