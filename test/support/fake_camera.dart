// Die Kamera-Attrappe für die Tests.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte für
// lib/screens/verification/parts/verificationvideoscreenstate.dart 263
// offene Zeilen bei 334 gesamt - der ganze Screen mit der
// Kamera-Aufnahme war ungetestet.
//
// DER WEG: Die Kamera spricht über die Plattform-Schnittstelle
// (`CameraPlatform.instance`) - nicht über einen MethodChannel. Der
// Test kann sie also durch einen Ersatz ziehen, ganz ohne Änderung
// am Produktionscode.
//
// WAS DIE ATTRAPPE KANN:
//   * eine Kamera melden (die App fragt sie ab),
//   * die Aufnahme starten und stoppen (mit echter Datei),
//   * zählen, wie oft gefragt wurde (das prüft die Offenlegung).
import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';

/// Die Kamera-Attrappe.
///
/// DER WEG: Die Basisklasse wirft bei jedem Aufruf "nicht
/// implementiert" - die Attrappe überschreibt nur, was die App
/// wirklich benutzt. Ruft die App etwas anderes auf, fällt das im
/// Test sofort auf (statt still zu scheitern).
class FakeCameraPlatform extends CameraPlatform {
  /// Wie oft wurde die Kamera angefragt?
  int anfragen = 0;

  /// Wie oft wurde die Aufnahme gestartet?
  int aufnahmen = 0;

  /// Die Datei, die die Aufnahme liefert.
  ///
  /// DER GRUND: Die App sichert die Aufnahme anschliessend unter einem
  /// eigenen Namen - der Test braucht also eine echte Datei.
  String? aufnahmeDatei;

  /// Meldet die Attrappe überhaupt eine Kamera?
  final bool hatKamera;

  /// Scheitert das Öffnen der Kamera (der Fehlerfall)?
  final bool fehlerBeimOeffnen;

  /// Der Kanal für Kamerafehler (bleibt offen).
  final StreamController<CameraErrorEvent> _fehler =
      StreamController<CameraErrorEvent>();

  /// Der Kanal für die Gerätedrehung (bleibt offen).
  final StreamController<DeviceOrientationChangedEvent> _drehung =
      StreamController<DeviceOrientationChangedEvent>();

  FakeCameraPlatform({this.hatKamera = true, this.fehlerBeimOeffnen = false});

  /// Die Kamera, die die App sieht.
  CameraDescription get kamera => const CameraDescription(
    name: 'test-kamera',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 0,
  );

  @override
  Future<List<CameraDescription>> availableCameras() async {
    anfragen++;
    if (!hatKamera) return const <CameraDescription>[];
    return <CameraDescription>[kamera];
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    if (fehlerBeimOeffnen) {
      throw CameraException('Kamera', 'Die Kamera geht nicht');
    }
    return 1;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    // Die Kamera ist "bereit".
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) {
    return Stream<CameraInitializedEvent>.value(
      CameraInitializedEvent(
        cameraId,
        640,
        480,
        ExposureMode.auto,
        false,
        FocusMode.auto,
        false,
      ),
    );
  }

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) {
    // DER EREIGNIS-KANAL: Er bleibt offen (wie beim echten Plugin).
    // Ein leerer Stream würde beim `.first` "No element" werfen - der
    // Controller stünde dann mit einem Fehler statt mit einem Bild
    // da.
    return _fehler.stream;
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() {
    // Das Gerät meldet keine Drehung.
    return _drehung.stream;
  }

  /// Schließt die offenen Kanäle (am Ende des Tests).
  void schliessen() {
    _fehler.close();
    _drehung.close();
  }

  @override
  Widget buildPreview(int cameraId) {
    // DER VORSCHAU: Ein leeres Feld - der Test prüft den Ablauf, nicht
    // das Bild.
    return const SizedBox.shrink();
  }

  @override
  Future<void> startVideoRecording(
    int cameraId, {
    Duration? maxVideoDuration,
  }) async {
    aufnahmen++;
  }

  /// Wie oft wurde die Aufnahme beendet?
  int aufnahmenGestoppt = 0;

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    aufnahmenGestoppt++;
    // Die Aufnahme-Datei: der Test legt sie vorher an.
    return XFile(aufnahmeDatei ?? '');
  }

  @override
  Future<void> prepareForVideoRecording() async {
    // Auf iOS nötig - unter Windows nicht.
  }

  @override
  Future<Object?> dispose(int cameraId) async => null;

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 1;

  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;

  @override
  Future<double> getMaxExposureOffset(int cameraId) async => 0;

  @override
  Future<double> getMinExposureOffset(int cameraId) async => 0;

  @override
  Future<double> getExposureOffsetStepSize(int cameraId) async => 1;

  /// Legt die Aufnahme-Datei an (die App erwartet sie nach dem Stoppen).
  String legeAufnahmeAn() {
    final ordner = Directory.systemTemp.createTempSync('kamera_test');
    final datei = File('${ordner.path}/aufnahme.mp4');
    datei.writeAsBytesSync(<int>[1, 2, 3, 4]);
    aufnahmeDatei = datei.path;
    return datei.path;
  }
}
