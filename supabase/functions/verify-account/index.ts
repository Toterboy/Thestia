import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

// Supabase Edge Function: verify-account
//
// Drei Aktionen (body.action):
//   "submit"  – Eingeloggter Nutzer reicht sein Verifizierungs-Video ein.
//               Das Video wurde VORHER direkt in den privaten Bucket
//               `verification-videos/<userId>/video.mp4` hochgeladen
//               (Storage-Policy erlaubt nur den eigenen Ordner). Hier
//               wird nur der Pfad + Status 'pending' vermerkt. Optional
//               kann die lokale KI-Schätzung mitgegeben werden
//               (estimatedAge, faceCount) – sie landet ausschließlich als
//               Orientierung für die manuelle Prüfung in
//               `verification_estimated_age`.
//   "auto"    – KI-Triage unauffällig (Abweichung <= 2 Jahre, genau
//               1 Gesicht, Liveness ok): Das Video BLEIBT für Stichproben
//               erhalten, der Nutzer erhält sofort das Badge (Status
//               'auto'). Die Regel wird serverseitig nachgeprüft.
//               EHRlichkeitshinweis: Die lokale Prüfung ist ein Filter,
//               kein Beweis – modifizierte Clients könnten lügen. Deshalb
//               bleiben Video + Stichproben + manuelle Queue bestehen.
//   "review"  – Nur ADMIN-Nutzer (profiles.is_admin, serverseitig
//               gepflegt) setzen isVerified des Ziel-Nutzers und den
//               Verifizierungsstatus (approved/rejected). Bei Ablehnung
//               wird der Video-Pfad entfernt; das Objekt im Bucket
//               loescht die Funktion gleich mit.
//
// SICHERHEIT (Audit K2): isVerified kann NIEMALS vom Client frei gesetzt
// werden - review erfordert serverseitige Admin-Pruefung, auto die
// serverseitig nachgeprüfte 2-Jahre-Regel.

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

// DB-basiertes Rate-Limit pro Nutzer (Muster wie notify-user): Einreichungen
// sind selten - 10/h reichen dicke und stoppen Submit-Spam. Fail-open bei
// RPC-Fehlern (kein Lock-out durch Infra-Probleme), fail-closed bei
// erreichtem Limit.
async function isRateLimited(userId: string): Promise<boolean> {
  try {
    const { data, error } = await supabaseAdmin.rpc("consume_rate_limit", {
      p_key: `verify-account:${userId}`,
      p_max_hits: 10,
      p_window_seconds: 3600,
    });
    if (error) {
      console.error("consume_rate_limit error:", error);
      return false;
    }
    return data !== true;
  } catch (e) {
    console.error("consume_rate_limit exception:", e);
    return false;
  }
}

// Angegebenes Alter aus dem Geburtsdatum (vollendete Jahre).
function statedAgeFromBirthDate(birthDate: string | null): number | null {
  if (!birthDate) return null;
  const born = new Date(birthDate);
  if (Number.isNaN(born.getTime())) return null;
  const now = new Date();
  let age = now.getUTCFullYear() - born.getUTCFullYear();
  const m = now.getUTCMonth() - born.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < born.getUTCDate())) age--;
  return age;
}

async function isAdminUser(userId: string): Promise<boolean> {
  const { data: profile } = await supabaseAdmin
    .from("profiles")
    .select("is_admin")
    .eq("user_id", userId)
    .maybeSingle();
  return profile?.is_admin === true;
}

// ------------------------------------------------------------------
// Play Integrity (v0.9.0, Manipulationsschutz).
//
// Play-Builds schicken integrityToken + integrityNonce mit (action
// "auto"). Der Server prüft das Verdict bei Google: Nur
// PLAY_RECOGNIZED-Apps auf integeren Geräten (DEVICE oder STRONG)
// mit passendem Package + Nonce + frischem Zeitstempel bestehen.
// Alles andere (fehlgeschlagenes Verdict, abgelaufen, SA nicht
// konfiguriert) landet in der manuellen Prüfung (422) - fail-closed
// dorthin, nie harter Fehler. KEIN Token (F-Droid, iOS, alte Builds)
// = bisheriges Verhalten; die Stichprobe (Migration 120) bleibt Netz.
//
// Setup (Betreiber): Google-Cloud-Projekt mit der Play-App verknüpfen
// (Play Console -> App-Integrität), Service-Account + JSON-Key, als
// Function-Secret PLAY_INTEGRITY_SA_JSON hinterlegen. Siehe
// docs/PLAY_INTEGRITY.md.
// ------------------------------------------------------------------
const PLAY_PACKAGE_NAME = "com.thestia.app";
const PLAY_INTEGRITY_DECODE_URL =
  "https://playintegrity.googleapis.com/v1/" + PLAY_PACKAGE_NAME +
  ":decodeIntegrityToken";

let _playAuthCache: { token: string; expMs: number } | null = null;

function b64urlEncode(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlDecodeToBytes(s: string): Uint8Array {
  const norm = s.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(norm);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function playIntegrityAccessToken(
  saJson: string,
): Promise<string | null> {
  const now = Date.now();
  if (_playAuthCache && _playAuthCache.expMs - 60000 > now) {
    return _playAuthCache.token;
  }
  let sa: { client_email?: string; private_key?: string };
  try {
    sa = JSON.parse(saJson);
  } catch {
    console.error("integrity: PLAY_INTEGRITY_SA_JSON ungueltig");
    return null;
  }
  if (!sa.client_email || !sa.private_key) {
    console.error("integrity: SA ohne client_email/private_key");
    return null;
  }
  const header = b64urlEncode(
    new TextEncoder().encode(JSON.stringify({
      alg: "RS256",
      typ: "JWT",
    })),
  );
  const claims = b64urlEncode(
    new TextEncoder().encode(JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/playintegrity",
      aud: "https://oauth2.googleapis.com/token",
      iat: Math.floor(now / 1000),
      exp: Math.floor(now / 1000) + 3600,
    })),
  );
  const pem = sa.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    b64urlDecodeToBytes(pem).buffer as ArrayBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion =
    `${header}.${claims}.${b64urlEncode(new Uint8Array(sig))}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" +
      encodeURIComponent(assertion),
  });
  if (!res.ok) {
    console.error("integrity: token exchange", res.status);
    return null;
  }
  const data = await res.json();
  if (typeof data.access_token !== "string") return null;
  _playAuthCache = { token: data.access_token, expMs: now + 3500 * 1000 };
  return data.access_token;
}

async function verifyPlayIntegrity(
  token: string,
  nonce: string,
): Promise<boolean> {
  try {
    const saJson = Deno.env.get("PLAY_INTEGRITY_SA_JSON") ?? "";
    if (!saJson) {
      // Betreiber-Setup fehlt: laut loggen, Auto ablehnen (manuelle
      // Queue greift). Kein stilles Fail-open.
      console.error(
        "integrity: PLAY_INTEGRITY_SA_JSON fehlt - Auto abgelehnt",
      );
      return false;
    }
    const access = await playIntegrityAccessToken(saJson);
    if (!access) return false;
    const res = await fetch(PLAY_INTEGRITY_DECODE_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${access}`,
      },
      body: JSON.stringify({ integrityToken: token }),
    });
    if (!res.ok) {
      console.error("integrity: decode", res.status);
      return false;
    }
    const v = await res.json();
    const appVerdict = v?.appRecognitionVerdict?.appRecognitionVerdict;
    const deviceVerdicts: string[] =
      v?.deviceRecognitionVerdict?.deviceRecognitionVerdict ?? [];
    const req = v?.requestDetails ?? {};
    if (appVerdict !== "PLAY_RECOGNIZED") {
      console.error("integrity: app verdict", appVerdict);
      return false;
    }
    if (
      !deviceVerdicts.includes("MEETS_DEVICE_INTEGRITY") &&
      !deviceVerdicts.includes("MEETS_STRONG_INTEGRITY")
    ) {
      console.error("integrity: device verdict", deviceVerdicts);
      return false;
    }
    if (req.packageName !== PLAY_PACKAGE_NAME || req.nonce !== nonce) {
      console.error("integrity: package/nonce mismatch");
      return false;
    }
    const reqMs = Number(req.requestTimeMillis ?? 0);
    if (!Number.isFinite(reqMs) || Date.now() - reqMs > 10 * 60 * 1000) {
      console.error("integrity: stale token");
      return false;
    }
    return true;
  } catch (e) {
    console.error("integrity: exception", e);
    return false;
  }
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    // Aufrufer aus JWT bestimmen - serverseitig verifiziert.
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

    const body = await req.json();
    const action = String(body.action ?? "review");

    // ------------------------------------------------------------------
    // Aktion: Eigene Einreichung (kein Admin noetig).
    // ------------------------------------------------------------------
    if (action === "submit") {
      if (await isRateLimited(user.id)) {
        return new Response(
          JSON.stringify({ error: "Zu viele Versuche, bitte spaeter erneut." }),
          { status: 429, headers: { "Content-Type": "application/json" } },
        );
      }
      // Der Pfad kommt NICHT aus dem Body - er wird serverseitig aus dem
      // JWT-Subject gebaut. Manipulierte Pfade sind damit unmoeglich.
      const videoPath = `${user.id}/video.mp4`;

      // Existiert das hochgeladene Objekt wirklich?
      const { data: obj } = await supabaseAdmin.storage
        .from("verification-videos")
        .list(user.id, { limit: 10 });
      if (!obj || !obj.some((o) => o.name === "video.mp4")) {
        return new Response(
          JSON.stringify({ error: "Video nicht gefunden (Upload fehlt)" }),
          { status: 400, headers: { "Content-Type": "application/json" } },
        );
      }

      // Optionale KI-Schaetzung (nur Orientierung fuer die manuelle
      // Pruefung, Plausibilitaets-Grenzen werden serverseitig geprüft).
      const rawEstimate = Number(body.estimatedAge);
      const rawFaces = Number(body.faceCount);
      const estimatedAge = Number.isFinite(rawEstimate)
        ? Math.round(rawEstimate)
        : null;
      const faceCount = Number.isFinite(rawFaces)
        ? Math.round(rawFaces)
        : null;
      const estimateOk = estimatedAge !== null && estimatedAge >= 5 &&
        estimatedAge <= 120 && faceCount !== null && faceCount >= 0 &&
        faceCount <= 10;

      const { error: updateError } = await supabaseAdmin
        .from("profiles")
        .update({
          verification_video_path: videoPath,
          verification_status: "pending",
          ...(estimateOk ? { verification_estimated_age: estimatedAge } : {}),
        })
        .eq("user_id", user.id);

      if (updateError) {
        console.error("Submit update error:", updateError);
        return new Response(JSON.stringify({ error: "Update failed" }), {
          status: 500, headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ ok: true, status: "pending" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }

    // ------------------------------------------------------------------
    // Aktion: Auto (KI-Triage unauffaellig, 095).
    //
    // Voraussetzungen (alle serverseitig nachgeprueft):
    //   - Video-Objekt existiert (gegen leere Auto-Calls),
    //   - genau 1 Gesicht, Liveness ok (Client-Claim),
    //   - Abweichung |KI - angegebenes Alter| <= 2 Jahre,
    //   - Play Integrity (v0.9.0): WENN ein Token mitgeschickt wurde
    //     (nur Play-Builds), MUSS das Google-Verdict bestehen, sonst
    //     manuelle Prüfung. KEIN Token (F-Droid, iOS, alte Builds)
    //     ändert nichts - die Stichprobe (Migration 120) bleibt das Netz.
    //   - aktueller Status 'none' oder 'rejected' (kein Ueberspringen
    //     einer laufenden manuellen Pruefung, kein Doppel-Badge).
    // Wirkung: Badge sofort (is_verified), Status 'auto', Video bleibt
    // fuer Stichproben erhalten.
    // ------------------------------------------------------------------
    if (action === "auto") {
      if (await isRateLimited(user.id)) {
        return new Response(
          JSON.stringify({ error: "Zu viele Versuche, bitte spaeter erneut." }),
          { status: 429, headers: { "Content-Type": "application/json" } },
        );
      }
      const estimatedAge = Math.round(Number(body.estimatedAge));
      const faceCount = Math.round(Number(body.faceCount));
      const livenessOk = body.liveness === true;

      if (
        !Number.isFinite(estimatedAge) || estimatedAge < 5 ||
        estimatedAge > 120 || !Number.isFinite(faceCount) ||
        !livenessOk
      ) {
        return new Response(
          JSON.stringify({ error: "Ungueltige KI-Angaben" }),
          { status: 400, headers: { "Content-Type": "application/json" } },
        );
      }
      // Play Integrity (v0.9.0): Token MITgeschickt -> Verdict MUSS
      // bestehen, sonst manuelle Prüfung (fail-closed dorthin). KEIN
      // Token (F-Droid, iOS, alte Builds, Fehler) -> bisheriger Pfad.
      const integrityToken = typeof body.integrityToken === "string"
        ? body.integrityToken
        : null;
      const integrityNonce = typeof body.integrityNonce === "string"
        ? body.integrityNonce
        : null;
      if (integrityToken && integrityNonce) {
        const integrityOk = await verifyPlayIntegrity(
          integrityToken,
          integrityNonce,
        );
        if (!integrityOk) {
          return new Response(
            JSON.stringify({ error: "Manuelle Pruefung erforderlich" }),
            { status: 422, headers: { "Content-Type": "application/json" } },
          );
        }
      }
      // Server-seitige Abweichung (Fix: client-gelieferte `deviation` wird
      // IGNORIERT - modifizierte Clients konnten eine passende Abweichung
      // behaupten und das Badge erschleichen). Angegebenes Alter kommt aus
      // dem Profil-Geburtsdatum.
      const { data: ageProfile } = await supabaseAdmin
        .from("profiles")
        .select("birth_date")
        .eq("user_id", user.id)
        .maybeSingle();
      const statedAge = statedAgeFromBirthDate(
        (ageProfile as { birth_date?: string } | null)?.birth_date ?? null,
      );
      if (statedAge == null) {
        return new Response(
          JSON.stringify({ error: "Manuelle Pruefung erforderlich" }),
          { status: 422, headers: { "Content-Type": "application/json" } },
        );
      }
      if (faceCount !== 1 || Math.abs(estimatedAge - statedAge) > 2) {
        return new Response(
          JSON.stringify({ error: "Manuelle Pruefung erforderlich" }),
          { status: 422, headers: { "Content-Type": "application/json" } },
        );
      }

      const { data: obj } = await supabaseAdmin.storage
        .from("verification-videos")
        .list(user.id, { limit: 10 });
      if (!obj || !obj.some((o) => o.name === "video.mp4")) {
        return new Response(
          JSON.stringify({ error: "Video nicht gefunden (Upload fehlt)" }),
          { status: 400, headers: { "Content-Type": "application/json" } },
        );
      }

      const { data: profile } = await supabaseAdmin
        .from("profiles")
        .select("verification_status, is_verified")
        .eq("user_id", user.id)
        .maybeSingle();
      const currentStatus = profile?.verification_status ?? "none";
      if (profile?.is_verified === true || currentStatus === "pending") {
        return new Response(
          JSON.stringify({ error: "Keine Auto-Freigabe moeglich" }),
          { status: 409, headers: { "Content-Type": "application/json" } },
        );
      }

      const { error: updateError } = await supabaseAdmin
        .from("profiles")
        .update({
          verification_video_path: `${user.id}/video.mp4`,
          verification_estimated_age: estimatedAge,
          verification_status: "auto",
          is_verified: true,
        })
        .eq("user_id", user.id);

      if (updateError) {
        console.error("Auto update error:", updateError);
        return new Response(JSON.stringify({ error: "Update failed" }), {
          status: 500, headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ ok: true, status: "auto" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }

    // ------------------------------------------------------------------
    // Aktion: Review (nur Admin).
    // ------------------------------------------------------------------
    if (!(await isAdminUser(user.id))) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403, headers: { "Content-Type": "application/json" },
      });
    }

    const targetUserId = String(body.targetUserId ?? "");
    const { isVerified } = body;

    if (!UUID_REGEX.test(targetUserId) || typeof isVerified !== "boolean") {
      return new Response(
        JSON.stringify({ error: "targetUserId (uuid) and isVerified (boolean) required" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const { error: updateError } = await supabaseAdmin
      .from("profiles")
      .update({
        is_verified: isVerified,
        verification_status: isVerified ? "approved" : "rejected",
        // Bei Ablehnung Pfad entfernen (Video wird unten geloescht).
        ...(isVerified ? {} : { verification_video_path: null }),
      })
      .eq("user_id", targetUserId);

    if (updateError) {
      console.error("Update error:", updateError);
      return new Response(JSON.stringify({ error: "Update failed" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    // Bei Ablehnung das private Video endgueltig loeschen (DSGVO).
    if (!isVerified) {
      await supabaseAdmin.storage
        .from("verification-videos")
        .remove([`${targetUserId}/video.mp4`]);
    }

    return new Response(JSON.stringify({
      userId: targetUserId, isVerified, updated: true,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error("Error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
