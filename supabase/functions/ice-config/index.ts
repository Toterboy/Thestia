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
// Ohne TURN_URL (oder ohne passende Zugangsdaten) verhält sich die
// Funktion wie bisher (nur STUN).
//
// Hinweis zur Zieladresse: TURN braucht eine TURN-Adresse im Format
// turn:host:port oder turns:host:port. Eine wss://-Adresse ist KEIN
// ICE-Server, sondern ein Signalisierungskanal - darueber laesst sich
// kein Medienstrom routen. Bei den geprueften Anbietern war nur
// relay.metered.ca:80 als TURN-Host erreichbar (STUN-Antwort
// verifiziert); openrelay.metered.ca zeigt auf Test-Net-Adressen
// (192.0.2.1 / 100::1) und ist nicht direkt benutzbar.

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

// TURN-Konfiguration. ZWEI Modi, weil die Anbieter verschiedene
// Zugangsdaten liefern:
//
//   * TURN_SECRET (geteiltes Geheimnis): Die Function erzeugt
//     kurzlebige REST-Credentials (Benutzername = Ablaufzeit, Kennwort
//     = HMAC-SHA1 ueber das Geheimnis). Das ist das Schema von
//     coturn mit use-auth-secret. KURZLIEBIG, besser.
//
//   * TURN_USERNAME + TURN_CREDENTIAL (statisch): Manche Anbieter
//     geben im Dashboard feste Zugangsdaten aus. Die Function reicht
//     sie unveraendert durch.
//
// Es gilt, was gesetzt ist: mit TURN_SECRET wird der REST-Modus
// benutzt, sonst der statische. Ohne beides bleibt es bei STUN.
//
// TURN_URL kann MEHERE Adressen enthalten, kommagetrennt. Jede wird
// als eigener ICE-Server-Eintrag geliefert - der Client probiert sie
// durch, und ein Relay, das von einer Firewall blockiert wird, faellt
// nicht gleich auf, weil ein zweiter daneben steht.
const TURN_URL = Deno.env.get("TURN_URL") ?? "";
const TURN_SECRET = Deno.env.get("TURN_SECRET") ?? "";
const TURN_USERNAME = Deno.env.get("TURN_USERNAME") ?? "";
const TURN_CREDENTIAL = Deno.env.get("TURN_CREDENTIAL") ?? "";
const TURN_TTL = Number(Deno.env.get("TURN_TTL") ?? "3600") || 3600;

const TURN_URLS = TURN_URL.split(",")
  .map((u) => u.trim())
  .filter((u) => u.length > 0);

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

  // Optionaler TURN-Relay.
  //
  // REST-Modus (TURN_SECRET gesetzt): kurzlebige Credentials, die
  // nur fuer die Laufzeit des Tokens gelten. Der Benutzername traegt
  // die Nutzer-ID, damit ein Relay-Mitschnitt nachvollziehbar bleibt,
  // ohne dass der Server etwas ueber den Nutzer wissen muss, was
  // nicht im Token steht.
  if (TURN_URLS.length > 0 && TURN_SECRET) {
    const username = `${Math.floor(Date.now() / 1000) + ttlSeconds}:${user.id}`;
    const credential = await hmacSha1Base64(TURN_SECRET, username);
    for (const url of TURN_URLS) {
      iceServers.push({ urls: url, username, credential });
    }
  } else if (TURN_URLS.length > 0 && TURN_USERNAME && TURN_CREDENTIAL) {
    // Statischer Modus: feste Zugangsdaten aus dem Dashboard.
    for (const url of TURN_URLS) {
      iceServers.push({
        urls: url,
        username: TURN_USERNAME,
        credential: TURN_CREDENTIAL,
      });
    }
  }

  return json({ iceServers, ttlSeconds });
});
