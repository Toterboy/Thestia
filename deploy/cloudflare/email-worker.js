/**
 * Cloudflare Email Worker: schiebt eingehende Mails an die Edge Function
 * `mail-ingest`, damit sie im Admin-Bereich der App stehen.
 *
 * Das ist der zweite Weg neben `tool/mail_imap_poll.py`:
 *
 *   - Worker: der Mailanbieter schiebt die Mail sofort per Webhook.
 *     Kein Abholen, kein Timer, keine Abfrage von Postfächern.
 *   - IMAP: ein lokaler Dienst holt die Mails in Abständen.
 *
 * Welcher Weg passt, hängt am Mailanbieter. Für thestia.de ist der
 * MX aktuell auf Spaceship eFwd (Weiterleitung). Wer auf Cloudflare
 * Email Routing wechselt, bekommt diesen Worker; der IMAP-Weg
 * funktioniert unabhängig davon und ist deshalb der einfachere Start.
 *
 * AUFBAU (Cloudflare Dashboard):
 *
 *  1. "Email Routing" aktivieren, die Adresse (z. B. kinderschutz@)
 *     auf den Worker zeigen lassen.
 *  2. Einen Worker anlegen und diese Datei als Modul eintragen.
 *  3. Zwei Secrets setzen:
 *       SUPABASE_FUNCTIONS_URL = https://<projekt>.supabase.co/functions/v1
 *       THESTIA_INTERNAL_SECRET = <das interne Secret>
 *  4. Fertig. Der Worker schiebt jede Mail sofort weiter.
 *
 * WICHTIG:
 *
 *   - Der Worker liest die Mail, speichert aber nichts selbst: er
 *     meldet sie an die Edge Function. Die Speicherung passiert in der
 *     Datenbank, mit der Admin-Sicht.
 *   - Es wird nichts beantwortet. Der Worker kann keine Mails senden -
 *     das ist Absicht (siehe migration 168: keine Antwortfunktion).
 *   - Der Inhalt wird nur an die eigene Supabase-Instanz geschickt.
 */

// @ts-nocheck

const MAX_BODY = 20000;

function decodeMime(raw) {
  // Sehr einfache Dekodierung der haeufigsten Kodierungen. Der Worker
  // hat keine MIME-Bibliothek - fuer die Anzeige im Admin-Bereich
  // reicht diese Naeherung.
  if (!raw) return "";
  const text = raw.replace(/=\r?\n/g, "");
  return text
    .replace(/=\?utf-8\?B\?([^?]+)\?=/gi, (_, b64) => {
      try {
        const bin = atob(b64);
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        return new TextDecoder("utf-8").decode(bytes);
      } catch (_) {
        return "";
      }
    })
    .replace(/=\?utf-8\?Q\?([^?]+)\?=/gi, (_, q) =>
      decodeURIComponent(q.replace(/_/g, " ").replace(/=([0-9A-F]{2})/gi,
        (m, h) => String.fromCharCode(parseInt(h, 16))))
    )
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'");
}

function htmlZuText(html) {
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|tr|li|h[1-6])>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export default {
  async email(message, env, ctx) {
    const base = (env.SUPABASE_FUNCTIONS_URL || "").replace(/\/$/, "");
    const secret = env.THESTIA_INTERNAL_SECRET || "";
    if (!base || !secret) {
      console.error(
        "email-worker: SUPABASE_FUNCTIONS_URL oder THESTIA_INTERNAL_SECRET fehlt.",
      );
      message.setReject("Konfiguration fehlt");
      return;
    }

    let raw = "";
    try {
      raw = await new Response(message.raw).text();
    } catch (e) {
      console.error("email-worker: Mail nicht lesbar:", e);
    }

    const headers = message.headers;
    const empfaenger = String(message.to || "").toLowerCase();
    const von = String(headers.get("from") || "");
    const betreff = decodeMime(String(headers.get("subject") || ""));
    const messageId = String(headers.get("message-id") || "").trim();

    // Der Rumpf: der Worker sieht die unveraenderte Quelle. HTML wird
    // zu Text gemacht, damit die Anzeige im Admin-Bereich lesbar ist.
    const trennIndex = raw.indexOf("\r\n\r\n") >= 0
      ? raw.indexOf("\r\n\r\n")
      : raw.indexOf("\n\n");
    let body = trennIndex >= 0 ? raw.slice(trennIndex + 4) : raw;
    body = decodeMime(body);
    if (/<\/?[a-z][\s\S]*>/i.test(body)) {
      body = htmlZuText(body);
    }
    if (body.length > MAX_BODY) body = body.slice(0, MAX_BODY);

    // Absendername und -adresse trennen.
    let vonName = "";
    let vonAdresse = von;
    const winkel = von.match(/^(.*)<([^>]+)>\s*$/);
    if (winkel) {
      vonName = winkel[1].trim().replace(/^"|"$/g, "");
      vonAdresse = winkel[2].trim();
    }

    const payload = {
      recipient: empfaenger,
      messageId: messageId,
      from: vonAdresse,
      fromName: vonName,
      subject: betreff,
      text: body,
      receivedAt: new Date().toISOString(),
      source: "cloudflare",
      sizeBytes: raw.length,
    };

    try {
      const antwort = await fetch(`${base}/mail-ingest`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-thestia-internal": secret,
        },
        body: JSON.stringify(payload),
      });
      if (!antwort.ok) {
        console.error(
          "email-worker: mail-ingest antwortete",
          antwort.status,
          await antwort.text(),
        );
        // Die Mail NICHT zurueckweisen: sie geht an den Empfangsserver
        // und ist dort zustellbar. Nur der Admin-Bereich sieht sie dann
        // nicht.
      }
    } catch (e) {
      console.error("email-worker: mail-ingest nicht erreichbar:", e);
    }
  },
};
