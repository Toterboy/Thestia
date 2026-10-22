import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

// ICE-Konfiguration fuer WebRTC: STUN (EU).
//
// TURN ist vorerst NICHT aktiv (21.10.2026).
//
// Grund: Es gab keinen Relay-Anbieter, der ohne Kreditkarte und ohne
// Eigenbetrieb nutzbar waere - und ohne TURN funktionieren Anrufe
// hinter symmetrischem NAT oder strengen Firmen-Firewalls nicht. Der
// komplette TURN-Support (Relay-Anbieter, Credential-Modi, mehrere
// Adressen, Datenschutz-Eintrag) steht als Aufgabe auf der Roadmap.
//
// Diese Function liefert daher ausschliesslich STUN-Server. Ueber sie
// fliessen KEINE Inhalte, nur die oeffentliche IP-Adresse fuer den
// Direktverbindungsversuch. Das deckt sich mit Abschnitt 6 der
// Datenschutz-Erklaerung.

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

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  // Defense in Depth: Gateway prueft JWT bereits (config.toml), hier noch
  // einmal explizit verifizieren (Audit W-4).
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Unauthorized" }, 401);
  const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !user) return json({ error: "Invalid token" }, 401);

  // Gueltigkeit der Antwort: die Lebensdauer der STUN-Konfiguration
  // im Client-Cache.
  const ttlSeconds = 3600;

  // STUN-Server in der EU. Ueber sie fliessen keine Inhalte, nur die
  // oeffentliche IP-Adresse fuer den Direktverbindungsversuch.
  const iceServers: Record<string, unknown>[] = [
    { urls: "stun:stun.nextcloud.com:443" },   // Hetzner, DE
    { urls: "stun:stun.miwifi.com:3478" },     // OVH, FR
    { urls: "stun:stun.voipgate.com:3478" },   // DE
    { urls: "stun:stun.voipstunt.com:3478" },  // NL
  ];

  return json({ iceServers, ttlSeconds });
});
