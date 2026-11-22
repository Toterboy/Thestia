// Die Standort-Hinweise im Profil-Editor.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/profile/parts/locationnotice.dart 0 % Abdeckung. Der Kasten
// ist die einzige Stelle, an der der Nutzer erfaehrt bekommt, dass der
// Standort nicht ermittelt werden konnte - ohne ihn steht da einfach
// kein Bundesland, und der Nutzer wundert sich.
//
// WAS HIER GEPRUEFT WIRD:
//   * ohne GPS (kein Standort) kommt der Hinweis "Standort nicht
//     ermittelt",
//   * ein Standort, der zu weit vom bisherigen Geraet abweicht, kommt mit
//     dem Verdachts-Hinweis (nicht stillschweigend gespeichert).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
// Das Plattform-Interface wird von permission_handler exportiert, aber
// nicht weitergereicht - der Test setzt die Attrappe darueber.
// ignore: depend_on_referenced_packages
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import 'hilfen.dart';

/// Der Ort-Dienst, der jeden Standort als "verdaechtig" meldet.
class _VerdaechtigerOrtService extends FakeOrtService {
  _VerdaechtigerOrtService({super.position});

  @override
  Future<bool> isLocationSuspicious(
    Position newPosition, {
    double thresholdMeters = 100,
  }) async => true;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // Der Supabase-Client zeigt auf den Fake-Server: es geht KEINE
    // Anfrage raus.
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
    server.antwortetMitFehler = false;
    server.rpcAntworten.clear();
    server.zeilen.clear();
    server.schreibvorgaenge.clear();
    // DIE BERECHTIGUNGEN: ohne diesen Ersatz ruft der Bildschirm das
    // echte Plugin (im Test gibt es das nicht).
    PermissionHandlerPlatform.instance = ProfileEditScreenBerechtigungen();
  });

  /// Tippt den GPS-Knopf (der sitzt weit unten im Formular).
  Future<void> tippeGps(WidgetTester tester) async {
    final gps = find.byIcon(Icons.my_location);
    await tester.scrollUntilVisible(
      gps,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFrames(tester);
    await tester.tap(gps);
    await pumpFrames(tester);
    // DIE OFFENLEGUNG: Sie kommt VOR der Berechtigung (das verlangt
    // Google Play) - ohne sie passiert gar nichts.
    await tester.tap(
      find.text(L10n.tWithoutContext('location.disclosureAccept')),
    );
    await pumpFrames(tester);
  }

  group('Die Standort-Hinweise', () {
    testWidgets('ohne GPS kommt der Hinweis "nicht ermittelt"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // OHNE POSITION: Das Geraet gibt keine Position her.
      await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
        ortService: FakeOrtService(),
      );

      await tippeGps(tester);

      expect(
        find.text(L10n.tWithoutContext('profile.edit.locationFailed')),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, WARUM kein Standort im Profil steht - '
            'sonst denkt er, die App haette sein Bundesland geloescht.',
      );

      await aufraeumen(tester);
    });

    testWidgets('ein abweichender Standort wird als verdächtig gemeldet', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
        ortService: _VerdaechtigerOrtService(
          position: profileEditScreenPosition(),
        ),
      );

      await tippeGps(tester);

      expect(
        find.text(L10n.tWithoutContext('profile.edit.locationSuspicious')),
        findsOneWidget,
        reason:
            'Ein Standort weit vom bisherigen Geraet ist ein Muster von '
            'Massen-Konten - der Nutzer muss darauf hingewiesen werden, '
            'bevor er ihn speichert.',
      );

      await aufraeumen(tester);
    });
  });
}
