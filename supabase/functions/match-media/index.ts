import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

// match-media: Liefert signierte URLs für Partner-Medien (Intro-Audio,
// Avatar) NUR wenn eine Berechtigung besteht. Die Dateien liegen im
// privaten "avatars"-Bucket; ohne diese Funktion wären sie für andere
// Nutzer unerreichbar (RLS erlaubt nur den eigenen Ordner).
//
// Berechtigungen:
//  - kind=avatar: nur wenn ein Match zwischen Aufrufer und Ziel existiert.
//    Bei "Find your Match"-Matches zusätzlich erst ab Quiz-Stufe 2
//    (serverseitig erzwungen, Audit E2).
//  - kind=intro: Intro-Vorstellungen sind das "Aushängeschild" im Modus
//    "Find your Match" und werden VOR dem Like angehört (Kandidaten-Deck).
//    Daher ist das Intro für authentifizierte Nutzer abrufbar, solange das
//    Zielprofil eine Vorstellung hinterlegt hat. Enthalten ist bewusst
//    keine PII - nur die Vorstellung selbst.
//
// WICHTIG (Bugfix): Die Match-Prüfung nutzt EIN EINZIGES .or() mit
// and()-Gruppen. Zwei verkettete .or()-Aufrufe würden sich gegenseitig
// überschreiben (supabase-js) - das hätte einen Auth-Bypass bedeutet
// ("existiert irgendein Match des Ziels" statt "Match zwischen uns").

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
const BUCKET = "avatars";
const URL_EXPIRES_IN = 3600;

// Strikte UUID-Validierung: targetUserId fließt in PostgREST-Filter und
// Storage-Pfade - ohne Prüfung wäre Filter-/Pfad-Injection möglich (M6).
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// CORS: Bewusst KEINE CORS-Header (Audit M7) – die Funktion wird nur von
// der nativen App aufgerufen; Browser-Zugriffe werden dadurch geblockt.
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Match GENAU zwischen user und target - oder null. */
async function getMatchBetween(
  user: string,
  target: string,
): Promise<{ id: number; created_via: string } | null> {
  const { data } = await supabaseAdmin
    .from("matches")
    .select("id, created_via")
    .or(
      `and(user_one_id.eq.${user},user_two_id.eq.${target}),` +
        `and(user_one_id.eq.${target},user_two_id.eq.${user})`,
    )
    .limit(1)
    .maybeSingle();
  return data ?? null;
}

/** Quiz-Freischaltstufe eines Matches (0, falls kein State existiert). */
async function quizUnlockLevel(matchId: number): Promise<number> {
  const { data } = await supabaseAdmin
    .from("match_quiz_state")
    .select("unlock_level")
    .eq("match_id", matchId)
    .maybeSingle();
  return (data?.unlock_level as number | undefined) ?? 0;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) {
    return json({ error: "Nicht authentifiziert" }, 401);
  }

  try {
    const {
      data: { user },
    } = await supabaseAdmin.auth.getUser(token);
    if (!user) {
      return json({ error: "Nicht authentifiziert" }, 401);
    }

    const body = await req.json();
    const targetUserId = (body.targetUserId ?? "").toString();
    const kind = (body.kind ?? "").toString();
    // Optionaler Dateipfad (nur Avatar-Hauptbild + max. 3 Zusatzbilder des
    // Ziels, 107). Default: avatar.jpg (Quiz-Flow, abwärtskompatibel).
    const requestedPath = typeof body.path === "string" ? body.path : "";

    if (
      !UUID_REGEX.test(targetUserId) ||
      (kind !== "avatar" && kind !== "intro")
    ) {
      return json({ error: "Ungültige Parameter" }, 400);
    }
    if (targetUserId === user.id) {
      return json({ error: "Ungültige Parameter" }, 400);
    }
    // Pfad-Allowlist gegen Storage-Pfad-Traversal (M6): strikt
    // "<targetUuid>/(avatar.jpg|photos/1..3.jpg)".
    const pathAllowlist = new RegExp(
      `^${targetUserId}/(avatar\\.jpg|photos/[123]\\.jpg)$`,
    );
    const filePath =
      kind === "avatar"
        ? (requestedPath !== "" ? requestedPath : `${targetUserId}/avatar.jpg`)
        : `${targetUserId}/intro.m4a`;
    if (kind === "avatar" && !pathAllowlist.test(filePath)) {
      return json({ error: "Ungültige Parameter" }, 400);
    }

    if (kind === "avatar") {
      const match = await getMatchBetween(user.id, targetUserId);
      if (!match) {
        console.log(`avatar 403: kein Match (caller=${user.id}, target=${targetUserId})`);
        return json({ error: "Kein Match" }, 403);
      }
      // Audit E2: Bei Find-your-Match-Matches wird das scharfe Foto erst
      // nach Quiz-Stufe 2 freigegeben - serverseitig erzwungen, nicht mehr
      // nur clientseitig unscharf dargestellt.
      if (match.created_via === "find_match") {
        const level = await quizUnlockLevel(match.id);
        if (level < 2) {
          console.log(`avatar 403: Quiz-Lock (match=${match.id}, via=${match.created_via}, level=${level})`);
          return json({ error: "Quiz nicht bestanden" }, 403);
        }
      }
      // 107: AES-Schlüssel/IV stammen aus der Profil-Zeile (Service-Role)
      // und werden NUR an berechtigte Betrachter ausgeliefert - nie mehr
      // über die Public-View. Legacy-Klartextpfade liefern key/iv = null.
      // Fix: Bei mehreren Refs mit gleichem Pfad (Re-Uploads) den LETZTEN
      // nehmen (Arrays werden appended, letzter = aktuellster Schlüssel).
      const { data: targetProfile } = await supabaseAdmin
        .from("profiles")
        .select("photos")
        .eq("user_id", targetUserId)
        .maybeSingle();
      const refs = Array.isArray((targetProfile as { photos?: unknown } | null)?.photos)
        ? ((targetProfile as { photos: unknown[] }).photos as string[])
        : [];
      const matching = refs.filter(
        (r) => typeof r === "string" && r.split("|")[0] === filePath,
      );
      const ref = matching.length > 0 ? matching[matching.length - 1] : undefined;
      let keyB64: string | null = null;
      let ivB64: string | null = null;
      if (typeof ref === "string") {
        const parts = ref.split("|");
        if (parts.length >= 3) {
          keyB64 = parts[1] || null;
          ivB64 = parts[2] || null;
        }
      }

      const { data: signed, error } = await supabaseAdmin.storage
        .from(BUCKET)
        .createSignedUrl(filePath, URL_EXPIRES_IN);

      if (error || !signed) {
        return json({ error: "Datei nicht gefunden" }, 404);
      }

      return json({
        url: signed.signedUrl,
        expiresIn: URL_EXPIRES_IN,
        keyB64,
        ivB64,
      });
    } else {
      // Intro: Zielprofil muss existieren und eine Vorstellung haben.
      const { data: target } = await supabaseAdmin
        .from("profiles")
        .select("intro_audio_path")
        .eq("user_id", targetUserId)
        .maybeSingle();
      if (!target || !target.intro_audio_path) {
        return json({ error: "Keine Vorstellung vorhanden" }, 404);
      }
    }

    // Nur noch Intro erreicht diese Stelle (Avatar returned oben früh).
    const introPath = `${targetUserId}/intro.m4a`;

    const { data: signed, error } = await supabaseAdmin.storage
      .from(BUCKET)
      .createSignedUrl(introPath, URL_EXPIRES_IN);

    if (error || !signed) {
      return json({ error: "Datei nicht gefunden" }, 404);
    }

    return json({ url: signed.signedUrl, expiresIn: URL_EXPIRES_IN });
  } catch (e) {
    console.error("match-media error:", e);
    return json({ error: "Interner Fehler" }, 500);
  }
});
