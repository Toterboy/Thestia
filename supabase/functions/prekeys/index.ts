import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

// Von Supabase automatisch injected (niemals manuell setzen!)
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
  auth: { persistSession: false },
});

// In-Memory Rate-Limiting pro User/IP (Cold-Start reset ist akzeptabel,
// da es nur um Abschwächung von Missbrauch geht).
const rateMap = new Map<string, number[]>();
const RATE_LIMIT = 30;        // Aufrufe pro Zeitfenster
const RATE_WINDOW_MS = 60_000; // 1 Minute

/**
 * Client-IP robust bestimmen (Security 2026-09-26).
 *
 * BUG VORHER: `req.headers.get("x-forwarded-for")` liefert die GESAMTE
 * Komma-Liste als String. Der Angreifer rotiert den Header-Wert einfach
 * ("1.2.3.4, 5.6.7.8, ...") - der Rate-Limit-Key wechselt damit und das
 * Limit ist wirkungslos.
 *
 * Reihenfolge: x-client-ip / cf-connecting-ip (von der Plattform gesetzt)
 * -> ERSTER Eintrag aus x-forwarded-for. "unknown" nur, wenn nichts da ist.
 */
function clientIp(req: Request): string {
  const direct =
    req.headers.get("x-client-ip") ??
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("true-client-ip");
  if (direct) return direct.trim().slice(0, 64);

  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) return first.slice(0, 64);
  }
  return "unknown";
}

function rateLimitKey(req: Request, userId?: string): string {
  if (userId) return `user:${userId}`;
  return `ip:${clientIp(req)}`;
}

function isRateLimited(key: string): boolean {
  const now = Date.now();
  const timestamps = rateMap.get(key)?.filter((t) => now - t < RATE_WINDOW_MS) ?? [];
  timestamps.push(now);
  rateMap.set(key, timestamps);
  return timestamps.length > RATE_LIMIT;
}

interface PreKeyBundle {
  identityKeyPublic: string;
  registrationId: number;
  preKeyId: number;
  preKeyPublic: string;
  signedPreKeyId: number;
  signedPreKeyPublic: string;
  signedPreKeySignature: string;
}

serve(async (req) => {
  // CORS: Bewusst KEINE CORS-Header (Audit M7) – die Funktion wird nur von
  // der nativen App aufgerufen; Browser-Zugriffe werden dadurch geblockt.
  // OPTIONS fällt ins Method-not-allowed (405).

  const url = new URL(req.url);
  const pathParts = url.pathname.split("/").filter(Boolean);

  // Rate-Limit für alle Operationen prüfen (schon vor Auth, da billig).
  if (isRateLimited(rateLimitKey(req))) {
    return new Response(
      JSON.stringify({ error: "Too many requests" }),
      { status: 429, headers: { "Content-Type": "application/json" } },
    );
  }

  // Route: GET /prekeys/:userId
  // Die Edge-Function-URL ist /functions/v1/prekeys, der Pfad danach
  // enthält ggf. die userId. Beispiel: .../prekeys/abc-123
  if (req.method === "GET" && pathParts.length >= 1) {
    // Audit E3: Auch der Bundle-Abruf erfordert einen gültigen JWT.
    // Ohne Prüfung genügte der öffentliche Anon-Key am Gateway, um
    // PreKey-Bundles abzurufen und existierende User-IDs zu enumerieren.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Nicht authentifiziert." }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }
    const callerToken = authHeader.slice(7);
    const { data: callerAuth, error: callerError } = await supabaseAdmin.auth
      .getUser(callerToken);
    if (callerError || !callerAuth?.user) {
      return new Response(
        JSON.stringify({ error: "Ungültiger Token." }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const userId = pathParts[pathParts.length - 1];
    if (!userId || userId === "prekeys") {
      return new Response(
        JSON.stringify({ error: "userId erforderlich." }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Strikt validieren: nur UUIDs sind erlaubte Pfad-Parameter.
    const UUID_REGEX =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!UUID_REGEX.test(userId)) {
      return new Response(
        JSON.stringify({ error: "userId muss eine UUID sein." }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Zusätzliches Rate-Limit pro authentifiziertem User.
    if (isRateLimited(rateLimitKey(req, callerAuth.user.id))) {
      return new Response(
        JSON.stringify({ error: "Too many requests" }),
        { status: 429, headers: { "Content-Type": "application/json" } },
      );
    }

    // M-23: Persistentes DB-Rate-Limit (überlebt Cold Starts).
    // 240/h statt 60/h: Der Client pollt beim Warten auf ein Partner-
    // Bundle (404) ~2 GETs je 75 s (Partner-Fetch + Self-Heal-Check des
    // eigenen Bundles) - mit 60/h griff das Limit nach ~40 Min Wartezeit
    // und erzeugte ein scheinbares "der Fehler kommt wieder" (429).
    // Missbrauchsschutz bleibt der In-Memory-Burst-Limiter (30/min).
    const { data: dbRateOk } = await supabaseAdmin.rpc("consume_rate_limit", {
      p_key: `prekeys_get:${callerAuth.user.id}`,
      p_max_hits: 240,
      p_window_seconds: 3600,
    });
    if (dbRateOk !== true) {
      return new Response(
        JSON.stringify({ error: "Too many requests" }),
        { status: 429, headers: { "Content-Type": "application/json" } },
      );
    }

    // ---------------------------------------------------------------
    // SECURITY (2026-09-26): Beziehungspruefung.
    //
    // BEFUND: Vorher konnte JEDER angemeldete Nutzer ueber eine beliebige
    // UUID das Identity-Key-Bundle jedes anderen Nutzers laden - also genau
    // das Schluesselmaterial fuer den Erstkontakt. Die Funktion nutzt
    // durchgehend `supabaseAdmin` (Service-Role), die RLS-Festung auf
    // `prekeys` (061:30-35) wirkte daher nicht. 404 vs. 200 war zusaetzlich
    // ein User-Existenzorakel.
    //
    // Erlaubt sind exakt die Wege, ueber die der Client eine E2E-Session
    // aufbaut (p2p_chat_service.connect / relay_service.send):
    //   eigenes Bundle (Self-Heal), Match-Partner, aktive Zufallschat- oder
    //   Dating-Hour-Session, laufendes Transit-Signal-Paar.
    // Alles andere: 404 OHNE Aussage darueber, ob der Nutzer existiert.
    // ---------------------------------------------------------------
    const callerId = callerAuth.user.id;
    let related = userId === callerId;

    if (!related) {
      const { data: m } = await supabaseAdmin
        .from("matches")
        .select("id")
        .or(
          `and(user_one_id.eq.${callerId},user_two_id.eq.${userId}),` +
          `and(user_two_id.eq.${callerId},user_one_id.eq.${userId})`,
        )
        .limit(1)
        .maybeSingle();
      related = !!m;
    }

    if (!related) {
      const { data: rc } = await supabaseAdmin
        .from("random_chat_sessions")
        .select("id")
        .eq("status", "active")
        .or(
          `and(user_a.eq.${callerId},user_b.eq.${userId}),` +
          `and(user_a.eq.${userId},user_b.eq.${callerId})`,
        )
        .limit(1)
        .maybeSingle();
      related = !!rc;
    }

    if (!related) {
      const { data: dh } = await supabaseAdmin
        .from("dating_hour_session")
        .select("id")
        .is("ended_at", null)
        .or(
          `and(user_a.eq.${callerId},user_b.eq.${userId}),` +
          `and(user_b.eq.${callerId},user_a.eq.${userId})`,
        )
        .limit(1)
        .maybeSingle();
      related = !!dh;
    }

    if (!related) {
      const { data: tr } = await supabaseAdmin
        .from("transit_signals")
        .select("id")
        .in("status", ["pending", "matched"])
        .or(
          `and(user_id.eq.${callerId},matched_with.eq.${userId}),` +
          `and(user_id.eq.${userId},matched_with.eq.${callerId})`,
        )
        .limit(1)
        .maybeSingle();
      related = !!tr;
    }

    if (!related) {
      return new Response(
        JSON.stringify({ error: "nicht verfuegbar" }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    const { data, error } = await supabaseAdmin
      .from("prekeys")
      .select("bundle")
      .eq("user_id", userId)
      .maybeSingle();

    if (error) {
      console.error("PreKey-Fetch DB-Fehler:", error);
      return new Response(
        JSON.stringify({ error: "Datenbankfehler beim Abruf." }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    if (!data) {
      return new Response(
        // Neutral formuliert: gibt keine Auskunft darueber, ob der Nutzer
        // existiert (kein Enumeration-Signal).
        JSON.stringify({ error: "Kein Bundle verfügbar." }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify(data.bundle),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // Route: POST /prekeys
  // Legt ein neues Bundle an oder aktualisiert ein bestehendes.
  // Authentifizierung: User-Token aus Authorization-Header extrahieren.
  if (req.method === "POST") {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Nicht authentifiziert." }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const token = authHeader.slice(7);
    const { data: authData, error: authError } = await supabaseAdmin.auth.getUser(token);

    if (authError || !authData?.user) {
      return new Response(
        JSON.stringify({ error: "Ungültiger Token." }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const userId = authData.user.id;

    // Zusätzliches Rate-Limit pro authentifiziertem User.
    if (isRateLimited(rateLimitKey(req, userId))) {
      return new Response(
        JSON.stringify({ error: "Too many requests" }),
        { status: 429, headers: { "Content-Type": "application/json" } },
      );
    }

    // M-23: Persistentes DB-Rate-Limit (überlebt Cold Starts).
    const { data: dbRateOk } = await supabaseAdmin.rpc("consume_rate_limit", {
      p_key: `prekeys_post:${userId}`,
      p_max_hits: 30,
      p_window_seconds: 3600,
    });
    if (dbRateOk !== true) {
      return new Response(
        JSON.stringify({ error: "Too many requests" }),
        { status: 429, headers: { "Content-Type": "application/json" } },
      );
    }

    let bundle: PreKeyBundle;
    try {
      bundle = await req.json() as PreKeyBundle;
    } catch {
      return new Response(
        JSON.stringify({ error: "Ungültiges JSON im Body." }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Schema-Validierung: alle öffentlichen Felder müssen vorhanden und
    // vom erwarteten Typ sein. Verhindert Bundle-Injection/Format-Angriffe.
    const requiredFields: { [key: string]: string } = {
      identityKeyPublic: "string",
      registrationId: "number",
      preKeyId: "number",
      preKeyPublic: "string",
      signedPreKeyId: "number",
      signedPreKeyPublic: "string",
      signedPreKeySignature: "string",
    };
    for (const [field, expectedType] of Object.entries(requiredFields)) {
      const value = (bundle as Record<string, unknown>)[field];
      if (value === undefined || value === null || typeof value !== expectedType) {
        return new Response(
          JSON.stringify({ error: `Feld ${field} fehlt oder hat ungültigen Typ.` }),
          { status: 400, headers: { "Content-Type": "application/json" } },
        );
      }
    }

    const { error: upsertError } = await supabaseAdmin
      .from("prekeys")
      .upsert({
        user_id: userId,
        bundle,
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id" });

    if (upsertError) {
      console.error("PreKey-Upsert DB-Fehler:", upsertError);
      return new Response(
        JSON.stringify({ error: "Datenbankfehler beim Speichern." }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({ ok: true }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({ error: "Method not allowed" }),
    { status: 405, headers: { "Content-Type": "application/json" } },
  );
});
