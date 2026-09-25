// Supabase Edge Function: /confirm
//
// Bestätigungs-Redirect aus der E-Mail. Leitet direkt zur GoTrue-Verify-Seite
// weiter (302), damit der Nutzer mit EINEM Klick bestätigt.
//
// WICHTIG: HTML-Antworten von Edge Functions werden vom Supabase-Gateway als
// text/plain ausgeliefert (CSP "default-src 'none'; sandbox" + nosniff) und
// wuerden als Quelltext angezeigt. Deshalb hier KEIN HTML.
//
// GoTrue GET /auth/v1/verify liest NUR den Query-Parameter "token" und
// wertet ihn als Token-HASH aus ("token_hash" im Query wird ignoriert ->
// 400 "Verify requires a token or a token hash"). Der E-Mail-Link enthält
// deshalb den Hash ("sha256$<hex>" aus email_data.token_hash) und wird hier
// unverändert als "token" weitergereicht.
//
// Nach erfolgreicher Verifikation leitet GoTrue zu "redirect_to" weiter.
// Wir zeigen dafür eine schlichte Text-Seite an (text/plain rendert der
// Browser sauber). Ohne redirect_to wuerde GoTrue zur Site-Root
// (<ref>.supabase.co) leiten, wo das Gateway "requested path is invalid"
// anzeigt.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const CONFIRM_URL = `${SUPABASE_URL}/functions/v1/confirm`;

serve(async (req) => {
  const url = new URL(req.url);
  const token = url.searchParams.get("token") ?? "";
  const type = url.searchParams.get("type") ?? "signup";

  // Nach der Verifikation landet der Nutzer ohne Token wieder hier ->
  // Erfolgsmeldung als Klartext anzeigen (text/plain wird korrekt gerendert).
  if (!token) {
    return new Response(
      "Deine E-Mail-Adresse wurde bestätigt. ✅\n\n" +
        "Du kannst dieses Fenster schließen und zur Thestia-App zurückkehren – " +
        "sie erkennt die Bestätigung automatisch und geht weiter.",
      { status: 200, headers: { "Content-Type": "text/plain; charset=utf-8" } },
    );
  }

  const verifyUrl = `${SUPABASE_URL}/auth/v1/verify?token=${encodeURIComponent(token)}&type=${encodeURIComponent(type)}&redirect_to=${encodeURIComponent(CONFIRM_URL)}`;

  return Response.redirect(verifyUrl, 302);
});
