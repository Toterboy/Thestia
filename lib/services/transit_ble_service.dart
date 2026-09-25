import 'dart:async';

import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:thestia/services/transit_encounter_service.dart';

/// BLE-Schicht für Transit Spark (Phase 1, v0.9.0).
///
/// Prinzip: Beide Geräte ADVERTISEN ihr ephemeres Token im
/// Hersteller-Feld (ID 0xFFFF = SIG-reserviert, Payload-Marker "WST1" +
/// Token-ASCII) und SCANNEN gleichzeitig die Umgebung. Sichtung =
/// fremdes Token in Reichweite (3-10 m).
///
/// Implementation:
///  - Advertising über den NATIVEN Platform-Channel "thestia/transit_ble"
///    (MainActivity.kt) - bewusst kein Plugin: flutter_ble_peripheral
///    kompilierte mit unserem Kotlin-Setup nicht. Scanning läuft über
///    flutter_blue_plus.
///
/// Datenschutz: Nur zufällige Tokens, keine Geräte-Adresse/Name-Übernahme,
/// kein Standort. Tokens rotieren pro Aktivierung.
///
/// HINWEIS (v1): Vordergrund-Betrieb (Radarscreen offen) - Hintergrund-
/// Scanning und iOS-spezifische Einschränkungen folgen in 0.9.x.
class TransitBleService {
  TransitBleService._();
  static final TransitBleService instance = TransitBleService._();

  static const MethodChannel _channel = MethodChannel('thestia/transit_ble');

  StreamSubscription<List<ScanResult>>? _scanSub;

  bool _advertising = false;
  bool _scanning = false;
  String? _currentToken;

  bool get isActive => _advertising || _scanning;

  /// Maschinenlesbarer Grund des letzten Fehlschlags (für gezielte
  /// UI-Hinweise statt generischem "startFailed"):
  /// 'location_permission' | 'location_service' | 'bluetooth_scan' |
  /// 'bluetooth_connect' | 'bluetooth_advertise' | 'bluetooth_off' | null.
  String? lastError;

  /// Laufzeit-Berechtigungen fürs Radar (v0.9.0-Feedback: "Radar lässt
  /// sich auf Android 11 nicht starten"; v0.9.1: Standort-Dienst +
  /// ADVERTISE fehlten).
  ///
  ///  - Android <= 11: ACCESS_FINE_LOCATION ist PFLICHT für BLE-Scan
  ///    (Manifest hat sie, aber sie wurde NIE angefragt) - plus
  ///    BLUETOOTH/BLUETOOTH_ADMIN als Manifest-Permissions. Zusätzlich
  ///    muss der Standort-DIENST (GPS) eingeschaltet sein - sonst wirft
  ///    startScan still (v0.9.1-Fix: Geolocator-Check mit lastError
  ///    'location_service', die UI bietet "Standort einschalten" an).
  ///  - Android >= 12: BLUETOOTH_SCAN + BLUETOOTH_CONNECT +
  ///    BLUETOOTH_ADVERTISE als Laufzeit-Berechtigungen (ADVERTISE fehlte
  ///    bisher -> natives startAdvertising warf SecurityException, die
  ///    MainActivity still als false schluckte).
  Future<bool> _ensurePermissions() async {
    lastError = null;
    try {
      if (kIsWeb) return true;
      if (Platform.isIOS) {
        var bt = await Permission.bluetooth.status;
        if (!bt.isGranted) bt = await Permission.bluetooth.request();
        final ok = bt.isGranted || bt.isLimited;
        if (!ok) lastError = 'bluetooth_scan';
        return ok;
      }
      if (!Platform.isAndroid) return true;

      var location = await Permission.locationWhenInUse.status;
      if (!location.isGranted) {
        location = await Permission.locationWhenInUse.request();
      }
      if (!location.isGranted) {
        lastError = 'location_permission';
        return false;
      }

      // Standort-DIENST (GPS) muss AN sein - sonst scheitert der BLE-Scan
      // (besonders Android 11) ohne klare Exception. Die App kann den
      // Dienst nicht selbst einschalten (Android verbietet das), aber die
      // UI kann per Geolocator.openLocationSettings() dorthin führen.
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          lastError = 'location_service';
          return false;
        }
      } catch (_) {
        // Geolocator nicht verfügbar -> nicht blockieren.
      }

      // Bluetooth AUS? (Fix "Bluetooth-Popup kam nicht"): Permissions
      // können vollständig erteilt sein und der Adapter trotzdem AUS
      // sein - dann schlägt Advertising mit 'advertise_failed' fehl und
      // der Screen bricht ab, ohne den Aktivieren-Dialog zu zeigen.
      try {
        final adapterState = await FlutterBluePlus.adapterState.first;
        if (adapterState != BluetoothAdapterState.on) {
          lastError = 'bluetooth_off';
          return false;
        }
      } catch (_) {
        // Adapter-Status nicht ablesbar -> nicht blockieren.
      }

      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt >= 31) {
        var scan = await Permission.bluetoothScan.status;
        if (!scan.isGranted) scan = await Permission.bluetoothScan.request();
        var connect = await Permission.bluetoothConnect.status;
        if (!connect.isGranted) {
          connect = await Permission.bluetoothConnect.request();
        }
        var advertise = await Permission.bluetoothAdvertise.status;
        if (!advertise.isGranted) {
          advertise = await Permission.bluetoothAdvertise.request();
        }
        if (!scan.isGranted) {
          lastError = 'bluetooth_scan';
          return false;
        }
        if (!connect.isGranted) {
          lastError = 'bluetooth_connect';
          return false;
        }
        if (!advertise.isGranted) {
          lastError = 'bluetooth_advertise';
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[TransitBle] Berechtigungsprüfung fehlgeschlagen: $e');
      return true;
    }
  }

  /// Ob der Standort-Dienst aktuell eingeschaltet ist (für UI-Hinweise).
  Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return true;
    }
  }

  /// Startet Advertising (eigenes Token) + Scanning (fremde Tokens).
  /// [onEncounter] feuert pro gesichtetem fremden Token.
  Future<bool> start({
    required String token,
    required void Function(String token, int rssi) onEncounter,
  }) async {
    await stop();
    _currentToken = token;

    // Laufzeit-Berechtigungen (Android 11 braucht STANDORT fürs Scanning,
    // Android 12+ braucht SCAN/CONNECT) - vorher kam der Start mit einer
    // unbegründeten Exception nicht zustande.
    if (!await _ensurePermissions()) {
      debugPrint('[TransitBle] Berechtigungen verweigert - Radar startet '
          'nicht.');
      return false;
    }

    // Defensive Längenprüfung: Ein zu langes Token würde nativ mit
    // ADVERTISE_FAILED_DATA_TOO_LARGE scheitern (stille Funkstille).
    if (!TransitEncounterService.blePayloadFits(token)) {
      debugPrint('[TransitBle] Token zu lang für BLE-Paket - Radar startet '
          'nicht.');
      lastError = 'advertise_failed';
      return false;
    }

    try {
      // --- Advertising (nativ, ECHTES Ergebnis via AdvertiseCallback) ---
      final ok = await _channel
          .invokeMethod<bool>('startAdvertise', {'token': token})
          .timeout(const Duration(seconds: 10));
      _advertising = ok ?? false;
      if (!_advertising) {
        debugPrint('[TransitBle] Natives Advertising abgelehnt.');
        lastError = 'advertise_failed';
        await stop();
        return false;
      }

      // --- Scanning (fremde Tokens) ---
      await FlutterBluePlus.startScan(timeout: null);
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final token = _extractToken(r);
          if (token != null && token != _currentToken) {
            onEncounter(token, r.rssi);
          }
        }
      });
      _scanning = true;
      return true;
    } catch (e) {
      debugPrint('[TransitBle] Start fehlgeschlagen: $e');
      await stop();
      return false;
    }
  }

  /// Rotiert das Token (beibehaltener Betrieb, z. B. alle 10 Minuten).
  Future<void> rotateToken({
    required String newToken,
    required void Function(String token, int rssi) onEncounter,
  }) async {
    if (!_advertising) return;
    _currentToken = newToken;
    try {
      final ok = await _channel
          .invokeMethod<bool>('startAdvertise', {'token': newToken})
          .timeout(const Duration(seconds: 8));
      if (ok != true) {
        debugPrint('[TransitBle] Rotation fehlgeschlagen');
      }
    } catch (e) {
      debugPrint('[TransitBle] Rotate fehlgeschlagen: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _scanSub?.cancel();
      await FlutterBluePlus.stopScan();
      await _channel.invokeMethod('stopAdvertise');
    } catch (e) {
      debugPrint('[TransitBle] Stop fehlgeschlagen: $e');
    } finally {
      _scanSub = null;
      _advertising = false;
      _scanning = false;
      _currentToken = null;
    }
  }

  /// Extrahiert das Thestia-Transit-Token aus einem Scan-Ergebnis
  /// (Hersteller-Feld 0xFFFF: Marker + Token).
  String? _extractToken(ScanResult r) {
    try {
      final md = r.advertisementData.manufacturerData;
      if (md.isEmpty) return null;
      // Nur unser Hersteller-ID-Eintrag (Key = 0xFFFF).
      final entry = md[0xFFFF];
      if (entry == null || entry.isEmpty) return null;
      final markerBytes = utf8.encode(TransitEncounterService.bleMarker);
      if (entry.length <= markerBytes.length) return null;
      for (var i = 0; i < markerBytes.length; i++) {
        if (entry[i] != markerBytes[i]) return null;
      }
      final token = utf8.decode(
        entry.sublist(markerBytes.length),
        allowMalformed: true,
      );
      if (token.length < 8 || token.length > 64) return null;
      return token;
    } catch (_) {
      return null;
    }
  }
}
