// Supabase Edge Function: send-confirmation-email
//
// Sendet Bestätigungs-E-Mails über Mailjet (EU, Frankreich, Free-Tier)
// mit deaktiviertem Link-Tracking (TrackClicks/TrackOpens = none) –
// Links bleiben roh (confirm.thestia.de) und funktionieren auch mit
// DNS-Filtern (z. B. DNS Forge). Brevo dient nur als letzter Fallback
// (verschleiert Links mit Tracking-Domains).
//
// Konfiguration:
//   supabase secrets set MAILJET_API_KEY=xxx        (Mailjet: primärer Versender
//                                                    ohne Link-Wrapping)
//   supabase secrets set MAILJET_API_SECRET=xxx
//   supabase secrets set BREVO_API_KEY=xxx          (letzter Fallback)
//   supabase secrets set HOOK_SECRET=whsec_xxx      (muss dem Dashboard-Hook-Secret
//                                                    "v1,whsec_xxx" entsprechen)
//
// Auth-Hook-Verifikation:
// GoTrue (aktuelle Version) authentifiziert Hook-Aufrufe mit der
// Standard-Webhooks-Signatur (Header "webhook-signature" im Format
// "v1,<base64(HMAC-SHA256(secret, webhook-id + "." + webhook-timestamp +
// "." + rawBody))>"). Ohne Verifikation dieser Signatur antwortet diese
// Funktion mit 401 – GoTrue wrappt das als 500
// "Hook requires authorization token" und der E-Mail-Versand (Signup,
// Resend, Recovery) bricht ab.
// WICHTIG: HOOK_SECRET muss dem RAW-Secret entsprechen, das im Dashboard
// unter Auth -> Hooks -> Send email -> Secrets konfiguriert ist.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const HOOK_SECRET = Deno.env.get("HOOK_SECRET") ?? "";

/// Maximale erlaubte Abweichung des webhook-timestamp (Replay-Schutz).
const MAX_TIMESTAMP_SKEW_SECONDS = 300;

/// Prüft die Standard-Webhooks-Signatur (webhook-signature Header).
///
/// WICHTIG: Der Secret-Wert folgt dem Standard-Webhooks-Format
/// "whsec_<base64>" (im Dashboard mit "v1,"-Präfix hinterlegt:
/// "v1,whsec_<base64>"). GoTrue streift "v1," und "whsec_" ab und
/// dekodiert den Rest als Standard-Base64 - hier identisch.
/// Leitet die moeglichen HMAC-Schluesselbytes aus dem Secret ab.
///
/// Siehe die Erklaerung in [verifyWebhookSignature]: das Dashboard
/// liefert 64 Hex-Zeichen, der Standard-Webhooks-Text erwartet
/// "whsec_<base64>". Beide Formen muessen funktionieren.
function secretKeyCandidates(secret: string): Uint8Array[] {
  const out: Uint8Array[] = [];
  // Der Dashboard-Wert kann in drei Gestalten kommen:
  //   "v1,whsec_<base64>" (voll, mit Versions-Marker),
  //   "whsec_<base64>"    (ohne Marker) oder
  //   "<base64>"          (nur der Schluessel).
  // Alle drei muessen zum selben Schluessel fuehren - deshalb werden
  // BEIDE Praefixe hier entfernt (Security-Audit 24.10.2026: der
  // "v1,"-Marker wurde vorher nicht entfernt; ein voll eingefuegter
  // Wert produzierte dann statt eines Schluessels nur Muell und die
  // Function antwortete weiter mit 401).
  let trimmed = secret.trim();
  if (trimmed.startsWith("v1,")) trimmed = trimmed.slice(3);
  if (trimmed.startsWith("whsec_")) trimmed = trimmed.slice("whsec_".length);
  if (trimmed.length === 0) return out;

  const push = (bytes: Uint8Array) => {
    if (bytes.length === 0) return;
    for (const b of out) {
      if (b.length === bytes.length && b.every((x, i) => x === bytes[i])) return;
    }
    out.push(bytes);
  };

  // 1) Base64 (Standard-Webhooks)
  try {
    const binary = atob(trimmed);
    push(Uint8Array.from(binary, (c) => c.charCodeAt(0)));
  } catch {
    // kein Base64 - die anderen Wege greifen
  }

  // 2) Hex (Supabase-Dashboard: 64 Hex-Zeichen = 32 Byte)
  if (/^[0-9a-fA-F]+$/.test(trimmed) && trimmed.length % 2 === 0) {
    const bytes = new Uint8Array(trimmed.length / 2);
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = parseInt(trimmed.slice(i * 2, i * 2 + 2), 16);
    }
    push(bytes);
  }

  // 3) Die rohen Bytes des Strings - falls der Secret gar nicht
  // kodiert ist.
  //
  // WICHTIG: TextEncoder.encode() liefert bereits ein Uint8Array
  // (Zahlen). Uint8Array.from(..., (c) => c.charCodeAt(0)) waere ein
  // TypeError, weil c eine Zahl und keine Zeichenkette ist. Genau
  // dieser Fehler hat jeden Aufruf mit Signatur-Header mit einem 500
  // beantwortet, waehrend die Funktion selbst fehlerfrei startete.
  push(new TextEncoder().encode(secret));

  return out;
}

async function verifyWebhookSignature(
  secret: string,
  webhookId: string,
  webhookTimestamp: string,
  signatureHeader: string,
  rawBody: string,
): Promise<boolean> {
  if (!webhookId || !webhookTimestamp || !signatureHeader) return false;

  // "whsec_"-Präfix entfernen, Rest als Base64 in Bytes dekodieren (HMAC-Key).
  // Der HMAC-Schluessel wird aus dem Secret abgeleitet. PROBLEM (war ein
  // echter Bug, 21.10.2026): Es gab nur EINEN Weg - "whsec_" abschneiden
  // und den Rest als Base64 dekodieren.
  //
  // Das Supabase-Dashboard liefert den Hook-Secret aber als 64
  // HEX-Zeichen (32 Byte Rohschluessel). Hex-Zeichen sind gueltige
  // Base64-Zeichen, atob() gibt also KEINEN Fehler zurueck, sondern
  // 48 Byte Muell. Die Signatur passte damit NIE, die Function
  // antwortete immer mit 401, und GoTrue meldete den Hook als
  // fehlgeschlagen - ohne dass irgendwo eine Mail als nicht
  // zugestellt auffiel.
  //
  // Deshalb werden jetzt alle gaengigen Interpretationen gebildet und
  // die Signatur gegen jede davon geprueft:
  //   * Base64 (Standard-Webhooks, "whsec_<base64>")
  //   * Hex (Supabase-Dashboard, 64 Hex-Zeichen)
  //   * die rohen Bytes des Strings
  //
  // Der Aufrufer muss also nicht wissen, in welchem Format das
  // Dashboard den Secret anzeigt.
  const candidates = secretKeyCandidates(secret);
  if (candidates.length === 0) return false;

  const signatures = signatureHeader
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  const content = `${webhookId}.${webhookTimestamp}.${rawBody}`;
  const encoder = new TextEncoder();

  // Header-Format (Standard Webhooks): "v1,<sig1>, v1,<sig2>" - ein
  // Eintrag pro konfiguriertem Secret. Die "v1"-Marker entfernen und
  // die berechnete Base64-Signatur gegen die Eintraege vergleichen.
  const provided = signatures.filter((s) => s !== "v1");
  if (provided.length === 0) return false;

  for (const keyBytes of candidates) {
    const key = await crypto.subtle.importKey(
      "raw",
      keyBytes,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const sig = await crypto.subtle.sign(
      "HMAC",
      key,
      encoder.encode(content),
    );
    const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)));
    if (provided.includes(sigB64)) return true;
  }
  return false;
}

/// Zeitkonstanter String-Vergleich (N-10) - length-leak ist hier
/// irrelevant (Secret-Länge ist kein Geheimnis), aber jede Byte-Position
/// muss konstant verglichen werden.
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    // Vergleich trotzdem durchführen, um timing auf Längenunterschied
    // hin konstant zu halten.
    let dummy = 0;
    for (let i = 0; i < Math.max(a.length, b.length); i++) {
      dummy |= (a.charCodeAt(i % a.length || 1) ^ b.charCodeAt(i % b.length || 1));
    }
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

serve(async (req) => {
  // Fail-closed: Ohne konfiguriertes HOOK_SECRET ist diese Funktion
  // nicht aufrufbar (Schutz gegen Missbrauch/Spam).
  if (!HOOK_SECRET) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401, headers: { "Content-Type": "application/json" },
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  // Body einmal roh lesen (für Signatur-Prüfung UND Parsing).
  const rawBody = await req.text();

  const webhookId = req.headers.get("webhook-id") ?? "";
  const webhookTimestamp = req.headers.get("webhook-timestamp") ?? "";
  const webhookSignature = req.headers.get("webhook-signature") ?? "";

  let authorized = false;

  if (webhookSignature) {
    // Aktueller GoTrue-Hook-Framework: Standard-Webhooks-Signatur prüfen.
    const skew = Math.abs(
      Date.now() / 1000 - Number(webhookTimestamp || "0"),
    );
    if (skew <= MAX_TIMESTAMP_SKEW_SECONDS) {
      authorized = await verifyWebhookSignature(
        HOOK_SECRET,
        webhookId,
        webhookTimestamp,
        webhookSignature,
        rawBody,
      );
    }
  } else {
    // Legacy-Fallback (ältere GoTrue-Versionen): Authorization-Bearer-Secret.
    // N-10: zeitkonstanter Vergleich statt === (Timing-Leak).
    const auth = req.headers.get("Authorization") ?? "";
    const token = auth.replace(/^Bearer\s+/i, "");
    authorized = timingSafeEqual(token, HOOK_SECRET);
  }

  if (!authorized) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body = JSON.parse(rawBody);
    const email = body.user?.email;
    // WICHTIG: token_hash verwenden (GoTrue liefert ihn als "sha256$<hex>").
    // GET /auth/v1/verify akzeptiert NUR den token-Parameter und wertet ihn
    // als HASH aus - ein roher JWT würde dort nicht funktionieren.
    const token = body.email_data?.token_hash ?? body.email_data?.token;

    if (!email || !token) {
      return new Response(JSON.stringify({ error: "Missing email or token" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    // BUG (Security-Audit 22.10.2026): hier stand ein 422 fuer jede
    // Aktion ausser "signup".
    //
    // GoTrue wertet eine Nicht-2xx-Antwort des Send-Email-Hooks als
    // Fehler: der Auth-Request bricht ab. Betroffen waren
    //   * "recovery"  - der Passwort-Reset (die App hat eine
    //                   /forgot-password-Seite und ruft
    //                   resetPasswordForEmail auf),
    //   * "resend"    - das erneute Senden der Bestaetigungsmail.
    // Es kam keine Mail an, und der Nutzer sah einen Fehler.
    //
    // JETZT: jede Aktion bekommt ihre eigene Mail mit passendem Link.
    // Unbekannte Aktionen werden nicht abgewiesen, sondern wie eine
    // Bestaetigung behandelt - eine Mail, die ankommt, ist besser als
    // ein abgewiesener Auth-Request.
    const emailData = (body.email_data ?? {}) as Record<string, unknown>;
    const actionType = String(
      emailData.email_action_type ?? "signup",
    );
    const redirectTo = String(
      emailData.redirect_to ?? emailData.site_url ?? "",
    );
    const encodedToken = encodeURIComponent(token);

    let subject = "Bestätige deine E-Mail-Adresse – Thestia";
    let confirmUrl = `https://confirm.thestia.de/?token=${encodedToken}` +
      `&type=signup`;
    let heading = "Bestätige deine E-Mail-Adresse";
    let intro = "Klicke auf den Button, um deinen Account zu aktivieren:";
    let buttonLabel = "E-Mail bestätigen";
    let validity = "Link ist 24 Std. gültig.";

    if (actionType === "recovery") {
      // Das Ziel muss in der Redirect-Allowlist des Projekts stehen -
      // die App uebergibt genau 'thestia://reset-password'.
      const target = redirectTo || "thestia://reset-password";
      confirmUrl = `https://confirm.thestia.de/?token=${encodedToken}` +
        `&type=recovery&redirect=${encodeURIComponent(target)}`;
      subject = "Setze dein neues Passwort – Thestia";
      heading = "Neues Passwort festlegen";
      intro = "Klicke auf den Button, um ein neues Passwort zu setzen:";
      buttonLabel = "Neues Passwort setzen";
      validity = "Link ist 60 Std. gültig.";
    } else if (actionType === "email_change") {
      confirmUrl = `https://confirm.thestia.de/?token=${encodedToken}` +
        `&type=email_change`;
      subject = "Bestätige deine neue E-Mail-Adresse – Thestia";
      heading = "Neue E-Mail-Adresse bestätigen";
      intro = "Klicke auf den Button, um die Änderung zu bestätigen:";
      buttonLabel = "Änderung bestätigen";
    } else if (actionType === "magiclink") {
      confirmUrl = `https://confirm.thestia.de/?token=${encodedToken}` +
        `&type=magiclink`;
      subject = "Dein Magic Link für Thestia";
      heading = "Einmal-Anmeldung";
      intro = "Klicke auf den Button, um dich anzumelden:";
      buttonLabel = "Anmelden";
    } else if (actionType !== "signup" && actionType !== "resend") {
      // Unbekannte Aktion: nicht ablehnen. Die Standard-Mail schicken
      // und im Log vermerken, damit der Fall auffällt.
      console.log("Unbekannte Hook-Aktion, Standard-Mail gesendet:", actionType);
    }

    const html = buildHtml(confirmUrl, heading, intro, buttonLabel, validity);
    const text =
      `${heading} – Thestia:\n${confirmUrl}\n\n${validity}`;

    // --- 1) Primär: Mailjet (EU, Frankreich; Free-Tier) ---------------------
    // WICHTIG: TrackClicks/TrackOpens = "none" => KEIN Link-Wrapping.
    // Die Bestätigungs-Links bleiben roh (confirm.thestia.de) und
    // funktionieren auch mit DNS-Filtern (z. B. DNS Forge), die
    // Tracking-Domains blockieren.
    let sent = false;
    let mailjetError: unknown = null;
    const MAILJET_API_KEY = Deno.env.get("MAILJET_API_KEY") ?? "";
    const MAILJET_API_SECRET = Deno.env.get("MAILJET_API_SECRET") ?? "";
    if (!sent && MAILJET_API_KEY && MAILJET_API_SECRET) {
      try {
        const mjResp = await fetch("https://api.mailjet.com/v3.1/send", {
          method: "POST",
          headers: {
            "Authorization": "Basic " +
              btoa(`${MAILJET_API_KEY}:${MAILJET_API_SECRET}`),
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            Messages: [{
              From: { Email: "support@thestia.de", Name: "Thestia" },
              To: [{ Email: email }],
              Subject: subject,
              HTMLPart: html,
              TextPart: text,
              TrackClicks: "none",
              TrackOpens: "none",
            }],
          }),
        });
        const mjBody = await mjResp.json();
        const mjOk = mjResp.ok &&
          mjBody?.Messages?.[0]?.Status === "success";
        if (mjOk) {
          sent = true;
          console.log(
            "Mailjet OK:", mjBody.Messages[0].To[0].MessageID,
          );
        } else {
          mailjetError = mjBody;
          console.error(
            "Mailjet abgelehnt (HTTP " + mjResp.status + "):",
            JSON.stringify(mjBody),
          );
        }
      } catch (e) {
        mailjetError = String(e);
        console.error("Mailjet-Fehler:", e);
      }
    } else if (!sent) {
      mailjetError = "MAILJET_API_KEY/SECRET not set";
    }

    // --- 2) Fallback: Brevo (v3 SMTP API) -----------------------------------
    // Greift nur, wenn Mailjet nicht liefert.
    let brevoError: unknown = null;
    const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
    if (!sent && BREVO_API_KEY) {
      try {
        const brevoResp = await fetch("https://api.brevo.com/v3/smtp/email", {
          method: "POST",
          headers: {
            "accept": "application/json",
            "api-key": BREVO_API_KEY,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            sender: { email: "support@thestia.de", name: "Thestia" },
            to: [{ email }],
            subject: subject,
            htmlContent: html,
            textContent: text,
          }),
        });
        const bResult = await brevoResp.json();
        if (brevoResp.ok) {
          sent = true;
          console.log("Brevo OK:", bResult.messageId);
        } else {
          brevoError = bResult;
          console.error(
            "Brevo-Fehler (HTTP " + brevoResp.status + "):",
            JSON.stringify(bResult),
          );
        }
      } catch (e) {
        brevoError = String(e);
        console.error("Brevo-Fehler:", e);
      }
    } else if (!sent) {
      brevoError = "BREVO_API_KEY not set";
    }

    // Details mitgeben, damit die Ursache in den Function-Logs UND in der
    // HTTP-Antwort sichtbar ist (z. B. ungültiger Key, Domain nicht
    // verifiziert, Account suspendiert, Guthaben leer).
    return new Response(
      JSON.stringify({ ok: sent, mailjet: mailjetError, brevo: brevoError }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("Hook crash:", e);
    return new Response(JSON.stringify({ warning: "crash" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }
});

function buildHtml(
  confirmUrl: string,
  heading: string,
  intro: string,
  buttonLabel: string,
  validity: string,
): string {
  return `<!DOCTYPE html>
<html lang="de">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin:0;padding:0;background:#f4f4f8;font-family:'Helvetica Neue',Arial,sans-serif">
<table width="100%" cellpadding="0" cellspacing="0" style="padding:40px 0">
<tr><td align="center">
<table width="480" cellpadding="0" cellspacing="0" style="max-width:480px;background:#fff8f5;border-radius:16px;overflow:hidden;box-shadow:0 2px 16px rgba(0,0,0,0.06)">
<tr><td style="background:linear-gradient(135deg,#ff8fab,#ff6b9d);padding:40px 30px;text-align:center">
<h1 style="color:#fff;font-size:28px;margin:0;font-weight:600;letter-spacing:1px">Thestia</h1>
</td></tr>
<tr><td style="padding:40px 30px;text-align:center">
<h2 style="color:#2d2d2d;font-size:22px;margin:0 0 10px">${heading}</h2>
<p style="color:#666;font-size:15px;line-height:1.6;margin:0 0 30px">${intro}</p>
<a href="${confirmUrl}" style="display:inline-block;background:linear-gradient(135deg,#ff8fab,#ff6b9d);color:#fff;text-decoration:none;padding:14px 40px;border-radius:30px;font-size:16px;font-weight:600;box-shadow:0 4px 12px rgba(255,107,157,0.3)">${buttonLabel}</a>
<p style="color:#999;font-size:13px;margin:30px 0 0;line-height:1.5">${validity}</p>
</td></tr>
<tr><td style="background:#fdf0ee;padding:20px 30px;text-align:center">
<p style="color:#b0b0b0;font-size:12px;margin:0">Thestia &middot; Alle Rechte vorbehalten</p>
</td></tr>
</table>
</td></tr>
</table>
</body></html>`;
}
