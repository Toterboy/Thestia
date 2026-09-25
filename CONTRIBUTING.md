# Beitragen zu Thestia

Danke für dein Interesse! Thestia ist Open Source (AGPLv3) und lebt von
Beiträgen – Code, Design, Übersetzungen, Dokumentation und Bug-Reports.

## Setup

```bash
git clone <repo-url>
cd blind_date_app
cp .env.example .env        # Werte vom Projektbetreuer erfragen
flutter pub get
flutter run                  # oder: flutter build apk --debug
```

- **Supabase-Zugang**: Für eigene Tests reicht ein kostenloses Supabase-Projekt;
  die Migrationen liegen unter `supabase/migrations/` und werden mit
  `supabase db push` eingespielt.
- **Code-Generierung** ist nur nach Änderungen an Hive-Modellen nötig:
  `dart run build_runner build --delete-conflicting-outputs`

## Qualität vor dem Pushen

Bitte stelle sicher:

1. `flutter analyze` läuft **fehlerfrei**
2. `flutter test` ist **grün**
3. Neue Features haben sinnvolle Tests
4. Keine Secrets im Code (Tokens/Keys gehören in `.env`, Edge Functions lesen
   ausschließlich `Deno.env.get(...)`)

Die CI (`.github/workflows/ci.yml`) prüft 1 + 2 automatisch bei jedem PR.

## Pull Requests

- Kleine, thematisch fokussierte PRs schlagen große Misch-PRs
- Beschreibe *Was* und *Warum*; Screenshots bei UI-Änderungen
- Rebase auf den aktuellen `main` statt Merge-Commits

## Sicherheitsprobleme

Bitte **nicht** als öffentliches Issue melden – siehe [SECURITY.md](SECURITY.md).

## Verhaltenskodex

Mitwirkende verpflichten sich zum [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
