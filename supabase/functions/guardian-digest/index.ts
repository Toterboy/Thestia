// Supabase Edge Function: /guardian-digest
//
// Buendelt die Funken-Ereignisse fuer die Sorgeberechtigten und
// verschickt sie als E-Mail (v0.10.0, Migration 165).
//
// AUFRUF: nur aus der Datenbank (pg_cron -> run_guardian_digest ->
// net.http_post) mit dem internen Secret. verify_jwt = false in
// supabase/config.toml, die eigene Pruefung passiert hier.
//
// WAS IN DER MAIL STEHT - UND WAS NICHT:
//
//   Enthalten: die Anzahl der entstandenen Funken, der Zeitraum, ein
//   Link zum Portal.
//
//   NICHT enthalten: Name, Alter, Profil, Standort, Bild oder Inhalte
//   der anderen Person. Die Vorgabe des Betreibers lautet, dass die
//   Eltern "nicht zu sehr in die Privatsphaere der Jugendlichen
//   eindringen" sollen. Ein Funke ist ein Ereignis, keine Einladung
//   zur Spionage: der Elternteil erfaehrt, DASS etwas passiert ist.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const INTERNAL_SECRET = Deno.env.get("THESTIA_INTERNAL_SECRET") ?? "";
const SENDER_EMAIL = "support@thestia.de";
const SENDER_NAME = "Thestia";
const PORTAL_URL = "https://auth.thestia.de/eltern";

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

const PERIOD_LABEL: Record<string, string> = {
  daily: "Tag",
  weekly: "Woche",
  monthly: "Monat",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

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

  const guardianEmail = String(body.guardianEmail ?? "");
  const period = String(body.period ?? "weekly");
  const count = Number(body.count ?? 0);
  if (!guardianEmail || !Number.isFinite(count) || count <= 0) {
    // Nichts zu senden. Der Digest wird nur bei mindestens einem Ereignis
    // verschickt - eine leere Mail jeden Tag waere nur Aerger.
    return json({ ok: true, skipped: true });
  }

  const label = PERIOD_LABEL[period] ?? "Zeitraum";
  const anzahl = count === 1 ? "ein neuer Funke" : `${count} neue Funken`;
  const link = `${PORTAL_URL}`;

  const html = `<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Thestia - Nachricht für Sorgeberechtigte</title>
</head>
<body style="margin:0;padding:0;background:#f4f0f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f0f7;padding:24px 12px">
<tr><td align="center">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:16px;overflow:hidden">
<tr><td style="background:#5b3fa8;padding:28px 30px">
  <h1 style="margin:0;color:#ffffff;font-size:22px;font-weight:700">Kurz aus Thestia</h1>
</td></tr>
<tr><td style="padding:30px;color:#2d2d2d;font-size:15px;line-height:1.65">
<p>Hallo,</p>
<p>im Zeitraum einer <strong>${escapeHtml(label)}</strong> ist ${escapeHtml(anzahl)} entstanden.</p>

<div style="background:#f7f5fa;border-radius:10px;padding:14px 16px;margin:22px 0">
  <p style="margin:0;color:#55555f;font-size:14px;line-height:1.6">
  Wir schicken dir bewusst <strong>keine Namen und keine Profile</strong>.
  Ein Funke bedeutet, dass zwei Menschen sich gegenseitig ausgewählt haben -
  wer das war, bleibt im Account deines Kindes.
  </p>
</div>

<p>Wie oft du diese Nachrichten bekommst, bestimmst du selbst:
<a href="${escapeHtml(link)}" style="color:#5b3fa8">Einstellungen öffnen</a>.
Dort kannst du auch die Nutzungszeit begrenzen und die Freigabe jederzeit
widerrufen.</p>
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

  if (BREVO_API_KEY === "") {
    console.error("guardian-digest: BREVO_API_KEY fehlt - kein Versand.");
    return json({ ok: false, error: "missing_key" }, 500);
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
      to: [{ email: guardianEmail }],
      subject: count === 1
        ? "Kurz aus Thestia: ein neuer Funke"
        : `Kurz aus Thestia: ${count} neue Funken`,
      htmlContent: html,
    }),
  });

  if (!resp.ok) {
    console.error(
      "guardian-digest: Brevo-Fehler",
      resp.status,
      await resp.text(),
    );
    return json({ ok: false }, 502);
  }

  return json({ ok: true });
});
