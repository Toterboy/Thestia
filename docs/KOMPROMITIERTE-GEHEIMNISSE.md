# Kompromittierte Geheimnisse aus der Git-Historie

Befund vom 30.09.2026, aus einem Audit der Release-Pipeline. Der Anlass
war ein anderer Fehler (ein Admin-Build unter oeffentlichem Namen, siehe
[ADMIN-UUID.md](ADMIN-UUID.md)); dabei ist aufgefallen, dass im
Repository-Verlauf **drei echte Geheimnisse** liegen.

## Was gefunden wurde

| # | Was | Wo in der Historie | Wirkung |
|---|---|---|---|
| 1 | Firebase-API-Key, Projektnummer `879918312600`, App-ID | `2b77182` (Initial-Commit), `android/app/google-services.json` | Mit dem API-Key kann beliebig Firebase-Project genutzt werden: Push an fremde Tokens, Analytics verfälschen, Projektressourcen verbrauchen. |
| 2 | `whsec_…` - Signatur-Secret des Supabase-Auth-Hooks von Projekt `jftuigjbmmuvrckbchqo` | `2b77182:CHANGELOG.md` | `send-confirmation-email` läuft mit `verify_jwt = false` (`supabase/config.toml`). Wer das Secret kennt, kann gefälschte Webhooks senden und damit E-Mail-Bestätigungen für fremde Adressen auslösen. |
| 3 | internes Funktions-Secret | `2b77182:supabase/functions/notify-user/index.ts` | `notify-user` autorisiert nur über dieses Secret, ebenfalls `verify_jwt = false`. |

Zu 2 und 3 ist der aktuelle Stand besser als die Historie: `notify-user`
prüft inzwischen auf ein **nicht leeres** Secret und bricht sonst ab
(`index.ts:35`, `:303`) - also fail-closed statt fail-open wie im
Initial-Commit. An den Werten selbst hat sich nichts geändert.

**Diese Werte gelten als bekannt.** Sie stehen in jedem Clone, in jedem
Backup und in jedem CI-Log, das `git log -p` ausführt.

## Was NICHT gefunden wurde

Ausdrücklich geprüft und sauber:

- `ADMIN_UUID` steht in keiner Datei und in keinem Commit.
- Kein Supabase-`service_role`-Key, kein `sb_secret_…`, kein JWT.
- `.env`, `android/key.properties`, `google-services.json`, `*.jks`,
  `*.keystore`, `*.p12`, `*.p12`, `*.pem`, `*.mobileprovision` waren
  **nie** committet - weder im HEAD noch in irgendeinem Commit.
- Kein Geheimnis in `build/`: 0 Treffer in über 20 000 Textdateien.
- Die CI verwendet kein einziges `secrets.*`; es wird nichts als
  Kommandozeilenargument übergeben.

## Offen - muss der Betreiber tun

Das kann ich nicht aus Code heraus erledigen, weil es Zugänge zu
Diensten braucht:

1. **Firebase-Key rotieren.** Neuer Key im Projekt
   `wisp-a044f` erzeugen, in eine neue `google-services.json` eintragen,
   alten Key deaktivieren. Der API-Key ist im Firebase-Projekt selbst
   sperrbar.
2. **`HOOK_SECRET` des Supabase-Auth-Hooks neu setzen** und in
   `supabase/functions/send-confirmation-email` hinterlegen.
3. **Internes Funktions-Secret neu setzen** und in `notify-user`
   hinterlegen.
4. Prüfen, ob `jftuigjbmmuvrckbchqo` und `wisp-a044f` überhaupt noch
   existieren und wofür sie benutzt werden. Eventuell sind das
   Altprojekte aus der `wisp`-Zeit und fallen weg.

## Wieder prüfen

```powershell
# Nach jeder Rotation: darf nichts mehr finden.
git log --all -S "<neuer Wert>" --oneline
git log --all -S "whsec_" --oneline
git log --all -S "879918312600" --oneline
```

Die Ergebnisse gehören hierher, mit Datum.

## Warum die Historie nicht umgeschrieben wird

`git filter-repo` würde die Werte aus der Historie entfernen, aber:

- Jeder, der das Repository schon geklont hat, hat sie trotzdem.
- Alle Commit-Hashes ändern sich, damit wird jeder offene PR und jede
- Verknüpfung wertlos.
- Der Nutzen ist nach der Rotation null.

Die Reihenfolge ist deshalb: **erst rotieren, dann entscheiden, ob eine
Umschreibung zusätzlich gewollt ist.** Nach der Rotation ist das
Umschreiben reine Kosmetik.

Siehe auch [SECURITY.md](../SECURITY.md) und
[INCIDENT-RESPONSE.md](../INCIDENT-RESPONSE.md).
