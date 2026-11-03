// Supabase Edge Function: /guardian-consent
//
// Eltern-Erlaubnis fuer 16- und 17-Jaehrige (v0.10.0, Migration 165).
//
// ZWEI WEGE, DIE FUNKTION AUFGERUFEN WIRD:
//
// 1) INTERN aus der Datenbank (pg_cron / Trigger / RPC):
//    Der Header "x-thestia-internal" mit THESTIA_INTERNAL_SECRET.
//    Aktionen: send_consent_mail, send_confirmed_notice.
//    -> Die Datenbank uebergibt hier den Klartext-Token. Der Server
//       speichert nur den Hash; der Klartext existiert nur in dieser
//       Mail und im Speicher fuer den Versand.
//
// 2) OEFFENTLICH aus dem Eltern-Portal (passkey-assets/eltern.html):
//    Kein JWT - der Token in der URL IST die Berechtigung. Er ist
//    32 Byte Zufall, wird nur als SHA-256-Hash gespeichert und ist nach
//    14 Tagen ungueltig.
//    Aktionen: confirm, settings, revoke.
//
// verify_jwt = false (supabase/config.toml) - beide Wege pruefen ihre
// Berechtigung selbst: intern ueber das Secret, oeffentlich ueber den
// Token (Rate-Limit pro IP dazu).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const INTERNAL_SECRET = Deno.env.get("THESTIA_INTERNAL_SECRET") ?? "";

// Das Eltern-Portal. Dort kann der Elternteil bestaetigen, einstellen
// und widerrufen.
const PORTAL_URL = "https://auth.thestia.de/eltern";

// Absender. Eine Elternmail kommt vom Support-Postfach, nicht vom
// Kinderschutz-Postfach: der Kinderschutz-Eingang ist fuer Meldungen
// ueber Kindesmissbrauch da, nicht fuer die Elternkorrespondenz.
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

// ---------------------------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------------------------

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "content-type, x-thestia-internal",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
  });
}

/** Zeitvergleicher Vergleich (nicht zeitkonstant genug fuer Passwoerter,
 *  aber besser als ein einfacher Vergleich fuer ein Secret). */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function isInternal(req: Request): boolean {
  const header = req.headers.get("x-thestia-internal") ?? "";
  if (INTERNAL_SECRET === "" || header === "") return false;
  return timingSafeEqual(header, INTERNAL_SECRET);
}

/** HTML-Escaping. Der Betreff und die Inhalte enthalten Angaben aus der
 *  Datenbank (Name des Kindes) - die duerfen nicht als HTML interpretiert
 *  werden. */
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// In-Memory Rate-Limit fuer die oeffentlichen Portal-Aktionen.
// Der Token ist nicht erratbar, aber ein Rate-Limit kostet nichts und
// haelt einen Angreifer davon ab, die Endpunkte zu ueberfluten.
const rateMap = new Map<string, number[]>();
const RATE_LIMIT = 30;
const RATE_WINDOW_MS = 60 * 60 * 1000;

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const timestamps =
    rateMap.get(ip)?.filter((t) => now - t < RATE_WINDOW_MS) ?? [];
  timestamps.push(now);
  rateMap.set(ip, timestamps);
  return timestamps.length > RATE_LIMIT;
}

function clientIp(req: Request): string {
  const direct =
    req.headers.get("x-client-ip") ??
    req.headers.get("cf-connecting-ip") ??
    (req.headers.get("x-forwarded-for") ?? "").split(",")[0]?.trim();
  return direct && direct.length > 0 ? direct : "unknown";
}

// ---------------------------------------------------------------------------
// Mailversand (Brevo)
// ---------------------------------------------------------------------------

async function sendMail(
  to: string,
  subject: string,
  htmlContent: string,
): Promise<boolean> {
  if (BREVO_API_KEY === "") {
    console.error("guardian-consent: BREVO_API_KEY fehlt - kein Versand.");
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
      "guardian-consent: Brevo-Fehler",
      resp.status,
      await resp.text(),
    );
    return false;
  }
  return true;
}

function shell(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
</head>
<body style="margin:0;padding:0;background:#f4f0f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f0f7;padding:24px 12px">
<tr><td align="center">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:16px;overflow:hidden">
<tr><td style="background:#5b3fa8;padding:28px 30px">
  <h1 style="margin:0;color:#ffffff;font-size:22px;font-weight:700">${escapeHtml(title)}</h1>
</td></tr>
<tr><td style="padding:30px;color:#2d2d2d;font-size:15px;line-height:1.65">
${body}
</td></tr>
<tr><td style="background:#f7f5fa;padding:20px 30px">
  <p style="margin:0;color:#8b8b96;font-size:12px;line-height:1.6">
    Thestia &middot; Thoralf Illg &middot; Datenschutz: <a href="https://thestia.de/datenschutz" style="color:#5b3fa8">thestia.de/datenschutz</a>
    &middot; Kinderschutz: <a href="https://auth.thestia.de/kinderschutz" style="color:#5b3fa8">auth.thestia.de/kinderschutz</a>
  </p>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// Aktion 1: Mail an den Elternteil (intern)
// ---------------------------------------------------------------------------

async function sendConsentMail(
  guardianEmail: string,
  token: string,
  childName: string,
): Promise<boolean> {
  const link = `${PORTAL_URL}?token=${encodeURIComponent(token)}`;
  const html = shell(
    "Dein Kind möchte Thestia nutzen",
    `<p>Hallo,</p>
<p><strong>${escapeHtml(childName)}</strong> möchte Thestia nutzen. Thestia ist eine
Dating-App. Für 16- und 17-Jährige verlangt die App die Zustimmung der
Sorgeberechtigten.</p>

<p>Mit einem Klick bestätigst du, dass du Sorgeberechtigte oder Sorgeberechtigter
von ${escapeHtml(childName)} bist und dass ${escapeHtml(childName)} die App nutzen darf:</p>

<p style="margin:26px 0">
  <a href="${escapeHtml(link)}" style="display:inline-block;background:#5b3fa8;color:#ffffff;text-decoration:none;padding:14px 26px;border-radius:30px;font-weight:600">Freigabe bestätigen</a>
</p>

<p>Nach der Bestätigung kannst du im selben Bereich einstellen, wie oft du
benachrichtigt werden möchtest, ob die Nutzungszeit begrenzt wird, und eine
vierstellige PIN festlegen, mit der diese Einstellungen geschützt sind.
Du kannst die Freigabe jederzeit widerrufen - mit einem Klick, ohne Rückfrage.</p>

<div style="background:#f7f5fa;border-radius:10px;padding:14px 16px;margin:22px 0">
  <p style="margin:0 0 6px;color:#5b3fa8;font-size:13px;font-weight:600">Was wir dir schicken</p>
  <p style="margin:0;color:#55555f;font-size:14px;line-height:1.6">
  Wenn zwischen ${escapeHtml(childName)} und einer anderen Person ein Funke entsteht,
  bekommst du eine Nachricht - in dem Rhythmus, den du selbst wählst
  (täglich, wöchentlich, monatlich oder gar nicht). Wir schicken dir <strong>keine
  Namen, keine Profile und keine Inhalte</strong> der Nachrichten. Es gibt nur den
  Hinweis, dass ein Funke entstanden ist.
  </p>
</div>

<p style="color:#8b8b96;font-size:13px">Dieser Link enthält einen Zugangsschlüssel.
Bitte leite diese E-Mail nicht weiter. Der Link ist 14 Tage gültig.</p>`,
  );
  return await sendMail(
    guardianEmail,
    `${childName} möchte Thestia nutzen - bitte bestätigen`,
    html,
  );
}

// ---------------------------------------------------------------------------
// Aktion 2: Hinweis an den Jugendlichen (intern)
// ---------------------------------------------------------------------------

async function sendConfirmedNotice(
  childUserId: string,
  childName: string,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin.auth.admin.getUserById(
    childUserId,
  );
  if (error || !data?.user?.email) {
    console.error("guardian-consent: Kind-Mail ohne Adresse:", error);
    return false;
  }
  const html = shell(
    "Dein Elternteil hat bestätigt",
    `<p>Hallo ${escapeHtml(childName)},</p>
<p>Dein Elternteil hat die Freigabe bestätigt. Du kannst Thestia jetzt
vollständig nutzen.</p>

<p>In den <strong>Einstellungen unter „Kinderschutz &amp; Elternzugriff"</strong>
siehst du den Stand jederzeit. Dort kannst du den Elternzugriff auch selbst
beenden - oder, wenn du 18 wirst, entscheiden, wie lange er noch bestehen soll.</p>`,
  );
  return await sendMail(
    data.user.email,
    "Deine Eltern haben bestätigt",
    html,
  );
}

// ---------------------------------------------------------------------------
// Hauptfunktion
// ---------------------------------------------------------------------------

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "content-type, x-thestia-internal",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Invalid JSON" }, 400);
  }

  const action = String(body.action ?? "");

  // ---------------------------------------------------------------------
  // Interner Weg (Datenbank -> Function)
  // ---------------------------------------------------------------------
  if (isInternal(req)) {
    if (action === "send_consent_mail") {
      const guardianEmail = String(body.guardianEmail ?? "");
      const token = String(body.token ?? "");
      const childUserId = String(body.childUserId ?? "");
      if (!guardianEmail || !token || !childUserId) {
        return json({ error: "Missing fields" }, 400);
      }
      const { data: profile } = await supabaseAdmin
        .from("profiles")
        .select("name")
        .eq("user_id", childUserId)
        .maybeSingle();
      const childName = String(profile?.name ?? "Dein Kind")
        .split(" ")[0]
        .slice(0, 40);
      const sent = await sendConsentMail(guardianEmail, token, childName);
      return json({ ok: sent });
    }
    if (action === "send_confirmed_notice") {
      const childUserId = String(body.childUserId ?? "");
      if (!childUserId) return json({ error: "Missing fields" }, 400);
      const { data: profile } = await supabaseAdmin
        .from("profiles")
        .select("name")
        .eq("user_id", childUserId)
        .maybeSingle();
      const childName = String(profile?.name ?? "Dein Kind")
        .split(" ")[0]
        .slice(0, 40);
      const sent = await sendConfirmedNotice(childUserId, childName);
      return json({ ok: sent });
    }
    return json({ error: "Unknown action" }, 400);
  }

  // ---------------------------------------------------------------------
  // Oeffentlicher Weg (Eltern-Portal)
  // ---------------------------------------------------------------------
  if (isRateLimited(clientIp(req))) {
    return json({ error: "rate_limited" }, 429);
  }

  const token = String(body.token ?? "");
  if (token.length < 16) {
    return json({ error: "invalid_token" }, 400);
  }

  if (action === "confirm") {
    const { data, error } = await supabaseAdmin.rpc(
      "confirm_guardian_consent",
      { p_token: token },
    );
    if (error) {
      console.error("guardian-consent: confirm:", error);
      return json({ error: "server_error" }, 500);
    }
    // Die RPC antwortet mit {ok, error}. Sie unterscheidet bewusst NICHT
    // zwischen "unbekannter Token" und "abgelaufen" - nach aussen sieht
    // beides gleich aus.
    const ok = (data as { ok?: boolean } | null)?.ok === true;
    return json({ ok });
  }

  if (action === "status") {
    // Der Stand der elterlichen Einstellungen. Enthaelt KEINE Daten des
    // Kindes - nur den Freigabestand (Migration 166).
    const { data, error } = await supabaseAdmin.rpc(
      "guardian_portal_status",
      { p_token: token },
    );
    if (error) {
      console.error("guardian-consent: status:", error);
      return json({ error: "server_error" }, 500);
    }
    return json(data ?? { ok: false });
  }

  if (action === "settings") {
    const { data, error } = await supabaseAdmin.rpc(
      "set_guardian_portal_settings",
      {
        p_token: token,
        p_notify_enabled: body.notifyEnabled === true,
        p_notify_frequency: String(body.notifyFrequency ?? "weekly"),
        p_usage_limit_enabled: body.usageLimitEnabled === true,
        p_usage_start_min: body.usageStartMin === undefined ||
            body.usageStartMin === null
          ? null
          : Number(body.usageStartMin),
        p_usage_end_min: body.usageEndMin === undefined ||
            body.usageEndMin === null
          ? null
          : Number(body.usageEndMin),
        p_pin: body.pin === undefined || body.pin === null
          ? null
          : String(body.pin),
      },
    );
    if (error) {
      console.error("guardian-consent: settings:", error);
      return json({ error: "server_error" }, 500);
    }
    return json(data ?? { ok: false });
  }

  if (action === "revoke") {
    const { data, error } = await supabaseAdmin.rpc(
      "revoke_guardian_consent_by_token",
      { p_token: token },
    );
    if (error) {
      console.error("guardian-consent: revoke:", error);
      return json({ error: "server_error" }, 500);
    }
    return json(data ?? { ok: false });
  }

  return json({ error: "Unknown action" }, 400);
});
