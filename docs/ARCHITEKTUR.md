# Architektur-Dokumentation

> Status: September 2026 (v0.8.x) · Dieser Text beschreibt die AKTUELLE
> Architektur und die geplanten Bausteine für v0.10.0 (Sanctuary) und
> v0.11.0 (Web-Bridge). Entscheidungshistorie: [adr/](adr/).

## 1. Überblick (aktuell)

```
┌──────────────────────────── Flutter App (Dart) ───────────────────────────┐
│  UI (lib/screens)          State (lib/providers, Riverpod)                │
│  Router: go_router         Persistenz: SharedPreferences / SecureStorage  │
│  (Shell + Fullscreen)      + Hive (Signal-Keys, Chat-Verlauf SecureHive)  │
├────────────────────────────────────────────────────────────────────────────┤
│  Services (lib/services)                                                  │
│   • SupabaseAuth/Database/Storage  • E2E: Signal-Protokoll                │
│   • Dating-Hour- & Matching-RPCs   • WebRTC P2P (Audio/Video/Chat)        │
│   • Notification (FCM|UnifiedPush) • DeviceSession (+ device_model, 078)  │
│   • PasskeyAuth (WebAuthn)         • ServerTime (Anti-Cheat)              │
│   • ImageSafetyService (NSFW on-   • AvatarCrypto (AES-256-GCM vor        │
│     device, onnxruntime, gebündelt)  dem Avatar-Upload)                   │
└──────────────┬──────────────────────────────┬──────────────────────────────┘
               │ HTTPS/PostgREST (RLS)         │ WebRTC DataChannel/DTLS
┌──────────────▼──────────────┐   ┌───────────▼───────────────────────────┐
│ Supabase (eu-central-1)     │   │ Peer-to-Peer (Signal/E2E)             │
│ Auth (GoTrue, Passkeys/MFA) │   │ Signaling über Supabase Realtime;     │
│ Postgres + RLS + Views/RPCs │   │ TURN-Relay (Cloudflare) sieht keine   │
│ Edge Functions (Deno)       │   │ Inhalte (SRTP/DTLS-SRTP)              │
│ Storage (Avatar/Audio,      │   └───────────────────────────────────────┘
│  Avatare nur als Ciphertext)│
└─────────────────────────────┘
```

### Sicherheit als Architekturprinzip

- **Default-deny RLS**: Direkte Tabellenzugriffe sind minimiert; fremde
  Profil-Lesezugriffe laufen NUR über die auditierte View
  `public_profiles` (bewusster Definer-Modus, siehe Migration 072) und
  die RPC-Funktionen (006/033/047/050/056).
- **Jugendschutz serverseitig**: `age_compatible` filtert Zeilen in View
  und RPCs (Migration 056); der Client kann die Filter nicht umgehen.
- **E2E**: Identitäten/Sessions im Keystore, PreKey-Service auf dem
  Server (JWT-geschützt), Zertifikat-Pinning für HTTPS.
- **Onboarding-Garantie**: `profiles.onboarding_done` (065) + Setup-Flags
  verhindern Wiederholungen der Einrichtung nach Neuinstallation.
- **Konto-Datenhalt** („Nichts geht verloren"): Präferenzen (066),
  UI-Flags/Theme/DH-Intro (071), Musik/Score/`ui_prefs` (074), Pausenmodus
  + Dealbreaker (076) und Profilbilder (077) werden serverseitig
  gespiegelt und beim Login wiederhergestellt.
- **Migrations-robuste Sync-Schicht** (v0.8.x): Ladevorgänge wählen
  stufenweise ältere Spaltensätze (Profil zweistufig mit/ohne `photos`,
  Präferenzen dreistufig inkl. `theme_name`); Schreibvorgänge erkennen
  PostgREST-„missing column"-Fehler und entfernen die fehlende Spalte
  automatisch – eine fehlende Migration kann nie den kompletten Restore
  oder Save auslöschen.
- **Verschlüsselte Avatare**: `AvatarCrypto` (AES-256-GCM,
  Zufalls-Schlüssel pro Bild) verschlüsselt vor dem Upload; der
  Schlüssel liegt im `photos`-Eintrag (`pfad|key|iv`), Anzeige nur nach
  lokalem Download + Entschlüsselung (`loadAvatarBytes`). Legacy-
  Klartext-Avatare bleiben lesbar.
- **NSFW on-device**: `ImageSafetyService` klassifiziert Profilbilder
  vor dem Upload lokal (gebündeltes ONNX-Modell, onnxruntime); bei
  Nichtbestehen verlässt das Bild das Gerät nicht (Einspruch → Upload +
  Team-Review). Modell-Load ist durch einen Inferenz-Test abgesichert
  (IR-Version-Patch, Batch-Dimension, 0-255-Pixelskalierung).

## 2. Geplante Architektur v0.10.0 – Sanctuary (lokaler KI-Reflexions-Chat)

Neuer, vollständig OFFLINE diced Teilbereich ohne Supabase-Bezug:

```
lib/
├─ services/
│  ├─ llm_engine_service.dart        # llama.cpp-FFI bzw. MediaPipe/LiteRT
│  ├─ model_registry_service.dart    # kuratierte Modelle + Quantisierungen
│  ├─ model_download_service.dart    # HF-Download, Hash, Resume, Speicher
│  ├─ sanctuary_prompt_service.dart  # modellspezifische System-Prompts
│  └─ crisis_detection_service.dart  # Regex-Erkennung, Notfallkontakte
├─ models/sanctuary_models.dart      # ModelEntry, DownloadTask, ChatTurn
├─ providers/sanctuary_provider.dart # Zustand: Modellwahl, Chat, Download
└─ screens/sanctuary/                # Auswahl, Download, Chat, Meldung
```

Designpunkte:

- **Modell-Registry**: Kuratierte Stufen (1: Gemma 4 E2B, Spark-X2.5-1.7B;
  2: Qwen 3.5-4B, Gemma 4 E4B, Spark-X2.5-4B) mit
  Quantisierungs-Varianten (Q3/Q4_K_M/Q5/Q6) inkl. RAM-Schätzungen.
- **Eigene-Modell-Erkennung**: Hash-/Name-Matching importierter GGUF-
  Dateien gegen die Registry → automatische Übernahme der geprüften
  System-Prompts; unbekannte Modelle erhalten den editierbaren
  Standard-Prompt.
- **Datenschutz by design**: Chat nur im RAM; optional AES-verschlüsselt
  in Hive (Schlüssel im Keystore). Netzwerkzugriff ist im Sanctuary
  Prozesspfad bewusst NICHT vorgesehen (außer der explizite
  Modell-Download).
- **Sicherheit**: Pflicht-Disclaimer, Krisen-Erkennung mit
  Notfallkontakt-Karte, strukturierte Qualitäts-Meldung (Textauszug +
  Metadaten, nur nach Nutzerbestätigung).

## 3. Geplante Architektur v0.11.0 – Web-Bridge & Transit-Reachability

Erweiterung um Flutter-Web als LEICHTE GAST-Fläche (ohne App-Install):

```
┌────────────── Codeberg Pages (Berlin, trackerfrei) ──────────────┐
│ Flutter-Web-Build: Gast-Profil, Gast-Chat (WebRTC/WASM), /live   │
└───────────────┬──────────────────────────────────────────────────┘
                │ Einmal-Token  thestia.app/spark/<token>
┌───────────────▼──────────────────────────────────────────────────┐
│ Supabase: flüchtige Spark-Sessions (TTL 24–48 h), Rate-Limits,   │
│ Same-Train-Lobbys (BSSID-Hash, Zugnummer), Realtime-Signaling    │
└──────────────────────────────────────────────────────────────────┘

Nahbereichskanäle (ohne Server):
  • OS-Share-Sheet (Quick Share / AirDrop) → Einladungskarte + Link
  • Hotspot-SSID-Beacon + Offline-Captive-Portal (lokal gehostet)
  • NFC-Sticker/Karten (NDEF-Link)
  • BLE/Wi-Fi-Direct (aus 0.9.0 Transit Spark wiederverwendet)
```

Designpunkte:

- **Zero-Install**: Gast ohne Konto/Telefon/E-Mail; identitätloses,
  kryptografisch gesichertes Session-Token; Sitzung flüchtig.
- **E2E auch für Gäste**: Schlüsselpaar wird im Browser (WASM) erzeugt;
  der Server vermittelt nur Signaling/STUN.
- **Missbrauchsschutz**: Rate-Limits pro Konto für Token-Erzeugung,
  Bild-Blur für Gäste, Meldungen mit manueller Admin-Prüfung, nahtlose
  Konvertierung in ein reguläres Konto nach App-Installation.
- **Same-Train-Erkennung**: BSSID-/Gateway-Hashes (keine Klartext-SSIDs)
  + GPS-Vektor-/Geschwindigkeits-Heuristik; Lobbys verfallen automatisch.

## 4. Dokument-Landkarte

| Dokument | Inhalt |
|---|---|
| [ROADMAP.md](../ROADMAP.md) | Versionsplanung inkl. 0.8–0.11 |
| [DATENSCHUTZ.md](DATENSCHUTZ.md) | Öffentliche Datenschutzerklärung |
| [DATENSCHUTZ-ENTWURF.md](DATENSCHUTZ-ENTWURF.md) | Arbeitsentwurf/Platzhalter |
| [PASSKEYS_SERVER_SETUP.md](PASSKEYS_SERVER_SETUP.md) | GoTrue-WebAuthn-Konfiguration (RP-Origins, apk-key-hash) |
| [BUILD.md](BUILD.md) | Build/Flavors |
| [FDROID.md](FDROID.md) | F-Droid-Pipeline |
| [adr/](adr/) | Architektur-Entscheidungen (ADRs) |
