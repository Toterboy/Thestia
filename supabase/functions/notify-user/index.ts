// Supabase Edge Function: notify-user
//
// Sendet Push-Benachrichtigungen direkt über die FCM-API v1
// (Transport). Verarbeitung/Speicherung der Daten bleibt in der EU
// (Supabase eu-central-1). FCM dient nur als Zustell-Transport.
//
// Aufrufer:
//   1. DB-Trigger (likes/matches via pg_net) mit Header
//      "x-wisp-internal: <WISP_INTERNAL_SECRET>"
//   2. Authentifizierter Client (JWT) – z. B. beim Senden einer
//      Chat-Nachricht (NUR Metadaten, niemals Nachrichteninhalte – E2E).
//
// Die Einzel-Schalter (profiles.notify_matches/likes/messages/dating_hour
// + notifications_enabled) werden VOR dem Versand serverseitig geprüft.
//
// Voraussetzung: kostenloses Firebase-Konto
//   - google-services.json in android/app (Client)
//   - Service-Account-JSON als Secret FIREBASE_SERVICE_ACCOUNT_JSON
//     (Firebase Console -> Project Settings -> Service Accounts ->
//      Generate new private key)
//
// Secrets:
//   WISP_INTERNAL_SECRET          – muss zum Vault-Secret 'wisp_internal_secret'
//                                   passen (Migration 040). KEIN hartcodierter
//                                   Fallback: fehlt das Env, ist die Funktion
//                                   für interne Aufrufe geschlossen (fail-closed).
//   SUPABASE_SECRET_KEYS / SUPABASE_SECRET_KEY – automatisch injizierte
//                                   sb_-Keys (secret_jwt_template ->
//                                   service_role)
//   FIREBASE_SERVICE_ACCOUNT_JSON – Service-Account-Schlüssel (siehe oben)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

const WISP_INTERNAL_SECRET = Deno.env.get("WISP_INTERNAL_SECRET") ?? "";
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

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

/** Constant-time-Vergleich (verhindert Timing-Leaks beim Secret-Check). */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/**
 * M-11 (SSRF-Guard): Der UnifiedPush-Endpunkt ist client-kontrolliert.
 * Vor dem serverseitigen Fetch prüfen: https-only, keine Userinfo,
 * kein IP-Literal/localhost, aufgelöste IPs nicht in privaten/internen
 * Netzen. DNS-Fehler werden fail-closed behandelt.
 */
async function isSafeUpEndpoint(
  rawUrl: string,
): Promise<{ ok: boolean; reason?: string }> {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    return { ok: false, reason: "not_a_url" };
  }
  if (url.protocol !== "https:") return { ok: false, reason: "not_https" };
  if (url.username || url.password) return { ok: false, reason: "userinfo" };
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (!host || host === "localhost" || host.endsWith(".localhost") ||
      host.endsWith(".local") || host.endsWith(".internal")) {
    return { ok: false, reason: "blocked_host" };
  }
  if (/^[0-9.]+$/.test(host)) {
    // IPv4-Literal
    if (isPrivateIPv4(host)) return { ok: false, reason: "private_ip" };
    return { ok: false, reason: "ip_literal_not_allowed" };
  }
  if (host.includes(":")) return { ok: false, reason: "ipv6_literal_not_allowed" };

  // DNS-Auflösung gegen private Bereiche (falls im Edge-Runtime verfügbar).
  try {
    const records = await Deno.resolveDns(host, "A");
    for (const ip of records) {
      if (isPrivateIPv4(ip)) return { ok: false, reason: "resolves_private" };
    }
  } catch {
    // resolveDns nicht verfügbar oder NXDOMAIN -> Hostname-Heuristik genügt;
    // echte Auflösung übernimmt der fetch mit ausgehender Netzkontrolle des
    // Betreibers.
  }
  return { ok: true };
}

function isPrivateIPv4(ip: string): boolean {
  const parts = ip.split(".").map((p) => parseInt(p, 10));
  if (parts.length !== 4 || parts.some((p) => Number.isNaN(p))) return true; // fail-closed
  const [a, b] = parts;
  if (a === 10 || a === 127 || a === 0) return true;
  if (a === 169 && b === 254) return true;         // link-local
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT
  if (a >= 224) return true;                        // multicast/reserved
  return false;
}

/**
 * DB-basiertes Rate-Limit pro Absender (Audit B4).
 * Nutzt die persistente RPC consume_rate_limit (Migration 042) –
 * überlebt Cold Starts und ist über alle Instanzen hinweg gültig.
 */
const RATE_LIMIT_MAX = 20;
const RATE_LIMIT_WINDOW_S = 60;

async function isRateLimited(callerId: string): Promise<boolean> {
  try {
    const { data, error } = await admin.rpc("consume_rate_limit", {
      p_key: `notify-user:${callerId}`,
      p_max_hits: RATE_LIMIT_MAX,
      p_window_seconds: RATE_LIMIT_WINDOW_S,
    });
    if (error) {
      // Fail-closed: Wenn das Limit nicht geprüft werden kann, wird der
      // Versand blockiert (Push ist Best-Effort, kein kritischer Pfad).
      console.error("consume_rate_limit error:", error);
      return true;
    }
    return data !== true;
  } catch (e) {
    console.error("consume_rate_limit exception:", e);
    return true;
  }
}

/** Serverseitig generierte Texte pro kind (kein client-kontrollierter Text). */
const clientTextsByKind: Record<string, { title: string; body: string }> = {
  messages: { title: "WispDating", body: "Du hast eine neue Nachricht erhalten." },
  // v0.9.0-Feedback ("auf dem anderen Gerät passiert gar nichts"): Nach
  // einem QR-Scan/Like soll die gescannte Person einen Push erhalten.
  // Der Text ist serverseitig fix (kein Phishing), die E1-Beziehungs-
  // prüfung unten verlangt einen EIGENEN Like des Aufrufers an das Ziel.
  likes: { title: "WispDating", body: "Jemand hat deine Vorstellung entdeckt." },
};

/**
 * Audit E1: Clients dürfen nur Nutzer benachrichtigen, mit denen eine
 * reale Beziehung besteht (Match zwischen beiden ODER eigener Like an
 * das Ziel ODER aktive Zufallschat-Session ODER offene Dating-Hour-
 * Session). Interne Trigger-Aufrufe sind davon ausgenommen.
 *
 * NUTZERWUNSCH "Ich muss im Chat sein, um Nachrichten zu erhalten":
 * Zufallschat-/Dating-Hour-Partner sind KEINE Matches - ohne diese
 * Erweiterung wurde ihr Nachrichten-Push mit no_relationship
 * abgelehnt, obwohl eine aktive Session existiert.
 */
async function hasRelationshipBetween(
  callerId: string,
  targetUserId: string,
): Promise<boolean> {
  try {
    const { data } = await admin
      .from("matches")
      .select("id")
      .or(
        `and(user_one_id.eq.${callerId},user_two_id.eq.${targetUserId}),` +
          `and(user_one_id.eq.${targetUserId},user_two_id.eq.${callerId})`,
      )
      .limit(1)
      .maybeSingle();
    if (data) return true;

    // Aktive Zufallschat-Session zwischen beiden (Paarung in BEIDEN
    // Richtungen möglich).
    const { data: randomSession } = await admin
      .from("random_chat_sessions")
      .select("id")
      .eq("status", "active")
      .or(
        `and(user_a.eq.${callerId},user_b.eq.${targetUserId}),` +
          `and(user_a.eq.${targetUserId},user_b.eq.${callerId})`,
      )
      .limit(1)
      .maybeSingle();
    if (randomSession) return true;

    // Offene Dating-Hour-Session zwischen beiden.
    const { data: dhSession } = await admin
      .from("dating_hour_session")
      .select("id")
      .is("ended_at", null)
      .or(
        `and(user_a.eq.${callerId},user_b.eq.${targetUserId}),` +
          `and(user_a.eq.${targetUserId},user_b.eq.${callerId})`,
      )
      .limit(1)
      .maybeSingle();
    if (dhSession) return true;

    // Noch kein Match: ein eigener (auch unbeantworteter) Like genügt,
    // damit Like-Benachrichtigungen zustellen können.
    const { data: like } = await admin
      .from("likes")
      .select("id")
      .eq("user_id", callerId)
      .eq("liked_user_id", targetUserId)
      .limit(1)
      .maybeSingle();
    return !!like;
  } catch (e) {
    console.error("relationship check failed:", e);
    // Fail-closed: ohne Beziehungsnachweis wird nicht gepusht.
    return false;
  }
}

/** Erzeugt ein kurzlebiges FCM-Access-Token aus dem Service-Account (JWT-Flow). */
async function getFcmAccessToken(serviceAccountJson: string): Promise<string> {
  const sa = JSON.parse(serviceAccountJson);
  const now = Math.floor(Date.now() / 1000);

  // JWT-Header/Payload (RS256) für Google OAuth.
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri ?? "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const b64 = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const unsigned = `${b64(header)}.${b64(claims)}`;

  // PKCS#8-PEM in CryptoKey umwandeln und signieren.
  const pem = sa.private_key as string;
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(pemBody);
  const keyBytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const assertion = `${unsigned}.${sigB64}`;

  const tokenResp = await fetch(sa.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!tokenResp.ok) {
    throw new Error(`Google-OAuth fehlgeschlagen: ${tokenResp.status} ${await tokenResp.text()}`);
  }
  const tokenData = await tokenResp.json();
  return tokenData.access_token as string;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  // Auth: interner Trigger-Aufruf ODER authentifizierter Client (JWT).
  const internal = req.headers.get("x-wisp-internal") ?? "";
  const isInternal =
    WISP_INTERNAL_SECRET !== "" &&
    internal !== "" &&
    timingSafeEqual(internal, WISP_INTERNAL_SECRET);

  let callerId = "";
  if (!isInternal) {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    try {
      const { data } = await admin.auth.getUser(token);
      if (!data.user) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401, headers: { "Content-Type": "application/json" },
        });
      }
      callerId = data.user.id;
    } catch {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  const targetUserId = String(body.target_user_id ?? "");
  const kind = String(body.kind ?? "");

  if (!targetUserId || !kind) {
    return new Response(JSON.stringify({ error: "Missing target_user_id or kind" }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  // Strikte UUID-Validierung (wie match-media): target_user_id fließt in
  // PostgREST-Filter (.or()-Interpolation) - ohne Prüfung wäre die
  // Beziehungsprüfung theoretisch umlenkbar.
  const UUID_REGEX =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!UUID_REGEX.test(targetUserId)) {
    return new Response(JSON.stringify({ error: "Invalid target_user_id" }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  // Nur internen Aufrufen (DB-Trigger) ist es erlaubt, Titel/Text frei zu
  // wählen. Clients bekommen feste, serverseitig generierte Texte - das
  // verhindert Push-Phishing mit beliebigem Inhalt im App-Look.
  // Rate-Limit gilt für BEIDE Zweige (interner Zweig mit globalem Bucket:
  // Secret-Leak darf nicht zu unbegrenztem Push führen).
  let title: string;
  let text: string;
  if (isInternal) {
    if (await isRateLimited("internal:global")) {
      return new Response(JSON.stringify({ ok: false, reason: "rate_limited" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }
    title = String(body.title ?? "WispDating").slice(0, 100);
    text = String(body.body ?? "").slice(0, 200);
  } else {
    const fixed = clientTextsByKind[kind];
    if (!fixed) {
      // Client darf nur die unterstützten kinds auslösen.
      return new Response(JSON.stringify({ error: "Invalid kind" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }
    if (await isRateLimited(callerId)) {
      return new Response(JSON.stringify({ ok: false, reason: "rate_limited" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }
    // Audit E1: Push nur an Nutzer, mit denen der Aufrufer eine reale
    // Beziehung hat (Match oder eigener Like). Verhindert Belästigung
    // über beliebige target_user_id-Werte.
    if (!(await hasRelationshipBetween(callerId, targetUserId))) {
      return new Response(JSON.stringify({ ok: false, reason: "no_relationship" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }
    title = fixed.title;
    text = fixed.body;
  }

  // Einzel-Schalter + Master serverseitig prüfen (Service-Role, RLS-frei).
  const { data: profile } = await admin
    .from("profiles")
    .select("notifications_enabled, notify_matches, notify_likes, notify_messages, notify_dating_hour, fcm_token, up_endpoint")
    .eq("user_id", targetUserId)
    .maybeSingle();

  if (!profile) {
    return new Response(JSON.stringify({ ok: false, reason: "no_profile" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }
  if (profile.notifications_enabled !== true) {
    return new Response(JSON.stringify({ ok: false, reason: "master_disabled" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }
  const flagByKind: Record<string, string> = {
    matches: "notify_matches",
    likes: "notify_likes",
    messages: "notify_messages",
    dating_hour: "notify_dating_hour",
  };
  const flag = flagByKind[kind];
  if (flag && profile[flag] !== true) {
    return new Response(JSON.stringify({ ok: false, reason: "kind_disabled" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }

  // ---- UnifiedPush (Google-frei, F-Droid-Variante) ----
  // Wenn ein Endpunkt hinterlegt ist, geht der Versand DORTHIN (z. B.
  // eigener ntfy-Server) und FCM wird nicht mehr kontaktiert.
  const upEndpoint = (profile.up_endpoint as string | null)?.trim();
  if (upEndpoint) {
    // M-11 (SSRF-Guard): Endpunkt ist client-kontrolliert. Vor dem Fetch
    // https + Host-Checks + DNS-Auflösung gegen private/interne Netze.
    const endpointSafe = await isSafeUpEndpoint(upEndpoint);
    if (!endpointSafe.ok) {
      console.error("UnifiedPush-Endpunkt abgelehnt:", endpointSafe.reason);
      return new Response(JSON.stringify({ ok: false, reason: "up_invalid" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }
    try {
      const upResp = await fetch(upEndpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title,
          message: text,
          kind,
          from_user_id: isInternal
            ? String((body as Record<string, unknown>).from_user_id ?? "")
            : callerId,
        }),
      });
      if (!upResp.ok) {
        console.error("UnifiedPush-Fehler:", upResp.status, await upResp.text());
        return new Response(JSON.stringify({ ok: false, reason: "up_error" }), {
          status: 200, headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ ok: true, transport: "unifiedpush" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    } catch (e) {
      console.error("UnifiedPush-Exception:", e);
      return new Response(JSON.stringify({ ok: false, reason: "up_error" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }
  }

  const fcmToken = profile.fcm_token;
  if (!fcmToken) {
    return new Response(JSON.stringify({ ok: false, reason: "no_fcm_token" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }

  const serviceAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";
  if (!serviceAccount) {
    console.error("FIREBASE_SERVICE_ACCOUNT_JSON not set");
    return new Response(JSON.stringify({ ok: false, reason: "not_configured" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const accessToken = await getFcmAccessToken(serviceAccount);
    const projectId = (JSON.parse(serviceAccount) as { project_id?: string }).project_id;
    if (!projectId) throw new Error("project_id fehlt im Service-Account");

    // NUTZERWUNSCH ("Benachrichtigung fehlt, wenn App offen"): Die App
    // zeigt FCM-Nachrichten im VORDERGRUND selbst an - dafür braucht sie
    // die Metadaten (kind + Absender), um den push im offenen Chat des
    // Absenders zu unterdrücken. Nur Metadaten (keine Inhalte, E2E).
    const fromUserId = isInternal
      ? String((body as Record<string, unknown>).from_user_id ?? "")
      : callerId;

    const resp = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: { title, body: text },
            data: { kind: kind, from_user_id: fromUserId },
            android: {
              priority: "high",
              // WICHTIG: Ohne icon zeigt Android in der Statusleiste das
              // App-Launcher-Icon (opakes Viereck). Das rund maskierte
              // drawable der App sorgt für das Wisp-Zeichen.
              notification: { icon: "notification_icon" },
            },
          },
        }),
      },
    );
    const respBody = await resp.text();
    if (!resp.ok) {
      console.error("FCM-Send-Fehler:", resp.status, respBody);
      return new Response(JSON.stringify({ ok: false, reason: "fcm_error" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }
    console.log("FCM OK:", respBody.slice(0, 200));
    return new Response(JSON.stringify({ ok: true }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("FCM-Exception:", e);
    return new Response(JSON.stringify({ ok: false, reason: "error" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }
});
