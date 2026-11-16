// Die Bluetooth-Ersatzwaerter fuer die Tests.
//
// ANLASS (15.11.2026): Der Transit-Dienst (Transit Spark) startet das
// Bluetooth-Advertising und fragt den Adapter-Zustand ab. Beides geht
// nur auf einem echten Geraet - im Test wartet der Adapter-Zustand
// endlos (das Plugin antwortet auf dem Testrechner nicht) und der
// Dienst haengt beim Start.
//
// WICHTIG: Diese Datei gehoert NUR zu den Tests. Sie aendert nichts an
// der App - das Bluetooth laeuft auf dem Geraet genau wie vorher. Der
// Ersatz beantwortet nur die Plugin-Kanaele im Testprozess.
//
// WAS HIER ERSETZT WIRD:
//   * der Adapter-Zustand (flutter_blue_plus) - "an",
//   * der Start/Stopp des nativen Advertising (Kanal 'thestia/transit_ble').
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Der Kanal des nativen Advertising (Transit Spark).
///
/// DER GRUND: Das Advertising laeuft nicht ueber flutter_blue_plus,
/// sondern ueber einen eigenen Kanal der App (Android/MacOS nativ).
const MethodChannel transitBleKanal = MethodChannel('thestia/transit_ble');

/// Der BLE-Adapter im Test: eingeschaltet, der Scan liefert nichts.
///
/// Die nicht benutzten Methoden der Schnittstelle werden bewusst
/// NICHT nachgebaut - ein Aufruf waere im Test ein Fehler (und kein
/// stilles "geht schon").
base class _FakeBluePlus extends FlutterBluePlusPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Im Test nicht gebraucht: ${invocation.memberName}');
  }

  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async => true;

  @override
  Future<BmBluetoothAdapterState> getAdapterState(
    BmBluetoothAdapterStateRequest request,
  ) async => BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);

  @override
  Future<bool> startScan(BmScanSettings request) async => true;

  @override
  Future<bool> stopScan(BmStopScanRequest request) async => true;
}

/// Beantwortet die Bluetooth-Aufrufe.
///
/// [advertisingMoeglich]=false simuliert ein Geraet, auf dem das
/// Advertising abgelehnt wird (der Dienst meldet dann
/// 'advertise_failed').
void mockBluetooth({bool advertisingMoeglich = true}) {
  FlutterBluePlusPlatform.instance = _FakeBluePlus();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(transitBleKanal, (anfrage) async {
        switch (anfrage.method) {
          case 'startAdvertise':
            return advertisingMoeglich;
          case 'stopAdvertise':
            return null;
        }
        return null;
      });
}

/// Nimmt die Bluetooth-Ersatzwaerter wieder aus dem Spiel.
void unmockBluetooth() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(transitBleKanal, null);
}
