# Modelle (On-Device-KI)

Dieser Ordner enthält lokale KI-Modelle für WispDating.

## image-safety-classifier-xs.onnx (NSFW-Bildmoderation, v0.8.0)

Die Datei `image-safety-classifier-xs.onnx` (OwenElliott/
image-safety-classifier-xs, Hugging Face) gehört HIER hinein und wird
in `pubspec.yaml` als Asset gebündelt.

- Eingang: 224x224 RGB, Float32, NCHW (Name in der Regel `input`)
- Ausgang: 3 Wahrscheinlichkeiten in der Reihenfolge `[NSFL, NSFW, SFW]`
- Nutzung: AUSSCHLIESSLICH lokale Vorprüfung nach manueller Bild-Meldung
  (Human-in-the-Loop) - niemals beim Senden/Empfangen (E2E-Schutz)
- Läuft über das Paket `onnxruntime` komplett auf dem Gerät

Fehlt die Datei, deaktiviert sich die lokale Prüfung automatisch
(`ImageSafetyService.isAvailable == false`) und der bisherige Flow
(serverseitiger Fallback-Scan) greift.

## face_detector.onnx (1,1 MB, GEBÜNDELT, v0.9.1)

**UltraFace RFB-320 simplified** (Linzaer/Ultra-Light-Fast-Generic-
Face-Detector-1MB, **MIT-Lizenz**;
`models/onnx/version-RFB-320_simplified.onnx`). Per `onnx.checker`
verifiziert:

- Eingang `input`: [1,3,240,320] (Höhe 240, Breite 320), (x-127)/128
- Ausgang: `scores` [1,4420,2] + `boxes` [1,4420,4] (bereits dekodiert,
  normiert, Opset 9). NMS (IoU 0.4) + Schwellwert (0.5) in der App.
- Alternativ: einzelner Output [N,>=5] mit (x1,y1,x2,y2,score).
- Fehlt die Datei, meldet `AgeEstimationService` `faceCount = -1`
  (unbekannt) – der Fall landet in der manuellen Prüfung.

## age_estimator.onnx (81 MB, GEBÜNDELT, v0.9.1)

**FairFace** (yakhyo/fairface-onnx, Gewichte laut Repo unter
**CC BY 4.0**, `releases/download/weights/fairface.onnx`). Per
`onnx.checker` verifiziert:

- Eingang `input`: [1,3,224,224] RGB Float32, ImageNet-Norm
  (Konstante `AgeEstimationService.ageInputNorm`, Opset 17).
- Ausgänge: `race_output` [?,7] + `gender_output` [?,2] +
  `age_output` [?,9]. Die App wählt den Alters-Kopf anhand der Form
  (9 = FairFace-Gruppen 0-2 … 70+, es werden die Gruppenmitten
  [1, 6, 14.5, 24.5, 34.5, 44.5, 54.5, 64.5, 75] gewichtet);
  zusätzlich verstanden: [1,1] (Jahre direkt) und [1,N]
  (Erwartungswert 0..N-1).
- Hinweis: FairFace liefert nur den Alterskopf, Race/Gender werden
  ignoriert (nichts davon verlässt das Gerät).
- Robustheit (v0.9.0, Mehrframe-Median): Geschätzt wird NICHT mehr
  aus einem einzigen Selfie, sondern aus bis zu 6 Frames (5 über
  den Videoclip verteilte Frames via `video_thumbnail` + 1 Selfie,
  mind. 3 verwertbar). Der Median (`summarizeFrames`) schluckt
  Einzelbild-Ausreißer (z. B. 27 statt 18 durch einen ungünstigen
  Winkel). 2-Jahre-Regel und manuelle Prüfung bleiben identisch.
- Ehrlicher Hinweis zur Genauigkeit: 10-Jahres-Gruppen liefern grobe
  Werte – legitime Nutzer landen dadurch häufiger in der manuellen
  Prüfung (sichere Richtung: mehr Reviews, keine falschen Freigaben).
  APK-Wirkung: Die beiden Dateien (1 MB + 81 MB) werden mitgebündelt
  und vergrößern die APK entsprechend.
- 2-Jahre-Regel: Weicht der Median mehr als 2 Jahre vom angegebenen
  Alter ab (oder war nicht in jedem Frame genau ein Gesicht zu
  sehen), geht der Fall in die manuelle Prüfung – automatisch
  freigegeben wird nie ohne Video + Liveness-Challenge +
  Server-Nachprüfung (Edge Action "auto", Migration 095).
- Fehlt die Datei, ist `AgeEstimationService.isAvailable == false` und
  ALLE Fälle laufen über die manuelle Queue.
- Genau EIN Modell, kein Zweitmodell: Scheitert die Schätzung, ist
  die manuelle Prüfung durch den Support der Fallback.

## Geprüft und verworfen (v0.9.0, nicht gebündelt)

- `age_gender.onnx` (1,3 MB, 96x96, Output `fc1` [1,3]): Auf 16
  gelabelten UTKFace-Gesichtern vermessen – Kanal 0/1 ist ein
  Gender-Logit-Paar (c1 = -c0, trennt männlich/weiblich), Kanal 2
  korreliert NICHT mit dem Alter (r ≈ +0.28, Werte 0.15–0.70 ohne
  Altersbezug). Fazit: Gender-Klassifikator ohne nutzbaren
  Alterskanal – als Altersersatz ungeeignet, Datei entfernt
  (Backup lokal beim Entwickler, nicht im Repo).
- `age-gender-recognition-retail-0013` (Intel, Apache 2.0): Laut
  Datenblatt mittlerer Altersfehler 6,99 Jahre und nur für 18–75
  ausgelegt (keine Kinder) – schlechter als FairFace bei jungen
  Gesichtern, daher nicht übernommen.
- `age-gender-prediction-ONNX` (ViT, Apache 2.0): 345 MB – für die
  APK zu groß, nicht übernommen.
- SSR-Net u. ä. Kleinstmodelle ohne klare Lizenz wurden aus
  Lizenzgründen nicht evaluiert.

## Ehrlichkeitshinweis

On-Device-KI ist ein Triage-Filter, kein Beweis: Modifizierte Clients
könnten falsche Werte behaupten. Deshalb bleiben Video-Upload,
serverseitige Regel-Nachprüfung (verify-account/action "auto"),
Admin-Queue und Stichproben bestehen. Niemals allein auf den
KI-Wert verlassen.

## Supply-Chain (Modelle + Runtime)

- Es werden AUSSCHLIESSLICH gebündelte Modelle geladen (keine
  Downloads zur Laufzeit). Jede Modell-Datei ist per SHA-256 im Code
  gepinnt (`AgeEstimationService.expected*Sha256`) - ausgetauschte
  Dateien fallen fail-closed in die manuelle Prüfung. Das entspricht
  der empfohlenen Mitigation gegen bekannte ONNX-Modellparser-Lücken
  (z. B. CVE-2026-14647 OOB-Read, CVE-2026-34445/34446 beim Laden
  fremder Modelle): Fremde Modelle kommen gar nicht erst auf das Gerät.
