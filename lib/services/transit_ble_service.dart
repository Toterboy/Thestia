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
import 'package:thestia/services/transit_ble_privacy.dart';
import 'package:thestia/utils/best_effort.dart';

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
      // Geolocator nicht verfügbar -> nicht blockieren.
      final dienstOk = await bestEffortOr(
        'Geolocator.isLocationServiceEnabled',
        () async => await Geolocator.isLocationServiceEnabled(),
        true,
      );
      if (!dienstOk) {
        lastError = 'location_service';
        return false;
      }

      // Bluetooth AUS? (Fix "Bluetooth-Popup kam nicht"): Permissions
      // können vollständig erteilt sein und der Adapter trotzdem AUS
      // sein - dann schlägt Advertising mit 'advertise_failed' fehl und
      // der Screen bricht ab, ohne den Aktivieren-Dialog zu zeigen.
      // Adapter-Status nicht ablesbar -> nicht blockieren.
      final adapterOk = await bestEffortOr(
        'FlutterBluePlus.adapterState',
        () async {
          final adapterState = await FlutterBluePlus.adapterState.first;
          return adapterState == BluetoothAdapterState.on;
        },
        true,
      );
      if (!adapterOk) {
        lastError = 'bluetooth_off';
        return false;
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
    _onEncounter = onEncounter;

    // Laufzeit-Berechtigungen (Android 11 braucht STANDORT fürs Scanning,
    // Android 12+ braucht SCAN/CONNECT) - vorher kam der Start mit einer
    // unbegründeten Exception nicht zustande.
    if (!await _ensurePermissions()) {
      debugPrint(
        '[TransitBle] Berechtigungen verweigert - Radar startet '
        'nicht.',
      );
      return false;
    }

    // Defensive Längenprüfung: Ein zu langes Token würde nativ mit
    // ADVERTISE_FAILED_DATA_TOO_LARGE scheitern (stille Funkstille).
    if (!TransitEncounterService.blePayloadFits(token)) {
      debugPrint(
        '[TransitBle] Token zu lang für BLE-Paket - Radar startet '
        'nicht.',
      );
      lastError = 'advertise_failed';
      return false;
    }

    try {
      // --- Advertising (nativ, ECHTES Ergebnis via AdvertiseCallback) ---
      final ok = await _channel
          .invokeMethod<bool>('startAdvertise', {
            'token': token,
            // Jitter-Zyklus: die native Seite startet das Advertising nach
            // dieser Zeit neu. Ohne sie laeuft LOW_LATENCY 45 min im
            // starren ~100-ms-Takt - ein Fingerprint.
            'cycleMs': TransitBlePrivacy.advertiseCycleDelay().inMilliseconds,
          })
          .timeout(const Duration(seconds: 10));
      _advertising = ok ?? false;
      if (!_advertising) {
        debugPrint('[TransitBle] Natives Advertising abgelehnt.');
        lastError = 'advertise_failed';
        await stop();
        return false;
      }

      // --- Scanning (fremde Tokens) ---
      //
      // withMsd filtert schon im Plattform-Callback auf unsere
      // Hersteller-ID: alles andere in der Luft (Uhren, Kopfhoerer,
      // Beacons) erreicht die App gar nicht erst. Das war vorher die
      // Hauptlast und ein passiver Fremdverkehrs-Sniffer des Geraets.
      _startScanWindow();
      _schedulePulseNext();
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
    // Der neue Token wird IMMER gemerkt - auch wenn gerade kein Funk
    // laeuft (App im Hintergrund). Sonst waere nach dem Zurueckkommen
    // ein aelteres Token aktiv, obwohl die Rotation eigentlich lief.
    _currentToken = newToken;
    if (!_advertising) return;
    try {
      final ok = await _channel
          .invokeMethod<bool>('startAdvertise', {
            'token': newToken,
            // Neuer Zyklus mit neuer Jitter-Dauer: der Restart faellt dann
            // nicht mit der Token-Rotation zusammen.
            'cycleMs': TransitBlePrivacy.advertiseCycleDelay().inMilliseconds,
          })
          .timeout(const Duration(seconds: 8));
      if (ok != true) {
        debugPrint('[TransitBle] Rotation fehlgeschlagen');
      }
    } catch (e) {
      debugPrint('[TransitBle] Rotate fehlgeschlagen: $e');
    }
  }

  /// Callback fuer Begegnungen; wird von den Impulsfenstern genutzt.
  void Function(String token, int rssi)? _onEncounter;

  /// Timer fuer die Scan-Impulse (v0.9.2: gepulstes Scannen statt
  /// Dauerscan - siehe ROADMAP 0.9.0, dort war es behauptet, nicht gebaut).
  Timer? _pulseTimer;

  /// Startet ein Scan-Fenster.
  ///
  /// Der Plattform-Callback filtert schon auf unsere Hersteller-ID, es
  /// kommen also nur Thestia-Advertisements an.
  Future<void> _startScanWindow() async {
    try {
      await FlutterBluePlus.startScan(
        timeout: kScanPulseOn,
        withMsd: [MsdFilter(kThestiaManufacturerId)],
        continuousUpdates: true,
        oneByOne: false,
      );
      _scanSub = FlutterBluePlus.scanResults.listen(_onResults);
    } catch (e) {
      debugPrint('[TransitBle] Scan-Fenster start fehlgeschlagen: $e');
    }
  }

  /// Schliesst das aktuelle Fenster und plant das nächste nach einer
  /// unregelmässigen Pause (Datenschutz + Akku, siehe ROADMAP 0.9.2).
  void _schedulePulseNext() {
    _pulseTimer?.cancel();
    _pulseTimer = Timer(TransitBlePrivacy.scanPulseOff(), () async {
      if (!_scanning) return;
      await _stopScanWindow();
      if (!_scanning) return;
      await _startScanWindow();
      if (!_scanning) return;
      _schedulePulseNext();
    });
  }

  Future<void> _stopScanWindow() async {
    try {
      await _scanSub?.cancel();
      _scanSub = null;
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('[TransitBle] Scan-Fenster stop fehlgeschlagen: $e');
    } finally {}
  }

  void _onResults(List<ScanResult> results) {
    for (final r in results) {
      final token = _extractToken(r);
      if (token == null || token == _currentToken) continue;
      // Jedes Token nur EINMAL melden.
      //
      // BEFUND (06.11.2026): Das Advertising läuft im ~100-ms-Takt. Jede
      // Advertisement fuehrte zu einem setState im Provider und zu einem
      // Schreibvorgang des Caches - bei 10 Signalen pro Sekunde ein
      // Bildschirm-Neuaufbau pro Signal. Das Token selbst aendert sich
      // nur alle 6-14 Minuten (Rotation), also reicht die Meldung beim
      // ersten Sichtkontakt.
      if (!_gemeldeteTokens.add(token)) continue;
      _onEncounter?.call(token, r.rssi);
    }
  }

  /// Die bereits gemeldeten Tokens (Sitzung).
  ///
  /// Wird beim Stop geleert - ein neuer Radarlauf darf die gleichen
  /// Geraete wieder melden (die Zahl in der Anzeige ist dann wieder
  /// aktuell).
  final Set<String> _gemeldeteTokens = <String>{};

  /// Haelt das Funk-Radio an, ohne die Sitzung zu beenden.
  ///
  /// AKKU + PRIVATSPHARE (03.11.2026): Das Advertising lief im
  /// Hintergrund weiter - der native Zyklus sendet bis zu 45 Minuten im
  /// ~100-ms-Takt (LOW_LATENCY). Der Kommentar am Dateianfang sagt
  /// "Vordergrund-Betrieb"; die Umsetzung war es nicht. Mit diesem
  /// Aufruf wird es wieder so.
  ///
  /// Der Token bleibt erhalten: beim Zurueckkommen wird mit demselben
  /// Token weitergearbeitet (siehe [resume]).
  Future<void> suspend() async {
    if (!_advertising && !_scanning) return;
    _scanning = false;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    try {
      await _stopScanWindow();
      await _channel.invokeMethod('stopAdvertise');
    } catch (e) {
      debugPrint('[TransitBle] Suspend fehlgeschlagen: $e');
    }
    _advertising = false;
    // _currentToken und _onEncounter bleiben erhalten - das ist der
    // Unterschied zu [stop].
  }

  /// Startet das Funk-Radio nach einem [suspend] wieder.
  ///
  /// [token] setzt einen neuen Token. Das ist der Normalfall: Nach dem
  /// Hintergrund muss ein FRISCHES Token gesendet werden. Wer das Geraet
  /// eine Stunde lang ausgeschaltet hatte, sendet nach dem Zurueckkommen
  /// sonst wieder denselben Pseudonym-Token - genau die Kontinuitaet, die
  /// ein Beobachter sucht (ROADMAP, "BLE-Tracking-Haertung": "frische
  /// Token pro Advertising-Neustart").
  ///
  /// Gibt false zurueck, wenn nicht gestartet werden konnte (z. B. weil
  /// die Bluetooth-Berechtigung inzwischen fehlt).
  Future<bool> resume({String? token}) async {
    token = token ?? _currentToken;
    if (token == null) return false;
    if (_advertising) return true;
    try {
      final ok = await _channel
          .invokeMethod<bool>('startAdvertise', {
            'token': token,
            'cycleMs': TransitBlePrivacy.advertiseCycleDelay().inMilliseconds,
          })
          .timeout(const Duration(seconds: 10));
      _advertising = ok ?? false;
      if (!_advertising) {
        debugPrint('[TransitBle] Resume abgelehnt.');
        return false;
      }
      _startScanWindow();
      _schedulePulseNext();
      _scanning = true;
      return true;
    } catch (e) {
      debugPrint('[TransitBle] Resume fehlgeschlagen: $e');
      return false;
    }
  }

  Future<void> stop() async {
    // _scanning VOR dem Abo-Kill setzen: sonst plant _schedulePulseNext
    // den naechsten Zyklus, der nach dem Stop wieder aufwacht.
    _scanning = false;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    try {
      await _stopScanWindow();
      await _channel.invokeMethod('stopAdvertise');
    } catch (e) {
      debugPrint('[TransitBle] Stop fehlgeschlagen: $e');
    } finally {
      _scanSub = null;
      _advertising = false;
      _onEncounter = null;
      _currentToken = null;
      // Die gemeldeten Tokens gehoeren zur Sitzung: ein neuer Radarlauf
      // darf die gleichen Geraete wieder zaehlen.
      _gemeldeteTokens.clear();
    }
  }

  /// Extrahiert das Thestia-Transit-Token aus einem Scan-Ergebnis
  /// (Hersteller-Feld kThestiaManufacturerId: Marker + Token).
  ///
  /// BEFUND (06.11.2026, Betreiber): "Android 16 erkennt praktisch
  /// unendlich Thestia-Geräte (Es gibt maximal 1 anderes). Es werden
  /// immer mehr (aktuell über 100 gefunden)."
  ///
  /// Die Ursache: Die Hersteller-ID 0xFFFF ist die reservierte
  /// SIG-Nummer - sie wird von vielen echten Geraeten benutzt. Die alte
  /// Pruefung take nur die ersten vier Bytes ("WST1") und liest den Rest
  /// als Token. Auf Android 16 wird der Plattformfilter nicht
  /// zuverlaessig angewandt, es kamen also viele fremde Geraete herein -
  /// und jedes erzeugte einen neuen "Token", der im Cache landete. Die
  /// Zahl "Thestia-Geräte in Reichweite" war damit eine Zahl ueber
  /// fremde Bluetooth-Geraete.
  ///
  /// DIE REGEL: Ein echtes Thestia-Token ist EXAKT 20 Hexzeichen
  /// (10 Byte, siehe [TransitEncounterService.generateToken]). Alles
  /// andere wird verworfen. Damit kann die Zahl nur noch echte
  /// Thestia-Geraete zaehlen.
  ///
  /// Der Marker wird GESUCHT und nicht nur an Position 0 geprueft:
  /// manche Android-Versionen liefern die Firmen-ID mit im Payload.
  String? _extractToken(ScanResult r) {
    try {
      final md = r.advertisementData.manufacturerData;
      if (md.isEmpty) return null;
      // Nur unser Hersteller-ID-Eintrag. Die Konstante ist dieselbe, die der
      // withMsd-Filter beim Scannen benutzt - beide muessen zusammenpassen,
      // sonst sieht der Scanner nichts (bzw. filtert zu viel weg).
      final entry = md[kThestiaManufacturerId];
      if (entry == null || entry.isEmpty) return null;
      final markerBytes = utf8.encode(TransitEncounterService.bleMarker);
      final markerPos = _findeMarker(entry, markerBytes);
      if (markerPos < 0) return null;
      // Danach muss das Token stehen - genau 20 Hexzeichen.
      final rest = entry.sublist(markerPos + markerBytes.length);
      if (rest.length < TransitEncounterService.tokenLaenge) return null;
      final token = utf8.decode(
        rest.sublist(0, TransitEncounterService.tokenLaenge),
      );
      if (!TransitEncounterService.isValidToken(token)) return null;
      return token;
    } catch (_) {
      return null;
    }
  }

  /// Die Position des Markers im Payload (-1 = nicht gefunden).
  static int _findeMarker(List<int> entry, List<int> marker) {
    if (entry.length < marker.length) return -1;
    for (var start = 0; start <= entry.length - marker.length; start++) {
      var passt = true;
      for (var i = 0; i < marker.length; i++) {
        if (entry[start + i] != marker[i]) {
          passt = false;
          break;
        }
      }
      if (passt) return start;
    }
    return -1;
  }
}
