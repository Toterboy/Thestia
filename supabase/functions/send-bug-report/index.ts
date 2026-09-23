import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

const BUGREPORT_EMAIL = "bugreport@wispdating.de";
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

// In-Memory Rate Limiter: 5 Reports pro IP pro Stunde
const rateMap = new Map<string, number[]>();
const RATE_LIMIT = 5;
const RATE_WINDOW_MS = 60 * 60 * 1000;

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const timestamps = rateMap.get(ip)?.filter(t => now - t < RATE_WINDOW_MS) ?? [];
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

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  // Rate Limiting
  const ip = req.headers.get("x-forwarded-for") ?? req.headers.get("cf-connecting-ip") ?? "unknown";
  if (isRateLimited(ip)) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429, headers: { "Content-Type": "application/json" },
    });
  }

  if (!BREVO_API_KEY) {
    return new Response(JSON.stringify({ error: "Server config missing" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    // JWT-Authentifizierung (verify_jwt = true in config.toml)
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    // Defense-in-Depth: Ungültiger Token wird abgelehnt, auch wenn das
    // Gateway verify_jwt=true bereits prüft.
    const { data: authData, error: authError } = await supabaseAdmin.auth
      .getUser(token);
    if (authError || !authData?.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }

    // Persistentes Pro-Nutzer-Limit (Fix: reines IP-Limit war per
    // IP-Rotation + Cold-Start-Verlust umgehbar). Fail-open bei
    // RPC-Fehlern (kein Lock-out durch Infra-Probleme).
    try {
      const { data: allowed, error: limitError } = await supabaseAdmin.rpc(
        "consume_rate_limit",
        {
          p_key: `bug-report:${authData.user.id}`,
          p_max_hits: 10,
          p_window_seconds: 3600,
        },
      );
      if (!limitError && allowed !== true) {
        return new Response(JSON.stringify({ error: "Too many requests" }), {
          status: 429, headers: { "Content-Type": "application/json" },
        });
      }
    } catch (e) {
      console.error("consume_rate_limit exception:", e);
    }

    const body = await req.json();
    const descriptionRaw = (body.description ?? "").toString();
    const deviceInfoRaw = (body.deviceInfo ?? "").toString();

    if (descriptionRaw.trim().length < 5 || descriptionRaw.length > 5000) {
      return new Response(JSON.stringify({ error: "Beschreibung: 5-5000 Zeichen." }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    // Bilder: maximal 5 Anhänge, jede Datei als {name, content(base64)}.
    // Größenlimit (M8): max. 2 MB Base64 pro Bild, 8 MB insgesamt -
    // verhindert E-Mail-Kontingent-/Größen-DoS.
    const MAX_ATTACHMENT_BASE64 = 2 * 1024 * 1024;
    const MAX_TOTAL_BASE64 = 8 * 1024 * 1024;
    const imagesRaw = Array.isArray(body.images) ? body.images : [];
    if (imagesRaw.length > 5) {
      return new Response(JSON.stringify({ error: "Maximal 5 Bilder erlaubt." }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }
    const attachments = imagesRaw
      .slice(0, 5)
      .map((img: unknown, i: number) => {
        const entry = (img ?? {}) as { name?: unknown; content?: unknown };
        const name = typeof entry.name === "string" && entry.name.trim()
          ? entry.name.trim().replace(/[^a-zA-Z0-9._-]/g, "_")
          : `screenshot_${i + 1}.jpg`;
        const content = typeof entry.content === "string" ? entry.content : "";
        return { name, content };
      })
      .filter((a) => a.content.length > 0);

    if (attachments.some((a) => a.content.length > MAX_ATTACHMENT_BASE64)) {
      return new Response(JSON.stringify({ error: "Ein Bild überschreitet 2 MB." }), {
        status: 413, headers: { "Content-Type": "application/json" },
      });
    }
    const totalSize = attachments.reduce((sum, a) => sum + a.content.length, 0);
    if (totalSize > MAX_TOTAL_BASE64) {
      return new Response(JSON.stringify({ error: "Anhänge überschreiten insgesamt 8 MB." }), {
        status: 413, headers: { "Content-Type": "application/json" },
      });
    }

    // HTML-escaped Werte (gegen Stored XSS)
    const description = escapeHtml(descriptionRaw.trim());
    const deviceInfo = escapeHtml(deviceInfoRaw.trim());
    const user = authData.user;
    const userId = escapeHtml(user.id);
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
          <!-- Header -->
          <tr>
            <td style="background:linear-gradient(135deg,#ff8fab 0%,#ff6b9d 100%);padding:40px 30px;text-align:center">
              <h1 style="color:#fff;font-size:28px;margin:0;font-weight:600;letter-spacing:1px">WispDating</h1>
            </td>
          </tr>
          <!-- Body -->
          <tr>
            <td style="padding:40px 30px;text-align:left">
              <h2 style="color:#2d2d2d;font-size:22px;margin:0 0 10px">Bug Report</h2>
              <p style="color:#666;font-size:14px;line-height:1.6;margin:0 0 20px">
                <strong>Datum:</strong> ${escapeHtml(now)}
              </p>
              <p style="color:#666;font-size:14px;line-height:1.6;margin:0 0 20px">
                <strong>User ID:</strong> ${userId}
              </p>
              <div style="background:#fff;border:1px solid #f0d0d8;border-radius:8px;padding:16px;margin:0 0 20px">
                <p style="color:#999;font-size:12px;margin:0 0 4px">Geräteinformationen</p>
                <pre style="color:#666;font-size:13px;margin:0;white-space:pre-wrap">${deviceInfo || "Keine Angabe"}</pre>
              </div>
              <div style="background:#fff;border:1px solid #f0d0d8;border-radius:8px;padding:16px">
                <p style="color:#999;font-size:12px;margin:0 0 4px">Beschreibung</p>
                <p style="color:#2d2d2d;font-size:15px;margin:0;line-height:1.6">${description}</p>
              </div>
              ${attachments.length > 0 ? `<p style="color:#999;font-size:13px;margin:20px 0 0">📎 ${attachments.length} Screenshot(s) angehängt</p>` : ''}
            </td>
          </tr>
          <!-- Footer -->
          <tr>
            <td style="background:#fdf0ee;padding:20px 30px;text-align:center">
              <p style="color:#b0b0b0;font-size:12px;margin:0">
                WispDating &middot; Automatischer Bug Report
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
        sender: { email: BUGREPORT_EMAIL, name: "Wisp Bug Report" },
        to: [{ email: SUPPORT_EMAIL, name: "Wisp Support" }],
        subject: `Bug Report – ${now.slice(0, 10)}`,
        htmlContent,
        ...(attachments.length > 0 ? { attachment: attachments } : {}),
      }),
    });

    if (!brevoResp.ok) {
      console.error("Brevo error:", brevoResp.status, await brevoResp.text());
      return new Response(JSON.stringify({ error: "Send failed" }), {
        status: 502, headers: { "Content-Type": "application/json" },
      });
    }

    const result = await brevoResp.json();

    // Report zusaetzlich zeilenbasiert speichern (Migration 052), damit
    // der Admin-Screen ihn anzeigen kann. Best-Effort: Scheitert der
    // Insert, ist die Email trotzdem raus - der Versand bleibt erfolgreich.
    try {
      await supabaseAdmin.from("bug_reports").insert({
        user_id: user?.id ?? null,
        description: descriptionRaw,
        device_info: deviceInfoRaw,
        attachment_count: attachments.length,
      });
    } catch (dbErr) {
      console.error("bug_reports insert failed:", dbErr);
    }

    return new Response(JSON.stringify({ success: true, messageId: result.messageId }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("Error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
