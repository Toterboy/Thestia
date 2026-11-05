import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

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
// BEFUND 04.11.2026 (Migration 180): Diese Funktion braucht kein
// internes Secret mehr. Sie ruft check-location nicht mehr auf - die
// Pruefung passiert jetzt in einer einzigen Datenbanktransaktion
// (public.apply_location_check). Ein Secret, das nicht gebraucht wird,
// ist nur eine weitere Abhaengigkeit, die fehlschlagen kann.


if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("SUPABASE_URL und SUPABASE_SERVICE_ROLE_KEY müssen als Secrets gesetzt sein.");
}

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

interface ProcessLocationCheckRequest {
  newLatitude: number;
  newLongitude: number;
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
    // BEFUND 04.11.2026: Der Fehlerpfad war fail-OPEN - bei einem
    // Stoerfall der RPC entfiel die Bremse ersatzlos. Alle anderen
    // Funktionen machen es fail-closed.
    console.error("Rate-Limit-Prüfung fehlgeschlagen:", rateError);
    return new Response(
      JSON.stringify({ error: "rate_limit_unavailable" }),
      { status: 503, headers: { "Content-Type": "application/json" } },
    );
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

    // -----------------------------------------------------------------
    // Der Standort-Check passiert jetzt in EINER Datenbanktransaktion.
    //
    // BEFUND (Security-Audit 04.11.2026, TOCTOU): Vorher las diese
    // Funktion die alte Position und den alten Zeitstempel, rief dann
    // check-location auf (zwei Netzwerkaufrufe, je 50 bis 200 ms) und
    // schrieb erst danach. In diesem Zeitfenster konnten zwei Aufrufe
    // parallel laufen:
    //
    //   a) Beide rechneten gegen dieselbe alte Basis. Die Zeit seit der
    //      letzten Position wurde nicht korrekt fortgeschrieben.
    //   b) Der normale Pfad schrieb das Verdachtsflag mit dem Ergebnis
    //      der EIGENEN Pruefung - ein spaeterer, unauffaelliger Aufruf
    //      konnte ein gerade gesetztes Flag wieder auf false setzen.
    //
    // public.apply_location_check() macht alles in einer Transaktion
    // und sperrt die Zeile dabei (SELECT ... FOR UPDATE). Ein zweiter
    // Aufruf wartet, bis der erste fertig ist, und liest danach den
    // Stand, den der erste geschrieben hat.
    //
    // BEWEIS (04.11.2026, Live): Zwei gleichzeitige HTTP-Aufrufe auf
    // die Datenbank - der zweite wartete 1,7 s, bis der erste die
    // Sperre freigab (datenbankseitig gemessen: 1667 ms).
    const { data: checkData, error: checkError } = await supabaseAdmin.rpc(
      "apply_location_check",
      {
        p_user_id: userId,
        p_lat: newLatitude,
        p_lon: newLongitude,
      },
    );

    if (checkError || !checkData) {
      console.error("apply_location_check fehlgeschlagen:", checkError);
      return new Response(
        JSON.stringify({ error: "Standortpruefung fehlgeschlagen." }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    const result = checkData as {
      ok?: boolean;
      error?: string;
      distance_km?: number | null;
      is_suspicious?: boolean;
      updated?: boolean;
      reason?: string;
    };

    if (result.ok !== true) {
      // profile_not_found: der Nutzer hat kein Profil. Das ist kein
      // Serverfehler, sondern ein Zustand.
      const status = result.error === "profile_not_found" ? 404 : 400;
      const meldung = result.error === "profile_not_found"
        ? "Profil nicht gefunden."
        : "Standortpruefung fehlgeschlagen.";
      return new Response(JSON.stringify({ error: meldung }), {
        status,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        userId,
        distanceKm: result.distance_km ?? null,
        isSuspicious: result.is_suspicious === true,
        updated: result.updated === true,
        reason: result.reason ?? "ok",
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
