import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

// ICE-Konfiguration: STUN (EU) + OPTIONALER TURN-Relay (Audit M-10).
//
// TURN ist die wichtigste Maßnahme gegen IP-Lecks an den Peer und für
// Konnektivität hinter symmetrischen NATs. Statische Credentials werden
// NICHT unterstützt; stattdessen werden kurzlebige TURN-REST-Credentials
// (coturn `use-auth-secret`) generiert, falls konfiguriert:
//
//   TURN_URL      z. B. "turn:turn.example.com:3478?transport=udp"
//   TURN_SECRET   Shared Secret des coturn (NUR hier serverseitig!)
//   TURN_TTL      Gültigkeit der Credentials in Sekunden (Default 3600)
//
// Ohne TURN_URL verhält sich die Funktion wie bisher (nur STUN).

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

const TURN_URL = Deno.env.get("TURN_URL") ?? "";
const TURN_SECRET = Deno.env.get("TURN_SECRET") ?? "";
const TURN_TTL = Number(Deno.env.get("TURN_TTL") ?? "3600") || 3600;

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function hmacSha1Base64(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  // Defense in Depth: Gateway prüft JWT bereits (config.toml), hier noch
  // einmal explizit verifizieren (Audit W-4).
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Unauthorized" }, 401);
  const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !user) return json({ error: "Invalid token" }, 401);

  const ttlSeconds = TURN_TTL;
  const iceServers: Record<string, unknown>[] = [
    { urls: "stun:stun.nextcloud.com:443" },   // Hetzner, DE
    { urls: "stun:stun.miwifi.com:3478" },     // OVH, FR
    { urls: "stun:stun.voipgate.com:3478" },   // DE
    { urls: "stun:stun.voipstunt.com:3478" },  // NL
  ];

  // Optionaler TURN-Relay mit kurzlebigen REST-Credentials.
  if (TURN_URL && TURN_SECRET) {
    const username = `${Math.floor(Date.now() / 1000) + ttlSeconds}:${user.id}`;
    const credential = await hmacSha1Base64(TURN_SECRET, username);
    iceServers.push({ urls: TURN_URL, username, credential });
  }

  return json({ iceServers, ttlSeconds });
});
