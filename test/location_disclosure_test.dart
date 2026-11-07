import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Das Plattform-Interface wird von permission_handler exportiert, aber
// nicht weitergereicht - der Test setzt die Attrappe darueber.
// Das Paket ist ueber permission_handler ohnehin im Baum (es wird nur
// nicht direkt deklariert, weil die App es nicht selbst benutzt).
// ignore: depend_on_referenced_packages
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/widgets/location_disclosure.dart';

/// Tests fuer die prominente Standort-Offenlegung.
///
/// WARUM (06.11.2026): Google Play verlangt fuer EMPFINDLICHE
/// Berechtigungen (Kamera, Mikrofon, Standort) eine sichtbare
/// Begruendung IN DER APP, bevor der Systemdialog erscheint. Die App
/// hatte das fuer Kamera und Mikrofon - fuer den Standort fehlte es.
///
/// Diese Tests halten fest:
///   1) Fehlt die Berechtigung, erscheint die Offenlegung.
///   2) Ist sie erteilt, wird der Nutzer NICHT behelligt.
///   3) Einmal bestaetigt - dann nie wieder.
class _Berechtigungen extends PermissionHandlerPlatform {
  _Berechtigungen();

  /// Ist die Standort-Berechtigung erteilt?
  bool erteilt = false;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      erteilt ? PermissionStatus.granted : PermissionStatus.denied;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    erteilt = true;
    return {for (final p in permissions) p: PermissionStatus.granted};
  }
}

class _Speicher implements LocalStorage {
  final map = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async => map[key] = value;

  @override
  Future<String?> getString(String key) async => map[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      map[key] = value ? 'true' : 'false';

  @override
  Future<bool?> getBool(String key) async => map[key] == 'true';

  @override
  Future<void> saveInt(String key, int value) async => map[key] = '$value';

  @override
  Future<int?> getInt(String key) async =>
      map[key] == null ? null : int.tryParse(map[key]!);

  @override
  Future<void> remove(String key) async => map.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Berechtigungen berechtigungen;

  setUp(() {
    berechtigungen = _Berechtigungen();
    PermissionHandlerPlatform.instance = berechtigungen;
  });

  testWidgets('ohne Berechtigung erscheint die Offenlegung', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStorageProvider.overrideWithValue(_Speicher())],
        child: const MaterialApp(home: Scaffold(body: _Probe())),
      ),
    );
    await tester.pump();

    expect(
      find.text(L10n.tWithoutContext('location.disclosureTitle')),
      findsOneWidget,
      reason:
          'ohne Offenlegung fragt die App die Berechtigung im Hintergrund '
          'ab - das verlangt Google Play nicht',
    );

    await tester.tap(
      find.text(L10n.tWithoutContext('location.disclosureAccept')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(L10n.tWithoutContext('location.disclosureTitle')),
      findsNothing,
    );
  });

  testWidgets('mit Berechtigung wird der Nutzer nicht behelligt', (
    tester,
  ) async {
    berechtigungen.erteilt = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStorageProvider.overrideWithValue(_Speicher())],
        child: const MaterialApp(home: Scaffold(body: _Probe())),
      ),
    );
    await tester.pump();

    expect(
      find.text(L10n.tWithoutContext('location.disclosureTitle')),
      findsNothing,
      reason:
          'wenn die Berechtigung schon da ist, wird nichts angefragt und '
          'es braucht keine Begruendung',
    );
  });

  testWidgets('einmal bestaetigt - dann keine Offenlegung mehr', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStorageProvider.overrideWithValue(_Speicher())],
        child: const MaterialApp(home: Scaffold(body: _Probe())),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.text(L10n.tWithoutContext('location.disclosureAccept')),
    );
    await tester.pumpAndSettle();

    // Die Einstellung ist gemerkt.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_Probe)),
    );
    expect(container.read(settingsProvider).locationDisclosureAccepted, isTrue);

    // Und beim naechsten Mal kommt kein Dialog mehr.
    berechtigungen.erteilt = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStorageProvider.overrideWithValue(_Speicher())],
        child: const MaterialApp(home: Scaffold(body: _Probe())),
      ),
    );
    await tester.pump();
    expect(
      find.text(L10n.tWithoutContext('location.disclosureTitle')),
      findsNothing,
    );
  });
}

/// Ruft die Offenlegung beim Start auf (wie die Bildschirme es tun).
class _Probe extends ConsumerStatefulWidget {
  const _Probe();

  @override
  ConsumerState<_Probe> createState() => _ProbeState();
}

class _ProbeState extends ConsumerState<_Probe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ensureLocationDisclosure(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
