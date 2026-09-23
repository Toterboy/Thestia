// Edge Function: report-image
//
// Bild-Meldung mit automatischer KI-Vorprüfung (NSFW).
//
// Ablauf:
//  1. Client (meldender Nutzer) sendet das lokal entschlüsselte Chat-Bild
//     (Base64) + Grund. Chat-Bilder werden NIE automatisch gescannt -
//     ausschließlich im Rahmen einer Meldung (berechtigtes Interesse).
//  2. Die Function scannt das Bild über einen NSFW-Klassifikator
//     (Hugging Face Inference Router, Falconsai/nsfw_image_detection).
//     HF_API_TOKEN liegt ausschließlich als Function-Secret hier.
//  3. Ergebnis wird in photo_moderation gespeichert (Migration 064:
//     reporter_id, reason, escalated) UND der Betreiber erhält eine
//     E-Mail via Brevo (Bild als Anhang + Report + KI-Ergebnis).
//  4. Der Client erhält das KI-Ergebnis direkt zurück - der Meldende
//     sieht sofort, ob die KI die Einschätzung teilt. Bei Widerspruch
//     kann er erneut aufrufen (escalate=true) -> manuelle Prüfung.
//
// Secrets: HF_API_TOKEN (optional - ohne Token: KI "nicht verfügbar",
// Meldung + Eskalation funktionieren trotzdem), BREVO_API_KEY (Pflicht).
// Mail-Adresse des Betreibers: MODERATION_EMAIL (Default s.u.).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

const MODERATION_EMAIL = Deno.env.get("MODERATION_EMAIL") ?? "moderation@wispdating.de";
const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const HF_API_TOKEN = Deno.env.get("HF_API_TOKEN") ?? "";
// HF Inference Router (hf-inference-Provider) mit NSFW-Klassifikator.
const HF_MODEL_URL =
  "https://router.huggingface.co/hf-inference/models/Falconsai/nsfw_image_detection";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
// API-Keys: Legacy-JWTs (anon/service_role) ZUERST - funktionierende
// Konfiguration (Grants live verifiziert). Die neuen sb_-Keys sind nur
// RESERVE (sie mappen nicht auf service_role-Rechte - live bewiesen).
// Legacy im Dashboard erst deaktivieren, wenn sb_ nachweislich trägt.
function _pickApiKey(autoDict: string, custom: string, legacy: string): string {
  const old = Deno.env.get(legacy) ?? "";
  if (old.length > 0) return old;
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

const SUPABASE_SERVICE_ROLE_KEY = _pickApiKey("SUPABASE_SECRET_KEYS", "SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY");

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// NSFW-Schwellwert: >= 0.80 gilt als "KI bestätigt unangemessen".
// 0.20-0.80 wäre Grenzfall -> wie "nicht bestätigt" behandelt (Eskalation
// bleibt dem Nutzer überlassen).
const NSFW_THRESHOLD = 0.8;

// In-Memory Rate Limiter: 10 Bild-Meldungen pro User pro Stunde
// (Eskalationen zählen mit - verhindert Mail-Kontingent-DoS).
const rateMap = new Map<string, number[]>();
const RATE_LIMIT = 10;
const RATE_WINDOW_MS = 60 * 60 * 1000;

function isRateLimited(userId: string): boolean {
  const now = Date.now();
  const timestamps = rateMap.get(userId)?.filter((t) => now - t < RATE_WINDOW_MS) ?? [];
  timestamps.push(now);
  rateMap.set(userId, timestamps);
  return timestamps.length > RATE_LIMIT;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

interface AiResult {
  available: boolean;
  nsfw: boolean;
  score: number; // NSFW-Score 0..1
  label: string; // "nsfw" | "normal" | "unavailable" | Fehlerlabel
}

async function scanImage(imageBase64: string): Promise<AiResult> {
  if (!HF_API_TOKEN) {
    return { available: false, nsfw: false, score: 0, label: "no_api_token" };
  }
  try {
    const resp = await fetch(HF_MODEL_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${HF_API_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ inputs: imageBase64 }),
    });
    if (!resp.ok) {
      console.error("HF error:", resp.status, await resp.text());
      return { available: false, nsfw: false, score: 0, label: `hf_error_${resp.status}` };
    }
    const data = await resp.json();
    // Format: [{label: "nsfw", score: 0.97}, {label: "normal", score: 0.03}]
    const entries = Array.isArray(data) ? data : [];
    let nsfwScore = 0;
    let topLabel = "unknown";
    let topScore = 0;
    for (const e of entries) {
      const label = String(e?.label ?? "");
      const score = Number(e?.score ?? 0);
      if (label === "nsfw" || label === "porn" || label === "hentai" || label === "sexy") {
        nsfwScore = Math.max(nsfwScore, score);
      }
      if (score > topScore) {
        topScore = score;
        topLabel = label;
      }
    }
    return {
      available: true,
      nsfw: nsfwScore >= NSFW_THRESHOLD,
      score: Math.round(nsfwScore * 1000) / 1000,
      label: topLabel,
    };
  } catch (e) {
    console.error("HF exception:", e);
    return { available: false, nsfw: false, score: 0, label: "hf_exception" };
  }
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  // JWT-Pflicht (verify_jwt = true in config.toml) + Defense-in-Depth.
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const { data: authData, error: authError } = await supabaseAdmin.auth.getUser(token);
  if (authError || !authData?.user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401, headers: { "Content-Type": "application/json" },
    });
  }
  const reporter = authData.user;

  if (isRateLimited(reporter.id)) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    const imageBase64 = typeof body.imageBase64 === "string" ? body.imageBase64 : "";
    const reportedUserId = typeof body.reportedUserId === "string" ? body.reportedUserId : "";
    const reason = typeof body.reason === "string" ? body.reason.slice(0, 200) : "";
    const details = typeof body.details === "string" ? body.details.slice(0, 2000) : "";
    const escalate = body.escalate === true;

    if (imageBase64.length < 100 || imageBase64.length > 3 * 1024 * 1024) {
      return new Response(JSON.stringify({ error: "Bild: 100 Bytes bis 3 MB (Base64)." }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }
    if (!/^[0-9a-f-]{36}$/i.test(reportedUserId)) {
      return new Response(JSON.stringify({ error: "Ungültige reportedUserId." }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }
    // Selbst-Meldungen blocken (sinnlos + Mail-Kontingent-Missbrauch).
    if (reportedUserId.toLowerCase() === reporter.id.toLowerCase()) {
      return new Response(JSON.stringify({ error: "Selbst-Meldung nicht möglich." }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }
    if (!escalate && reason.trim().length === 0) {
      return new Response(JSON.stringify({ error: "Grund erforderlich." }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    // 1) KI-Scan (immer frisch - auch bei Eskalation, damit die Mail ein
    // aktuelles Ergebnis enthält).
    const ai = await scanImage(imageBase64);

    // Hash über die ROHEN Bildbytes (konsistent zur Client-Registrierung:
    // Der Sender registriert SHA-256 der Bytes beim Versand - Migration
    // 068, Tabelle chat_image_hashes).
    const imageBytes = Uint8Array.from(atob(imageBase64), (c) => c.charCodeAt(0));
    const photoHashHex = Array.from(
      new Uint8Array(await crypto.subtle.digest("SHA-256", imageBytes)),
    )
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // Lückenfix: NACHWEIS, dass das Bild wirklich zwischen Meldendem und
    // Gemeldetem geflossen ist (sonst könnten beliebige fremde Bilder
    // untergeschoben werden). Die Hash-Registrierung passiert beim Senden
    // (register_chat_image_hash, Migration 068) - nur Hashes, keine Bilder.
    const { data: knownRows, error: knownErr } = await supabaseAdmin
      .from("chat_image_hashes")
      .select("id")
      .or(
        `and(sender_id.eq.${reporter.id},receiver_id.eq.${reportedUserId}),` +
        `and(sender_id.eq.${reportedUserId},receiver_id.eq.${reporter.id})`,
      )
      .eq("photo_hash", photoHashHex)
      .limit(1);
    if (knownErr) {
      console.error("chat_image_hashes lookup failed:", knownErr);
    }
    const knownInChat = !knownErr && (knownRows?.length ?? 0) > 0;
    if (!knownInChat) {
      return new Response(
        JSON.stringify({
          error:
            "Dieses Bild konnte diesem Chat nicht zugeordnet werden. " +
            "Nur tatsächlich in diesem Chat versendete/empfangene Bilder " +
            "können gemeldet werden.",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // 2) DB-Eintrag (Service-Role; Migration 064 + 069).
    // Status: KI-Fund -> rejected (Auto-Bann-Zählung bleibt Client-/Admin-
    // Sache), Eskalation/KI nicht verfügbar -> pending_review (manuelle
    // Prüfung), KI harmless ohne Eskalation -> approved (Dokumentation).
    // Pseudonymisierung (H-06): reporter_id nur als SHA-256-Hash - der
    // Gemeldete könnte seine eigene Zeile via RLS lesen und darf die
    // Identität des Meldenden NICHT sehen.
    const status = ai.available
      ? (ai.nsfw ? "rejected" : (escalate ? "pending_review" : "approved"))
      : "pending_review";
    const reporterHash = Array.from(
      new Uint8Array(
        await crypto.subtle.digest(
          "SHA-256",
          new TextEncoder().encode(reporter.id),
        ),
      ),
    )
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    try {
      await supabaseAdmin.from("photo_moderation").insert({
        user_id: reportedUserId,
        photo_hash: photoHashHex,
        status,
        hf_categories: ai.available ? { nsfw: ai.score } : null,
        hf_label: ai.label,
        reporter_id: reporterHash,
        report_reason: reason,
        report_details: details || null,
        escalated: escalate,
        escalated_at: escalate ? new Date().toISOString() : null,
      });
    } catch (dbErr) {
      console.error("photo_moderation insert failed:", dbErr);
      // Weiter machen - die E-Mail ist das wichtige Element.
    }

    // 3) Betreiber-Mail via Brevo (Bild als Anhang).
    let notified = false;
    if (BREVO_API_KEY) {
      const aiText = ai.available
        ? (ai.nsfw
            ? `Die KI bestätigt die Meldung (unangemessen). NSFW-Score: ${(ai.score * 100).toFixed(1)}% (Label: ${escapeHtml(ai.label)})`
            : `Die KI sieht das Bild NICHT als unangemessen. NSFW-Score: ${(ai.score * 100).toFixed(1)}% (Label: ${escapeHtml(ai.label)})`)
        : "KI-Scan nicht verfügbar (kein Token oder Fehler) - manuelle Prüfung erforderlich.";
      const escalationText = escalate
        ? "<p style='color:#c0392b'><strong>Eskaliert:</strong> Der Meldende hat das Bild trotz KI-Entlastung zur manuellen Prüfung weitergeleitet.</p>"
        : "";
      const now = new Date().toISOString();

      const htmlContent = `<!DOCTYPE html>
<html lang="de"><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#f4f4f8;font-family:'Helvetica Neue',Arial,sans-serif">
<table width="100%" cellpadding="0" cellspacing="0" style="padding:40px 0"><tr><td align="center">
<table width="480" cellpadding="0" cellspacing="0" style="max-width:480px;background:#fff8f5;border-radius:16px;overflow:hidden;box-shadow:0 2px 16px rgba(0,0,0,0.06)">
  <tr><td style="background:linear-gradient(135deg,#ff8fab 0%,#ff6b9d 100%);padding:28px 30px;text-align:center">
    <h1 style="color:#fff;font-size:24px;margin:0;font-weight:600">Bild-Meldung${escalate ? " (eskaliert)" : ""}</h1>
  </td></tr>
  <tr><td style="padding:30px;text-align:left">
    <p style="color:#666;font-size:14px;margin:0 0 12px"><strong>Datum:</strong> ${escapeHtml(now)}</p>
    <p style="color:#666;font-size:14px;margin:0 0 12px"><strong>Gemeldeter Nutzer:</strong> ${escapeHtml(reportedUserId)}</p>
    <p style="color:#666;font-size:14px;margin:0 0 12px"><strong>Meldender Nutzer:</strong> ${escapeHtml(reporter.id)}</p>
    <p style="color:#666;font-size:14px;margin:0 0 12px"><strong>Grund:</strong> ${escapeHtml(reason)}</p>
    ${details ? `<div style="background:#fff;border:1px solid #f0d0d8;border-radius:8px;padding:14px;margin:0 0 16px"><p style="color:#999;font-size:12px;margin:0 0 4px">Details des Meldenden</p><p style="color:#2d2d2d;font-size:14px;margin:0">${escapeHtml(details)}</p></div>` : ""}
    <div style="background:#fff;border:1px solid #f0d0d8;border-radius:8px;padding:14px;margin:0 0 16px">
      <p style="color:#999;font-size:12px;margin:0 0 4px">KI-Ergebnis (automatischer Scan)</p>
      <p style="color:#2d2d2d;font-size:14px;margin:0">${aiText}</p>
    </div>
    ${escalationText}
    <p style="color:#999;font-size:13px;margin:16px 0 0">Das gemeldete Bild ist dieser E-Mail angehängt (reported_image.jpg).</p>
  </td></tr>
  <tr><td style="background:#fdf0ee;padding:18px 30px;text-align:center">
    <p style="color:#b0b0b0;font-size:12px;margin:0">WispDating &middot; Automatische Bild-Moderation</p>
  </td></tr>
</table>
</td></tr></table></body></html>`;

      const brevoResp = await fetch("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: {
          accept: "application/json",
          "api-key": BREVO_API_KEY,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          sender: { email: "moderation@wispdating.de", name: "Wisp Moderation" },
          to: [{ email: MODERATION_EMAIL, name: "Wisp Moderation" }],
          subject: `Bild-Meldung${ai.available && ai.nsfw ? " (KI bestätigt)" : ""}${escalate ? " - eskaliert" : ""} – ${now.slice(0, 10)}`,
          htmlContent,
          attachment: [{ name: "reported_image.jpg", content: imageBase64 }],
        }),
      });
      if (!brevoResp.ok) {
        console.error("Brevo error:", brevoResp.status, await brevoResp.text());
      } else {
        notified = true;
      }
    }

    return new Response(
      JSON.stringify({
        available: ai.available,
        nsfw: ai.nsfw,
        score: ai.score,
        label: ai.label,
        notified,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("Error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
