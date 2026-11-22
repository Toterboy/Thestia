// Der Chat der Dating Hour (bisher ungetestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/dating_hour/dating_hour_chat_screen.dart 650 offene
// Zeilen - der Screen, in dem fuenf Minuten lang zwei fremde Menschen
// miteinander reden.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * der Leerzustand steht da (mit dem Gesprächsstarter),
//   * der Timer lässt sich aus- und wieder einblenden (Nutzerwunsch:
//     "einen Timer gibt, den man sichtbar und unsichtbar machen kann"),
//   * das Beenden des Gesprächs fragt erst nach,
//   * ohne Gegenstelle sagt die App, dass die Nachricht nicht rausging
//     (statt sie zu verschlucken),
//   * das Verlassen fragt nach.
//
// OHNE SERVER: Der Dating-Hour-Dienst und der Datenbank-Dienst werden
// durch Hand-Fakes ersetzt. Es geht KEINE Anfrage raus.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/dating_hour/dating_hour_models.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/dating_hour/dating_hour_chat_screen.dart';
import 'package:thestia/services/dating_hour/dating_hour_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/chat/relay_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';
import 'package:thestia/services/server/supabase_database_service.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/widgets/chat/funke_overlay.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM - die Einstellungen kommen daraus.
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _daten = {};

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
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

/// Hand-Fake des Dating-Hour-Dienstes.
///
/// Der echte Dienst spricht mit der Datenbank. Der Fake haelt die
/// Session im RAM und merkt sich, ob das Gespraech beendet wurde - so
/// wird sichtbar, ob die App wirklich beendet hat oder nur so tut.
class _FakeDatingHourService extends DatingHourService {
  _FakeDatingHourService(this.session);

  /// Die Session, die der Screen sehen soll.
  final DatingHourSession session;

  /// Die IDs der beendeten Gespraeche.
  final List<String> beendet = [];

  /// Die Session, die nach der Entscheidung zurueckkommt.
  ///
  /// DER GRUND: Nach dem Abstimmen entscheidet die App, ob es einen
  /// Funken gibt (beide haben "Annehmen" gedrueckt) oder nicht (einer
  /// hat abgelehnt). Der echte Dienst liest das aus der Datenbank - im
  /// Test kommt es von hier.
  DatingHourSession? entscheidung;

  /// Die Abstimmungen, die der Screen gemeldet hat.
  final List<({String userId, bool accept})> abstimmungen = [];

  /// Wenn gesetzt, schlaegt [getSession] mit diesem Fehler fehl.
  Object? ladeFehler;

  @override
  Future<DatingHourSession?> getSession(String sessionId) async {
    final fehler = ladeFehler;
    if (fehler != null) throw fehler;
    return session;
  }

  @override
  Future<DatingHourSession?> recordDecision(
    String sessionId,
    String userId,
    bool accept,
  ) async {
    abstimmungen.add((userId: userId, accept: accept));
    return entscheidung;
  }

  @override
  Future<bool> endConversation(String sessionId) async {
    beendet.add(sessionId);
    return true;
  }
}

/// Der Keystore ohne Plugin (das Profil liegt nur im RAM).
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Hand-Fake des Datenbank-Dienstes.
///
/// Nur das oeffentliche Profil des Chat-Partners wird beantwortet
/// (die Kopfzeile zeigt daraus die Gewohnheiten an).
class _FakeSupabaseDatabaseService extends SupabaseDatabaseService {
  _FakeSupabaseDatabaseService(super.client);

  @override
  Future<Map<String, dynamic>?> fetchPublicProfile(String userId) async {
    return {'smoking': 'nein', 'alcohol': 'selten', 'drugs': null};
  }
}

/// Der Relay-Dienst, der ablehnt.
///
/// DER GRUND (15.11.2026): Der Fehlerfall muss deterministisch sein.
/// Ueber den Server zu arbeiten (alles auf 500) haengt an der
/// Wiederholung im PreKey-Abruf - der Test laeuft dann in die
/// Wartezeit statt in die Aussage.
///
/// DER WEG: Der Fake wirft beim Ablegen sofort - so ist der Fall
/// "das Relay nimmt die Nachricht nicht" genau der, den der Bildschirm
/// dem Nutzer melden muss.
class _FakeRelayService extends RelayService {
  _FakeRelayService(super.ref);

  /// Die Texte, die abgelegt werden sollten.
  final List<String> abgelegt = <String>[];

  @override
  Future<void> storeText({
    required String peerId,
    required String text,
    String kind = 'text',
  }) async {
    abgelegt.add(text);
    throw StateError('Relay nicht erreichbar');
  }
}

/// Der P2P-Service ohne WebRTC.
///
/// DER GRUND (15.11.2026): Die echte Direktverbindung braucht das
/// WebRTC-Plugin - im Test gibt es kein Geraet. Ohne diesen Ersatz
/// bleibt `connect()` im EventChannel des Plugins HANGEN, und damit
/// auch der halbe Bildschirm-Aufbau.
class _FakeP2PChatService extends P2PChatService {
  _FakeP2PChatService(super.webrtc, super.prekey);

  @override
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {}

  @override
  Future<void> dispose() async {}
}

/// Der Router des Tests.
///
/// DER GRUND: Beim Funke ("Ein Funke ist uebersprungen!") und bei der
/// Absage ("Kein Funke") springt der Bildschirm weiter - `context.go`.
/// Ohne Router waere das ein Absturz - und der Test wuerde an einer
/// Stelle scheitern, an der der Bildschirm gar nichts falsch gemacht
/// hat.
GoRouter _router() {
  return GoRouter(
    initialLocation: '/dh',
    routes: [
      GoRoute(
        path: '/dh',
        builder: (_, _) => const DatingHourChatScreen(sessionId: 'session-1'),
      ),
      GoRoute(
        path: AppRoutes.interessen,
        builder: (_, _) => const Scaffold(body: Text('Funken')),
      ),
      GoRoute(
        path: AppRoutes.datingHourEvent,
        builder: (_, _) => const Scaffold(body: Text('Event')),
      ),
    ],
  );
}

void main() {
  /// Der Ersatz-Server (Antworten aus dem RAM).
  late FakeSupabaseServer server;

  setUpAll(() async {
    // DER SPEICHER DES GERAETS: der Auth-Client holt sich daraus die
    // Sitzung - ohne den Mock schlaegt der Aufbau fehl.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // DER SERVER: die Edge Functions (Push an die Gegenseite) gehen
    // ueber den Client - ohne den Ersatz-Server wartet der Aufruf.
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
    // ANGEMELDET: ohne Sitzung bricht der P2P-Aufbau ab (der Bildschirm
    // braucht die echte auth.uid() - kein Demo-Ersatz).
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
    // HIVE: die verschluesselten Schluessel (Signal-Protokoll) liegen in
    // Hive-Boxen. Ohne initialisierten Hive schlaegt der Aufbau fehl.
    final tempDir = await Directory.systemTemp.createTemp('thesia_dh');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  /// Die Session, die der Screen sehen soll: laeuft noch (4 Minuten
  /// Restzeit), niemand hat entschieden.
  DatingHourSession session() {
    final jetzt = DateTime.now();
    // ICH bin Teilnehmer B (der angemeldete Nutzer 'ich'): die Gegenseite
    // ist dann Teilnehmer A - so steht der Name in der Kopfzeile.
    return DatingHourSession(
      id: 'session-1',
      eventId: 'event-1',
      userA: 'partner',
      userB: 'ich',
      startedAt: jetzt.subtract(const Duration(minutes: 1)),
      expiresAt: jetzt.add(const Duration(minutes: 4)),
    );
  }

  /// Pumpt eine feste Zahl von Frames.
  ///
  /// `pumpAndSettle` waere hier falsch: der Timer tickt jede Sekunde -
  /// es wird nie "alles ruhig".
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Laesst die echte Ereignisschleife laufen.
  ///
  /// DER GRUND: Die HTTP-Anfragen (der serverseitige Like) kommen nur in
  /// der echten Ereignisschleife an - mit blossem "pump" bleiben sie
  /// haengen.
  Future<void> lassServerArbeiten(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Eine abgelaufene Session (die fuenf Minuten sind um).
  DatingHourSession abgelaufeneSession() {
    final jetzt = DateTime.now();
    return DatingHourSession(
      id: 'session-1',
      eventId: 'event-1',
      userA: 'partner',
      userB: 'ich',
      startedAt: jetzt.subtract(const Duration(minutes: 6)),
      expiresAt: jetzt.subtract(const Duration(minutes: 1)),
    );
  }

  /// Die Session, nach der BEIDE "Annehmen" gedrueckt haben.
  DatingHourSession gegenseitigAngenommen() {
    final jetzt = DateTime.now();
    return DatingHourSession(
      id: 'session-1',
      eventId: 'event-1',
      userA: 'partner',
      userB: 'ich',
      startedAt: jetzt.subtract(const Duration(minutes: 6)),
      expiresAt: jetzt.subtract(const Duration(minutes: 1)),
      userADecision: 'accept',
      userBDecision: 'accept',
      isMatch: true,
    );
  }

  /// Die Session, nach der einer abgelehnt hat.
  DatingHourSession abgelehnt() {
    final jetzt = DateTime.now();
    return DatingHourSession(
      id: 'session-1',
      eventId: 'event-1',
      userA: 'partner',
      userB: 'ich',
      startedAt: jetzt.subtract(const Duration(minutes: 6)),
      expiresAt: jetzt.subtract(const Duration(minutes: 1)),
      userADecision: 'reject',
      userBDecision: 'accept',
      endedAt: jetzt,
      isMatch: false,
    );
  }

  /// Baut den Screen mit den Fakes.
  ///
  /// [geburtsdatum] setzt das eigene Profil - ohne Geburtsdatum kennt
  /// der Bildschirm das eigene Alter nicht und kann den Alters-Hinweis
  /// fuer die Gegenseite nicht zeigen.
  ///
  /// [sitzung] ist die Session, die der Screen sehen soll (Standard:
  /// eine laufende Sitzung mit vier Minuten Restzeit).
  Future<_FakeDatingHourService> zeigeScreen(
    WidgetTester tester, {
    DateTime? geburtsdatum,
    DatingHourSession? sitzung,
    _FakeDatingHourService? dienst,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = dienst ?? _FakeDatingHourService(sitzung ?? session());
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(_FakeLocalStorage()),
          datingHourServiceProvider.overrideWithValue(service),
          supabaseDatabaseServiceProvider.overrideWithValue(
            _FakeSupabaseDatabaseService(supabase.Supabase.instance.client),
          ),
          p2pChatServiceProvider.overrideWith((ref) {
            final dienst = _FakeP2PChatService(
              ref.watch(webRTCServiceProvider),
              ref.watch(preKeyServiceProvider),
            );
            ref.onDispose(dienst.dispose);
            return dienst;
          }),
          // DER RELAY-FAKE: das Ablegen schlaegt fehl - so ist der
          // Fall "die Nachricht kommt nicht raus" bestimmt (und nicht
          // von einem Serverfehler abhaengig).
          relayServiceProvider.overrideWith((ref) => _FakeRelayService(ref)),
          if (geburtsdatum != null)
            profileProvider.overrideWith((ref) {
              final notifier = ProfileNotifier(
                _FakeLocalStorage(),
                _FakeSecureProfileStore(),
              );
              notifier.setProfile(
                UserProfile(
                  id: 'ich',
                  name: 'Lena',
                  bio: '',
                  birthDate: geburtsdatum,
                ),
              );
              return notifier;
            }),
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await pumpFrames(tester);
    return service;
  }

  group('Dating-Hour-Chat', () {
    testWidgets('baut sich ohne Absturz', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(DatingHourChatScreen), findsOneWidget);
    });

    testWidgets('der Leerzustand steht da', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Der Name der Gegenseite steht in der Kopfzeile.
      expect(find.text('Teilnehmer A'), findsWidgets);
      // Der Leerzustand erklaert, was los ist, und bietet den
      // Gesprächsstarter an - ein leerer Chat sonst wäre tote Hose.
      expect(find.textContaining('Sag hallo zu'), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('dh.chat.icebreakerBtn')),
        findsOneWidget,
      );
    });

    testWidgets('die Gewohnheiten der Gegenseite stehen in der Kopfzeile', (
      tester,
    ) async {
      await zeigeScreen(tester);

      // Der Chip wartet auf die Antwort des Servers - erst nach einem
      // weiteren Frame ist er da.
      await pumpFrames(tester);
      expect(find.text('Rauchen: nein'), findsOneWidget);
      expect(find.text('Alkohol: selten'), findsOneWidget);
    });

    testWidgets('der Timer lässt sich aus- und wieder einblenden', (
      tester,
    ) async {
      await zeigeScreen(tester);

      // Der Timer ist da (das E2E-Schild).
      expect(find.text(L10n.tWithoutContext('dh.chat.e2e')), findsOneWidget);
      expect(
        find.byTooltip(L10n.tWithoutContext('dh.chat.timerHide')),
        findsOneWidget,
      );

      // Ausblenden (NUTZERWUNSCH: der Timer soll auch unsichtbar sein).
      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('dh.chat.timerHide')),
      );
      await pumpFrames(tester);

      expect(find.text(L10n.tWithoutContext('dh.chat.e2e')), findsNothing);
      expect(
        find.byTooltip(L10n.tWithoutContext('dh.chat.timerShow')),
        findsOneWidget,
      );

      // Und wieder einblenden.
      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('dh.chat.timerShow')),
      );
      await pumpFrames(tester);

      expect(find.text(L10n.tWithoutContext('dh.chat.e2e')), findsOneWidget);
    });

    testWidgets('das Beenden des Gespraechs fragt erst nach', (tester) async {
      final service = await zeigeScreen(tester);

      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('dh.chat.endConversation')),
      );
      await pumpFrames(tester);

      // Die Rueckfrage steht da.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('dh.chat.endConversationTitle')),
        findsOneWidget,
      );
      // Und "Abbrechen" beendet wirklich NICHT.
      await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      await pumpFrames(tester);

      expect(service.beendet, isEmpty);
    });

    testWidgets('das Beenden des Gespraechs funktioniert', (tester) async {
      final service = await zeigeScreen(tester);

      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('dh.chat.endConversation')),
      );
      await pumpFrames(tester);
      await tester.tap(
        find.text(L10n.tWithoutContext('dh.chat.endConversation')),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Server wurde wirklich informiert ...
      expect(service.beendet, contains('session-1'));
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(
        find.text(L10n.tWithoutContext('dh.chat.endConversationDone')),
        findsOneWidget,
      );
    });

    testWidgets(
      'ohne Gegenstelle meldet die App die fehlgeschlagene Nachricht',
      (tester) async {
        await zeigeScreen(tester);

        // Der Gesprächsstarter schreibt die Nachricht und sendet sie.
        await tester.tap(
          find.text(L10n.tWithoutContext('dh.chat.icebreakerBtn')),
        );
        await pumpFrames(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext('dh.chat.sendFailed')),
          findsOneWidget,
          reason:
              'Ohne Gegenstelle muss der Nutzer erfahren, dass die Nachricht '
              'nicht rausging - sonst schreibt er ins Leere.',
        );
      },
    );

    testWidgets('bei grosser Altersdifferenz steht ein Hinweis da', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // ICH bin 30, die Gegenseite 60 - zehn Jahre Unterschied.
      server.rpcAntworten['get_public_profile'] = <String, dynamic>{'age': 60};
      await zeigeScreen(
        tester,
        geburtsdatum: DateTime.now().subtract(const Duration(days: 365 * 30)),
      );
      await pumpFrames(tester);
      // Der RPC-Abruf braucht echte Zeit (die Antwort kommt aus der
      // echten Event-Loop) - ohne das steht der Hinweis noch nicht da.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('mindestens 10 Jahre'),
        findsOneWidget,
        reason:
            'Bei zehn Jahren Unterschied oder mehr muss der Chat darauf '
            'hinweisen - das ist der Schutz vor einem Altersmissverstaendnis.',
      );
    });

    testWidgets('das Verlassen fragt nach', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(find.byIcon(Icons.close));
      await pumpFrames(tester);

      // Die Rueckfrage steht da - ohne sie waere der Chat nach einem
      // Fehlgriff weg.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('dh.chat.leaveTitle')),
        findsOneWidget,
      );
      expect(find.text(L10n.tWithoutContext('dh.chat.stay')), findsOneWidget);
    });

    // Die fuenf Minuten sind um: jetzt entscheidet der Nutzer, ob es
    // einen Funken geben soll. Das ist der wichtigste Moment im
    // Dating-Hour-Chat - bisher war er untestet.
    testWidgets('ein Fehler beim Laden wird dem Nutzer gesagt', (tester) async {
      final dienst = _FakeDatingHourService(session());
      // Die Sitzung laesst sich nicht laden (z. B. weil der Server sie
      // schon geloescht hat).
      dienst.ladeFehler = DatingHourException('Die Sitzung ist weg.');
      await zeigeScreen(tester, dienst: dienst);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Die Sitzung ist weg.'),
        findsWidgets,
        reason:
            'Der Nutzer muss erfahren, warum der Chat leer bleibt - sonst '
            'glaubt er, es ist ein Fehler der App.',
      );
    });

    group('Nach den fuenf Minuten', () {
      testWidgets('die App fragt nach der Entscheidung', (tester) async {
        await zeigeScreen(tester, sitzung: abgelaufeneSession());

        // Der Timer tickt jede Sekunde - nach einer Sekunde fragt die App.
        await tester.pump(const Duration(seconds: 2));
        await pumpFrames(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext('dh.chat.accept')),
          findsOneWidget,
          reason:
              'Nach den fuenf Minuten muss der Nutzer entscheiden koennen - '
              'sonst laeuft das Gespraech ohne Ende weiter.',
        );
        expect(
          find.text(L10n.tWithoutContext('dh.chat.decline')),
          findsOneWidget,
        );
      });

      testWidgets('wenn beide annehmen, gibt es einen Funken', (tester) async {
        final service = await zeigeScreen(
          tester,
          sitzung: abgelaufeneSession(),
        );
        // Die Gegenseite hat auch "Annehmen" gedrueckt.
        service.entscheidung = gegenseitigAngenommen();

        await tester.pump(const Duration(seconds: 2));
        await pumpFrames(tester);

        await tester.tap(find.text(L10n.tWithoutContext('dh.chat.accept')));
        await pumpFrames(tester);
        await lassServerArbeiten(tester);

        expect(tester.takeException(), isNull);
        // Die eigene Abstimmung ging wirklich an den Dienst.
        expect(service.abstimmungen, hasLength(1));
        expect(service.abstimmungen.first.accept, isTrue);

        // Die Funke-Animation steht da - der Nutzer soll den Moment sehen.
        expect(find.byType(FunkeOverlay), findsOneWidget);
        // Ein Tipp schliesst sie sofort.
        await tester.tapAt(const Offset(20, 20));
        await pumpFrames(tester);
        await lassServerArbeiten(tester);

        // Und der Nutzer erfaehrt, was passiert ist.
        expect(
          find.textContaining(
            L10n.tWithoutContext('dh.chat.sparkJumped').split(' ').first,
          ),
          findsWidgets,
        );
        // Der Bildschirm springt zu den Funken (der neue Funke waere
        // sonst unsichtbar).
        await tester.pump(const Duration(milliseconds: 1600));
        await pumpFrames(tester);
        expect(find.text('Funken'), findsOneWidget);
      });

      testWidgets('wenn einer ablehnt, gibt es keinen Funken', (tester) async {
        final service = await zeigeScreen(
          tester,
          sitzung: abgelaufeneSession(),
        );
        // Die Gegenseite hat abgelehnt.
        service.entscheidung = abgelehnt();

        await tester.pump(const Duration(seconds: 2));
        await pumpFrames(tester);

        await tester.tap(find.text(L10n.tWithoutContext('dh.chat.decline')));
        await pumpFrames(tester);
        await lassServerArbeiten(tester);

        expect(tester.takeException(), isNull);
        expect(service.abstimmungen.first.accept, isFalse);
        // Der Nutzer sieht klar, dass es keinen Funke gibt.
        expect(
          find.text(L10n.tWithoutContext('dh.chat.noSpark')),
          findsOneWidget,
          reason:
              'Der Nutzer muss erfahren, dass kein Funke entstanden ist - '
              'sonst wartet er vergeblich.',
        );
        expect(
          find.text(L10n.tWithoutContext('dh.chat.keepSearching')),
          findsOneWidget,
        );

        // "Weiter suchen" bringt ihn zur Uebersicht.
        await tester.tap(
          find.text(L10n.tWithoutContext('dh.chat.keepSearching')),
        );
        await pumpFrames(tester);
        expect(find.text('Event'), findsOneWidget);
      });
    });

    // Das Warten auf die Gegenseite (ANLASS 22.11.2026: Die Coverage-
    // Messung zeigte fuer lib/screens/dating_hour/parts/waitingforpartner.dart
    // 0 % - der Bildschirm, in dem man nach der eigenen Entscheidung
    // wartet, war komplett ungetestet).
    group('Das Warten auf die Gegenseite', () {
      testWidgets('nach der eigenen Entscheidung wartet die App', (
        tester,
      ) async {
        final service = await zeigeScreen(
          tester,
          sitzung: abgelaufeneSession(),
        );
        // DIE GEGENSEITE HAT NOCH NICHT ENTSCHIEDEN: Der Dienst meldet
        // eine Session, in der nur ich entschieden habe.
        service.entscheidung = abgelaufeneSession();

        await tester.pump(const Duration(seconds: 2));
        await pumpFrames(tester);

        await tester.tap(find.text(L10n.tWithoutContext('dh.chat.accept')));
        await pumpFrames(tester);
        await lassServerArbeiten(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext('dh.chat.voted')),
          findsOneWidget,
          reason:
              'Nach der eigenen Entscheidung muss der Nutzer sehen, dass '
              'die App wartet - sonst tippt er vergeblich weiter.',
        );
        expect(
          find.text(L10n.tWithoutContext('dh.chat.resultPending')),
          findsOneWidget,
          reason: 'Der Grund des Wartens muss benannt sein.',
        );
      });

      testWidgets('der Weg zurueck zur Uebersicht steht da', (tester) async {
        final service = await zeigeScreen(
          tester,
          sitzung: abgelaufeneSession(),
        );
        service.entscheidung = abgelaufeneSession();

        await tester.pump(const Duration(seconds: 2));
        await pumpFrames(tester);

        await tester.tap(find.text(L10n.tWithoutContext('dh.chat.accept')));
        await pumpFrames(tester);
        await lassServerArbeiten(tester);

        // DER KNOPF: Er bringt zur Uebersicht der Runden.
        final knopf = find.text(L10n.tWithoutContext('dh.chat.backToOverview'));
        expect(knopf, findsOneWidget);
        await tester.tap(knopf);
        await pumpFrames(tester);

        expect(
          find.text('Event'),
          findsOneWidget,
          reason:
              'Wer nicht mehr wartet, muss wieder in die Uebersicht kommen '
              '- sonst sitzt er in einem leeren Chat fest.',
        );
      });
    });
  });
}
