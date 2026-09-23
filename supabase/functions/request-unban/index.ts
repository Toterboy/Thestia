// Supabase Edge Function: /request-unban
//
// Entsperrungsantrag für gesperrte E-Mail-Adressen (Plattform-Sperre,
// Migration 045). Der Nutzer ist NICHT eingeloggt (verifiziert gegen
// public.banned_emails) – deshalb verify_jwt = false in config.toml und
// eigene Absicherung:
//   - Nur E-Mails, die wirklich in banned_emails stehen, erhalten eine
//     Mail. Nach AUSSEN ist die Antwort identisch (Anti-Enumeration).
//   - In-Memory-Rate-Limit pro IP (5/Stunde) + persistentes Rate-Limit
//     pro E-Mail über consume_rate_limit (3/Stunde).
//   - HTML-Escaping gegen Stored XSS in der Admin-Mail.
// Die Mail geht wie beim Bug Report über Brevo an den Support.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

const SUPPORT_EMAIL = "support@wispdating.de";
const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
// API-Keys: sb_-Keys (secret_jwt_template -> service_role). Nach
// Migration 122 (SELECT-Grants) live verifiziert (GoTrue listUsers OK +
// PostgREST-DELETE 204). Legacy-JWTs sind entfernt. Reihenfolge:
// SUPABASE_SECRET_KEY ('default') zuerst, Reserve SUPABASE_SECRET_KEYS.
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

const SUPABASE_SERVICE_ROLE_KEY = _pickApiKey("SUPABASE_SECRET_KEYS", "SUPABASE_SECRET_KEY");

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// In-Memory Rate Limiter: 5 Anträge pro IP pro Stunde
const rateMap = new Map<string, number[]>();
const RATE_LIMIT = 5;
const RATE_WINDOW_MS = 60 * 60 * 1000;

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const timestamps = rateMap.get(ip)?.filter((t) => now - t < RATE_WINDOW_MS) ?? [];
  timestamps.push(now);
  rateMap.set(ip, timestamps);
  return timestamps.length > RATE_LIMIT;
}

// HTML-Escaping gegen Stored XSS
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method !== "POST") {
    return jsonError("Method not allowed", 405);
  }

  const ip =
    req.headers.get("x-forwarded-for") ??
    req.headers.get("cf-connecting-ip") ??
    "unknown";
  if (isRateLimited(ip)) {
    return jsonError("Too many requests", 429);
  }

  if (!BREVO_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonError("Server config missing", 500);
  }

  try {
    const body = await req.json();
    const emailRaw = (body.email ?? "").toString().trim().toLowerCase();
    const reasonRaw = (body.reason ?? "").toString().trim();

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailRaw)) {
      return jsonError("Ungültige E-Mail-Adresse.", 400);
    }
    if (reasonRaw.length < 20 || reasonRaw.length > 2000) {
      return jsonError("Begründung: 20-2000 Zeichen.", 400);
    }

    // Persistentes Rate-Limit pro E-Mail (überlebt Cold Starts).
    const { data: limited } = await supabaseAdmin.rpc("consume_rate_limit", {
      p_key: "unban_request:" + emailRaw,
      p_max_hits: 3,
      p_window_seconds: 3600,
    });
    if (limited === false) {
      return jsonError("Zu viele Anfragen für diese E-Mail-Adresse. Bitte warte eine Stunde.", 429);
    }

    // Nur echte Ban-Einträge erhalten eine Mail. Nach AUSSEN ist die
    // Antwort identisch (Einheitsantwort), damit Angreifer nicht per
    // Ausprobieren erkennen koennen, welche E-Mails gesperrt sind
    // (Anti-Enumeration).
    const { data: banEntry, error: banError } = await supabaseAdmin
      .from("banned_emails")
      .select("reason")
      .eq("email", emailRaw)
      .maybeSingle();
    if (banError) {
      console.error("banned_emails query error:", banError);
      return jsonError("Internal error", 500);
    }
    if (!banEntry) {
      // Identische Antwort wie bei erfolgreichem Antrag.
      return new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const reason = escapeHtml(reasonRaw);
    const banReason = escapeHtml(banEntry.reason ?? "");
    const now = new Date().toISOString();

    const htmlContent = `<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0;padding:0;background:#f4f4f8;font-family:'Helvetica Neue',Arial,sans-serif">
  <table width="100%" cellpadding="0" cellspacing="0" style="padding:40px 0">
    <tr>
      <td align="center">
        <table width="480" cellpadding="0" cellspacing="0" style="max-width:480px;background:#fff8f5;border-radius:16px;overflow:hidden;box-shadow:0 2px 16px rgba(0,0,0,0.06)">
          <tr>
            <td style="background:linear-gradient(135deg,#ff8fab 0%,#ff6b9d 100%);padding:40px 30px;text-align:center">
              <h1 style="color:#fff;font-size:28px;margin:0;font-weight:600;letter-spacing:1px">WispDating</h1>
            </td>
          </tr>
          <tr>
            <td style="padding:40px 30px;text-align:left">
              <h2 style="color:#2d2d2d;font-size:22px;margin:0 0 10px">Entsperrungsantrag</h2>
              <p style="color:#666;font-size:14px;line-height:1.6;margin:0 0 20px">
                <strong>Datum:</strong> ${escapeHtml(now)}
              </p>
              <p style="color:#666;font-size:14px;line-height:1.6;margin:0 0 20px">
                <strong>E-Mail:</strong> ${escapeHtml(emailRaw)}
              </p>
              <div style="background:#fff;border:1px solid #f0d0d8;border-radius:8px;padding:16px;margin:0 0 20px">
                <p style="color:#999;font-size:12px;margin:0 0 4px">Hinterlegter Sperr-Grund</p>
                <p style="color:#666;font-size:13px;margin:0">${banReason || "Keine Angabe"}</p>
              </div>
              <div style="background:#fff;border:1px solid #f0d0d8;border-radius:8px;padding:16px">
                <p style="color:#999;font-size:12px;margin:0 0 4px">Begründung des Nutzers</p>
                <p style="color:#2d2d2d;font-size:15px;margin:0;line-height:1.6;white-space:pre-wrap">${reason}</p>
              </div>
            </td>
          </tr>
          <tr>
            <td style="background:#fdf0ee;padding:20px 30px;text-align:center">
              <p style="color:#b0b0b0;font-size:12px;margin:0">
                WispDating &middot; Automatischer Entsperrungsantrag
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

    const brevoResp = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: {
        "accept": "application/json",
        "api-key": BREVO_API_KEY,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        sender: { email: "support@wispdating.de", name: "Wisp Entsperrungsantrag" },
        to: [{ email: SUPPORT_EMAIL, name: "Wisp Support" }],
        subject: `Entsperrungsantrag – ${emailRaw}`,
        htmlContent,
      }),
    });

    if (!brevoResp.ok) {
      console.error("Brevo error:", brevoResp.status, await brevoResp.text());
      return jsonError("Send failed", 502);
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("Error:", e);
    return jsonError("Internal error", 500);
  }
});