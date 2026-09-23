import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
// API-Keys: Selbst-validierende Wahl (kein blinder Fallback!).
//
// Hintergrund (live bewiesen + upstream issue supabase-js#1568): Alte
// supabase-js-Versionen schicken den API-Key als Authorization-Bearer-
// Fallback mit. Legacy-JWTs (anon/service_role) sind gültige JWTs und
// funktionieren; sb_-Keys sind KEINE JWTs ("Expected 3 parts in JWT")
// und fielen dadurch auf eine Rolle ohne Rechte zurück (fälschlich
// "permission denied" trotz korrekter Grants).
//
// Deshalb wird hier NICHT geraten, sondern GEMESSEN: Jeder Kandidat
// (sb_ aus Auto-Dict, custom Secret, Legacy) wird mit einem harmlosen
// Service-Read (profiles head-count: service_role OK, anon denied)
// geprüft. Der erste funktionierende Key gewinnt und wird für die
// Isolate-Lebensdauer gecacht. Schlägt alles fehl, gilt Legacy
// (letzter bekannter Stand) - lieber langsamer als kaputt.
type _KeyCand = { key: string; source: string };

function _keyCandidates(): _KeyCand[] {
  const out: _KeyCand[] = [];
  try {
    const dict = JSON.parse(
      Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}",
    ) as Record<string, unknown>;
    const named = dict["default"];
    if (typeof named === "string" && named.length > 0) {
      out.push({ key: named, source: "auto-dict" });
    }
  } catch (_) {}
  const single = Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
  if (single.length > 0) out.push({ key: single, source: "custom" });
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (legacy.length > 0) out.push({ key: legacy, source: "legacy" });
  return out;
}

async function _probeServiceKey(key: string): Promise<boolean> {
  // ECHTER Rechte-Nachweis (kein SELECT-Indiz!): Ein No-op-DELETE auf
  // bug_reports. service_role hat DELETE (Grant live verifiziert) und
  // trifft mit der unmöglichen UUID 0 Zeilen; anon (und alles, was
  // fälschlich als anon läuft, z. B. nicht erkannte sb_-Keys) bekommt
  // SOFORT "permission denied". SELECT-Tests taugen nicht: anon hat
  // mancherorts SELECT-Recht und würde fälschlich bestehen.
  try {
    const t = createClient(SUPABASE_URL, key, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error } = await t
      .from("bug_reports")
      .delete()
      .eq("user_id", "00000000-0000-0000-0000-000000000000");
    return error == null;
  } catch (_) {
    return false;
  }
}

let _adminCache: {
  client: ReturnType<typeof createClient>;
  source: string;
} | null = null;

/** Pro-Kandidat-Ergebnis der letzten Key-Wahl (Diagnose). */
let _lastKeyReport = "none";

/** Service-Client mit verifiziertem Key (selbstheilend, gecacht). */
async function admin(): Promise<{
  client: ReturnType<typeof createClient>;
  source: string;
}> {
  if (_adminCache) return _adminCache;
  const seen: string[] = [];
  for (const c of _keyCandidates()) {
    if (await _probeServiceKey(c.key)) {
      console.error(`delete-account: service-key OK (${c.source})`);
      seen.push(`${c.source}:ok`);
      _lastKeyReport = seen.join(",");
      _adminCache = {
        client: createClient(SUPABASE_URL, c.key, {
          auth: { autoRefreshToken: false, persistSession: false },
        }),
        source: c.source,
      };
      return _adminCache;
    }
    console.error(`delete-account: service-key unbrauchbar (${c.source})`);
    seen.push(`${c.source}:denied`);
  }
  _lastKeyReport = seen.length > 0 ? seen.join(",") : "no-candidates";
  // Letzter Ausweg: Legacy-Blindflug (historischer Stand).
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  console.error("delete-account: KEIN Key verifiziert, nutze Legacy blind");
  _adminCache = {
    client: createClient(SUPABASE_URL, legacy, {
      auth: { autoRefreshToken: false, persistSession: false },
    }),
    source: "legacy-blind",
  };
  return _adminCache;
}

// Buckets mit nutzerbezogenen Objekten (Ordner = User-ID), die bei der
// Account-Löschung mit entfernt werden müssen (Audit M-1: Storage hat
// keinen FK auf auth.users - CASCADE greift hier nicht).
const USER_SCOPED_BUCKETS = ["avatars", "verification-videos"];

/** Best-Effort: alle Objekte unter `<bucket>/<userId>/` löschen. */
async function purgeUserStorage(
  client: ReturnType<typeof createClient>,
  userId: string,
): Promise<string[]> {
  const warnings: string[] = [];
  for (const bucket of USER_SCOPED_BUCKETS) {
    try {
      const { data: files, error: listError } = await client.storage
        .from(bucket)
        .list(userId, { limit: 1000 });
      if (listError) {
        warnings.push(`${bucket}: list fehlgeschlagen (${listError.message})`);
        continue;
      }
      const paths = (files ?? [])
        .filter((f) => f.name)
        .map((f) => `${userId}/${f.name}`);
      if (paths.length === 0) continue;
      const { error: removeError } = await client.storage
        .from(bucket)
        .remove(paths);
      if (removeError) {
        // Zweiter Versuch (transiente Fehler), dann Warnung.
        const retry = await client.storage.from(bucket).remove(paths);
        if (retry.error) {
          warnings.push(`${bucket}: remove fehlgeschlagen (${retry.error.message})`);
        }
      }
    } catch (e) {
      warnings.push(`${bucket}: unerwarteter Fehler (${String(e)})`);
    }
  }
  return warnings;
}

/**
 * Löscht Nutzerzeilen, die KEIN ON DELETE CASCADE haben (DSGVO Art. 17,
 * live per pg_constraint verifiziert). Rückgabe: { ok, warnings }.
 * Bei ok === false darf der Aufrufer NICHT löschen (Retry möglich).
 */
async function purgeUserRows(
  client: ReturnType<typeof createClient>,
  userId: string,
  email: string | null,
): Promise<{ ok: boolean; warnings: string[]; failedStep: string | null }> {
  const warnings: string[] = [];
  // Eigene Bug-Reports (Beschreibung + Geräteinfos).
  const { error: bugError } = await client
    .from("bug_reports")
    .delete()
    .eq("user_id", userId);
  if (bugError) {
    console.error("purge bug_reports error:", bugError);
    return {
      ok: false,
      warnings,
      failedStep: `bug_reports: ${bugError.message ?? "?"}`,
    };
  }
  // Meldungen GEGEN den Nutzer (Beschreibung + Chat-Auszüge über ihn).
  // Eigene Meldungen (reporter_id) laufen über CASCADE.
  const { error: repError } = await client
    .from("user_reports")
    .delete()
    .eq("reported_user_id", userId);
  if (repError) {
    console.error("purge user_reports error:", repError);
    return {
      ok: false,
      warnings,
      failedStep: `user_reports: ${repError.message ?? "?"}`,
    };
  }
  // Operative Rate-Limit-Zähler mit User-ID/E-Mail im Schlüssel.
  const patterns = [`%${userId}%`];
  if (email) patterns.push(`%${email}%`);
  for (const p of patterns) {
    const { error: rlError } = await client
      .from("rate_limit_hits")
      .delete()
      .like("bucket_key", p);
    if (rlError) {
      warnings.push(`rate_limit_hits (${p}): ${rlError.message}`);
    }
  }
  return { ok: true, warnings, failedStep: null };
}

/** AAL-Claim aus einem bereits verifizierten Access-Token lesen. */
function aalFromToken(token: string): string | null {
  try {
    const payload = JSON.parse(atob(
      token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"),
    ));
    return typeof payload.aal === "string" ? payload.aal : null;
  } catch {
    return null;
  }
}

/**
 * M-14: Hat der Nutzer verifizierte MFA-Faktoren, erfordert die
 * Account-Löschung AAL2 (Client-seitige MFA-Umleitung ist umgehbar).
 * Ist die Admin-MFA-API in dieser supabase-js-Version nicht verfügbar,
 * wird der Check übersprungen (geloggt) statt die Löschung zu blockieren.
 */
async function mfaSatisfied(
  client: ReturnType<typeof createClient>,
  userId: string,
  token: string,
): Promise<boolean> {
  const aal = aalFromToken(token);
  if (aal === "aal2") return true;

  try {
    const adminAny = client.auth as unknown as {
      mfa?: { listFactors?: (uid: string) => Promise<{ data?: { factors?: { status?: string }[] } }> };
    };
    if (typeof adminAny.mfa?.listFactors !== "function") return true;
    const { data } = await adminAny.mfa.listFactors(userId);
    const hasVerified = (data?.factors ?? []).some((f) => f.status === "verified");
    if (hasVerified && aal !== "aal2") return false;
    return true;
  } catch (e) {
    console.warn("MFA-Faktor-Prüfung nicht verfügbar:", e);
    return true;
  }
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Service-Client EINMALIG mit verifiziertem Key auflösen (s. oben):
  // Alle Helfer darunter nutzen diese Instanz - kein blinder Secret.
  const { client: supabaseAdmin, source: KEY_SOURCE } = await admin();

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);
    if (authError || !user) {
      console.error("delete-account: getUser fehlgeschlagen:", authError?.message ?? "kein User");
      return new Response(JSON.stringify({ error: "Sitzung ungueltig - bitte neu anmelden" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

  // M-14: MFA-Geräte müssen die zweite Faktor-Ebene nachweisen.
  if (!(await mfaSatisfied(supabaseAdmin, user.id, token))) {
    return new Response(
      JSON.stringify({ error: "mfa_required", hint: "Bitte zunächst MFA-Challenge abschließen." }),
      { status: 403, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    // M-1: Storage-Objekte VOR dem User-Delete entfernen (danach fehlt
    // der Ordner-Bezug und Objekte würden unbegrenzt erhalten bleiben).
    const warnings = await purgeUserStorage(supabaseAdmin, user.id);

    // Vollständige Löschung (DSGVO Art. 17): Was kein ON DELETE CASCADE
    // hat (live per pg_constraint verifiziert), wird hier explizit
    // gelöscht - VOR dem Auth-User, damit ein Fehler den Abbruch noch
    // erlaubt (Retry möglich, nichts halb gelöscht):
    // - bug_reports (eigene Meldungen + Geräteinfos, SET NULL-Spalte),
    // - user_reports gegen den Nutzer (Beschreibung + Chat-Auszüge über
    //   ihn, reported_user_id wird sonst nur anonymisiert),
    // - rate_limit_hits (operative Zähler mit der User-ID im Schlüssel).
    // Automatisch per CASCADE gehen u. a.: profiles, likes (beide
    // Richtungen), matches (beide Seiten, inkl. match_quiz_state,
    // meet_intents, match_bucket_list darüber), prekeys, dating_hour_*,
    // user_mood, eigene user_reports, random_chat_sessions,
    // quiz_*/match_* (inkl. Antworten), blocked_users (beide Seiten),
    // auth_devices, direct_message_relay (beide Seiten), transit_*
    // (über profiles), profile_photo_appeals (über profiles) sowie das
    // komplette auth-Schema (Sessions, MFA, Passkeys/WebAuthn).
    // Bewusst erhalten: Tombstone-Hash in deleted_users (nur md5 der
    // UUID, keine personenbezogenen Daten), reviewed_by-Auditspalten
    // (Admin-Handeln), banned_emails (Sperrliste).
    // Hinweis: Der Service-Key selbst wurde beim Request-Start über
    // admin() verifiziert (Protokoll: "service-key OK (<Quelle>)").
    // Schlägt der Purge trotzdem fehl, liegt es an der Tabelle
    // (failedStep), nicht am Key.
    const dataPurge = await purgeUserRows(
      supabaseAdmin,
      user.id,
      user.email ?? null,
    );
    if (!dataPurge.ok) {
      console.error(
        `Delete user error: Zeilen-Purge fehlgeschlagen (key=${KEY_SOURCE})`,
      );
      return new Response(
        JSON.stringify({
          error: `Daten-Purge fehlgeschlagen (${dataPurge.failedStep ?? "?"}|key=${KEY_SOURCE}|keys=${_lastKeyReport})`,
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Löscht den Auth-User (CASCADE s. o.).
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(user.id);
    if (deleteError) {
      console.error("Delete user error:", deleteError);
      return new Response(JSON.stringify({ error: "User-Delete fehlgeschlagen" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const allWarnings = [...warnings, ...dataPurge.warnings];
    if (allWarnings.length > 0) {
      console.warn("Storage-Cleanup-Warnungen bei Löschung", user.id, ":", allWarnings);
    }

    return new Response(
      JSON.stringify({ userId: user.id, deleted: true, storageWarnings: allWarnings }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("Unexpected error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
