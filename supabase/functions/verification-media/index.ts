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

    const { data: signed, error } = await supabaseAdmin.storage
      .from("verification-videos")
      .createSignedUrl(`${targetUserId}/video.mp4`, URL_EXPIRES_IN);

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
