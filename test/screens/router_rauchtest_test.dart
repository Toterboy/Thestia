// Der Rauchtest ueber alle Routen.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte fuer
// lib/routing/app_router.dart 165 offene Zeilen - und die Bilanz
// ueber ganz lib/: 70 %. Der Router traegt die gesamte Navigation:
// 52 Routen, und fuer JEDE wird ein Bildschirm gebaut.
//
// DER WEG: Der Test geht jede Route einmal an und schaut, ob der
// Bildschirm aufgebaut wird. Das ist mehr als eine Messung: faellt ein
// Bildschirm beim Aufbau aus, sieht der Nutzer im Ernstfall einen
// schwarzen Bildschirm - und niemand merkt es, bis es jemandem
// passiert.
//
// EIN TEST JE ROUTE: Jede Route bekommt einen eigenen Test (und damit
// einen eigenen Widget-Baum). Sonst wuerde ein Absturz den folgenden
// Routen die Basis wegziehen (der Baum ist dann kaputt) - und man
// wuesste nicht, welche Route wirklich defekt ist.
//
// OHNE UMLEITUNG: Der Test benutzt die Routen-Tabelle direkt
// ([appRoutes]) und NICHT den Router der App. Sonst wuerde die
// Umleitung jeden Weg umlenken (je nach Zustand zum Login, zur
// Einrichtung oder zur Verifikation) - und der Test wuerde nur die
// Umleitungsziele sehen, nicht die Bildschirme.
//
// WAS HIER GEPRUEFT WIRD:
//   * jede Route baut einen Bildschirm auf (kein Absturz),
//   * der Bildschirm ist wirklich der erwartete (nicht die Fehlerseite).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/core/error_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import '../support/router_harness.dart';

/// Die Routen mit Platzhaltern - mit Werten, die es in der App gibt.
///
/// ANMERKUNG: `/onboarding` fehlt hier bewusst - hinter diesem Pfad
/// gibt es KEINEN Bildschirm (der Pfad wird nur in der Umleitung
/// verglichen). Der Rauchtest soll aber nur echte Bildschirme pruefen.
const Map<String, String> _routen = <String, String>{
  '/loading': '/loading',
  '/welcome': '/welcome',
  '/welcome-new': '/welcome-new',
  '/delete-data': '/delete-data',
  '/guardian-consent': '/guardian-consent',
  '/guardian-transition': '/guardian-transition',
  '/guardian-settings': '/guardian-settings',
  '/login': '/login',
  '/forgot-password': '/forgot-password',
  '/reset-password': '/reset-password',
  '/unban-request': '/unban-request',
  '/': '/',
  '/find-your-match': '/find-your-match',
  '/find-your-match/kategorie': '/find-your-match/kategorie',
  '/interessen': '/interessen',
  '/quiz/:matchId': '/quiz/1',
  '/spice/:matchId': '/spice/1',
  '/chat/:matchId': '/chat/1',
  '/profile': '/profile',
  '/profile/edit': '/profile/edit',
  '/profile/:userId': '/profile/partner-1',
  '/settings': '/settings',
  '/personality-test': '/personality-test',
  '/settings-privacy-once': '/settings-privacy-once',
  '/dating-safety-education': '/dating-safety-education',
  '/swipe-mode-selection': '/swipe-mode-selection',
  '/random-chat': '/random-chat',
  '/transit/radar': '/transit/radar',
  '/bug-report': '/bug-report',
  '/qr/profile': '/qr/profile',
  '/qr/scan': '/qr/scan',
  '/qr/contacts': '/qr/contacts',
  '/mood/picker': '/mood/picker',
  '/whats-new': '/whats-new',
  '/privacy': '/privacy',
  '/privacy/policy': '/privacy/policy',
  '/privacy/terms': '/privacy/terms',
  '/privacy/imprint': '/privacy/imprint',
  '/safety-center': '/safety-center',
  '/devices': '/devices',
  '/dating-hour': '/dating-hour',
  '/dating-hour/preferences': '/dating-hour/preferences',
  '/dating-hour/chat/:sessionId': '/dating-hour/chat/session-1',
  '/dating-hour/rules': '/dating-hour/rules',
  '/dating-hour/how-it-works': '/dating-hour/how-it-works',
  '/verification/video': '/verification/video',
  '/verification/complete': '/verification/complete',
  '/verification/info': '/verification/info',
  '/email-verification': '/email-verification',
  '/mfa-setup': '/mfa-setup',
  '/mfa-challenge': '/mfa-challenge',
  '/community-guidelines': '/community-guidelines',
  '/admin': '/admin',
};

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    mockZeitzone();
    // DIE AUFNAHME: Manche Bildschirme (der Vorstellungs-Editor)
    // starten nach ein paar Sekunden eine Aufnahme - ohne den
    // Ersatz wartet der Aufruf endlos.
    mockAufnahme();
    // DIE VERSION: Der "Was ist neu"-Bildschirm fragt die Build-Nummer.
    mockPackageInfo();
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
    server.zeilen.clear();
    server.rpcAntworten.clear();
    server.pfade.clear();
  });

  group('Der Rauchtest ueber alle Routen', () {
    for (final eintrag in _routen.entries) {
      testWidgets('${eintrag.key} baut einen Bildschirm auf', (tester) async {
        final container = ProviderContainer(
          overrides: <Override>[
            localStorageProvider.overrideWithValue(TestSpeicher()),
            secureProfileStoreProvider.overrideWithValue(TestKeystore()),
            settingsProvider.overrideWith((ref) => TestEinstellungen(ref)),
            profileProvider.overrideWith((ref) => TestProfil()),
            chatProvider.overrideWith((ref) => ChatNotifier(ChatService())),
          ],
        );
        // DER AUFRUM: Manche Anbieter starten einen Timer (z. B. der
        // Kinderschutz pollt den Server). Der endet erst beim
        // Abbau des Containers - sonst meldet der Test "A Timer is
        // still pending".
        var abgebaut = false;
        addTearDown(() {
          if (!abgebaut) container.dispose();
        });

        // DER ROUTER DES TESTS: Die Routen-Tabelle der App, aber OHNE
        // Umleitung - so ist jede Route erreichbar.
        final router = GoRouter(
          initialLocation: eintrag.value,
          errorBuilder: (context, state) => const ErrorScreen(),
          routes: appRoutes(),
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // DER ABSTURZ: Ein Bildschirm, der beim Aufbau stirbt, zeigt
        // dem Nutzer einen schwarzen Bildschirm.
        expect(
          tester.takeException(),
          isNull,
          reason:
              'Der Bildschirm der Route ${eintrag.key} stuerzt beim Aufbau ab.',
        );

        // Und die Fehlerseite des Routers darf nicht das Ergebnis
        // sein - dann hat die Route gar nicht gegriffen.
        expect(
          find.byType(ErrorScreen),
          findsNothing,
          reason:
              'Die Route ${eintrag.key} hat nicht gegriffen - sie zeigt '
              'die Fehlerseite statt des Bildschirms.',
        );

        // DER AUFRUM: Manche Bildschirme fragen im Hintergrund den
        // Server (mit einem Timeout). In der Test-Zone laeuft die
        // Zeit nur beim `pump` - ohne das bleibt der Timer offen und
        // der Test meldet "A Timer is still pending".
        //
        // DER WEG: Die Anfrage bekommt zuerst Zeit, wirklich anzukommen
        // (`runAsync` = die echte Zeit), dann wird der Bildschirm
        // abgebaut und die Uhr weiterlaufen gelassen, damit die
        // Timeouts der Hintergrundanfragen anschlagen.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 20));
        container.dispose();
        abgebaut = true;
      });
    }
  });
}
