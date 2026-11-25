// Die Wege des Funken-Tabs, die die Coverage-Messung als offen zeigte.
//
// ANLASS (25.11.2026): Die Coverage-Messung meldete fuer
// lib/screens/interests/parts/matchestabstate.dart 57 offene Zeilen -
// genau die Wege, die der Betreiber im November 2026 benutzt hat.
//
// WAS HIER GEPRUEFT WIRD (und was der Nutzer davon merkt):
//   * Beim Zurueckkommen aus dem Chat laedt die Funkenliste neu - im
//     Chat kann ja dazwischen geschrieben worden sein.
//   * Ein Funke ohne Aktivitaet wandert nach 72 Stunden von allein in die
//     "Archivierten Funken"; eine frische Nachricht oder ein Re-Funke
//     haelt ihn am Leben.
//   * Wird der LETZTE Funke abgewahlt, endet der Auswahl-Modus von
//     selbst - der Nutzer muss nicht noch auf "Abbrechen" tippen.
//   * Der Absage-Text beim Beenden geht wirklich als Nachricht raus und
//     die Gegenseite wird benachrichtigt (gegen das Ghosting).
//   * Das Oeffnen eines Funken geht in den Chat - auch dann, wenn die
//     einmalige Rueckfrage beim automatischen Funke scheitert.
//   * Ein Fehler beim Loeschen wird dem Nutzer gemeldet (nicht
//     verschluckt).
//   * Ein Chat mit ungelesenen Nachrichten steht oben in der Liste; bei
//     gleicher Zahl gewinnt der juengste Funke.
//   * Der Re-Funke meldet einen Fehler.
//   * Das gespeicherte Profil (QR-Kontakt) laesst sich oeffnen.
//
// NICHT TESTBAR (und warum):
//   * Der Leerzustand und der RefreshIndicator OHNE Einbettung - der
//     Abschnitt "_MatchesTab" ist privat, und die App benutzt ihn immer
//     eingebettet ("embedded: true"). Ein Test kann die private Klasse
//     nicht erzeugen.
//   * "Ein bereits gekuehlter Funke wird nochmal gekuehlt" - der Knopf
//     "Archivieren" steht nur an den Kacheln der AKTIVEN Funken (und an
//     den fixierten, die auch aktiv sind). Ein gekuehlter Funke hat seine
//     eigene Kachel ohne diesen Knopf - der Weg ist im Bildschirm nicht
//     erreichbar.
//
// OHNE SERVER: Der Find-your-Match-Service wird durch einen Hand-Fake
// ersetzt (test/interests_screen/hilfen.dart). Der Supabase-Client zeigt
// auf einen Ersatz-Server (test/support/fake_supabase_server.dart), damit
// die RPC und die Edge-Funktion beantwortet werden.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/find_match_models.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/interests/interessen_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/chat/relay_service.dart';
import 'package:thestia/services/dating_hour/find_your_match_service.dart';
import 'package:thestia/services/storage/local_storage.dart';

import '../../interests_screen/hilfen.dart';
import '../../support/fake_supabase_server.dart';
import '../../support/plugin_mocks.dart';

/// Das Relay als Ersatz: merkt sich, was zugestellt wurde.
///
/// DER GRUND: Der echte Relay-Dienst verschluesselt die Nachricht mit
/// Signal und legt sie beim Server ab. Das kann der Test nicht - der
/// Ersatz merkt sich nur, WELCHER Text an WEN geht. Genau das ist die
/// Frage des Nutzers: "ist mein Absage-Text angekommen?"
class FakeRelayService extends RelayService {
  FakeRelayService(super.ref);

  /// Die zugestellten Texte (Partner-ID und Text).
  final List<({String peerId, String text})> zugestellt =
      <({String peerId, String text})>[];

  @override
  Future<void> storeText({
    required String peerId,
    required String text,
    String kind = 'text',
  }) async {
    zugestellt.add((peerId: peerId, text: text));
  }
}

/// Der Find-your-Match-Dienst mit zusaetzlichen Fehlerwegen.
///
/// DER GRUND: Der gemeinsame Ersatz kann nur beim Laden, Kuehlen und
/// Ausblenden scheitern. Fuer "Loeschen" und "Re-Funke" braucht es
/// eigene Fehler - dort soll der Nutzer ja auch erfahren, wenn es
/// nicht geklappt hat.
class FehlerDienst extends FakeFindYourMatchService {
  FehlerDienst(super.client);

  /// Wirft [endMatch] diesen Fehler (null = alles gut).
  Object? endFehler;

  /// Wirft [resparkMatch] diesen Fehler (null = alles gut).
  Object? resparkFehler;

  @override
  Future<void> endMatch(int matchId) async {
    final fehler = endFehler;
    if (fehler != null) throw fehler;
    beendet.add(matchId);
  }

  @override
  Future<void> resparkMatch(int matchId) async {
    final fehler = resparkFehler;
    if (fehler != null) throw fehler;
    wiederEntzuend.add(matchId);
  }
}

/// Ein Funke fuer den Test - mit eigener Person und eigenen Zeiten.
MatchWithState funkeVon({
  required int id,
  required String personId,
  required String name,
  DateTime? erstellt,
  DateTime? reEntzuendet,
  String status = 'active',
  bool autoMatch = false,
}) {
  return MatchWithState(
    matchId: id,
    partner: person(id: personId, name: name),
    unlockLevel: 2,
    failedAttempts: 0,
    createdVia: 'swipe',
    status: status,
    // FRISCH: ein alter Funke wuerde von der Auto-Kuehlung (72 h)
    // erfasst - das will der Test nur, wenn er es sagt.
    createdAt: erstellt ?? DateTime.now(),
    resparkedAt: reEntzuendet,
    autoMatch: autoMatch,
  );
}

/// Der Router des Tests - mit dem Routen-Beobachter der App.
///
/// DER GRUND: Der Beobachter meldet dem Tab, dass der Nutzer
/// zurueckgekommen ist - dann laedt der Tab neu. Ohne den Beobachter
/// koennte der Test diesen Weg gar nicht stellen.
GoRouter _router() {
  return GoRouter(
    initialLocation: '/interessen',
    observers: <NavigatorObserver>[routeObserver],
    routes: <RouteBase>[
      GoRoute(
        path: '/interessen',
        builder: (context, state) => const InteressenScreen(),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Chat'))),
      ),
      GoRoute(
        path: '/profile/:id',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Profil'))),
      ),
    ],
  );
}

/// Baut den Screen auf (wie die anderen Tests des Bildschirms).
///
/// [groesse] ist die Bildschirmgroesse. Manche Tests brauchen einen
/// breiteren Bildschirm - das wird dort begruendet.
Future<void> _pump(
  WidgetTester tester, {
  required FindYourMatchService service,
  List<Override> overrides = const <Override>[],
  Size groesse = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(groesse);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(FakeLocalStorage()),
        findYourMatchServiceProvider.overrideWithValue(service),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: ThemeData(useMaterial3: true),
        routerConfig: router,
      ),
    ),
  );
  await pumpFrames(tester);
}

/// Der Dienst fuer die meisten Tests.
FehlerDienst _dienst() => FehlerDienst(supabase.Supabase.instance.client);

/// Das Menue (die drei Punkte) der Kachel mit diesem Namen.
///
/// DER GRUND: Die Kacheln liegen untereinander - ohne den Umweg ueber
/// den Namen wuerde der Test das Menue der FALSCHEN Kachel antippen.
Finder _menueVon(String name) {
  return find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(Card)),
    matching: find.byIcon(Icons.more_vert),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
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
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.pfade.clear();
    server.rpcAufrufe.clear();
    server.rpcFehler.clear();
    server.funktionsAufrufe.clear();
  });

  group('Das Zurueckkommen aus dem Chat', () {
    testWidgets('die Liste laedt neu, wenn der Nutzer zurueckkommt', (
      tester,
    ) async {
      final dienst = _dienst()
        ..funken = [funkeVon(id: 7, personId: 'p1', name: 'Mira')];
      await _pump(tester, service: dienst);

      final vorher = dienst.matchesAufrufe;

      // Der Nutzer tippt auf den Funken - der Chat geht auf.
      await tester.tap(find.text('Mira, 30'));
      await pumpFrames(tester);
      expect(
        find.text('Chat'),
        findsOneWidget,
        reason:
            'Ein Tipp auf den Funken muss den Chat oeffnen - das ist der '
            'ganze Zweck der Kachel.',
      );

      // Und kommt zurueck.
      final router = GoRouter.of(tester.element(find.text('Chat')));
      router.pop();
      await pumpFrames(tester);

      expect(
        dienst.matchesAufrufe,
        greaterThan(vorher),
        reason:
            'Nach dem Chat muss die Liste neu geladen werden - im Chat kann '
            'dazwischen geschrieben worden sein, der Nutzer soll den neuen '
            'Stand sehen.',
      );
    });
  });

  group('Der automatische Nachlauf nach 72 Stunden', () {
    testWidgets('ein alter Funke wandert von allein in die Archivierten', (
      tester,
    ) async {
      final dienst = _dienst()
        ..funken = [
          funkeVon(
            id: 7,
            personId: 'p1',
            name: 'Mira',
            erstellt: DateTime.now().subtract(const Duration(days: 5)),
          ),
        ];
      await _pump(tester, service: dienst);
      await lassServerArbeiten(tester);

      expect(
        dienst.gekuehlt,
        contains(7),
        reason:
            'Ein Funke ohne Aktivitaet wandert nach 72 Stunden von allein in '
            'die archivierten Funken - so raeumt die App auf, ohne dem '
            'Nutzer Druck zu machen.',
      );
      expect(
        find.text(L10n.tWithoutContext('interests.cooledTitle')),
        findsOneWidget,
        reason: 'Der Funke steht jetzt bei den archivierten Funken.',
      );
    });

    testWidgets('eine frische Nachricht haelt den Funke am Leben', (
      tester,
    ) async {
      // Der Chat hat eine frische Nachricht - der Funke ist also aktiv.
      final chatService = ChatService();
      chatService.addMessage(
        '7',
        Message(
          id: 'm1',
          senderId: 'p1',
          receiverId: 'ich',
          text: 'Hallo',
          timestamp: DateTime.now(),
        ),
      );

      final dienst = _dienst()
        ..funken = [
          funkeVon(
            id: 7,
            personId: 'p1',
            name: 'Mira',
            erstellt: DateTime.now().subtract(const Duration(days: 5)),
          ),
        ];
      await _pump(
        tester,
        service: dienst,
        overrides: [
          chatProvider.overrideWith((ref) => ChatNotifier(chatService)),
        ],
      );
      await lassServerArbeiten(tester);

      expect(
        dienst.gekuehlt,
        isEmpty,
        reason:
            'Wer gerade geschrieben hat, wird nicht archiviert - die letzte '
            'Aktivitaet zaehlt, nicht das Alter des Funken.',
      );
      expect(
        find.text('Mira, 30'),
        findsOneWidget,
        reason: 'Der Funke bleibt oben in der aktiven Liste stehen.',
      );
    });

    testWidgets('ein Re-Funke haelt den Funke am Leben', (tester) async {
      final dienst = _dienst()
        ..funken = [
          funkeVon(
            id: 7,
            personId: 'p1',
            name: 'Mira',
            erstellt: DateTime.now().subtract(const Duration(days: 5)),
            reEntzuendet: DateTime.now(),
          ),
        ];
      await _pump(tester, service: dienst);
      await lassServerArbeiten(tester);

      expect(
        dienst.gekuehlt,
        isEmpty,
        reason:
            'Wer den Funke neu entzuendet hat, will ihn noch - er darf '
            'deshalb nicht sofort wieder archiviert werden.',
      );
      expect(
        find.text('Mira, 30'),
        findsOneWidget,
        reason: 'Der Funke bleibt in der aktiven Liste.',
      );
    });
  });

  group('Die Auswahl', () {
    testWidgets('das Abwaehlen des letzten Funken beendet den Modus', (
      tester,
    ) async {
      final dienst = _dienst()
        ..funken = [funkeVon(id: 7, personId: 'p1', name: 'Mira')];
      await _pump(tester, service: dienst);

      // Der Stift startet den Auswahl-Modus.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await pumpFrames(tester);
      expect(find.byType(CheckboxListTile), findsOneWidget);

      // Der Funke wird angewaehlt ...
      await tester.tap(find.byType(CheckboxListTile));
      await pumpFrames(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InteressenScreen)),
      );
      expect(container.read(matchSelectModeProvider), isTrue);

      // ... und wieder abgewahlt.
      await tester.tap(find.byType(CheckboxListTile));
      await pumpFrames(tester);

      expect(
        container.read(matchSelectModeProvider),
        isFalse,
        reason:
            'Wird der letzte Funke abgewahlt, endet der Auswahl-Modus von '
            'selbst - der Nutzer muss nicht noch auf "Abbrechen" tippen.',
      );
      expect(
        find.byType(CheckboxListTile),
        findsNothing,
        reason: 'Die Kacheln sind wieder normale Funken-Kacheln.',
      );
    });
  });

  group('Das Beenden mit Absage-Text', () {
    testWidgets('der Absage-Text geht raus und benachrichtigt die Gegenseite', (
      tester,
    ) async {
      FakeRelayService? relay;
      final dienst = _dienst()
        ..funken = [funkeVon(id: 7, personId: 'p1', name: 'Mira')];
      await _pump(
        tester,
        service: dienst,
        overrides: [
          relayServiceProvider.overrideWith((ref) {
            relay = FakeRelayService(ref);
            return relay!;
          }),
        ],
      );

      // Das Menue der Kachel -> "Archivieren".
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await pumpFrames(tester);
      await tester.tap(find.text('Archivieren'));
      await pumpFrames(tester);

      // Der Dialog: "Ruhig enden lassen" ist voreingestellt - der Nutzer
      // waehlt einen vorbereiteten Absage-Text.
      final absage = find.text(L10n.tWithoutContext('chat.goodbye.1'));
      await tester.ensureVisible(absage);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(absage);
      await pumpFrames(tester);

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('chat.coolSpark'),
        ),
      );
      await pumpFrames(tester);
      await lassServerArbeiten(tester);

      expect(tester.takeException(), isNull);
      expect(
        relay?.zugestellt.map((e) => e.text),
        contains(L10n.tWithoutContext('chat.goodbye.1')),
        reason:
            'Der Absage-Text muss bei der Gegenseite ankommen - ein '
            'Ghosting ist genau das, was der Nutzer damit verhindern will.',
      );
      expect(
        relay?.zugestellt.map((e) => e.peerId),
        contains('p1'),
        reason: 'Der Text geht an die Person des Funken.',
      );
      expect(
        server.funktionsAufrufe.map((c) => c['funktion']),
        contains('notify-user'),
        reason:
            'Die Gegenseite muss Bescheid wissen - sonst wartet sie auf '
            'eine Nachricht, die nie kommt.',
      );
    });
  });

  group('Das Oeffnen eines Funken', () {
    testWidgets('der automatische Funke fragt nach - der Chat geht auch bei '
        'einem Fehler auf', (tester) async {
      // Der Server schweigt bei der Rueckfrage.
      server.rpcFehler.add('resolve_dating_hour_auto_match');

      final dienst = _dienst()
        ..funken = [
          funkeVon(id: 7, personId: 'p1', name: 'Mira', autoMatch: true),
        ];
      await _pump(tester, service: dienst);

      await tester.tap(find.text('Mira, 30'));
      await pumpFrames(tester);

      // DIE EINMALIGE RUECKFRAGE: der automatische Funke wurde nicht von
      // beiden Seiten bestaetigt.
      expect(
        find.text(L10n.tWithoutContext('dh.autoMatch.title')),
        findsOneWidget,
        reason:
            'Der automatische Funke fragt einmal nach - er wurde nicht von '
            'beiden Seiten bestaetigt.',
      );

      await tester.tap(
        find.widgetWithText(
          TextButton,
          L10n.tWithoutContext('dh.autoMatch.remove'),
        ),
      );
      await pumpFrames(tester);
      await lassServerArbeiten(tester);

      expect(
        find.text(L10n.tWithoutContext('dh.autoMatch.failed')),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass die Person nicht entfernt '
            'werden konnte.',
      );
      expect(
        find.text('Chat'),
        findsOneWidget,
        reason:
            'Die Rueckfrage darf den Nutzer nicht blockieren - der Chat '
            'geht auch dann auf, wenn das Entfernen nicht klappt.',
      );
    });

    testWidgets('der fixierte Funke laesst sich genauso oeffnen', (
      tester,
    ) async {
      final dienst = _dienst()
        ..funken = [funkeVon(id: 7, personId: 'p1', name: 'Mira')];
      await _pump(tester, service: dienst);

      // Fixieren - der Funke wandert in den eigenen Abschnitt.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await pumpFrames(tester);
      await tester.tap(find.text('Fixieren'));
      await pumpFrames(tester);
      expect(
        find.text(L10n.tWithoutContext('interests.pinnedSection')),
        findsOneWidget,
        reason: 'Der fixierte Funke steht im eigenen Abschnitt.',
      );

      // Der fixierte Funke laesst sich antippen ...
      await tester.tap(find.text('Mira, 30'));
      await pumpFrames(tester);
      expect(
        find.text('Chat'),
        findsOneWidget,
        reason:
            'Ein fixierter Funke ist ein ganz normaler Funke - er muss sich '
            'genauso oeffnen lassen.',
      );

      // ... und sein Profil aufrufen.
      final router = GoRouter.of(tester.element(find.text('Chat')));
      router.pop();
      await pumpFrames(tester);
      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('profile.detail.aboutMe')),
      );
      await pumpFrames(tester);
      expect(
        find.text('Profil'),
        findsOneWidget,
        reason: 'Auch beim fixierten Funke muss das Profil erreichbar sein.',
      );
    });

    testWidgets('der fixierte Funke laesst sich auch wegraeumen', (
      tester,
    ) async {
      final dienst = _dienst()
        ..funken = [funkeVon(id: 7, personId: 'p1', name: 'Mira')];
      await _pump(tester, service: dienst);

      // Zuerst fixieren - der Funke wandert in den eigenen Abschnitt.
      await tester.tap(_menueVon('Mira, 30'));
      await pumpFrames(tester);
      await tester.tap(find.text('Fixieren'));
      await pumpFrames(tester);
      expect(
        find.text(L10n.tWithoutContext('interests.pinnedSection')),
        findsOneWidget,
        reason: 'Der fixierte Funke steht im eigenen Abschnitt.',
      );

      // "Aus Liste entfernen" - auch beim fixierten Funken.
      await tester.tap(_menueVon('Mira, 30'));
      await pumpFrames(tester);
      await tester.tap(find.text('Aus Liste entfernen'));
      await pumpFrames(tester);
      await lassServerArbeiten(tester);

      expect(
        dienst.ausgeblendet,
        contains(7),
        reason:
            'Ein fixierter Funke laesst sich genauso aus der Liste nehmen - '
            'die Fixierung ist eine Anordnung, kein Vertrag.',
      );

      // Das endgueltige Loeschen.
      await tester.tap(_menueVon('Mira, 30'));
      await pumpFrames(tester);
      await tester.tap(
        find.text(L10n.tWithoutContext('interests.deleteSpark')),
      );
      await pumpFrames(tester);
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('interests.deleteSpark'),
        ),
      );
      await pumpFrames(tester);
      await lassServerArbeiten(tester);

      expect(
        dienst.beendet,
        contains(7),
        reason:
            'Auch beim fixierten Funke muss das endgueltige Loeschen gehen '
            '- sonst bleibt er fuer immer stehen.',
      );

      // "Archivieren" - der Funke wandert in die archivierten Funken.
      await tester.tap(_menueVon('Mira, 30'));
      await pumpFrames(tester);
      await tester.tap(find.text('Archivieren'));
      await pumpFrames(tester);
      await tester.tap(find.text(L10n.tWithoutContext('chat.coolSpark')));
      await pumpFrames(tester);
      await lassServerArbeiten(tester);

      expect(
        dienst.gekuehlt,
        contains(7),
        reason:
            'Auch beim fixierten Funke muss das Archivieren gehen - der '
            'Nutzer soll ihn auch dort ruhig stellen koennen.',
      );
    });
  });

  group('Die Fehlerwege', () {
    testWidgets('das Loeschen meldet dem Nutzer den Fehler', (tester) async {
      final dienst = _dienst()
        ..funken = [funkeVon(id: 7, personId: 'p1', name: 'Mira')];
      dienst.endFehler = StateError('Der Server hat nicht geantwortet.');
      await _pump(tester, service: dienst);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await pumpFrames(tester);
      await tester.tap(
        find.text(L10n.tWithoutContext('interests.deleteSpark')),
      );
      await pumpFrames(tester);

      // Die Rueckfrage: ohne sie waere das Loeschen ein Unfall.
      expect(
        find.text(L10n.tWithoutContext('interests.deleteSparkTitle')),
        findsOneWidget,
        reason: 'Das Loeschen muss gefragt werden.',
      );

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('interests.deleteSpark'),
        ),
      );
      await pumpFrames(tester);
      await lassServerArbeiten(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Fehler:'),
        findsOneWidget,
        reason:
            'Der Funke ist noch da - der Nutzer muss das wissen, sonst '
            'glaubt er, der Funke sei weg.',
      );
    });

    testWidgets('das Abbrechen beim Loeschen laesst den Funke stehen', (
      tester,
    ) async {
      final dienst = _dienst()
        ..funken = [funkeVon(id: 7, personId: 'p1', name: 'Mira')];
      await _pump(tester, service: dienst);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await pumpFrames(tester);
      await tester.tap(
        find.text(L10n.tWithoutContext('interests.deleteSpark')),
      );
      await pumpFrames(tester);

      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(dienst.beendet, isEmpty, reason: 'Abbrechen loescht nichts.');
      expect(
        find.text('Mira, 30'),
        findsOneWidget,
        reason: 'Der Funke steht noch da - ein Fehlgriff darf nichts kosten.',
      );
    });

    testWidgets('der Re-Funke meldet dem Nutzer den Fehler', (tester) async {
      final dienst = _dienst()
        ..funken = [
          funkeVon(id: 7, personId: 'p1', name: 'Mira', status: 'cooled'),
        ];
      dienst.resparkFehler = StateError('Der Server hat nicht geantwortet.');
      await _pump(tester, service: dienst);

      final knopf = find.text(L10n.tWithoutContext('interests.resparkBtn'));
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('interests.resparkFailed')),
        findsOneWidget,
        reason:
            'Der Re-Funke hat nicht geklappt - der Nutzer muss es wissen, '
            'sonst tippt er vergeblich immer wieder.',
      );
    });
  });

  group('Die Reihenfolge der Liste', () {
    testWidgets('ein Chat mit ungelesenen Nachrichten steht oben', (
      tester,
    ) async {
      // Der Chat mit Anna hat zwei ungelesene Nachrichten.
      final chatService = ChatService();
      final anna = chatService.createMatch(person(id: 'p1', name: 'Anna'));
      chatService.incrementUnread(anna.id);
      chatService.incrementUnread(anna.id);

      final dienst = _dienst()
        ..funken = [
          funkeVon(
            id: 7,
            personId: 'p1',
            name: 'Anna',
            erstellt: DateTime.now().subtract(const Duration(days: 2)),
          ),
          funkeVon(
            id: 8,
            personId: 'p2',
            name: 'Bert',
            erstellt: DateTime.now(),
          ),
        ];
      await _pump(
        tester,
        service: dienst,
        overrides: [
          chatProvider.overrideWith((ref) => ChatNotifier(chatService)),
        ],
      );

      final annaOben = tester.getTopLeft(find.text('Anna, 30')).dy;
      final bertOben = tester.getTopLeft(find.text('Bert, 30')).dy;

      expect(
        annaOben,
        lessThan(bertOben),
        reason:
            'Ein Chat mit ungelesenen Nachrichten gehoert nach oben - der '
            'Nutzer sieht sonst nicht, dass jemand auf ihn wartet.',
      );
    });

    testWidgets('bei gleicher Zahl gewinnt der juengste Funke', (tester) async {
      final dienst = _dienst()
        ..funken = [
          funkeVon(
            id: 7,
            personId: 'p1',
            name: 'Anna',
            erstellt: DateTime.now().subtract(const Duration(days: 2)),
          ),
          funkeVon(
            id: 8,
            personId: 'p2',
            name: 'Bert',
            erstellt: DateTime.now(),
          ),
        ];
      await _pump(tester, service: dienst);

      final annaOben = tester.getTopLeft(find.text('Anna, 30')).dy;
      final bertOben = tester.getTopLeft(find.text('Bert, 30')).dy;

      expect(
        bertOben,
        lessThan(annaOben),
        reason:
            'Ohne ungelesene Nachrichten steht der juengste Funke oben - '
            'der letzte Funke ist meist der interessanteste.',
      );
    });
  });

  group('Das gespeicherte Profil (QR-Kontakt)', () {
    testWidgets('das Profil laesst sich oeffnen', (tester) async {
      final chatService = ChatService();
      chatService.createQrContact(person(id: 'q1', name: 'Nora'));

      final dienst = _dienst();
      await _pump(
        tester,
        service: dienst,
        overrides: [
          chatProvider.overrideWith((ref) => ChatNotifier(chatService)),
        ],
      );

      expect(
        find.text('Nora, 30'),
        findsOneWidget,
        reason: 'Das gespeicherte Profil steht in der Liste.',
      );

      // Das Bild links geht auch zum Profil. (Der Kontakt steht weit
      // unten - erst dorthin scrollen, sonst trifft der Tap ins Leere.)
      final bild = find.byIcon(Icons.person);
      await tester.ensureVisible(bild);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(bild);
      await pumpFrames(tester);
      expect(
        find.text('Profil'),
        findsOneWidget,
        reason:
            'Das Bild der gespeicherten Person muss zum Profil fuehren - '
            'das ist der ganze Zweck des gespeicherten Profils.',
      );

      // Und zurueck: der Knopf rechts tut dasselbe.
      GoRouter.of(tester.element(find.text('Profil'))).pop();
      await pumpFrames(tester);
      final knopf = find.byTooltip(
        L10n.tWithoutContext('profile.detail.aboutMe'),
      );
      await tester.ensureVisible(knopf);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(knopf);
      await pumpFrames(tester);
      expect(
        find.text('Profil'),
        findsOneWidget,
        reason:
            'Der Knopf an der Zeile muss genauso zum Profil fuehren wie '
            'das Bild - der Nutzer sucht den Weg nicht zuerst am Bild.',
      );
    });

    testWidgets('der Kontakt laesst sich chatten', (tester) async {
      final chatService = ChatService();
      chatService.createQrContact(person(id: 'q1', name: 'Nora'));

      final dienst = _dienst();
      await _pump(
        tester,
        service: dienst,
        overrides: [
          chatProvider.overrideWith((ref) => ChatNotifier(chatService)),
        ],
      );

      await tester.ensureVisible(find.text('Nora, 30'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Nora, 30'));
      await pumpFrames(tester);

      expect(
        find.text('Chat'),
        findsOneWidget,
        reason:
            'Ein gespeichertes Profil ist zum Schreiben da - es muss den '
            'Chat oeffnen.',
      );
    });
  });

  group('Die archivierten Funken', () {
    testWidgets('der archivierte Funke laesst sich oeffnen', (tester) async {
      final dienst = _dienst()
        ..funken = [
          funkeVon(id: 7, personId: 'p1', name: 'Mira', status: 'cooled'),
        ];
      // DER BREITERE BILDSCHIRM: Die Kachel der archivierten Funken hat
      // drei Knoepfe rechts (Profil, Re-Funke, Loeschen). Auf einem schmalen
      // Bildschirm bleibt fuer den Namen kein Platz mehr - der Name hat
      // dann keine Breite und kann nicht getippt werden. Auf dem breiten
      // Bildschirm steht der Name da, und der Nutzer tippt ihn an.
      await _pump(tester, service: dienst, groesse: const Size(600, 900));

      await tester.tap(find.text('Mira'));
      await tester.pumpAndSettle();

      expect(
        find.text('Chat'),
        findsOneWidget,
        reason:
            'Auch ein archivierter Funke laesst sich noch oeffnen - die '
            'Verbindung ist kalt, die Person nicht.',
      );
    });
  });
}
