// Supabase Edge Function: /mail-ingest
//
// Nimmt eingehende Mails entgegen und legt sie in public.mail_messages
// ab - der Admin-Bereich zeigt sie danach an (v0.10.0, Migration 168).
//
// ZWEI EINGANGSWEGE, beide mit demselben Aufruf:
//
//   1) tool/mail_imap_poll.py (IMAP-Abfrage)
//   2) deploy/cloudflare/email-worker.js (Cloudflare Email Worker)
//
// Beide schicken dieselbe Struktur. Undurchsicht ist die Message-ID:
// darueber wird verhindert, dass dieselbe Mail zweimal gespeichert wird.
//
// AUTH: nur mit dem internen Secret (x-thestia-internal). Die Funktion
// schreibt mit der Service-Rolle - sonst wuerde jeder Client Mails in
// die Datenbank schreiben koennen.
//
// ES GIBT KEINE ANTWORTFUNKTION. Diese Funktion nimmt Mails an und
// speichert sie. Sie sendet nichts, und es gibt hier auch keinen Weg
// dazu - ein Antwortpfad aus der App heraus waere eine zweite
// Absenderidentitaet und eine zweite, unprotokollierte Kopie der
// Korrespondenz.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

const INTERNAL_SECRET = Deno.env.get("THESTIA_INTERNAL_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";

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

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** HTML zu Text - fuer die Anzeige im Admin-Bereich.
 *
 *  Das ist KEINE vollstaendige HTML-Analyse. Es reicht fuer die Anzeige:
 *  Block-Tags werden zu Zeilenumbruechen, Tags fliegen raus, und die
 *  haeufigsten Entities werden uebersetzt. */
function htmlZuText(html: string): string {
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|tr|li|h[1-6])>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
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

  const recipient = String(body.recipient ?? "").trim().toLowerCase();
  if (!recipient || !recipient.includes("@")) {
    return json({ error: "recipient_missing" }, 400);
  }

  const text = String(body.text ?? "");
  const html = String(body.html ?? "");
  const inhalt = text.trim().length > 0 ? text : htmlZuText(html);

  // Laenge begrenzen: eine Mail kann gross sein (danhaengende Datei,
  // Newsletter). Der Anzeigetext soll nicht das Datenbank-Feld
  // aufblaehen.
  const MAX = 20000;
  const gekuerzt = inhalt.length > MAX ? inhalt.slice(0, MAX) : inhalt;

  const eingang = body.receivedAt
    ? String(body.receivedAt)
    : new Date().toISOString();

  const { data, error } = await supabaseAdmin
    .from("mail_messages")
    .insert({
      recipient,
      message_id: body.messageId ? String(body.messageId) : null,
      from_email: body.from ? String(body.from) : null,
      from_name: body.fromName ? String(body.fromName) : null,
      subject: body.subject ? String(body.subject) : null,
      body_text: gekuerzt,
      received_at: eingang,
      source: body.source === "cloudflare" ? "cloudflare" : "imap",
      size_bytes: body.sizeBytes ? Number(body.sizeBytes) : gekuerzt.length,
    })
    .select("id, category")
    .single();

  if (error) {
    // Der UNIQUE-Index auf message_id: dieselbe Mail noch einmal. Das
    // ist kein Fehler, sondern der Normalfall, wenn IMAP und Worker
    // dieselbe Mail liefern.
    if (String(error.code) === "23505") {
      return json({ ok: true, duplicate: true });
    }
    console.error("mail-ingest: insert fehlgeschlagen:", error);
    return json({ error: "insert_failed" }, 500);
  }

  return json({ ok: true, id: (data as { id?: number } | null)?.id ?? null });
});
