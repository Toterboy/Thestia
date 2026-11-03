// Supabase Edge Function: /notify-new-login
//
// Meldet dem Kontoinhaber, wenn sich ein NEUES Geraet anmeldet.
//
// WARUM (03.11.2026): Auf die Frage "Gibt es E-Mail-Mitteilungen, wenn
// es fehlgeschlagene Anmeldeversuche gibt?" lautete die Antwort: nein.
// Es gab weder eine Mail bei Fehlversuchen noch bei einer Anmeldung von
// einem fremden Geraet.
//
// Der Fehlversuch ist der schlechtere Fall: Er wird von Supabase Auth
// (GoTrue) gezaehlt und gesperrt - er erreicht unseren Server gar nicht.
// Und eine Mail bei JEDEM Fehlversuch waere ein Spam-Relais (jede
// beliebige Adresse koennte Mails ausloesen) und eine Enumerationshilfe
// (eine Mail nur bei existierender Adresse verraet, ob es das Konto
// gibt).
//
// Der echte Fall ist die ERFOLGREICHE Anmeldung von einem unbekannten
// Geraet. Dafuer haben wir die Daten bereits: Jede App-Instanz hat eine
// stabile Geraete-ID und schreibt sie nach dem Login in auth_devices
// (Migration 071). Ist die ID dort unbekannt, ist es ein neues Geraet.
//
// DIE PRUEFUNG PASSIERT HIER, IM SERVER. Der Client darf es nicht
// entscheiden: ein Angreifer mit gestohlenem Passwort ruft die Funktion
// mit einer fremden Geraete-ID auf - die Mail geht an den Kontoinhaber
// (genau das ist gewuenscht), aber der Client darf nicht bestimmen
// "neues Geraet = keine Mail".
//
// AUTH: Der Aufrufer muss mit seinem JWT angemeldet sein. Die Funktion
// arbeitet mit der Service-Rolle, um die Geraete-Tabelle zu lesen und
// die Mail zu senden.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const SENDER_EMAIL = "support@thestia.de";
const SENDER_NAME = "Thestia";

// Ein Konto, das gerade erst angelegt wurde, loggt sich zum ersten Mal
// ein - da waere eine "neue Anmeldung"-Mail irritierend. Deshalb gilt
// das Fenster direkt nach der Registrierung als Ausnahme.
const NEU_REGISTRIERT_MINUTEN = 30;

// Hoechstzahl an Mails pro Konto und Stunde. Schützt davor, dass
// jemand durch das Löschen der App-Daten (neue Geraete-ID) den
// Postfach flutet.
const MAILS_PRO_STUNDE = 5;

function _pickApiKey(autoDict: string, custom: string): string {
  const single = Deno.env.get(custom) ?? "";
  if (single.length > 0) return single;
  try {
    const dict = JSON.parse(Deno.env.get(autoDict) ?? "{}") as Record<
      string,
      unknown
    >;
    const named = dict["default"];
    if (typeof named === "string" && named.length > 0) return named;
  } catch (_) {}
  return "";
}

const SUPABASE_SERVICE_ROLE_KEY = _pickApiKey(
  "SUPABASE_SECRET_KEYS",
  "SUPABASE_SECRET_KEY",
);

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** Wie viele "neue Geraete" bekam dieses Konto in der letzten Stunde? */
async function mailsLetzteStunde(userId: string): Promise<number> {
  const seit = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count } = await supabaseAdmin
    .from("auth_devices")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", seit);
  return count ?? 0;
}

async function sendMail(
  to: string,
  subject: string,
  htmlContent: string,
): Promise<boolean> {
  if (BREVO_API_KEY === "") {
    console.error("notify-new-login: BREVO_API_KEY fehlt - kein Versand.");
    return false;
  }
  const resp = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: {
      accept: "application/json",
      "api-key": BREVO_API_KEY,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      sender: { email: SENDER_EMAIL, name: SENDER_NAME },
      to: [{ email: to }],
      subject,
      htmlContent,
      textContent: htmlContent
        .replace(/<br\s*\/?>/gi, "\n")
        .replace(/<\/?p[^>]*>/gi, "\n")
        .replace(/<[^>]+>/g, " "),
    }),
  });
  if (!resp.ok) {
    console.error(
      "notify-new-login: Brevo-Fehler",
      resp.status,
      await resp.text(),
    );
    return false;
  }
  return true;
}

serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Unauthorized" }, 401);

  const { data: { user }, error: authError } = await supabaseAdmin.auth
    .getUser(token);
  if (authError || !user) {
    return json({ error: "Sitzung ungueltig - bitte neu anmelden" }, 401);
  }
  const userId = user.id;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Invalid JSON" }, 400);
  }

  const deviceId = String(body.deviceId ?? "").trim();
  if (!deviceId || deviceId.length > 100) {
    return json({ error: "deviceId fehlt" }, 400);
  }
  const deviceName = String(body.deviceName ?? "").slice(0, 120);
  const deviceModel = String(body.deviceModel ?? "").slice(0, 120);
  const platform = String(body.platform ?? "").slice(0, 40);
  const appVersion = String(body.appVersion ?? "").slice(0, 60);

  // Bekanntes Geraet? Dann nur last_seen auffrischen.
  const { data: bekannt } = await supabaseAdmin
    .from("auth_devices")
    .select("id")
    .eq("user_id", userId)
    .eq("device_id", deviceId)
    .maybeSingle();

  if (bekannt) {
    await supabaseAdmin
      .from("auth_devices")
      .update({ last_seen_at: new Date().toISOString() })
      .eq("user_id", userId)
      .eq("device_id", deviceId);
    return json({ ok: true, isNew: false, emailed: false });
  }

  // Neues Geraet: Zeile anlegen (die Liste soll vollstaendig sein).
  const { error: insertError } = await supabaseAdmin
    .from("auth_devices")
    .insert({
      user_id: userId,
      device_id: deviceId,
      device_name: deviceName,
      platform,
      app_version: appVersion,
      device_model: deviceModel || null,
      last_seen_at: new Date().toISOString(),
    });

  if (insertError) {
    // 23505: Ein gleichzeitiger zweiter Aufruf hat die Zeile schon
    // angelegt - das ist kein Fehler, sondern der Normalfall bei zwei
    // Anmeldungen im selben Moment.
    if (String(insertError.code) !== "23505") {
      console.error("notify-new-login: insert fehlgeschlagen:", insertError);
      return json({ error: "insert_failed" }, 500);
    }
    return json({ ok: true, isNew: false, emailed: false });
  }

  // Direkt nach der Registrierung keine Mail (siehe Konstante oben).
  const altersMinuten = (Date.now() - new Date(user.created_at).getTime()) /
    60000;
  if (altersMinuten < NEU_REGISTRIERT_MINUTEN) {
    return json({ ok: true, isNew: true, emailed: false });
  }

  // Bremse: nicht mehr als MAILS_PRO_STUNDE neue Geraete-Mails.
  const bereits = await mailsLetzteStunde(userId);
  if (bereits >= MAILS_PRO_STUNDE) {
    console.log(
      `notify-new-login: Mail-Bremse greift (${bereits} neue Geraete in der Stunde).`,
    );
    return json({ ok: true, isNew: true, emailed: false });
  }

  const email = user.email;
  if (!email) {
    console.log("notify-new-login: Konto ohne E-Mail-Adresse - keine Mail.");
    return json({ ok: true, isNew: true, emailed: false });
  }

  const gerät = deviceModel || deviceName || "unbekanntes Gerät";
  const zeitpunkt = new Date().toLocaleString("de-DE", {
    timeZone: "Europe/Berlin",
    dateStyle: "medium",
    timeStyle: "short",
  });

  const html = `<!DOCTYPE html>
<html lang="de">
<head><meta charset="utf-8"><title>Neue Anmeldung</title></head>
<body style="margin:0;padding:0;background:#f4f0f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f0f7;padding:24px 12px">
<tr><td align="center">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:16px;overflow:hidden">
<tr><td style="background:#5b3fa8;padding:28px 30px">
  <h1 style="margin:0;color:#ffffff;font-size:22px;font-weight:700">Neue Anmeldung in Thestia</h1>
</td></tr>
<tr><td style="padding:30px;color:#2d2d2d;font-size:15px;line-height:1.65">
  <p>Hallo,</p>
  <p>dein Thestia-Konto wurde gerade auf einem Ger&auml;t angemeldet, das wir
  noch nicht kennen:</p>
  <div style="background:#f7f5fa;border-radius:10px;padding:14px 16px;margin:22px 0">
    <p style="margin:0 0 6px;color:#5b3fa8;font-size:13px;font-weight:600">Ger&auml;t</p>
    <p style="margin:0 0 10px">${escapeHtml(gerät)}${
      appVersion ? ` &middot; App ${escapeHtml(appVersion)}` : ""
    }</p>
    <p style="margin:0 0 6px;color:#5b3fa8;font-size:13px;font-weight:600">Zeitpunkt</p>
    <p style="margin:0">${escapeHtml(zeitpunkt)}</p>
  </div>
  <p>War das du? Dann kannst du diese Meldung ignorieren. Deine
  Ger&auml;teliste findest du in den Einstellungen unter
  <strong>Datenschutz &amp; Account &rarr; Ger&auml;te</strong>.</p>
  <p>War das <strong>nicht</strong> du, ist das ein Zeichen, dass jemand
  dein Passwort kennt. Bitte &auml;ndere dein Passwort und melde alle
  fremden Sitzungen ab (in derselben Liste). Wenn du 2FA aktiviert hast,
  sch&auml;tze sie ebenfalls.</p>
</td></tr>
<tr><td style="background:#f7f5fa;padding:20px 30px">
  <p style="margin:0;color:#8b8b96;font-size:12px;line-height:1.6">
    Thestia &middot; Thoralf Illg &middot; Datenschutz:
    <a href="https://thestia.de/datenschutz" style="color:#5b3fa8">thestia.de/datenschutz</a>
    &middot; Kinderschutz:
    <a href="https://auth.thestia.de/kinderschutz" style="color:#5b3fa8">auth.thestia.de/kinderschutz</a>
  </p>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>`;

  const gesendet = await sendMail(
    email,
    "Neue Anmeldung in deinem Thestia-Konto",
    html,
  );

  return json({ ok: true, isNew: true, emailed: gesendet });
});
