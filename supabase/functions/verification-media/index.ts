import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

// Supabase Edge Function: verification-media
//
// Liefert eine KURZLEBIGE signierte URL fuer das Verifizierungs-Video
// eines Nutzers - ausschliesslich fuer ADMIN-Pruefung (serverseitiger
// is_admin-Check). Der Bucket ist privat; ohne diese Funktion ist das
// Video fuer niemanden erreichbar (kein oeffentlicher Zugriff, keine
// Storage-Policy fuer Fremde).
//
// Der Nutzer selbst sieht sein eigenes Video nur im lokalen Review-Flow
// vor dem Upload; nach dem Einreichen benoetigt er die URL nicht mehr.

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

/** Base64-dekodiert; liefert null bei ungueltigem Input. */
function atobSafe(b64: string): Uint8Array | null {
  try {
    const raw = atob(b64);
    const out = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Kurze Lebensdauer: Der Admin schaut das Video unmittelbar an.
const URL_EXPIRES_IN = 600;

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }

    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }

    // Serverseitiger Admin-Check (fail-closed).
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("is_admin")
      .eq("user_id", user.id)
      .maybeSingle();
    if (!profile || profile.is_admin !== true) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403, headers: { "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const targetUserId = String(body.targetUserId ?? "");
    if (!UUID_REGEX.test(targetUserId)) {
      return new Response(JSON.stringify({ error: "targetUserId (uuid) required" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    // v0.10.0 (Migration 151): Das Video liegt VERSCHLUESSELT im Bucket.
    //
    // Der Chiffrat wird hier entschluesselt und als Klartext-Vorschau
    // unter einem zweiten Pfad abgelegt. Der Admin bekommt eine
    // signierte URL DARAUF - so bleibt der Browser-Pfad unveraendert.
    //
    // Warum eine Vorschau und nicht direkt der Chiffrat: Der Browser
    // kann kein Chiffrat abspielen. Die Vorschau ist eine
    // Klartextdatei im SELBEN privaten Bucket, sie wird aber per Cron
    // (cleanup-verification-previews) nach kurzer Zeit wieder entfernt.
    // Der Dauerzustand im Bucket ist damit ausschliesslich Chiffrat.
    const { data: cipherFile, error: cipherError } = await supabaseAdmin.storage
      .from("verification-videos")
      .download(`${targetUserId}/video.mp4.enc`);

    if (cipherError || !cipherFile) {
      return new Response(JSON.stringify({ error: "Video nicht gefunden" }), {
        status: 404, headers: { "Content-Type": "application/json" },
      });
    }

    // Schluessel holen. Die Tabelle hat keine Policy fuer den Client -
    // nur service_role (also diese Function) kommt hierher.
    const { data: keyRow, error: keyError } = await supabaseAdmin
      .from("verification_video_keys")
      .select("key_b64, iv_b64")
      .eq("user_id", targetUserId)
      .maybeSingle();

    if (keyError || !keyRow) {
      return new Response(
        JSON.stringify({ error: "Video-Schluessel fehlt" }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    const keyBytes = atobSafe(keyRow.key_b64);
    const ivBytes = atobSafe(keyRow.iv_b64);
    if (!keyBytes || !ivBytes) {
      return new Response(
        JSON.stringify({ error: "Video-Schluessel ungueltig" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // AES-256-GCM entschluesseln. Das Auth-Tag haengt am Ciphertext -
    // so liefert es der Dart-Client (pointycastle) und so erwartet es
    // WebCrypto hier. Bei Manipulation schlaegt decrypt fehl.
    let plain: ArrayBuffer;
    try {
      const cryptoKey = await crypto.subtle.importKey(
        "raw",
        keyBytes,
        { name: "AES-GCM" },
        false,
        ["decrypt"],
      );
      plain = await crypto.subtle.decrypt(
        { name: "AES-GCM", iv: ivBytes, tagLength: 128 },
        cryptoKey,
        await cipherFile.arrayBuffer(),
      );
    } catch (e) {
      console.error("Entschluesselung fehlgeschlagen:", e);
      return new Response(
        JSON.stringify({ error: "Video nicht lesbar" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // Vorschau ablegen. Der Pfad endet auf .preview.mp4 und wird vom
    // Cron nach wenigen Minuten wieder geloescht.
    const previewPath = `${targetUserId}/preview.mp4`;
    const { error: uploadError } = await supabaseAdmin.storage
      .from("verification-videos")
      .uploadBinary(previewPath, new Uint8Array(plain), {
        contentType: "video/mp4",
        upsert: true,
      });
    if (uploadError) {
      console.error("Vorschau nicht ablegbar:", uploadError);
      return new Response(
        JSON.stringify({ error: "Video nicht abspielbar" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    const { data: signed, error } = await supabaseAdmin.storage
      .from("verification-videos")
      .createSignedUrl(previewPath, URL_EXPIRES_IN);

    if (error || !signed) {
      return new Response(JSON.stringify({ error: "Video nicht gefunden" }), {
        status: 404, headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({ url: signed.signedUrl, expiresIn: URL_EXPIRES_IN }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("Error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
