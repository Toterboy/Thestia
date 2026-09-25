// Edge Function: admin-ban
//
// Admin-Werkzeug: Nutzer sperren/entsperren (E-Mail + optional bestehender
// Account). Nur für die konfigurierte Admin-ID aufrufbar.
//
// Was passiert beim Sperren:
//  1. E-Mail in public.banned_emails hinterlegen (blockiert Neu-
//     Registrierung serverseitig via handle_new_user-Trigger, Migration 045;
//     der Login-Client erkennt die Sperre via check_email_ban_status und
//     bietet den Entsperrungsantrag an).
//  2. Wurde eine USER-ID angegeben, wird zusätzlich der bestehende Account
//     über die GoTrue-Admin-API gesperrt (ban_duration) - die Sessions
//     verlieren sofort ihre Gültigkeit.
//  3. Optional: Der Nutzer erhält per E-Mail (Brevo) die Begründung und den
//     Hinweis auf den Entsperrungsantrag.
//
// Auth: JWT-Pflicht + die JWT-User-ID muss dem Secret ADMIN_UUID entsprechen
// (denselben Wert wie das Build-Flag --dart-define=ADMIN_UUID setzen).
// Fail-closed: Ohne gesetztes Secret lehnt die Funktion ALLE Anfragen ab.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

const ADMIN_UUID = Deno.env.get("ADMIN_UUID") ?? "";
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

// GoTrue-Ban-Dauer für bestehende Accounts: 10 Jahre (= praktisch
// dauerhaft; die Entsperrung hebt die Sperre explizit auf).
const GO_TRUE_BAN_DURATION = "87600h";

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

  // JWT-Pflicht + Admin-Prüfung (fail-closed).
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const { data: authData, error: authError } = await supabaseAdmin.auth.getUser(token);
  if (authError || !authData?.user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401, headers: { "Content-Type": "application/json" },
    });
  }
  if (!ADMIN_UUID || authData.user.id !== ADMIN_UUID) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    const action = body.action === "unban" ? "unban" : "ban";
    const input = typeof body.emailOrUserId === "string" ? body.emailOrUserId.trim() : "";
    const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 1000) : "";
    const notifyUser = body.notifyUser === true;

    if (input.length === 0) {
      return new Response(JSON.stringify({ error: "E-Mail oder User-ID erforderlich." }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    // Eingabe auflösen: UUID -> Account-lookup; sonst als E-Mail behandeln.
    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input);
    let email: string | null = null;
    let targetUserId: string | null = null;
    let goTrueBanned = false;

    if (isUuid) {
      targetUserId = input.toLowerCase();
      const { data, error } = await supabaseAdmin.auth.admin.getUserById(targetUserId);
      if (error || !data?.user) {
        return new Response(JSON.stringify({ error: "User-ID nicht gefunden." }), {
          status: 404, headers: { "Content-Type": "application/json" },
        });
      }
      email = data.user.email ?? null;
    } else if (input.includes("@")) {
      email = input.toLowerCase();
    } else {
      return new Response(JSON.stringify({ error: "Ungültige E-Mail oder User-ID." }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }
    if (!email) {
      return new Response(JSON.stringify({ error: "Keine E-Mail-Adresse zum Account gefunden." }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    // User-ID anhand der E-Mail nachziehen (für den GoTrue-Ban), wenn nur
    // die E-Mail angegeben wurde. profiles speichert die E-Mail nicht - der
    // Weg läuft über die GoTrue-Admin-Liste, jetzt PAGINIERT (bis 5000
    // Accounts), damit die Sperrung auch bei größeren Instanzen greift.
    if (!targetUserId && action === "ban") {
      for (let page = 1; page <= 25 && !targetUserId; page++) {
        const { data: list, error: listErr } = await supabaseAdmin.auth.admin.listUsers({
          page, perPage: 200,
        });
        if (listErr || !list?.users || list.users.length === 0) break;
        const match = list.users.find((u) => (u.email ?? "").toLowerCase() === email);
        if (match) targetUserId = match.id;
      }
    }

    if (action === "ban") {
      if (reason.length < 3) {
        return new Response(JSON.stringify({ error: "Begründung erforderlich (min. 3 Zeichen)." }), {
          status: 400, headers: { "Content-Type": "application/json" },
        });
      }

      // 1) E-Mail-Sperre (Registrierungs-Trigger, Migration 045).
      const { error: insertErr } = await supabaseAdmin
        .from("banned_emails")
        .upsert(
          { email, reason, banned_by: authData.user.id },
          { onConflict: "email" },
        );
      if (insertErr) {
        console.error("banned_emails upsert failed:", insertErr);
        return new Response(JSON.stringify({ error: "Sperre konnte nicht gespeichert werden." }), {
          status: 500, headers: { "Content-Type": "application/json" },
        });
      }

      // 2) Bestehenden Account sofort sperren (wenn Account bekannt).
      if (targetUserId) {
        const { error: banErr } = await supabaseAdmin.auth.admin.updateUserById(
          targetUserId,
          { ban_duration: GO_TRUE_BAN_DURATION },
        );
        if (!banErr) {
          goTrueBanned = true;
        } else {
          console.error("GoTrue ban failed:", banErr);
        }
      }

      // 3) Optional: Nutzer per Mail informieren (Begriff + Entsperrungsweg).
      if (notifyUser && BREVO_API_KEY) {
        const html = `<!DOCTYPE html>
<html lang="de"><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#f4f4f8;font-family:'Helvetica Neue',Arial,sans-serif">
<table width="100%" cellpadding="0" cellspacing="0" style="padding:40px 0"><tr><td align="center">
<table width="480" cellpadding="0" cellspacing="0" style="max-width:480px;background:#fff8f5;border-radius:16px;overflow:hidden;box-shadow:0 2px 16px rgba(0,0,0,0.06)">
  <tr><td style="background:linear-gradient(135deg,#ff8fab 0%,#ff6b9d 100%);padding:28px 30px;text-align:center">
    <h1 style="color:#fff;font-size:24px;margin:0;font-weight:600">Dein Thestia-Konto</h1>
  </td></tr>
  <tr><td style="padding:30px;text-align:left">
    <p style="color:#2d2d2d;font-size:15px;line-height:1.6;margin:0 0 16px">
      Dein Zugang wurde derzeit gesperrt. Grund:
    </p>
    <div style="background:#fff;border:1px solid #f0d0d8;border-radius:8px;padding:14px;margin:0 0 16px">
      <p style="color:#2d2d2d;font-size:14px;margin:0">${escapeHtml(reason)}</p>
    </div>
    <p style="color:#666;font-size:14px;line-height:1.6;margin:0">
      Wenn du denkst, dass es ein Missverständnis ist, kannst du in der App
      einen Entsperrungsantrag stellen - wir prüfen jeden Antrag persönlich.
    </p>
  </td></tr>
  <tr><td style="background:#fdf0ee;padding:18px 30px;text-align:center">
    <p style="color:#b0b0b0;font-size:12px;margin:0">Thestia &middot; Dein Team</p>
  </td></tr>
</table>
</td></tr></table></body></html>`;
        try {
          await fetch("https://api.brevo.com/v3/smtp/email", {
            method: "POST",
            headers: {
              accept: "application/json",
              "api-key": BREVO_API_KEY,
              "content-type": "application/json",
            },
            body: JSON.stringify({
              sender: { email: "moderation@thestia.de", name: "Thestia" },
              to: [{ email }],
              subject: "Dein Thestia-Konto wurde gesperrt",
              htmlContent: html,
            }),
          });
        } catch (mailErr) {
          console.error("Benachrichtigungs-Mail fehlgeschlagen:", mailErr);
          // Kein Fehler -> die Sperrung selbst ist erfolgreich.
        }
      }

      return new Response(JSON.stringify({
        ok: true, email, banned: true, goTrueBanned, reason,
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    // ---------------- Unban ----------------
    const { error: delErr } = await supabaseAdmin
      .from("banned_emails")
      .delete()
      .eq("email", email);
    if (delErr) {
      console.error("banned_emails delete failed:", delErr);
      return new Response(JSON.stringify({ error: "Entsperrung fehlgeschlagen." }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }
    if (targetUserId) {
      await supabaseAdmin.auth.admin.updateUserById(targetUserId, {
        ban_duration: "none",
      });
    }
    return new Response(JSON.stringify({
      ok: true, email, banned: false,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error("Error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
