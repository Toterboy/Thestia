import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

// Supabase Edge Function: cancel-registration
//
// Bricht eine NOCH NICHT bestätigte Registrierung ab und löscht den
// Account (Nutzer-Regel: Auf dem E-Mail-Bestätigungs-Screen muss man
// auch abbrechen können – dann wird der Supabase-Account gelöscht).
//
// Warum eine eigene Function: Unbestätigte Nutzer haben KEINE Session
// (kein JWT) und können daher weder die authentifizierte
// delete-account-Function nutzen noch sich einloggen. Der Nachweis der
// Inhaberschaft läuft über das Registrierungs-Passwort (nur im
// Speicher der App, nie persistiert):
//   1. signInWithPassword mit E-Mail + Passwort versuchen.
//   2. Erfolg  -> Account ist aktiv/bestätigt -> ABLEHNEN (dafür gibt
//      es Login + delete-account).
//   3. Fehler "Email not confirmed" -> Inhaberschaft bewiesen (nur wer
//      das Passwort kennt, bekommt genau diesen Fehler).
//   4. Jeder andere Fehler (falsches Passwort, unbekannt) -> ABLEHNEN.
// Erst danach wird GELÖSCHT – und nur, wenn der Account wirklich noch
// unbestätigt ist (Doppel-Check gegen Wettlauf mit der Bestätigung).
//
// Missbrauchs-Schutz: Rate-Limit pro E-Mail (5/h), keine
// User-Enumeration über Timing (gleiche Antwortzeit-Pfade), nur
// unbestätigte Accounts löschbar.

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
const SUPABASE_ANON_KEY = _pickApiKey("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY");

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// Buckets mit nutzerbezogenen Objekten (Ordner = User-ID). Frische
// Accounts haben i. d. R. nichts – trotzdem best-effort räumen.
const USER_SCOPED_BUCKETS = ["avatars", "verification-videos"];

async function isRateLimited(email: string): Promise<boolean> {
  try {
    const { data, error } = await supabaseAdmin.rpc("consume_rate_limit", {
      p_key: `cancel-registration:${email}`,
      p_max_hits: 5,
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

async function purgeUserStorage(userId: string): Promise<void> {
  for (const bucket of USER_SCOPED_BUCKETS) {
    try {
      const { data: files } = await supabaseAdmin.storage
        .from(bucket)
        .list(userId, { limit: 100 });
      const paths = (files ?? [])
        .filter((f) => f.name)
        .map((f) => `${userId}/${f.name}`);
      if (paths.length > 0) {
        await supabaseAdmin.storage.from(bucket).remove(paths);
      }
    } catch (e) {
      console.error(`purge ${bucket} failed:`, e);
    }
  }
}

/** Löst die User-ID zur E-Mail auf (Suche, max. 3 Seiten à 200). */
async function findUserIdByEmail(email: string): Promise<string | null> {
  const needle = email.toLowerCase();
  for (let page = 1; page <= 3; page++) {
    const { data, error } = await supabaseAdmin.auth.admin.listUsers({
      page,
      perPage: 200,
    });
    if (error || !data?.users) {
      console.error("listUsers error:", error);
      return null;
    }
    const hit = data.users.find(
      (u) => (u.email ?? "").toLowerCase() === needle,
    );
    if (hit) return hit.id;
    if (data.users.length < 200) break;
  }
  return null;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    if (!email.includes("@") || password.length === 0) {
      return new Response(JSON.stringify({ error: "Ungueltige Angaben" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    if (await isRateLimited(email)) {
      return new Response(
        JSON.stringify({ error: "Zu viele Versuche, bitte spaeter erneut." }),
        { status: 429, headers: { "Content-Type": "application/json" } },
      );
    }

    // 1) Inhaberschaft beweisen: Anmeldeversuch mit eigenem Client.
    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error: signInError } =
      await supabaseAnon.auth.signInWithPassword({ email, password });

    if (!signInError) {
      // Anmeldung erfolgreich -> Account aktiv/bestätigt. Dafür ist
      // Login + delete-account zuständig, nicht dieser Endpoint.
      return new Response(
        JSON.stringify({ error: "Bereits aktiv - bitte anmelden" }),
        { status: 409, headers: { "Content-Type": "application/json" } },
      );
    }
    if (!/email not confirmed/i.test(signInError.message)) {
      // Falsches Passwort oder unbekannte Adresse - kein Nachweis.
      // Absichtlich dieselbe neutrale Antwort (keine Enumeration).
      return new Response(JSON.stringify({ error: "Ungueltige Angaben" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }

    // 2) ID auflösen + Doppel-Check: wirklich noch unbestätigt?
    // (Schließt den Wettlauf "Bestätigung klickt, Abbruch läuft" aus.)
    const userId = await findUserIdByEmail(email);
    if (!userId) {
      return new Response(JSON.stringify({ error: "Ungueltige Angaben" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }
    const { data: fresh } = await supabaseAdmin.auth.admin.getUserById(
      userId,
    );
    if (!fresh?.user || fresh.user.email_confirmed_at) {
      return new Response(
        JSON.stringify({ error: "Bereits aktiv - bitte anmelden" }),
        { status: 409, headers: { "Content-Type": "application/json" } },
      );
    }

    // 3) Löschen (Storage best-effort, Rate-Limit-Reste zur eigenen
    // E-Mail, dann Auth-User). Bug-Reports/Meldungen kann ein nie
    // aktiver Account nicht haben.
    await purgeUserStorage(userId);
    try {
      await supabaseAdmin
        .from("rate_limit_hits")
        .delete()
        .like("bucket_key", `%${email}%`);
    } catch (e) {
      console.error("rate_limit purge failed:", e);
    }
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(
      userId,
    );
    if (deleteError) {
      console.error("deleteUser error:", deleteError);
      return new Response(JSON.stringify({ error: "Loeschen fehlgeschlagen" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ ok: true, deleted: true }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("Error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
