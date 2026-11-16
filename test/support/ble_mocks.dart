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
  _FakeBluePlus({this.adapterAn = true});

  /// Steht der Adapter (also das Bluetooth) auf dem Geraet an?
  final bool adapterAn;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Im Test nicht gebraucht: ${invocation.memberName}');
  }

  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async => true;

  @override
  Future<BmBluetoothAdapterState> getAdapterState(
    BmBluetoothAdapterStateRequest request,
  ) async => BmBluetoothAdapterState(
    adapterState: adapterAn ? BmAdapterStateEnum.on : BmAdapterStateEnum.off,
  );

  /// Der Adapter-Zustand als Strom.
  ///
  /// WICHTIG: Der Dienst liest den Zustand ueber
  /// `FlutterBluePlus.adapterState` - das ist dieser Strom. Ohne ihn
  /// wirft der Aufruf, der Dienst faengt das ab ("nicht blockieren")
  /// und der Radar startet auch bei ausgeschaltetem Bluetooth.
  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged =>
      Stream<BmBluetoothAdapterState>.value(
        BmBluetoothAdapterState(
          adapterState: adapterAn
              ? BmAdapterStateEnum.on
              : BmAdapterStateEnum.off,
        ),
      );

  @override
  Future<bool> startScan(BmScanSettings request) async => true;

  @override
  Future<bool> stopScan(BmStopScanRequest request) async => true;
}

/// Wie oft das Advertising gestartet wurde.
///
/// DER GRUND: Damit laesst sich pruefen, ob der Bildschirm den Dienst
/// wirklich anspricht - nicht nur, ob irgendwo eine Meldung steht.
int advertisingStarts = 0;

/// Setzt den Zaehler zurueck (vor jedem Test).
void resetAdvertisingZaehler() {
  advertisingStarts = 0;
}

/// Beantwortet die Bluetooth-Aufrufe.
///
/// [advertisingMoeglich]=false simuliert ein Geraet, auf dem das
/// Advertising abgelehnt wird (der Dienst meldet dann
/// 'advertise_failed').
///
/// [adapterAn]=false simuliert ein Geraet, auf dem das Bluetooth AUS ist
/// (der Dienst meldet dann 'bluetooth_off' - und der Bildschirm zeigt
/// den passenden Hinweis).
void mockBluetooth({bool advertisingMoeglich = true, bool adapterAn = true}) {
  FlutterBluePlusPlatform.instance = _FakeBluePlus(adapterAn: adapterAn);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(transitBleKanal, (anfrage) async {
        switch (anfrage.method) {
          case 'startAdvertise':
            advertisingStarts++;
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
