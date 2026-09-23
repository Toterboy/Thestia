import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

// ---------------------------------------------------------------------------
// WICHTIG: Diese Funktion wird AUSSCHLIESSLICH serverseitig ausgeführt.
// Sie darf NICHT aus dem Flutter-Client aufgerufen werden.
// ---------------------------------------------------------------------------

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

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("SUPABASE_URL und SUPABASE_SERVICE_ROLE_KEY müssen als Secrets gesetzt sein.");
}

const EARTH_RADIUS_KM = 6371;

function toRadians(deg: number) {
  return (deg * Math.PI) / 180;
}

function haversineKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_KM * c;
}

interface CheckLocationRequest {
  lat1: number;
  lon1: number;
  lat2: number;
  lon2: number;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // -------------------------------------------------------------------------
  // INTERNER SCHUTZ: Nur Aufrufe mit gültigem internen Secret zulassen
  // (constant-time Vergleich, Audit N5).
  // -------------------------------------------------------------------------
  const internalSecret = Deno.env.get("INTERNAL_SECRET");
  const receivedSecret = req.headers.get("x-internal-secret") ?? "";
  const secretsMatch =
    !!internalSecret &&
    internalSecret.length === receivedSecret.length &&
    [...internalSecret].every(
      (c, i) => c.charCodeAt(0) === receivedSecret.charCodeAt(i),
    );
  if (!secretsMatch) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  // JWT-Bindung (Fix: reines Secret ohne Nutzer-Kontext): Der interne
  // Aufrufer (process-location-check) reicht das User-JWT weiter; es muss
  // gültig sein. Damit ist die Funktion selbst bei Secret-Leak nicht mehr
  // frei als anonymes Rechen-Orakel aufrufbar.
  const authClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const callerToken = (req.headers.get("Authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  if (!callerToken) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }
  const { data: { user: caller }, error: callerError } =
    await authClient.auth.getUser(callerToken);
  if (callerError || !caller) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body = (await req.json()) as CheckLocationRequest;
    const { lat1, lon1, lat2, lon2 } = body;

    if (
      [lat1, lon1, lat2, lon2].some((v) => v == null || isNaN(v))
    ) {
      return new Response(JSON.stringify({ error: "Ungültige Eingabedaten." }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }
    if (
      lat1 < -90 || lat1 > 90 || lat2 < -90 || lat2 > 90 ||
      lon1 < -180 || lon1 > 180 || lon2 < -180 || lon2 > 180
    ) {
      return new Response(JSON.stringify({ error: "Ungültige Eingabedaten." }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const distanceKm = haversineKm(lat1, lon1, lat2, lon2);
    const isNear = distanceKm < 15;

    return new Response(
      JSON.stringify({
        distanceKm,
        isNear,
        thresholdKm: 15,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (e) {
    console.error("Unerwarteter Fehler:", e);
    return new Response(JSON.stringify({ error: "Interner Serverfehler." }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
