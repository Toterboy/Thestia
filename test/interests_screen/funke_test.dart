// Die Tests 'interessen_screen' (Teil 2).
//
// DER WEG: Die Testdatei war zu lang (> 1000 Zeilen). Die Tests
// sind nach Themen aufgeteilt; die Helfer liegen in
// test/support/interessen_screen_hilfen.dart.

// Widget-Tests fuer den Screen "Interessen" (Reiter der Startseite).
//
// ANLASS: Die Coverage-Messung (13.11.2026) zeigte fuer
// lib/screens/interests/interessen_screen.dart 835 offene Zeilen - der
// Screen war die groesste Luecke der App. Er ist die Antwort auf die
// Frage "was ist mit meinem Like passiert?" - und genau dort hat der
// Betreiber im November 2026 mehrere Befunde gemeldet (Funke
// verschwunden, Reiter springt, Leerzustand sah wie ein Fehler aus).
//
// WAS HIER GEPRUEFT WIRD:
//   * der Screen baut sich (kein Absturz, kein Render-Overflow),
//   * der Leerzustand steht da (nicht "nichts gefunden", sondern der
//     ausgeschriebene Leerzustand),
//   * die Funkenliste zeigt die Kachel mit Namen und Alter,
//   * "Aus Liste entfernen" blendet den Funken wirklich aus,
//   * ein fehlgeschlagener Abruf zeigt den Fehler MIT Wiederholen -
//     nicht die leere Liste (BEFUND 13.11.2026: "Außerdem ist mein
//     Funke verschwunden"),
//   * der Mehrfach-Auswahl-Modus blendet die gewaehlten Funken aus.
//
// OHNE SERVER: Der Find-your-Match-Service wird durch einen Hand-Fake
// ersetzt (siehe [_FakeFindYourMatchService]). Der Supabase-Client wird
// nur initialisiert, damit der Screen seinen Serverstand ueberhaupt
// abfragt - es geht KEINE Anfrage raus (alle Aufrufe landen im Fake).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:thestia/models/chat/find_match_models.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/pinned_matches_provider.dart';
import 'package:thestia/screens/interests/interessen_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

import 'hilfen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // Der Client wird nur initialisiert, damit
    // [SupabaseService.isInitialized] true ist und der Screen den
    // Serverstand ueberhaupt abfragt. Es geht keine Anfrage raus - der
    // Service ist ein Fake.
    //
    // autoRefreshToken: false - sonst laeuft ein periodischer Timer,
    // an dem der Test am Ende scheitern wuerde.
    // DER PFAD-KANAL: sonst ruft der Test auf dem CI-Runner
    // das echte Plugin (das findet dort kein XDG-Verzeichnis).
    await mockPfadProvider();
    // DER KEYSTORE: dasselbe Spiel - auf dem Linux-Runner
    // gibt es keine libsecret-Sitzung.
    mockKeystore();
    // HIVE: Die gespeicherten Profile (QR-Kontakte) liegen in einer
    // Hive-Box - ohne initialisiertes Hive wirft der Chat-Dienst
    // ("You need to initialize Hive").
    await mockHive();
    // DER SERVER: das Zuruecknehmen eines Likes geht ueber die
    // REST-Schnittstelle (DELETE auf 'likes') - ohne den Ersatz-Server
    // gaengt der Aufruf ins Leere.
    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
      ),
    );
    // ANGEMELDET: ohne Sitzung weiss der Bildschirm nicht, wessen Like
    // das ist - das Zuruecknehmen ginge dann gar nicht.
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Der Server merkt sich die Anfragen - fuer jeden Test beginnt er
    // neu. Sonst wuerde ein Test den Aufruf eines anderen sehen (und
    // der "schweigt"-Test wuerde alle folgenden stoeren).
    server.pfade.clear();
    server.rpcAufrufe.clear();
    server.rpcFehler.clear();
  });
  group('Fixieren', () {
    testWidgets('"Fixieren" stellt den Funke in den eigenen Abschnitt', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [funke()];
      await interessenScreenPump(tester, service: service);

      // Das Menue der Kachel oeffnen.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await pumpFrames(tester);
      await tester.tap(find.text('Fixieren'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Die Fixierung ist gesetzt ...
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InteressenScreen)),
      );
      expect(container.read(pinnedMatchesProvider), contains(7));
      // ... der eigene Abschnitt steht da ...
      expect(find.text('Fixiert'), findsOneWidget);
      // ... die Nadel ist zu sehen ...
      expect(find.byIcon(Icons.push_pin), findsWidgets);
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(find.text('Funke fixiert'), findsOneWidget);
    });

    testWidgets('"Fixieren" laesst sich wieder aufheben', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [funke()];
      await interessenScreenPump(tester, service: service);

      // Erste Mal fixieren.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await pumpFrames(tester);
      await tester.tap(find.text('Fixieren'));
      await pumpFrames(tester);
      expect(find.text('Fixiert'), findsOneWidget);

      // Die erste Meldung muss erst verschwinden - sonst wartet die
      // zweite in der Schlange hinter ihr (SnackBars stehen hinter-
      // einander an).
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 500));

      // Zweites Mal: die Fixierung geht wieder weg.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await pumpFrames(tester);
      await tester.tap(find.text('Fixieren'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InteressenScreen)),
      );
      expect(container.read(pinnedMatchesProvider), isEmpty);
      expect(find.text('Fixiert'), findsNothing);
      expect(find.text('Fixierung aufgehoben'), findsOneWidget);
    });
  });
  group('Das Ziehen nach unten', () {
    testWidgets('laedt die Funken neu', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [funke()];
      await interessenScreenPump(tester, service: service);

      final vorher = service.matchesAufrufe;

      // Nach unten ziehen (Pull-to-Refresh).
      await tester.drag(find.byType(ListView).first, const Offset(0, 300));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        service.matchesAufrufe,
        greaterThan(vorher),
        reason:
            'Das Ziehen nach unten muss die Funken neu laden - der Nutzer '
            'wartet sonst auf einen Stand, der gar nicht neu ist.',
      );
    });
  });
  group('Das gespeicherte Profil (QR-Kontakt)', () {
    testWidgets('"Entfernen" loescht den gespeicherten Kontakt', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Der Chat-Dienst mit einem gespeicherten Profil.
      final chatService = ChatService();
      chatService.createQrContact(person());

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      await interessenScreenPump(
        tester,
        service: service,
        overrides: [
          chatProvider.overrideWith((ref) => ChatNotifier(chatService)),
        ],
      );

      expect(tester.takeException(), isNull);
      // Der Abschnitt "Gespeicherte Profile" steht da.
      expect(find.text('Gespeicherte Profile'), findsOneWidget);
      expect(find.text('Mira, 30'), findsOneWidget);

      // Der Mülleimer fragt erst nach (der Chat-Verlauf geht mit).
      // Der Knoepfchen liegt weit unten (unter den Reitern) - erst
      // dorthin scrollen, sonst trifft der Tap ins Leere.
      final loeschen = find.byTooltip('Gespeichertes Profil entfernen');
      await tester.ensureVisible(loeschen);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(loeschen);
      await pumpFrames(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Gespeichertes Profil entfernen?'), findsOneWidget);

      // "Behalten" loescht nichts.
      await tester.tap(find.widgetWithText(TextButton, 'Behalten'));
      await pumpFrames(tester);
      expect(find.text('Mira, 30'), findsOneWidget);

      // Und jetzt "Entfernen".
      await tester.ensureVisible(loeschen);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(loeschen);
      await pumpFrames(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(FilledButton, 'Entfernen'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Kontakt ist weg ...
      expect(find.text('Mira, 30'), findsNothing);
      expect(find.text('Gespeicherte Profile'), findsNothing);
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(find.text('Mira wurde entfernt.'), findsOneWidget);
    });
  });
  group('Die Fehlerwege', () {
    testWidgets('das Kuehlen meldet dem Nutzer den Fehler', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.coolFehler = StateError('Der Server hat nicht geantwortet.');
      service.funken = [funke()];
      await interessenScreenPump(tester, service: service);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await pumpFrames(tester);
      await tester.tap(find.text('Archivieren'));
      await pumpFrames(tester);
      await tester.tap(find.text('Funke kühlen'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Fehler:'),
        findsOneWidget,
        reason:
            'Ein fehlgeschlagenes Kuehlen muss der Nutzer erfahren - '
            'sonst glaubt er, der Funke sei ruhig gestellt.',
      );
    });

    testWidgets('ein bereits gekuehlter Funke gilt als Erfolg', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      // Der Server meldet "bereits gekuehlt" (z. B. beim Doppel-Tap).
      service.coolFehler = Exception(
        'Funke nicht gefunden oder bereits gekuehlt/endet.',
      );
      service.funken = [funke()];
      await interessenScreenPump(tester, service: service);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await pumpFrames(tester);
      await tester.tap(find.text('Archivieren'));
      await pumpFrames(tester);
      await tester.tap(find.text('Funke kühlen'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Fehler:'),
        findsNothing,
        reason:
            '"Bereits gekuehlt" ist kein Fehler - der Wunsch ist ja '
            'erfuellt. Der Nutzer darf keinen Fehler sehen.',
      );
      expect(find.textContaining('Mira'), findsWidgets);
    });

    testWidgets('das Ausblenden eines Funken meldet den Fehler', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.hideFehler = StateError('Der Server hat nicht geantwortet.');
      service.funken = [funke()];
      await interessenScreenPump(tester, service: service);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await pumpFrames(tester);
      await tester.tap(find.text('Aus Liste entfernen'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Fehler:'),
        findsOneWidget,
        reason:
            'Der Funke ist noch da - der Nutzer muss das wissen, sonst '
            'wartet er vergeblich auf das Verschwinden.',
      );
    });

    testWidgets('das Annehmen eines Likes meldet den Fehler', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.respondFehler = StateError('Der Server hat nicht geantwortet.');
      service.erhalteneLikes = [
        ReceivedLike(
          likeId: 3,
          profile: person(name: 'Jonas', alter: 31),
          createdAt: DateTime.now(),
        ),
      ];
      await interessenScreenPump(tester, service: service);

      await tester.tap(find.text('Erhalten'));
      await pumpFrames(tester);
      await tester.tap(find.text('Funke bestätigen'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Fehler:'),
        findsOneWidget,
        reason: 'Der Like ist nicht bestaetigt - der Nutzer muss das wissen.',
      );
    });

    testWidgets('das Ausblenden eines Likes meldet den Fehler', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.ignoreFehler = StateError('Der Server hat nicht geantwortet.');
      service.erhalteneLikes = [
        ReceivedLike(
          likeId: 4,
          profile: person(name: 'Jonas', alter: 31),
          createdAt: DateTime.now(),
        ),
      ];
      await interessenScreenPump(tester, service: service);

      await tester.tap(find.text('Erhalten'));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip('Ignorieren'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Fehler:'),
        findsOneWidget,
        reason: 'Der Like ist nicht ausgeblendet - der Nutzer muss das wissen.',
      );
    });
  });
}
