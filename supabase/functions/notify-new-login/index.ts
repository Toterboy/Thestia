// Supabase Edge Function: /notify-new-login
//
// Sendet die Warn-Mail an den Kontoinhaber, wenn sich ein NEUES Geraet
// anmeldet.
//
// AUFBAU (v0.10.0, Migration 169):
//
// Der Aufruf kommt aus der DATENBANK - aus dem Trigger auf
// auth_devices, der bei jedem INSERT einer Geraete-Zeile feuert. Der
// Trigger entscheidet also, was "neu" ist, und diese Funktion schickt
// nur noch die Mail.
//
// WARUM nicht aus der App (die erste Fassung):
//
//   * FAELLT DER AUFRUF AUS, geht die Mail trotzdem raus. Der Trigger
//     haengt an der Tabelle, nicht an einem Aufruf der App - inklusive
//     des Fallback-Pfads der App, in dem sie die Zeile selbst schreibt.
//   * Die Entscheidung liegt damit in der Datenbank und nicht beim
//     Client.
//
// AUTH: Nur mit dem internen Secret (x-thestia-internal). Das ist der
// Aufruf des Triggers (Muster aus Migration 146). Ohne Secret: 401.
//
// DIE BREMSE: Der Trigger zaehlt die versendeten Mails (consume_rate_limit,
// 5 pro Konto und Stunde). Die Funktion muss nichts zaehlen - sonst
// wuerde eine haeufig neu registrierende App jeden Alarm unterdruecken.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const INTERNAL_SECRET = Deno.env.get("THESTIA_INTERNAL_SECRET") ?? "";
const SENDER_EMAIL = "support@thestia.de";
const SENDER_NAME = "Thestia";

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

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
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

  // AUTH: nur das interne Secret. Der Aufrufer ist der Trigger.
  const header = req.headers.get("x-thestia-internal") ?? "";
  if (
    INTERNAL_SECRET === "" || header === "" ||
    !timingSafeEqual(header, INTERNAL_SECRET)
  ) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Invalid JSON" }, 400);
  }

  const userId = String(body.userId ?? "").trim();
  if (!userId) return json({ error: "userId fehlt" }, 400);

  const deviceModel = String(body.deviceModel ?? "").slice(0, 120);
  const deviceName = String(body.deviceName ?? "").slice(0, 120);
  const appVersion = String(body.appVersion ?? "").slice(0, 60);

  // Die Adresse des Kontos. Der Trigger hat die Berechtigung, aber
  // nicht die Adresse - die holen wir hier mit der Service-Rolle.
  const { data: userData, error: userError } = await supabaseAdmin
    .from("auth.users")
    .select("email, raw_user_meta_data")
    .eq("id", userId)
    .maybeSingle();

  if (userError || !userData?.email) {
    console.log("notify-new-login: Konto ohne E-Mail-Adresse - keine Mail.");
    return json({ ok: true, emailed: false });
  }

  const email = String(userData.email);
  const vorname = String(
    (userData.raw_user_meta_data as Record<string, unknown> | null)?.name ?? "",
  ).split(" ")[0].slice(0, 40);

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
  <p>Hallo${vorname ? ` ${escapeHtml(vorname)}` : ""},</p>
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

  console.log(
    `notify-new-login: ${gesendet ? "Mail gesendet" : "Mail NICHT gesendet"} an ${email} (Geraet: ${gerät}).`,
  );

  return json({ ok: true, emailed: gesendet });
});
