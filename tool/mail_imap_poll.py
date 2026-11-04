#!/usr/bin/env python3
"""Holt neue Mails per IMAP und meldet sie an die Edge Function
``mail-ingest`` - damit stehen sie im Admin-Bereich der App.

Warum es dieses Skript gibt
===========================

Der Mailanbieter fuer thestia.de ist ein Weiterleiter (Spaceship eFwd).
Der eigentliche Posteingang liegt in einem Postfach, das man oeffnen
muss - und in einem Kinderschutz-Fall ist "ich habe die Mail nicht
gesehen" der schlimmste Fehler, den das System haben kann.

Dieses Skript laeuft deshalb als Kleinodienst (Aufgabenplaner, Cron,
systemd-Timer) und schiebt jede neue Mail in die Datenbank. Der
Admin-Bereich zeigt sie an - nach Adresse sortiert, nur zum Lesen.

Der zweite Weg (ohne IMAP-Abfrage): der Cloudflare Email Worker in
``deploy/cloudflare/email-worker.js`` schiebt die Mail direkt per
Webhook. Beide Wege landen in derselben Tabelle; die Message-ID
verhindert, dass dieselbe Mail zweimal gespeichert wird.

Einrichtung
===========

Die Zugangsdaten kommen aus `tool/mail_secrets.py` - in dieser
Reihenfolge:

  1. Umgebungsvariablen (fuer CI und Task-Planer):
       IMAP_HOST, IMAP_PORT, IMAP_USER, IMAP_PASSWORD, IMAP_FOLDER,
       THESTIA_FUNCTIONS_URL, THESTIA_INTERNAL_SECRET
  2. Secret-Datei ausserhalb des Projekts (Vorgabe):
       %USERPROFILE%\\.secrets\\thestia-mail.properties

Selbst einrichten (fragt nach den Werten ab, legt die Datei an und
richtet den Task-Planer ein):

  python tool/setup_mail_inbox.py

Beispiel (Windows, Aufgabenplaner alle 5 Minuten):

  set IMAP_HOST=imap.example.com
  set IMAP_USER=postfach@example.com
  set IMAP_PASSWORD=...
  set THESTIA_FUNCTIONS_URL=https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1
  set THESTIA_INTERNAL_SECRET=...
  python tool\\mail_imap_poll.py

Aufruf:

  python tool/mail_imap_poll.py            # einmal laufen
  python tool/mail_imap_poll.py --dry-run  # nur zeigen, nicht senden

Sicherheit
==========

* Nur die Standardbibliothek (imaplib, email, ssl) - keine
  Zusatzabhaengigkeiten.
* Das Passwort wird nicht gespeichert, nicht geloggt und nicht
  uebertragen: es geht nur an den IMAP-Server.
* Uebertragen wird nur an die eigene Supabase-Instanz, mit dem
  internen Secret.
"""
import email
import email.header
import email.utils
import imaplib
import json
import os
import pathlib
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mail_secrets  # noqa: E402

DEFAULT_PORT = 993
DEFAULT_FOLDER = "INBOX"
MAX_BODY = 20000


def log(text: str) -> None:
    print(f"[mail-poll] {text}", flush=True)


def header_value(msg, name: str) -> str:
    """Liest einen Header und decoded nach UTF-8.

    RFC 2047: "=?utf-8?B?...?=" - ohne das Decoding kaeme bei
    Umlauten im Betreff Muell im Admin-Bereich.
    """
    raw = msg.get(name)
    if raw is None:
        return ""
    parts = []
    for chunk, charset in email.header.decode_header(str(raw)):
        if isinstance(chunk, bytes):
            try:
                parts.append(chunk.decode(charset or "utf-8", errors="replace"))
            except LookupError:
                parts.append(chunk.decode("utf-8", errors="replace"))
        else:
            parts.append(chunk)
    return "".join(parts).strip()


def body_text(msg) -> str:
    """Der Text-Teil der Mail.

   Multipart-Mails werden durchlaufen; der erste text/plain-Teil
    gewinnt. Gibt es nur HTML, wird es zu Text gemacht - fuer die
    Anzeige im Admin-Bereich.
    """
    plain = ""
    html = ""
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_maintype() == "multipart":
                continue
            typ = part.get_content_type()
            if typ not in ("text/plain", "text/html"):
                continue
            try:
                content = part.get_payload(decode=True)
            except Exception:
                continue
            if content is None:
                continue
            charset = part.get_content_charset() or "utf-8"
            try:
                decoded = content.decode(charset, errors="replace")
            except LookupError:
                decoded = content.decode("utf-8", errors="replace")
            if typ == "text/plain" and not plain:
                plain = decoded
            elif typ == "text/html" and not html:
                html = decoded
    else:
        try:
            content = msg.get_payload(decode=True)
        except Exception:
            content = None
        if content:
            charset = msg.get_content_charset() or "utf-8"
            try:
                decoded = content.decode(charset, errors="replace")
            except LookupError:
                decoded = content.decode("utf-8", errors="replace")
            if msg.get_content_type() == "text/html":
                html = decoded
            else:
                plain = decoded

    text = plain.strip()
    if not text and html:
        import re
        text = re.sub(r"<[^>]+>", " ", html)
        text = re.sub(r"[ \t]+", " ", text)
        text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text


def send(payload: dict, url: str, secret: str, dry_run: bool) -> bool:
    if dry_run:
        log(f"(Trockenlauf) wuerde gemeldet: {payload['subject'][:80]}")
        return True
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "x-thestia-internal": secret,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read().decode("utf-8", errors="replace")
            log(f"gemeldet: {payload['subject'][:60]} -> {body[:120]}")
            return True
    except urllib.error.HTTPError as e:
        log(f"FEHLER {e.code}: {e.read().decode('utf-8', errors='replace')[:200]}")
        return False
    except Exception as e:  # noqa: BLE001 - der Dienst soll weiterlaufen
        log(f"FEHLER: {e}")
        return False


def main() -> int:
    dry_run = "--dry-run" in sys.argv

    # Die Zugangsdaten kommen aus tool/mail_secrets.py: Umgebung
    # zuerst, dann die Secret-Datei ausserhalb des Projekts. Vorher
    # standen hier nur Umgebungsvariablen - damit war der
    # Posteingang nur per Task-Planer einrichtbar, nicht "von Hand".
    settings = mail_secrets.read_settings()
    host = settings.get("IMAP_HOST", "").strip()
    user = settings.get("IMAP_USER", "").strip()
    password = settings.get("IMAP_PASSWORD", "")
    port = int(settings.get("IMAP_PORT", str(DEFAULT_PORT)))
    folder = settings.get("IMAP_FOLDER", DEFAULT_FOLDER)
    base = settings.get("THESTIA_FUNCTIONS_URL", "").rstrip("/")
    secret = settings.get("THESTIA_INTERNAL_SECRET", "")

    fehlend = [
        name
        for name, wert in (
            ("IMAP_HOST", host),
            ("IMAP_USER", user),
            ("IMAP_PASSWORD", password),
            ("THESTIA_FUNCTIONS_URL", base),
            ("THESTIA_INTERNAL_SECRET", secret),
        )
        if not wert
    ]
    if fehlend:
        log(f"FEHLT: {', '.join(fehlend)}")
        log("Einrichten:  python tool/setup_mail_inbox.py")
        return 2

    url = f"{base}/mail-ingest"

    try:
        mailbox = imaplib.IMAP4_SSL(host, port, ssl_context=ssl.create_default_context())
    except Exception as e:  # noqa: BLE001
        log(f"Verbindung zu {host}:{port} fehlgeschlagen: {e}")
        return 1

    try:
        typ, _ = mailbox.login(user, password)
        if typ != "OK":
            log("Anmeldung fehlgeschlagen")
            return 1
        typ, _ = mailbox.select(folder)
        if typ != "OK":
            log(f"Ordner {folder} nicht lesbar")
            return 1

        typ, daten = mailbox.search(None, "UNSEEN")
        if typ != "OK":
            log("Suche fehlgeschlagen")
            return 1

        ids = daten[0].split() if daten and daten[0] else []
        log(f"{len(ids)} ungelesene Mail(s) in {folder}")

        for nummer in ids:
            typ, daten = mailbox.fetch(nummer, "(BODY.PEEK[])")
            if typ != "OK" or not daten or not isinstance(daten[0], tuple):
                continue
            roh = daten[0][1]
            msg = email.message_from_bytes(roh)

            empfaenger = header_value(msg, "To") or user
            # Bei "Name <adresse>" zaehlt die Adresse.
            name, adresse = email.utils.parseaddr(empfaenger)
            empfaenger = adresse or empfaenger

            absender_name, absender = email.utils.parseaddr(
                header_value(msg, "From")
            )

            datum = header_value(msg, "Date")
            empfangen = ""
            if datum:
                try:
                    geparst = email.utils.parsedate_to_datetime(datum)
                    if geparst.tzinfo is None:
                        geparst = geparst.replace(tzinfo=timezone.utc)
                    empfangen = geparst.astimezone(timezone.utc).isoformat()
                except Exception:
                    empfangen = ""

            payload = {
                "recipient": empfaenger.lower(),
                "messageId": header_value(msg, "Message-ID"),
                "from": absender,
                "fromName": absender_name,
                "subject": header_value(msg, "Subject"),
                "text": body_text(msg)[:MAX_BODY],
                "receivedAt": empfangen or datetime.now(timezone.utc).isoformat(),
                "source": "imap",
                "sizeBytes": len(roh),
            }
            if not payload["subject"] and not payload["text"]:
                log(f"Mail {nummer.decode()} ohne Inhalt - uebersprungen")
                continue

            if send(payload, url, secret, dry_run):
                # Als gelesen markieren: das ist die zweite Sperre
                # gegen Doppelimport (die erste ist die Message-ID in
                # der Datenbank).
                try:
                    mailbox.store(nummer, "+FLAGS", "\\Seen")
                except Exception:
                    pass
    finally:
        try:
            mailbox.logout()
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
