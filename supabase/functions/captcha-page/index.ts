import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// captcha-page: Liefert das CAPTCHA-Widget-HTML (Cloudflare Turnstile oder
// hCaptcha) auf der Supabase-Projekt-Domain aus.
//
// HINTERGRUND: Turnstile/hCaptcha validieren den Hostnamen der aufrufenden
// Seite gegen die Widget-Konfiguration. Ein WebView mit loadHtmlString()
// hätte die Origin "about:blank" und würde abgelehnt (Turnstile-Fehler
// invalid domain). Diese Seite läuft dagegen unter
//   https://<project-ref>.supabase.co/functions/v1/captcha-page
// – dieser Hostname muss im Anbieter-Dashboard im Widget registriert sein.
//
// Query-Parameter (beide öffentlich, keine Secrets):
//   provider = turnstile | hcaptcha
//   sitekey  = öffentlicher Sitekey des Widgets
//
// config.toml: verify_jwt = false (Seite muss ohne Anmeldung ladbar sein).
// Das zugehörige SECRET liegt ausschließlich im Supabase Dashboard
// (Authentication -> CAPTCHA) und validiert das vom Client übermittelte
// Token bei signUp.

const ALLOWED_ORIGINS = new Set(["turnstile", "hcaptcha"]);

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

serve((req) => {
  const url = new URL(req.url);
  const provider = (url.searchParams.get("provider") ?? "").toLowerCase();
  const sitekey = url.searchParams.get("sitekey") ?? "";

  // Fail-closed: Nur erlaubte Anbieter, Sitekey muss wie ein Sitekey
  // aussehen ( Turnstile: 0x..., hCaptcha: UUID). Verhindert HTML-Injection
  // über Query-Parameter.
  const sitekeyOk = /^[A-Za-z0-9_-]{8,128}$/.test(sitekey);
  if (!ALLOWED_ORIGINS.has(provider) || !sitekeyOk) {
    return new Response("Invalid captcha configuration", { status: 400 });
  }

  const scriptUrl = provider === "turnstile"
    ? "https://challenges.cloudflare.com/turnstile/v0/api.js"
    : "https://js.hcaptcha.com/1/api.js";
  const widgetClass = provider === "turnstile"
    ? "cf-turnstile"
    : "h-captcha";
  const sitekeyAttr = escapeHtml(sitekey);

  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script src="${scriptUrl}" async defer></script>
</head>
<body style="margin:0;display:flex;justify-content:center;align-items:flex-start;padding-top:24px;background:#ffffff">
  <div class="${widgetClass}" data-sitekey="${sitekeyAttr}" data-callback="onCaptchaOk"></div>
  <script>
    function onCaptchaOk(token) {
      Captcha.postMessage(token);
    }
  </script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      // BEFUND 04.11.2026: Die Seite hatte keine Sicherheits-Header.
      // Ohne frame-ancestors liess sie sich in ein fremdes iframe
      // einbetten - Clickjacking auf das CAPTCHA. Ohne
      // X-Content-Type-Options kann der Browser den Inhalt
      // eigenmaechtig interpretieren.
      "Content-Security-Policy":
        "default-src 'self'; script-src 'self' 'unsafe-inline' " +
        "https://challenges.cloudflare.com https://js.hcaptcha.com; " +
        "frame-src https://challenges.cloudflare.com https://js.hcaptcha.com; " +
        "style-src 'self' 'unsafe-inline'; img-src 'self' data:; " +
        "frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "Referrer-Policy": "no-referrer",
    },
  });
});
