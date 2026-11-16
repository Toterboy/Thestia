import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

// ICE-Konfiguration fuer WebRTC: STUN und (optional) TURN.
//
// TURN (21.10.2026, Audit 16.11.2026):
// Bis jetzt lieferte diese Function ausschliesslich oeffentliche
// STUN-Server. Zwei Probleme:
//
//  1) Der Binding-Request geht im KLARTEXT an den STUN-Betreiber. Der
//     Betreiber sieht die IP-Adresse des Nutzers (und jeder Beobachter
//     im Netzpfad). Das ist in der Datenschutz-Erklaerung offengelegt.
//
//  2) Mit TURN (eigener Relay-Server) fallen zwei Dinge weg: die
//     Offenlegung an Dritte und der Betrieb hinter symmetrischem NAT.
//
//     Vorher fehlte dafuer das GESAMTE Konzept: es gab keine kurzen
//     Credentials, keine Ablaufzeit, keinen Rotationsmechanismus.
//     Jetzt ist es da: sobald TURN_SHARED_SECRET gesetzt ist, liefert
//     die Function kurzlebige HMAC-Credentials (coturn-REST-Format).
//     Ohne das Secret bleibt das Verhalten unveraendert (nur STUN).
//
// DIE CREDENTIALS (coturn "REST API"-Verfahren):
//   username    = "<Ablaufzeit>:<Nutzerkennung>"
//   credential  = base64(HMAC-SHA1(sharedSecret, username))
// Der Turn-Server prueft die Signatur und die Ablaufzeit selbst - der
// Schluessel liegt NIE beim Client und wird auch nicht uebertragen.
//
// Sicherheitsregeln:
//   * Das Secret kommt aus der Umgebung (Vault) - nie aus dem Repo.
//   * Die Credentials leben hoechstens eine Stunde (TTL unten).
//   * Der Client bekommt kein Fallback auf abgelaufene Credentials
//     (siehe lib/services/webrtc_service.dart).

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

/** Die STUN-Server (oeffentlich, EU). Ueber sie fliessen keine Inhalte,
 *  nur die oeffentliche IP-Adresse fuer den Direktverbindungsversuch. */
const STUN_SERVERS = [
  { urls: "stun:stun.nextcloud.com:443" },   // Hetzner, DE
  { urls: "stun:stun.miwifi.com:3478" },     // OVH, FR
  { urls: "stun:stun.voipgate.com:3478" },   // DE
  { urls: "stun:stun.voipstunt.com:3478" },  // NL
];

/** Die TURN-Server (eigener Betrieb). Leer = TURN ist nicht eingerichtet. */
function _turnUrls(): string[] {
  const roh = Deno.env.get("TURN_URLS") ?? "";
  return roh
    .split(",")
    .map((e) => e.trim())
    .filter((e) => e.length > 0);
}

/**
 * Erzeugt ein kurzlebiges TURN-Credential (coturn-REST-Verfahren).
 *
 * @param secret   Das gemeinsame Geheimnis (TURN_SHARED_SECRET)
 * @param identity Die Nutzerkennung (z. B. die User-ID)
 * @param ttlSeconds Lebensdauer in Sekunden
 */
async function _turnCredential(
  secret: string,
  identity: string,
  ttlSeconds: number,
): Promise<{ username: string; credential: string }> {
  const ablauf = Math.floor(Date.now() / 1000) + ttlSeconds;
  const username = `${ablauf}:${identity}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const signatur = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(username),
  );
  const bytes = new Uint8Array(signatur);
  let binaer = "";
  for (const b of bytes) binaer += String.fromCharCode(b);
  return {
    username,
    credential: btoa(binaer),
  };
}

serve(async (req) => {
  // Defense in Depth: Gateway prueft JWT bereits (config.toml), hier noch
  // einmal explizit verifizieren (Audit W-4).
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Unauthorized" }, 401);
  const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !user) return json({ error: "Invalid token" }, 401);

  // Gueltigkeit der Antwort: die Lebensdauer der ICE-Konfiguration
  // im Client-Cache. Bei TURN muss sie KURZER sein als die Lebensdauer
  // der Credentials - sonst liege im Cache ein abgelaufenes Credential.
  const ttlSeconds = 3600;

  const iceServers: Record<string, unknown>[] = [...STUN_SERVERS];

  // TURN (optional): nur wenn Secret UND Server-URL gesetzt sind.
  const turnSecret = Deno.env.get("TURN_SHARED_SECRET") ?? "";
  const turnUrls = _turnUrls();
  if (turnSecret.length > 0 && turnUrls.length > 0) {
    // Die Credential-Lebensdauer ist kuerzer als die Cache-Frist: die
    // Credentials sind 55 Minuten gueltig, der Cache haelt 60.
    const credentialTtl = 55 * 60;
    const { username, credential } = await _turnCredential(
      turnSecret,
      user.id,
      credentialTtl,
    );
    for (const url of turnUrls) {
      iceServers.push({
        urls: url,
        username,
        credential,
      });
    }
  }

  return json({ iceServers, ttlSeconds });
});
