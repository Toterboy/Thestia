// Supabase Edge Function: /delete-user-data
//
// Loescht einzelne Datenkategorien eines Kontos - OHNE das Konto zu
// loeschen (Art. 17 DSGVO, Art. 19 DSGVO).
//
// BISHER (02.11.2026): Es gab NUR die vollstaendige Kontoloeschung. Wer
// z. B. nur seinen Standort loeschen wollte, musste das Konto
// aufgeben. Das ist mehr, als das Gesetz verlangt, und fuer Menschen
// mit einer Lieblings-App eine ueberzogene Huerde.
//
// WAS HIER GESCHIEHT:
//
//   Der Aufrufer waehlt Kategorien. Die Funktion loescht genau diese -
//   serverseitig, mit der Service-Rolle, und immer nur die Daten
//   dieses einen Kontos.
//
// WICHTIG - und das ist der Kern:
//
//   * Das Konto bleibt. E-Mail, Passwort und die Anmeldung bleiben.
//   * Jede Loeschung ist unwiderruflich. Es gibt keinen "Wiederherstellen".
//   * Jede Kategorie loescht NUR die Daten des Aufrufers. Wo ein
//     Funke oder eine Nachricht auch die Gegenseite betrifft, wird das
//     im Text der App gesagt (z. B. endet der Chat fuer beide).
//
// DIE KATEGORIEN (das, was der Nutzer ankreuzen kann):
//
//   fotos         Profilfotos (Storage) und die Fotoliste
//   standort      Koordinaten und Bundesland
//   profil        Bio, Interessen, Musik, Intro, Vorstellung
//   likes         gesetzte und erhaltene Likes
//   funken        Funken (Matches) - beendet den Chat fuer beide
//   nachrichten   die von dir gesendeten Nachrichten (E2E-Chiffrat)
//   geraete       Geraeteliste, Passkeys, Push-Token, Prekeys
//   stimmung      Stimmung und Gewohnheiten (Mood, Smoking, ...)
//   meldungen     deine Meldungen und Fehlerberichte
//   transit       Transit-Spark-Daten (BLE-Signale, Praesenz, Pings)
//   elternaufsicht  die elterliche Freigabe (nur ab 18)
//   alles         alle Daten - das Konto bleibt
//
// AUTH: Der Aufrufer muss mit seinem JWT angemeldet sein (die App
// ruft die Funktion mit dem User-Token auf). Die Funktion loescht NUR
// fuer die UID dieses Tokens.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";

// Buckets mit nutzerbezogenen Objekten (Ordner = User-ID).
const USER_SCOPED_BUCKETS = ["avatars", "verification-videos"];

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
  if (single.length > 0) out.push({ key: single, source: "sbcustom" });
  return out;
}

async function _probeServiceKey(key: string): Promise<boolean> {
  // Echter Rechte-Nachweis (kein SELECT-Indiz!): ein No-op-DELETE auf
  // bug_reports mit einer unmoeglichen UUID.
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

let _adminCache: ReturnType<typeof createClient> | null = null;

async function admin(): Promise<ReturnType<typeof createClient>> {
  if (_adminCache) return _adminCache;
  for (const c of _keyCandidates()) {
    if (await _probeServiceKey(c.key)) {
      _adminCache = createClient(SUPABASE_URL, c.key, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
      return _adminCache;
    }
  }
  throw new Error("kein brauchbarer Service-Key");
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Loescht alle Objekte unter `<bucket>/<userId>/`. */
async function purgeUserStorage(
  client: ReturnType<typeof createClient>,
  bucket: string,
  userId: string,
  warnungen: string[],
): Promise<void> {
  try {
    const { data: list, error: listError } = await client.storage
      .from(bucket)
      .list(userId);
    if (listError) {
      warnungen.push(`${bucket}: list fehlgeschlagen`);
      return;
    }
    const pfade = (list ?? [])
      .filter((o) => o.name)
      .map((o) => `${userId}/${o.name}`);
    if (pfade.length === 0) return;
    const { error } = await client.storage.from(bucket).remove(pfade);
    if (error) {
      warnungen.push(`${bucket}: remove fehlgeschlagen`);
    }
  } catch (e) {
    warnungen.push(`${bucket}: ${e}`);
  }
}

/** Ein Loeschvorgang: Tabelle, Filter, Spalten-Feld. */
type Loeschung = {
  tabelle: string;
  filter: (c: ReturnType<typeof createClient>) => PromiseLike<
    { error: { message: string } | null; count?: number | null }
  >;
};

async function loesche(
  client: ReturnType<typeof createClient>,
  loeschungen: Loeschung[],
  warnungen: string[],
  bericht: Record<string, number>,
): Promise<void> {
  for (const l of loeschungen) {
    try {
      const { error, count } = await l.filter(client);
      if (error) {
        warnungen.push(`${l.tabelle}: ${error.message}`);
      } else {
        bericht[l.tabelle] = count ?? 0;
      }
    } catch (e) {
      warnungen.push(`${l.tabelle}: ${e}`);
    }
  }
}

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let supabaseAdmin: ReturnType<typeof createClient>;
  try {
    supabaseAdmin = await admin();
  } catch (e) {
    console.error("delete-user-data: Service-Key:", e);
    return json({ error: "server_error" }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Unauthorized" }, 401);

  const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);
  if (authError || !user) {
    return json({ error: "Sitzung ungueltig - bitte neu anmelden" }, 401);
  }
  const uid = user.id;

  let body: { kategorien?: string[] };
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Invalid JSON" }, 400);
  }

  const gewaehlt = new Set(
    (body.kategorien ?? []).map((k) => String(k).toLowerCase()),
  );
  if (gewaehlt.size === 0) return json({ error: "keine Auswahl" }, 400);

  const alles = gewaehlt.has("alles");
  const will = (k: string) => alles || gewaehlt.has(k);

  const warnungen: string[] = [];
  const bericht: Record<string, number> = {};

  // -------------------------------------------------------------------
  // Fotos
  // -------------------------------------------------------------------
  if (will("fotos")) {
    for (const bucket of USER_SCOPED_BUCKETS) {
      await purgeUserStorage(supabaseAdmin, bucket, uid, warnungen);
    }
    await loesche(supabaseAdmin, [
      {
        tabelle: "profiles.photos",
        filter: (c) =>
          c.from("profiles").update({ photos: "{}" }).eq("user_id", uid)
            .select("user_id"),
      },
    ], warnungen, bericht);
  }

  // -------------------------------------------------------------------
  // Standort
  // -------------------------------------------------------------------
  if (will("standort")) {
    await loesche(supabaseAdmin, [
      {
        tabelle: "profile_locations",
        filter: (c) =>
          c.from("profile_locations").delete().eq("user_id", uid).select("user_id"),
      },
      {
        tabelle: "profiles.state",
        filter: (c) =>
          c.from("profiles").update({ state: null }).eq("user_id", uid)
            .select("user_id"),
      },
    ], warnungen, bericht);
  }

  // -------------------------------------------------------------------
  // Profilangaben
  // -------------------------------------------------------------------
  if (will("profil")) {
    await loesche(supabaseAdmin, [
      {
        tabelle: "profiles",
        filter: (c) =>
          c.from("profiles").update({
            bio: "",
            interests: "[]",
            music_liked: "{}",
            music_disliked: "{}",
            intro_text: "",
            intro_audio_path: null,
            personality_type: null,
            smoking: null,
            alcohol: null,
            drugs: null,
            favorite_song: null,
            favorite_band: null,
            birthday_style: null,
          }).eq("user_id", uid).select("user_id"),
      },
    ], warnungen, bericht);
  }

  // -------------------------------------------------------------------
  // Likes
  // -------------------------------------------------------------------
  if (will("likes")) {
    await loesche(supabaseAdmin, [
      {
        tabelle: "likes (gesetzt)",
        filter: (c) =>
          c.from("likes").delete().eq("user_id", uid).select("user_id"),
      },
      {
        tabelle: "likes (erhalten)",
        filter: (c) =>
          c.from("likes").delete().eq("liked_user_id", uid).select("user_id"),
      },
    ], warnungen, bericht);
  }

  // -------------------------------------------------------------------
  // Funken (Matches)
  // -------------------------------------------------------------------
  if (will("funken")) {
    await loesche(supabaseAdmin, [
      {
        tabelle: "matches",
        filter: (c) =>
          c.from("matches").delete().or(`user_one_id.eq.${uid},user_two_id.eq.${uid}`)
            .select("user_one_id"),
      },
      {
        tabelle: "match_bucket_list",
        filter: (c) =>
          c.from("match_bucket_list").delete().or(
            `user_one_id.eq.${uid},user_two_id.eq.${uid}`,
          ).select("user_one_id"),
      },
    ], warnungen, bericht);
  }

  // -------------------------------------------------------------------
  // Nachrichten
  // -------------------------------------------------------------------
  // Nur die selbst gesendeten: die empfangenen sind die Daten der
  // Gegenseite (E2E-Chiffrat, von ihr gesendet). Sie verschwinden
  // fuer die Gegenseite ohnehin, wenn sie ihren Funken beendet.
  if (will("nachrichten")) {
    await loesche(supabaseAdmin, [
      {
        tabelle: "messages",
        filter: (c) =>
          c.from("messages").delete().eq("sender_id", uid).select("sender_id"),
      },
      {
        tabelle: "direct_message_relay",
        filter: (c) =>
          c.from("direct_message_relay").delete().or(
            `sender_id.eq.${uid},receiver_id.eq.${uid}`,
          ).select("sender_id"),
      },
    ], warnungen, bericht);
  }

  // -------------------------------------------------------------------
  // Geraete, Passkeys, Push
  // -------------------------------------------------------------------
  if (will("geraete")) {
    await loesche(supabaseAdmin, [
      {
        tabelle: "auth_devices",
        filter: (c) =>
          c.from("auth_devices").delete().eq("user_id", uid).select("user_id"),
      },
      {
        tabelle: "prekeys",
        filter: (c) =>
          c.from("prekeys").delete().eq("user_id", uid).select("user_id"),
      },
      {
        tabelle: "profiles.push",
        filter: (c) =>
          c.from("profiles").update({
            fcm_token: null,
            up_endpoint: null,
          }).eq("user_id", uid).select("user_id"),
      },
    ], warnungen, bericht);
  }

  // -------------------------------------------------------------------
  // Stimmung und Gewohnheiten
  // -------------------------------------------------------------------
  if (will("stimmung")) {
    await loesche(supabaseAdmin, [
      {
        tabelle: "user_mood",
        filter: (c) =>
          c.from("user_mood").delete().eq("user_id", uid).select("user_id"),
      },
    ], warnungen, bericht);
  }

  // -------------------------------------------------------------------
  // Meldungen und Berichte
  // -------------------------------------------------------------------
  if (will("meldungen")) {
    await loesche(supabaseAdmin, [
      {
        tabelle: "user_reports",
        filter: (c) =>
          c.from("user_reports").delete().eq("reporter_id", uid)
            .select("reporter_id"),
      },
      {
        tabelle: "bug_reports",
        filter: (c) =>
          c.from("bug_reports").delete().eq("user_id", uid).select("user_id"),
      },
      {
        tabelle: "photo_moderation",
        filter: (c) =>
          c.from("photo_moderation").delete().eq("user_id", uid)
            .select("user_id"),
      },
      {
        tabelle: "profile_photo_appeals",
        filter: (c) =>
          c.from("profile_photo_appeals").delete().eq("user_id", uid)
            .select("user_id"),
      },
    ], warnungen, bericht);
  }

  // -------------------------------------------------------------------
  // Transit Spark (BLE)
  // -------------------------------------------------------------------
  if (will("transit")) {
    await loesche(supabaseAdmin, [
      {
        tabelle: "transit_signals",
        filter: (c) =>
          c.from("transit_signals").delete().eq("user_id", uid).select("user_id"),
      },
      {
        tabelle: "transit_presence",
        filter: (c) =>
          c.from("transit_presence").delete().eq("user_id", uid).select("user_id"),
      },
      {
        tabelle: "transit_soft_pings",
        filter: (c) =>
          c.from("transit_soft_pings").delete().or(
            `from_user_id.eq.${uid},to_user_id.eq.${uid}`,
          ).select("from_user_id"),
      },
    ], warnungen, bericht);
  }

  // -------------------------------------------------------------------
  // Elternaufsicht (nur ab 18 sinnvoll - darunter ist die Freigabe
  // die Grundlage der Alterspruefung und geht mit dem Konto).
  // -------------------------------------------------------------------
  if (will("elternaufsicht")) {
    await loesche(supabaseAdmin, [
      {
        tabelle: "guardian_consents",
        filter: (c) =>
          c.from("guardian_consents").delete().eq("child_user_id", uid)
            .select("child_user_id"),
      },
      {
        tabelle: "guardian_notification_events",
        filter: (c) =>
          c.from("guardian_notification_events").delete().eq("child_user_id", uid)
            .select("child_user_id"),
      },
      {
        tabelle: "profiles.supervision",
        filter: (c) =>
          c.from("profiles").update({
            supervised: false,
            consent_state: "none",
            consent_parent_ref: null,
            consent_verified_at: null,
            consent_revoked_at: null,
            guardian_transition_done: true,
          }).eq("user_id", uid).select("user_id"),
      },
    ], warnungen, bericht);
  }

  // -------------------------------------------------------------------
  // ALLES: das Profil auf das Minimum zuruecksetzen. Das Konto bleibt.
  // -------------------------------------------------------------------
  if (alles) {
    await loesche(supabaseAdmin, [
      {
        tabelle: "profiles (Rest)",
        filter: (c) =>
          c.from("profiles").update({
            name: "",
            verified_age: null,
            is_verified: false,
            verification_status: "unverified",
            show_distance: false,
            ui_prefs: null,
          }).eq("user_id", uid).select("user_id"),
      },
      {
        tabelle: "rate_limit_hits",
        filter: (c) =>
          c.from("rate_limit_hits").delete().eq("identifier", uid)
            .select("identifier"),
      },
      {
        tabelle: "profile_photo_appeals",
        filter: (c) =>
          c.from("profile_photo_appeals").delete().eq("user_id", uid)
            .select("user_id"),
      },
    ], warnungen, bericht);
  }

  return json({
    ok: warnungen.length === 0,
    geloescht: bericht,
    warnungen,
  });
});
