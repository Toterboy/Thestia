import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

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
const INTERNAL_SECRET = Deno.env.get("INTERNAL_SECRET") ?? "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !INTERNAL_SECRET) {
  console.error("SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY und INTERNAL_SECRET müssen als Secrets gesetzt sein.");
}

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

interface ProcessLocationCheckRequest {
  newLatitude: number;
  newLongitude: number;
}

interface CheckLocationResponse {
  distanceKm: number;
  isNear: boolean;
  thresholdKm: number;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // -------------------------------------------------------------------------
  // JWT-Verifizierung: Aus dem Authorization-Header den Token extrahieren
  // und den zugehörigen Supabase-Auth-User verifizieren.
  // -------------------------------------------------------------------------
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace("Bearer ", "").trim();

  if (!token) {
    return new Response(JSON.stringify({ error: "Missing authorization token" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let user;
  try {
    const authResult = await supabaseAdmin.auth.getUser(token);
    user = authResult.data.user;
    if (authResult.error || !user) {
      console.error("Auth-Fehler:", authResult.error);
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }
  } catch (e) {
    console.error("Unerwarteter Fehler bei Auth-Verifizierung:", e);
    return new Response(JSON.stringify({ error: "Auth verification failed" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const userId = user.id;

  // M-23: Persistentes Rate-Limit (DB) - bisher gar keins. 10 Aufrufe/
  // Stunde reichen für legitime Standort-Checks (Profil-Edit/Onboarding)
  // und drosseln Missbrauch des Checks selbst.
  const { data: rateOk, error: rateError } = await supabaseAdmin.rpc(
    "consume_rate_limit",
    { p_key: `loccheck:${userId}`, p_max_hits: 10, p_window_seconds: 3600 },
  );
  if (rateError) {
    console.warn("Rate-Limit-Prüfung fehlgeschlagen (fail-open):", rateError);
  } else if (rateOk !== true) {
    return new Response(
      JSON.stringify({ error: "rate_limited" }),
      { status: 429, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const body = (await req.json()) as ProcessLocationCheckRequest;
    const { newLatitude, newLongitude } = body;

    if (newLatitude == null || newLongitude == null || isNaN(newLatitude) || isNaN(newLongitude)) {
      return new Response(JSON.stringify({ error: "Ungültige Eingabedaten." }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Bereichsvalidierung (Fix): Ohne Clamp landeten invalide Koordinaten
    // im Profil und dienten danach als Basislinie für Speed-Checks.
    if (
      newLatitude < -90 || newLatitude > 90 ||
      newLongitude < -180 || newLongitude > 180
    ) {
      return new Response(JSON.stringify({ error: "Ungültige Eingabedaten." }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Caller-JWT für den internen check-location-Aufruf weiterreichen
    // (dort JWT-Bindung zusätzlich zum Secret).
    const forwardAuth = authHeader.startsWith("Bearer ")
      ? authHeader
      : `Bearer ${token}`;

    // 1) Alte Position aus der Datenbank lesen
    const { data, error } = await supabaseAdmin
      .from("profiles")
      .select("location_lat, location_lng, location_checked_at")
      .eq("user_id", userId)
      .maybeSingle();

    if (error) {
      console.error("Fehler beim Lesen des Profils:", error);
      return new Response(JSON.stringify({ error: "Profil konnte nicht gelesen werden." }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (!data) {
      return new Response(JSON.stringify({ error: "Profil nicht gefunden." }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    const previousLat = (data["location_lat"] as number) ?? null;
    const previousLon = (data["location_lng"] as number) ?? null;
    const previousCheckedAt = (data["location_checked_at"] as string) ?? null;

    if (previousLat == null || previousLon == null) {
      // Keine alte Position vorhanden, daher keine Prüfung möglich.
      // In diesem Fall setzen wir is_location_suspicious auf false.
      const { error: updateError } = await supabaseAdmin
        .from("profiles")
        .update({
          location_lat: newLatitude,
          location_lng: newLongitude,
          is_location_suspicious: false,
          location_checked_at: new Date().toISOString(),
        })
        .eq("user_id", userId);

      if (updateError) {
        console.error("Fehler beim Aktualisieren des Profils:", updateError);
        return new Response(JSON.stringify({ error: "Profil konnte nicht aktualisiert werden." }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        });
      }

      return new Response(
        JSON.stringify({
          userId,
          distanceKm: null,
          isSuspicious: false,
          updated: true,
          reason: "no_previous_location",
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    // 1b) Speed-Plausibilität (M3): Ein "inkrementelles Herumwandern"
    // (viele kleine Sprünge < 15 km) wird erkannt, wenn die zurückgelegte
    // Distanz zur vergangenen Zeit physikalisch unplausibel ist
    // (> 300 km/h). In diesem Fall wird die Position NICHT übernommen
    // (sonst könnte ein Angreifer seine Basislinie schrittweise verschieben)
    // und der Account als verdächtig markiert.
    if (previousCheckedAt) {
      const elapsedMs =
        Date.now() - new Date(previousCheckedAt).getTime();
        if (Number.isFinite(elapsedMs) && elapsedMs > 0) {
        const { data: speedCheck } = await supabaseAdmin.functions.invoke(
          "check-location",
          {
            body: {
              lat1: previousLat,
              lon1: previousLon,
              lat2: newLatitude,
              lon2: newLongitude,
            },
            headers: {
              "x-internal-secret": INTERNAL_SECRET,
              "Authorization": forwardAuth,
            },
          },
        );
        const distanceKm =
          (speedCheck as CheckLocationResponse | null)?.distanceKm ?? null;
        if (distanceKm != null) {
          const speedKmh =
            distanceKm / (elapsedMs / 3_600_000);
          if (speedKmh > 300) {
            const { error: suspiciousError } = await supabaseAdmin
              .from("profiles")
              .update({ is_location_suspicious: true })
              .eq("user_id", userId);
            if (suspiciousError) {
              console.error("Fehler beim Markieren als verdächtig:", suspiciousError);
            }
            return new Response(
              JSON.stringify({
                userId,
                distanceKm,
                isSuspicious: true,
                updated: false,
                reason: "implausible_speed",
              }),
              {
                status: 200,
                headers: { "Content-Type": "application/json" },
              }
            );
          }
        }
      }
    }

    // 2) Intern check-location aufrufen (kein HTTP-Loopback, daher ist das
    // INTERNAL_SECRET nicht in Gateway-Logs sichtbar).
    let checkResponse: CheckLocationResponse;

    try {
      const { data, error } = await supabaseAdmin.functions.invoke(
        "check-location",
        {
          body: {
            lat1: previousLat,
            lon1: previousLon,
            lat2: newLatitude,
            lon2: newLongitude,
          },
          headers: {
            "x-internal-secret": INTERNAL_SECRET,
            "Authorization": forwardAuth,
          },
        },
      );

      if (error || !data) {
        console.error("check-location Fehler:", error);
        return new Response(JSON.stringify({ error: "Standortprüfung fehlgeschlagen." }), {
          status: 502,
          headers: { "Content-Type": "application/json" },
        });
      }

      checkResponse = data as CheckLocationResponse;
    } catch (e) {
      console.error("Interner Aufruf an check-location fehlgeschlagen:", e);
      return new Response(JSON.stringify({ error: "Interner Aufruf fehlgeschlagen." }), {
        status: 502,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 3) Ergebnis in profiles schreiben
    const isSuspicious = !checkResponse.isNear; // isNear = true wenn < 15km
    const { error: updateError } = await supabaseAdmin
      .from("profiles")
      .update({
        location_lat: newLatitude,
        location_lng: newLongitude,
        is_location_suspicious: isSuspicious,
        location_checked_at: new Date().toISOString(),
      })
      .eq("user_id", userId);

    if (updateError) {
      console.error("Fehler beim Aktualisieren des Profils:", updateError);
      return new Response(JSON.stringify({ error: "Profil konnte nicht aktualisiert werden." }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        userId,
        distanceKm: checkResponse.distanceKm,
        isSuspicious,
        updated: true,
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
