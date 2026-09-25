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
async function verifyWebhookSignature(
  secret: string,
  webhookId: string,
  webhookTimestamp: string,
  signatureHeader: string,
  rawBody: string,
): Promise<boolean> {
  if (!webhookId || !webhookTimestamp || !signatureHeader) return false;

  // "whsec_"-Präfix entfernen, Rest als Base64 in Bytes dekodieren (HMAC-Key).
  const trimmedSecret = secret.startsWith("whsec_")
    ? secret.slice("whsec_".length)
    : secret;
  let keyBytes: Uint8Array;
  try {
    const binary = atob(trimmedSecret);
    keyBytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  } catch {
    return false;
  }

  const signatures = signatureHeader
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  const content = `${webhookId}.${webhookTimestamp}.${rawBody}`;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(content));
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)));
  // Header-Format (Standard Webhooks): "v1,<sig1>, v1,<sig2>" – ein Eintrag
  // pro konfiguriertem Secret. Die "v1"-Marker entfernen und die berechnete
  // Base64-Signatur gegen die Einträge vergleichen.
  const provided = signatures.filter((s) => s !== "v1");
  return provided.includes(sigB64);
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
    const actionType = body.email_data?.email_action_type ?? "signup";

    if (!email || !token) {
      return new Response(JSON.stringify({ error: "Missing email or token" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    if (actionType !== "signup") {
      return new Response(JSON.stringify({ reason: actionType }), {
        status: 422, headers: { "Content-Type": "application/json" },
      });
    }

    // Schöner Bestätigungs-Link über die eigene Subdomain (Spaceship-Redirect,
    // Typ 301, NICHT masked). confirm.thestia.de leitet auf
    // <SUPABASE_URL>/functions/v1/confirm weiter – die Landing-Page liest
    // token/type aus den Query-Parametern (getestet: Parameter, Pfad und
    // HTTPS werden korrekt durchgereicht).
    const confirmUrl = `https://confirm.thestia.de/?token=${encodeURIComponent(token)}&type=signup`;
    const html = buildHtml(confirmUrl);
    const text =
      `Bestätige deine E-Mail-Adresse bei Thestia:\n${confirmUrl}\n\n` +
      "Der Link ist 24 Stunden gültig.";

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
              Subject: "Bestätige deine E-Mail-Adresse – Thestia",
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
            subject: "Bestätige deine E-Mail-Adresse – Thestia",
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

function buildHtml(confirmUrl: string): string {
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
<h2 style="color:#2d2d2d;font-size:22px;margin:0 0 10px">Bestätige deine E-Mail-Adresse</h2>
<p style="color:#666;font-size:15px;line-height:1.6;margin:0 0 30px">Klicke auf den Button, um deinen Account zu aktivieren:</p>
<a href="${confirmUrl}" style="display:inline-block;background:linear-gradient(135deg,#ff8fab,#ff6b9d);color:#fff;text-decoration:none;padding:14px 40px;border-radius:30px;font-size:16px;font-weight:600;box-shadow:0 4px 12px rgba(255,107,157,0.3)">E-Mail bestätigen</a>
<p style="color:#999;font-size:13px;margin:30px 0 0;line-height:1.5">Link ist 24 Std. gültig.</p>
</td></tr>
<tr><td style="background:#fdf0ee;padding:20px 30px;text-align:center">
<p style="color:#b0b0b0;font-size:12px;margin:0">Thestia &middot; Alle Rechte vorbehalten</p>
</td></tr>
</table>
</td></tr>
</table>
</body></html>`;
}
