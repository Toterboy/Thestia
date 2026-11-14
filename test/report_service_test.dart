// Unit-Tests fuer die Melde-Funktion (Reports).
//
// WAS HIER GEPRUEFT WIRD:
//   * die Pseudonymisierung der Nutzer-IDs (SHA-256, H-06/X-M-08),
//   * das Anlegen einer Meldung (lokal in Hive + beim Support),
//   * die Whitelist der Meldetypen und der Melde-Text,
//   * das Melden mit angehaengten Nachrichten (Bild-Meldung),
//   * die Filter der Liste (nach Melder, nach gemeldetem Nutzer, nach Tag),
//   * die Fehlerfaelle: Serverfehler, leere Antworten.
//
// WIE DER SERVER ERSETZT WIRD:
//   Der Service spricht mit Supabase ueber HTTP. Ein handgeschriebener
//   Fake ([_FakeServer]) beantwortet die drei RPCs (submit_report,
//   list_my_reports, list_blocked_users). Der Keystore von flutter_secure_storage
//   ( fuer die verschluesselte Hive-Box) wird ueber den Method-Channel
//   mit einem In-Memory-Speicher beantwortet.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/message.dart';
import 'package:thestia/models/report_models.dart';
import 'package:thestia/services/report_service.dart';

/// Der Kanal von flutter_secure_storage ( fuer die Hive-Verschluesselung).
const MethodChannel _keystoreKanal = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Der In-Memory-Keystore des Tests.
final Map<String, String> _keystore = <String, String>{};

/// Beantwortet die Keystore-Aufrufe.
Future<Object?> _keystoreAntwort(MethodCall anfrage) async {
  final args = (anfrage.arguments as Map?)?.cast<String, dynamic>() ?? {};
  switch (anfrage.method) {
    case 'read':
      return _keystore[args['key'] as String?];
    case 'write':
      _keystore[args['key'] as String] = args['value'] as String;
      return null;
    case 'delete':
      _keystore.remove(args['key']);
      return null;
    case 'containsKey':
      return _keystore.containsKey(args['key']);
    case 'readAll':
      return Map<String, String>.from(_keystore);
    case 'deleteAll':
      _keystore.clear();
      return null;
  }
  return null;
}

/// Der handgeschriebene Supabase-Server fuer die Report-RPCs.
class _FakeServer {
  _FakeServer();

  /// Die Anfragen, die der Server gesehen hat (inkl. Query).
  final List<String> anfragen = [];

  /// Die Koerper der RPC-Aufrufe (nach RPC-Namen).
  final Map<String, List<Map<String, dynamic>>> koerper = {};

  /// Die Antwort von list_my_reports.
  List<Map<String, dynamic>> eigeneMeldungen = [];

  /// Die Antwort von list_blocked_users.
  List<Map<String, dynamic>> blockierte = [];

  /// Wenn true, schlaegt submit_report mit einem Serverfehler fehl.
  bool submitFehler = false;

  /// Die Anfrage, die gerade beantwortet wird.
  http.Request? _aktuell;

  void _notiere(String rpc, Map<String, dynamic> parameter) {
    koerper[rpc] ??= [];
    koerper[rpc]!.add(parameter);
  }

  http.Response antworte(http.Request anfrage) {
    _aktuell = anfrage;
    final pfad = anfrage.url.path;
    anfragen.add('${anfrage.method} $pfad');

    if (pfad.contains('/rest/v1/rpc/')) {
      final rpc = pfad.split('/rest/v1/rpc/').last;
      // DER GRUND: Ein RPC ohne Parameter hat den Koerper "null" - der
      // darf nicht als Karte gelesen werden.
      final parameter = anfrage.body.isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(anfrage.body) as Map<String, dynamic>? ??
                <String, dynamic>{});
      _notiere(rpc, parameter);
      switch (rpc) {
        case 'submit_report':
          if (submitFehler) {
            return _json({'message': 'Serverfehler'}, 500);
          }
          return _json(null, 200);
        case 'list_my_reports':
          return _json(eigeneMeldungen);
        case 'list_blocked_users':
          return _json(blockierte);
        case 'unblock_user':
          return _json(true);
      }
    }

    return _json({}, 404);
  }

  http.Response _json(Object? inhalt, [int status = 200]) => http.Response(
    jsonEncode(inhalt),
    status,
    headers: {'content-type': 'application/json'},
    // DER GRUND: PostgREST liest die Methode aus "response.request" - ohne
    // das Feld stuerzt der Client auf einem Null-Check ab.
    request: _aktuell,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeServer server;
  late ReportService service;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('thestia_report_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(UserReportAdapter().typeId)) {
      Hive.registerAdapter(UserReportAdapter());
    }
    // BEFUND (13.11.2026): main.dart registriert nur den UserReportAdapter,
    // NICHT den ReportTypeAdapter (lib/main.dart:609-620). Ohne den
    // Enum-Adapter kann Hive den Meldetyp nicht schreiben ("Cannot write,
    // unknown type: ReportType") - die Meldung wird dann schon beim
    // lokalen Speichern abgewiesen und kommt nie beim Support an. Der
    // Test registriert den Adapter deshalb ausdruecklich, damit er das
    // gewuenschte Verhalten pruefen kann.
    if (!Hive.isAdapterRegistered(ReportTypeAdapter().typeId)) {
      Hive.registerAdapter(ReportTypeAdapter());
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystoreKanal, _keystoreAntwort);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();

    server = _FakeServer();
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'test-key',
      httpClient: MockClient((anfrage) async => server.antworte(anfrage)),
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );

    service = ReportService();
    await service.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystoreKanal, null);
  });

  setUp(() async {
    server.anfragen.clear();
    server.koerper.clear();
    server.eigeneMeldungen = [];
    server.blockierte = [];
    server.submitFehler = false;
    // Die Meldungen der vorherigen Tests wegraeumen, damit die Filter
    // jeweils nur ihre eigenen Meldungen sehen.
    await service.clearDrafts();
  });

  group('hashPii', () {
    test('die Kennung wird pseudonymisiert (SHA-256)', () {
      // DER GRUND (H-06/X-M-08): Bei einer Storage-Inspektion (verlorenes
      // Geraet, Debug-Bridge) darf nicht lesbar sein, wer gemeldet hat.
      expect(
        hashPii('reporter-1'),
        'd10b749e163a296ee0916a4fd2326c33721246622f243fd2c242ec61cfbe731e',
      );
      expect(
        hashPii('opfer-1'),
        '65e964b14a35691d3eb5a7364d2511d039bf4aca6c9b82db202c114e4bb64dcf',
      );
    });

    test('die Rohkennung steht nirgends im Hash', () {
      final hash = hashPii('reporter-1');

      expect(hash, isNot(contains('reporter-1')));
      expect(hash.length, 64, reason: 'SHA-256 liefert 64 Hex-Zeichen');
    });

    test('gleiche Eingabe, gleicher Hash - und leere Eingabe auch', () {
      expect(hashPii('gleich'), hashPii('gleich'));
      expect(hashPii(''), isNotEmpty);
    });
  });

  group('MyReportEntry', () {
    test('die Felder werden gelesen, der Status defaultet auf "pending"', () {
      final eintrag = MyReportEntry.fromJson({'id': 'meldung-1'});

      expect(eintrag.id, 'meldung-1');
      expect(eintrag.reportType, '');
      expect(eintrag.status, 'pending');
      expect(eintrag.createdAt, isNull);
    });

    test('das Status-Label unterscheidet "in Pruefung" und "geprueft"', () {
      expect(
        MyReportEntry.fromJson({'id': 'a', 'status': 'pending'}).statusLabel,
        'Wird geprüft',
      );
      expect(
        MyReportEntry.fromJson({'id': 'b', 'status': 'reviewed'}).statusLabel,
        'Wurde geprüft',
      );
    });
  });

  group('BlockedUserEntry', () {
    test('die Felder werden gelesen, der Name defaultet', () {
      final eintrag = BlockedUserEntry.fromJson({'blockedUserId': 'nutzer-9'});

      expect(eintrag.blockedUserId, 'nutzer-9');
      expect(eintrag.name, 'Unbekannt');
      expect(eintrag.createdAt, isNull);
    });

    test('ein gesetzter Zeitstempel wird gelesen', () {
      final eintrag = BlockedUserEntry.fromJson({
        'blockedUserId': 'nutzer-9',
        'name': 'Mara',
        'createdAt': '2026-11-01T10:00:00Z',
      });

      expect(eintrag.name, 'Mara');
      expect(eintrag.createdAt, DateTime.tryParse('2026-11-01T10:00:00Z'));
    });
  });

  group('ReportService.createReport', () {
    test('die Meldung landet lokal und beim Support', () async {
      final ergebnis = await service.createReport(
        reporterId: 'reporter-1',
        reporterUserName: 'Lena',
        reportedUserId: 'opfer-1',
        reportedUserName: 'Mara',
        type: ReportType.harassment,
        description: 'Beleidigungen im Chat',
      );

      expect(
        ergebnis.serverAccepted,
        isTrue,
        reason: 'Der Server hat die Meldung angenommen.',
      );
      expect(ergebnis.report.type, ReportType.harassment);
      expect(ergebnis.report.description, 'Beleidigungen im Chat');
      expect(
        server.koerper['submit_report'],
        isNotNull,
        reason: 'Die Meldung muss beim Support ankommen.',
      );
    });

    test('lokal werden nur die Hashes gespeichert', () async {
      // DER GRUND (X-M-07/X-M-08): Wer gemeldet hat und wer gemeldet
      // wurde, darf auf dem Geraet nicht im Klartext liegen.
      final ergebnis = await service.createReport(
        reporterId: 'reporter-1',
        reporterUserName: 'Lena',
        reportedUserId: 'opfer-1',
        reportedUserName: 'Mara',
        type: ReportType.spam,
      );

      expect(ergebnis.report.reporterId, hashPii('reporter-1'));
      expect(ergebnis.report.reportedUserId, hashPii('opfer-1'));
      expect(
        ergebnis.report.id.contains('reporter-1'),
        isFalse,
        reason:
            'Der Hive-Schluessel darf keine Nutzer-ID enthalten - er ist '
            'sonst im Klartext lesbar.',
      );
    });

    test('an den Server geht die ROH-ID des gemeldeten Nutzers', () async {
      // DER GRUND (Audit N-18): Der Server braucht die echte ID fuer
      // Moderation und RLS. Nur die lokale Ablage ist pseudonymisiert.
      await service.createReport(
        reporterId: 'reporter-1',
        reporterUserName: 'Lena',
        reportedUserId: 'opfer-1',
        reportedUserName: 'Mara',
        type: ReportType.fakeProfile,
      );

      final parameter = server.koerper['submit_report']!.single;
      expect(parameter['p_reported_user_id'], 'opfer-1');
      expect(parameter['p_report_type'], 'fakeProfile');
      expect(parameter['p_description'], isNull);
      expect(parameter['p_messages'], isEmpty);
    });

    test('alle Meldetypen sind erlaubt und behalten ihren Namen', () async {
      // DER GRUND: Die Whitelist der Typen (H-06) ist servergebunden -
      // der Client muss jeden erlaubten Typ auch melden koennen. Der
      // Wert [ReportType.value] geht an den Server.
      for (final typ in ReportType.values) {
        final ergebnis = await service.createReport(
          reporterId: 'reporter-1',
          reporterUserName: 'Lena',
          reportedUserId: 'opfer-1',
          reportedUserName: 'Mara',
          type: typ,
        );

        expect(ergebnis.report.type, typ);
        expect(
          server.koerper['submit_report']!.last['p_report_type'],
          typ.value,
        );
      }
    });

    test('der Melde-Text wird unveraendert an den Server gereicht', () async {
      // DER GRUND: Das Trimmen passiert im Melde-Dialog, nicht im
      // Service - der Service reicht den Text unveraendert durch. Und
      // "kein Text" (null) geht als null an den Server, nicht als
      // Leerstring.
      await service.createReport(
        reporterId: 'reporter-1',
        reporterUserName: 'Lena',
        reportedUserId: 'opfer-1',
        reportedUserName: 'Mara',
        type: ReportType.other,
        description: '  Ein Text  ',
      );
      expect(
        server.koerper['submit_report']!.single['p_description'],
        '  Ein Text  ',
      );

      await service.createReport(
        reporterId: 'reporter-1',
        reporterUserName: 'Lena',
        reportedUserId: 'opfer-1',
        reportedUserName: 'Mara',
        type: ReportType.other,
      );
      expect(server.koerper['submit_report']!.last['p_description'], isNull);
    });

    test('eine Bild-Meldung haengt die Nachrichten an', () async {
      // DER GRUND: Chats sind E2E-verschluesselt - nur ueber die Meldung
      // kann der Support den Inhalt sehen. Die angehaengten Nachrichten
      // sind deshalb genau der Punkt der Meldung.
      final jetzt = DateTime.now();
      await service.createReport(
        reporterId: 'reporter-1',
        reporterUserName: 'Lena',
        reportedUserId: 'opfer-1',
        reportedUserName: 'Mara',
        type: ReportType.inappropriateContent,
        description: 'Unangemessenes Bild',
        messages: [
          Message(
            id: 'm1',
            senderId: 'opfer-1',
            receiverId: 'reporter-1',
            text: 'Hier ist ein Foto',
            type: MessageType.image,
            mediaUrl: 'https://beispiel.de/bild.jpg',
            timestamp: jetzt,
          ),
        ],
      );

      final nachrichten =
          server.koerper['submit_report']!.single['p_messages'] as List;
      expect(nachrichten.length, 1);
      final nachricht = nachrichten.single as Map<String, dynamic>;
      expect(nachricht['sender_id'], 'opfer-1');
      expect(nachricht['type'], 'image');
      expect(nachricht['media_url'], 'https://beispiel.de/bild.jpg');
      expect(nachricht['text'], 'Hier ist ein Foto');
      expect(nachricht['sent_at'], jetzt.toIso8601String());
    });

    test('ein Serverfehler: die Meldung bleibt lokal, der Nutzer wird '
        'gewarnt', () async {
      // DER GRUND (Security-Audit 22.10.2026): Eine Meldung, die nicht
      // ankommt, ist keine Meldung. Das Ergebnis muss dem Aufrufer
      // sagen, dass der Server sie nicht angenommen hat.
      server.submitFehler = true;

      final ergebnis = await service.createReport(
        reporterId: 'reporter-1',
        reporterUserName: 'Lena',
        reportedUserId: 'opfer-1',
        reportedUserName: 'Mara',
        type: ReportType.childSafety,
      );

      expect(ergebnis.serverAccepted, isFalse);
      expect(
        service.getReportsByReporter('reporter-1'),
        hasLength(1),
        reason:
            'Die Meldung muss lokal bleiben - der Nutzer kann sie sonst '
            'spaeter erneut senden.',
      );
    });
  });

  group('ReportService.Filter', () {
    Future<void> meldungenAnlegen() async {
      await service.createReport(
        reporterId: 'reporter-1',
        reporterUserName: 'Lena',
        reportedUserId: 'opfer-1',
        reportedUserName: 'Mara',
        type: ReportType.harassment,
        description: 'erste',
      );
      await service.createReport(
        reporterId: 'reporter-2',
        reporterUserName: 'Tom',
        reportedUserId: 'opfer-2',
        reportedUserName: 'Kim',
        type: ReportType.spam,
        description: 'zweite',
      );
    }

    test('nach Melder gefiltert (ueber den Hash)', () async {
      await meldungenAnlegen();

      final liste = service.getReportsByReporter('reporter-1');

      expect(liste.length, 1);
      expect(liste.single.description, 'erste');
      expect(
        service.getReportsByReporter('gibt-es-nicht'),
        isEmpty,
        reason: 'Ein unbekannter Melder darf keine Meldungen sehen.',
      );
    });

    test('nach gemeldetem Nutzer gefiltert (ueber den Hash)', () async {
      await meldungenAnlegen();

      final liste = service.getReportsAgainstUser('opfer-2');

      expect(liste.length, 1);
      expect(liste.single.description, 'zweite');
    });

    test('die offenen Meldungen sind alle "pending"', () async {
      await meldungenAnlegen();

      expect(service.getPendingReports(), hasLength(2));
    });

    test('die Tagesliste nimmt nur die Meldungen des Tages', () async {
      await meldungenAnlegen();
      final heute = DateTime.now();

      expect(service.getReportsForDay(heute), hasLength(2));
      expect(
        service.getReportsForDay(heute.subtract(const Duration(days: 1))),
        isEmpty,
        reason:
            'Gestern gemeldete Meldungen gehoeren nicht in die Tagesliste '
            'von heute.',
      );
    });
  });

  group('ReportService.updateReportStatus', () {
    test(
      'der Status wird gesetzt und die Meldung als geprueft markiert',
      () async {
        final ergebnis = await service.createReport(
          reporterId: 'reporter-1',
          reporterUserName: 'Lena',
          reportedUserId: 'opfer-1',
          reportedUserName: 'Mara',
          type: ReportType.spam,
        );

        await service.updateReportStatus(
          ergebnis.report.id,
          'action_taken',
          moderatorNote: 'Konto gesperrt',
        );

        final meldung = service.getPendingReports();
        expect(
          meldung,
          isEmpty,
          reason: 'Die Meldung ist nicht mehr "pending".',
        );
        expect(
          service.getReportsByReporter('reporter-1').single.status,
          'action_taken',
        );
        expect(
          service.getReportsByReporter('reporter-1').single.moderatorNote,
          'Konto gesperrt',
        );
        expect(
          service.getReportsByReporter('reporter-1').single.resolvedAt,
          isNotNull,
          reason: 'Eine abgeschlossene Meldung braucht einen Zeitstempel.',
        );
      },
    );

    test('eine unbekannte Meldung wird ignoriert', () async {
      await expectLater(
        service.updateReportStatus('gibt-es-nicht', 'reviewed'),
        completes,
        reason: 'Ein unbekannter Aufruf darf nicht crashen.',
      );
    });
  });

  group('ReportService.clearDrafts', () {
    test('die lokalen Entwuerfe werden geloescht', () async {
      await service.createReport(
        reporterId: 'reporter-1',
        reporterUserName: 'Lena',
        reportedUserId: 'opfer-1',
        reportedUserName: 'Mara',
        type: ReportType.spam,
      );

      await service.clearDrafts();

      expect(service.getReportsByReporter('reporter-1'), isEmpty);
    });
  });

  group('ReportService.listMyReports', () {
    test('die eigenen Meldungen kommen vom Server', () async {
      server.eigeneMeldungen = [
        {
          'id': 'meldung-1',
          'reportType': 'spam',
          'status': 'pending',
          'createdAt': '2026-11-01T10:00:00Z',
        },
      ];

      final liste = await service.listMyReports();

      expect(liste.length, 1);
      expect(liste.single.id, 'meldung-1');
      expect(liste.single.reportType, 'spam');
      expect(liste.single.statusLabel, 'Wird geprüft');
    });

    test('eine leere Serverantwort ergibt eine leere Liste', () async {
      server.eigeneMeldungen = [];

      expect(await service.listMyReports(), isEmpty);
    });
  });

  group('ReportService.listBlockedUsers', () {
    test('die blockierten Nutzer kommen vom Server', () async {
      server.blockierte = [
        {'blockedUserId': 'nutzer-1', 'name': 'Mara'},
      ];

      final liste = await service.listBlockedUsers();

      expect(liste.length, 1);
      expect(liste.single.blockedUserId, 'nutzer-1');
      expect(liste.single.name, 'Mara');
    });

    test('eine leere Serverantwort ergibt eine leere Liste', () async {
      server.blockierte = [];

      expect(await service.listBlockedUsers(), isEmpty);
    });
  });

  group('ReportService.unblockUser', () {
    test('die Blockierung wird beim Server aufgehoben', () async {
      await service.unblockUser('nutzer-7');

      expect(server.koerper['unblock_user']?.single['p_blocked'], 'nutzer-7');
    });
  });
}
