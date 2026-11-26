// Die Bluetooth-Ersatzwärter für die Tests.
//
// ANLASS (15.11.2026): Der Transit-Dienst (Transit Spark) startet das
// Bluetooth-Advertising und fragt den Adapter-Zustand ab. Beides geht
// nur auf einem echten Gerät - im Test wartet der Adapter-Zustand
// endlos (das Plugin antwortet auf dem Testrechner nicht) und der
// Dienst hängt beim Start.
//
// WICHTIG: Diese Datei gehört NUR zu den Tests. Sie ändert nichts an
// der App - das Bluetooth läuft auf dem Gerät genau wie vorher. Der
// Ersatz beantwortet nur die Plugin-Kanäle im Testprozess.
//
// WAS HIER ERSETZT WIRD:
//   * der Adapter-Zustand (flutter_blue_plus) - "an",
//   * der Start/Stopp des nativen Advertising (Kanal 'thestia/transit_ble').
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Der Kanal des nativen Advertising (Transit Spark).
///
/// DER GRUND: Das Advertising läuft nicht über flutter_blue_plus,
/// sondern über einen eigenen Kanal der App (Android/MacOS nativ).
const MethodChannel transitBleKanal = MethodChannel('thestia/transit_ble');

/// Der BLE-Adapter im Test: eingeschaltet, der Scan liefert nichts.
///
/// Die nicht benutzten Methoden der Schnittstelle werden bewusst
/// NICHT nachgebaut - ein Aufruf wäre im Test ein Fehler (und kein
/// stilles "geht schon").
base class _FakeBluePlus extends FlutterBluePlusPlatform {
  _FakeBluePlus({this.adapterAn = true});

  /// Steht der Adapter (also das Bluetooth) auf dem Gerät an?
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
  /// WICHTIG: Der Dienst liest den Zustand über
  /// `FlutterBluePlus.adapterState` - das ist dieser Strom. Ohne ihn
  /// wirft der Aufruf, der Dienst fängt das ab ("nicht blockieren")
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
/// DER GRUND: Damit lässt sich prüfen, ob der Bildschirm den Dienst
/// wirklich anspricht - nicht nur, ob irgendwo eine Meldung steht.
int advertisingStarts = 0;

/// Setzt den Zähler zurück (vor jedem Test).
void resetAdvertisingZaehler() {
  advertisingStarts = 0;
}

/// Beantwortet die Bluetooth-Aufrufe.
///
/// [advertisingMoeglich]=false simuliert ein Gerät, auf dem das
/// Advertising abgelehnt wird (der Dienst meldet dann
/// 'advertise_failed').
///
/// [adapterAn]=false simuliert ein Gerät, auf dem das Bluetooth AUS ist
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

/// Nimmt die Bluetooth-Ersatzwärter wieder aus dem Spiel.
void unmockBluetooth() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(transitBleKanal, null);
}
