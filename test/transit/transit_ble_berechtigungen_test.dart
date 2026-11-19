// Die Berechtigungswege des Transit-Bluetooth-Dienstes.
//
// ANLASS (20.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/transit/transit_ble_service.dart 106 offene Zeilen. Der
// Grund: Auf dem Testrechner (Linux/Windows) sind `Platform.isAndroid`
// und `Platform.isIOS` immer false - die gesamte Berechtigungslogik
// war unerreichbar. Genau dort liegen aber die Fehlergruende
// ('location_permission', 'bluetooth_scan', 'bluetooth_connect' ...),
// die der Bildschirm dem Nutzer nennt.
//
// DER WEG: Die kleine Naht `TransitPlattform` (nur Plattform + SDK-Version)
// und die vorhandenen Plugin-Ersatzwaerter erlauben es, Android 11,
// Android 12 und iOS im Test nachzustellen. Der Produktionscode laeuft
// unveraendert auf dem echten Geraet.
import 'package:flutter_test/flutter_test.dart';
// Das Plattform-Interface wird von permission_handler exportiert, aber
// nicht weitergereicht - der Test setzt die Attrappe darueber.
// ignore: depend_on_referenced_packages
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import 'package:thestia/services/transit/transit_ble_service.dart';

import '../support/ble_mocks.dart';

/// Eine andere Plattform, als sie der Testrechner hat.
class FakeTransitPlattform extends TransitPlattform {
  FakeTransitPlattform({this.ios = false, this.android = false, this.sdk = 31});

  final bool ios;
  final bool android;
  final int sdk;

  @override
  bool get istIOS => ios;

  @override
  bool get istAndroid => android;

  @override
  Future<int> androidSdkInt() async => sdk;
}

/// Der Berechtigungs-Ersatz: eine ausgewaehlte Berechtigung wird
/// verweigert, alle anderen erteilt.
class FakeBerechtigungen extends PermissionHandlerPlatform {
  FakeBerechtigungen(this.verweigert);

  final Permission? verweigert;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      permission == verweigert
      ? PermissionStatus.denied
      : PermissionStatus.granted;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async => {
    for (final p in permissions)
      p: p == verweigert ? PermissionStatus.denied : PermissionStatus.granted,
  };

  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async => false;
}

void main() {
  late TransitPlattform originalPlattform;
  late PermissionHandlerPlatform originalBerechtigungen;
  final dienst = TransitBleService.instance;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    originalPlattform = TransitPlattform.instance;
    originalBerechtigungen = PermissionHandlerPlatform.instance;
    dienst.lastError = null;
    mockBluetooth();
  });

  tearDown(() {
    TransitPlattform.instance = originalPlattform;
    PermissionHandlerPlatform.instance = originalBerechtigungen;
    unmockBluetooth();
  });

  /// Stellt eine Plattform und die verweigerte Berechtigung ein.
  void stelle({
    bool ios = false,
    int? sdk,
    Permission? verweigert,
    bool adapterAn = true,
  }) {
    TransitPlattform.instance = FakeTransitPlattform(
      ios: ios,
      android: sdk != null,
      sdk: sdk ?? 31,
    );
    PermissionHandlerPlatform.instance = FakeBerechtigungen(verweigert);
    mockBluetooth(adapterAn: adapterAn);
  }

  group('Die Berechtigungen des Transit-Dienstes', () {
    test('Android 11 ohne Standort meldet den Grund', () async {
      stelle(sdk: 30, verweigert: Permission.locationWhenInUse);

      final ok = await dienst.start(
        token: 'token-1234',
        onEncounter: (token, rssi) {},
      );

      expect(ok, isFalse);
      expect(
        dienst.lastError,
        'location_permission',
        reason:
            'Bis Android 11 ist der genaue Standort fuer den BLE-Scan '
            'Pflicht - der Nutzer muss erfahren, warum das Radar nicht '
            'startet.',
      );
    });

    test('Android 12 ohne Scan-Berechtigung meldet den Grund', () async {
      stelle(sdk: 31, verweigert: Permission.bluetoothScan);

      final ok = await dienst.start(
        token: 'token-1234',
        onEncounter: (token, rssi) {},
      );

      expect(ok, isFalse);
      expect(dienst.lastError, 'bluetooth_scan');
    });

    test('Android 12 ohne Connect-Berechtigung meldet den Grund', () async {
      stelle(sdk: 31, verweigert: Permission.bluetoothConnect);

      final ok = await dienst.start(
        token: 'token-1234',
        onEncounter: (token, rssi) {},
      );

      expect(ok, isFalse);
      expect(dienst.lastError, 'bluetooth_connect');
    });

    test('Android 12 ohne Advertise-Berechtigung meldet den Grund', () async {
      stelle(sdk: 31, verweigert: Permission.bluetoothAdvertise);

      final ok = await dienst.start(
        token: 'token-1234',
        onEncounter: (token, rssi) {},
      );

      expect(ok, isFalse);
      expect(
        dienst.lastError,
        'bluetooth_advertise',
        reason:
            'Ohne ADVERTISE scheitert das nativ startAdvertising mit '
            'einer SecurityException - der Nutzer braucht den klaren '
            'Grund.',
      );
    });

    test('iOS ohne Bluetooth-Berechtigung meldet den Grund', () async {
      stelle(ios: true, verweigert: Permission.bluetooth);

      final ok = await dienst.start(
        token: 'token-1234',
        onEncounter: (token, rssi) {},
      );

      expect(ok, isFalse);
      expect(dienst.lastError, 'bluetooth_scan');
    });
  });
}
