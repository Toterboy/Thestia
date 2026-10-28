#!/usr/bin/env python3
"""Gemeinsames Web-Design fuer alle Seiten in passkey-assets/.

DREI VORGABEN, die hier zusammenkommen:

1. NUTZERWUNSCH (27.10.2026): Dark- und Light-Mode mit einem kleinen
   Umschalt-Knopf, und alles abgerundet - die Seiten sollen zum Design
   der App passen.

2. NUTZERWUNSCH (27.10.2026, zweite Runde): "Die Websiten sehen
   grauenhaft aus. Die Schriftart ist schlimm. Der Button zum Umschalten
   sieht vom Icon nicht ganz logisch aus." Daraus wurden drei Regeln:
     * eine echte Typografie (System-Schrift in der richtigen
       Reihenfolge, groessere Grundgroesse, klare Hierarchie, Zeilenlaenge
       begrenzt) statt der vorherigen Standard-Browser-Schrift,
     * eine Karten-Anordnung wie in der App (Karte auf getoentem
       Grund, Radius 24) statt einer nackten Textseite,
     * ein Umschalt-Knopf mit EINEM logischen Symbol.

3. PROJEKTREGEL: Die veroeffentlichten Seiten sind bewusst statisch.
   Kein JavaScript, keine externen Requests - das prueft
   test/privacy_policy_test.dart ("Die HTML-Datei ist statisch - kein
   Skript, keine externen Requests"). Ein Skript waere hier nicht nur
   unnoetig, es waere auch ein Grund, die Seite nicht mehr ohne
   Weiteres zu statischen Dateien zu halten.

DER UMSCHALTER OHNE JAVASCRIPT:

Ein echter Schalter, versteckt, plus ein sichtbares Label - beides
reines CSS ueber die Pseudo-Klasse :has():

    <input type="checkbox" id="modus-umschalter" class="modus-schalter">
    <label for="modus-umschalter" class="modus-knopf"> ... </label>

    html:has(#modus-umschalter:checked) { --bg: #0e0e13; ... }

Vorteile:
  * Die Checkbox bleibt fokussierbar und mit der Leertaste bedienbar -
    ein <label> allein waere fuer die Tastatur tot.
  * Der Klick auf das Label schaltet die Checkbox um, das Label ist der
    sichtbare Knopf.
  * Kein Skript, keine Speicherung, keine Anfrage.

Nachteil, ehrlich benannt: die Wahl ueberlebt das Neuladen NICHT (ohne
localStorage). Beim naechsten Besuch gilt wieder die Systemeinstellung.
Das ist der Preis fuer die Projektregel "statische Seite".

Browser ohne :has() (sehr alte Safari/Firefox) zeigen die Seite im
hellen Modus; `color-scheme: light dark` faerbt trotzdem die
Formularfelder und die Scrollleiste ein.

DAS SYMBOL DES KNOPFS (Nutzerwunsch, zweite Runde):

Vorher standen dort zwei Unicode-Zeichen (U+263D und U+263E, beides
Halbmonde) nebeneinander - die sahen weder nach Sonne noch nach Mond
aus und je nach System unterschiedlich aus. Jetzt ist es ein
SVG-Symbolpaar aus den Material-Icons (dark_mode / light_mode).

DIE LOGIK: das Symbol zeigt den Modus, in den man WECHSELT, nicht den,
in dem man ist. Im hellen Modus steht ein MOND (Klick = dunkel), im
dunklen Modus eine SONNE (Klick = hell). Das ist die uebliche
Konvention und die einzige, die man nicht nachschlagen muss.
"""

# Die Variablen und das, was der Knopf braucht.
THEME_CSS = """
    /* Web-Design (tool/web_theme.py) */
    /* ---------------------------------------------------------------
       Eine Quelle fuer alle Seiten.

       Die Farben kommen aus der App: Primaer #E9457B, heller
       Grund #F7F7FB, Karten weiss, dunkler Grund #121212, Karten
       #1E1E1E. Die Linkfarbe ist eine dunklere Variante des Rosa
       (#d62d6c), damit sie auf weiss den Kontrast-Anspruch von 4,5:1
       erreicht.
       --------------------------------------------------------------- */
    :root {
      color-scheme: light dark;
      --bg: #f2f2f8;
      --fg: #1b1b21;
      --muted: #575764;
      --card: #ffffff;
      --card-fg: #1b1b21;
      --line: #e4e2ee;
      --accent: #d62d6c;
      --accent-soft: rgba(214,45,108,.08);
      --accent-line: rgba(214,45,108,.30);
      --accent-fg: #ffffff;
      --shadow-sm: 0 1px 2px rgba(25,18,45,.06);
      --shadow: 0 1px 2px rgba(25,18,45,.04),
                 0 20px 44px -24px rgba(25,18,45,.40);
      --radius: 24px;
      --radius-s: 14px;
    }
    html:has(#modus-umschalter:checked) {
      --bg: #0e0e13;
      --fg: #ece9f2;
      --muted: #a29fb0;
      --card: #191920;
      --card-fg: #ece9f2;
      --line: #2b2a35;
      --accent: #ff86b3;
      --accent-soft: rgba(255,134,179,.12);
      --accent-line: rgba(255,134,179,.34);
      --accent-fg: #17161c;
      --shadow-sm: 0 1px 2px rgba(0,0,0,.55);
      --shadow: 0 1px 2px rgba(0,0,0,.40),
                 0 24px 48px -24px rgba(0,0,0,.85);
    }

    *, *::before, *::after { box-sizing: border-box; }

    html { -webkit-text-size-adjust: 100%; }

    body {
      margin: 0;
      padding: 0;
      max-width: none;
      background: var(--bg);
      color: var(--fg);
      /* Die Reihenfolge ist wichtig: `system-ui` zuerst nimmt die
         System-Schrift (San Francisco, Segoe UI Variable, Roboto) -
         das ist auf jedem Geraet die Schrift, fuer die die App gebaut
         ist. Die konkreten Namen danach sind der Fallback fuer
         aeltere Systeme, `sans-serif` der letzte Notnagel. */
      font-family: system-ui, -apple-system, "Segoe UI Variable Text",
                   "Segoe UI", Roboto, "Helvetica Neue", "Noto Sans",
                   Arial, sans-serif;
      font-size: 17px;
      line-height: 1.7;
      letter-spacing: -0.003em;
      -webkit-font-smoothing: antialiased;
      -moz-osx-font-smoothing: grayscale;
      text-rendering: optimizeLegibility;
    }

    /* --- Kopfzeile: Marke, Name, Umschalter ------------------------ */
    .kopf {
      position: sticky;
      top: 0;
      z-index: 10;
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 12px clamp(16px, 5vw, 40px);
      background: var(--bg);
      border-bottom: 1px solid var(--line);
    }
    .marke { display: inline-flex; line-height: 0; }
    .marke svg { display: block; width: 26px; height: 26px; }
    .marken-text {
      font-weight: 700;
      font-size: 1.05rem;
      letter-spacing: -0.015em;
    }

    /* Die Checkbox bleibt im Quelltext (Tastatur!), ist aber nicht
       sichtbar. Der Klick geht ueber das Label. */
    .modus-schalter {
      position: absolute;
      width: 1px;
      height: 1px;
      margin: 0;
      opacity: 0;
      pointer-events: none;
    }
    .modus-knopf {
      margin-left: auto;
      width: 42px;
      height: 42px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      border: 1px solid var(--line);
      border-radius: 999px;
      background: var(--card);
      color: var(--fg);
      box-shadow: var(--shadow-sm);
      cursor: pointer;
      transition: transform .15s ease, color .2s ease,
                  border-color .2s ease, background .2s ease;
    }
    .modus-knopf:hover {
      transform: scale(1.06);
      color: var(--accent);
      border-color: var(--accent-line);
    }
    .modus-knopf:active { transform: scale(.97); }
    .modus-schalter:focus-visible + .modus-knopf {
      outline: 2px solid var(--accent);
      outline-offset: 3px;
    }
    .modus-knopf svg { width: 20px; height: 20px; }

    /* Das Symbol zeigt den ZIEL-Modus: Mond im hellen Modus (Klick
       = dunkel), Sonne im dunklen Modus (Klick = hell). */
    .modus-knopf .icon-sonne { display: none; }
    html:has(#modus-umschalter:checked) .modus-knopf .icon-sonne {
      display: block;
    }
    html:has(#modus-umschalter:checked) .modus-knopf .icon-mond {
      display: none;
    }

    /* --- Inhalt: eine Karte auf getoentem Grund -------------------- */
    .inhalt {
      max-width: 46rem;
      margin: clamp(16px, 3vw, 32px) auto 0;
      padding: clamp(22px, 4vw, 32px);
      background: var(--card);
      color: var(--card-fg);
      border: 1px solid var(--line);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
    }
    .inhalt > :first-child { margin-top: 0; }
    .inhalt > :last-child { margin-bottom: 0; }

    /* --- Typografie ----------------------------------------------- */
    h1 {
      font-size: clamp(1.7rem, 1.2rem + 1.8vw, 2.15rem);
      line-height: 1.15;
      letter-spacing: -0.025em;
      font-weight: 700;
      margin: 0 0 .35rem;
    }
    h1 + p.lead { margin-top: 0; }
    h2 {
      font-size: 1.22rem;
      line-height: 1.3;
      letter-spacing: -0.012em;
      font-weight: 650;
      margin: 2.4rem 0 .7rem;
      padding-top: 1.4rem;
      border-top: 1px solid var(--line);
    }
    h3 {
      font-size: 1.03rem;
      line-height: 1.35;
      font-weight: 650;
      margin: 1.6rem 0 .5rem;
    }
    p { margin: 0 0 1.05rem; }
    p.lead {
      color: var(--muted);
      font-size: 1.06rem;
      margin-bottom: 1.6rem;
    }
    .klein { color: var(--muted); font-size: .9rem; }
    strong { font-weight: 650; }
    em { font-style: italic; }
    a {
      color: var(--accent);
      text-decoration: underline;
      text-decoration-thickness: 1px;
      text-underline-offset: 2px;
      text-decoration-color: var(--accent-line);
    }
    a:hover { text-decoration-color: var(--accent); }

    ul, ol { margin: .4rem 0 1.25rem; padding-left: 1.35rem; }
    li { margin-bottom: .4rem; }
    li::marker { color: var(--accent); }

    /* Hinweis-Boxen: wie die tonalen Karten der App. */
    .box, .hinweis {
      background: var(--accent-soft);
      color: var(--card-fg);
      border: 1px solid var(--accent-line);
      border-left: 1px solid var(--accent-line);
      border-radius: var(--radius-s);
      padding: 1rem 1.15rem;
      margin: 1.6rem 0;
    }
    .box > :last-child, .hinweis > :last-child { margin-bottom: 0; }

    /* --- Tabellen: abgerundete Karten ----------------------------- */
    .tabellen-huelle {
      overflow-x: auto;
      margin: 1.4rem 0 1.6rem;
      border-radius: 20px;
      border: 1px solid var(--line);
      background: var(--card);
      box-shadow: var(--shadow);
    }
    table {
      border-collapse: separate;
      border-spacing: 0;
      width: 100%;
      margin: 0;
      /* 0,88 rem statt 0,95: die grosse Tabelle der
         Datenschutzerklaerung brauchte 693 px, die Karte bietet 672 px.
         Mit der kleineren Schrift passt sie in die Karte - sonst
         schneidet der Kartenrand die letzte Spalte ab. */
      font-size: .88rem;
      background: var(--card);
      color: var(--card-fg);
    }
    th, td {
      border: 0;
      padding: .65rem .75rem;
      text-align: left;
      vertical-align: top;
    }
    th { font-weight: 650; }
    thead th {
      background: var(--accent-soft);
      border-bottom: 1px solid var(--line);
      white-space: nowrap;
    }
    tbody tr + tr td { border-top: 1px solid var(--line); }

    footer {
      max-width: 46rem;
      margin: 0 auto;
      padding: 20px clamp(16px, 4vw, 28px) 56px;
      color: var(--muted);
      font-size: .88rem;
    }
    footer p { margin-bottom: .4rem; }

    @media (max-width: 560px) {
      body { font-size: 16px; }
      table { font-size: .88rem; }
      th, td { padding: .6rem .7rem; }
    }
"""

# Der Schalter und sein sichtbares Label.
#
# Die Checkbox kommt ZUERST: das Label greift ueber `for` auf sie zu und
# die CSS-Regel `.modus-schalter:focus-visible + .modus-knopf` braucht das
# Label als unmittelbar nachfolgenden Geschwister.
#
# DIE SYMBOLE: Material-Icons als SVG (dark_mode / light_mode). Vorher
# standen hier zwei Unicode-Halbmonde - die wirkten weder wie eine Sonne
# noch wie ein Mond.
_SVG_SONNE = (
    '<svg class="icon-sonne" viewBox="0 0 24 24" fill="none" '
    'stroke="currentColor" stroke-width="1.8" stroke-linecap="round" '
    'aria-hidden="true">'
    '<circle cx="12" cy="12" r="4"/>'
    '<path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4'
    'M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>'
    '</svg>'
)
_SVG_MOND = (
    '<svg class="icon-mond" viewBox="0 0 24 24" fill="none" '
    'stroke="currentColor" stroke-width="1.8" stroke-linecap="round" '
    'stroke-linejoin="round" aria-hidden="true">'
    '<path d="M12 3a9 9 0 1 0 9 9 7 7 0 0 1-9-9Z"/>'
    '</svg>'
)

# Die Marke: das Herz der App in ihrem Verlaufsrot-Violett.
_SVG_MARKE = (
    '<svg viewBox="0 0 24 24" aria-hidden="true">'
    '<defs><linearGradient id="thestia-marke" x1="0" y1="0" x2="1" y2="1">'
    '<stop offset="0" stop-color="#ff6b95"/>'
    '<stop offset="1" stop-color="#7b4dd6"/>'
    '</linearGradient></defs>'
    '<path fill="url(#thestia-marke)" '
    'd="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 '
    '7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 '
    '22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>'
    '</svg>'
)

# Die Kopfzeile mit Marke, Name und Umschalt-Knopf.
KOPF_HTML = (
    '<header class="kopf">\n'
    '  <span class="marke">' + _SVG_MARKE + '</span>\n'
    '  <span class="marken-text">Thestia</span>\n'
    '  <input type="checkbox" id="modus-umschalter" class="modus-schalter" '
    'aria-label="Dark- und Light-Mode umschalten">\n'
    '  <label for="modus-umschalter" class="modus-knopf" '
    'title="Dark- und Light-Mode umschalten">'
    + _SVG_MOND + _SVG_SONNE +
    '</label>\n'
    '</header>'
)

# Kurzname fuer den Generator, der bisher ein eigenes CSS hatte.
CSS = THEME_CSS

# Marker: daran erkennt apply_theme(), dass eine Seite schon bearbeitet
# wurde. Ohne ihn waere jeder Lauf ein zweiter Durchgang.
MARKER = '/* Web-Design (tool/web_theme.py) */'

# AELTERE Marker. Das Design wurde zweimal ueberarbeitet; wer eine Seite
# mit einer aelteren Fassung bearbeitet, traegt deren CSS sonst ZUSAETZLICH
# zum neuen - zwei Umschalter-Regeln und ein Knopf an zwei Stellen.
# Deshalb werden beim Entfernen alle bekannten Marker beruecksichtigt.
AELTERE_MARKER = [
    # Fassung 0 (28.10.2026, erste Fassung des Themes).
    '/* modus-knopf (tool/web_theme.py)',
    # Fassung 1 (28.10.2026, die "eine Quelle"-Fassung). Ihr Marker
    # war NICHT exakt der Anfang des CSS-Blocks - deshalb hat
    # strip_theme() sie nicht gefunden und jede Ausfuehrung hat eine
    # weitere Kopie eingefuegt (am Ende waren es sieben in einer
    # Seite). Deshalb stehen HIER alle bekannten Fassungen.
    'Web-Design (tool/web_theme.py) - eine Quelle',
]


def strip_theme(html: str, remove_chrome: bool = True) -> str:
    """Entfernt ein bereits eingespieltes Design samt Schalter.

    Nötig, weil das Design nachgebessert wurde: ohne dieses Entfernen
    stuende in jeder Seite zweimal das alte Theme-CSS und der alte
    Schalter daneben - zwei Umschalter auf einer Seite.

    [remove_chrome] = False: die Kopfzeile und die Inhalts-Huelle
    bleiben stehen. Das braucht die Captcha-Seite (index.html): ihre
    Kopfzeile ist Teil der Seite (sie traegt die Landing-Ansicht), und
    ihre Huelle wird nicht eingefuegt.
    """
    import re

    # 1) Den CSS-Block des Themes entfernen (Marker bis </style>).
    #    Bei mehreren Markern zaehlt der FRUEHESTE - dann ist der Rest
    #    des Style-Blocks genau der Block, der weg muss.
    positionen = [i for i in (html.find(m) for m in [MARKER] + AELTERE_MARKER)
                  if i >= 0]
    if positionen:
        i = min(positionen)
        j = html.find('</style>', i)
        if j >= 0:
            html = html[:i] + html[j:]

    if remove_chrome:
        # 2) Alten Schalter und altes Label entfernen.
        html = re.sub(r'<input[^>]*id="modus-umschalter"[^>]*>\s*', '', html)
        html = re.sub(
            r'<label[^>]*for="modus-umschalter"[^>]*>.*?</label>\s*', '', html,
            flags=re.S)
        # 3) Die alte Kopfzeile entfernen, falls sie schon existiert.
        html = re.sub(r'<header class="kopf">.*?</header>\s*', '', html,
                      flags=re.S)
        # 4) Die alte Inhalts-Huelle entfernen. Ohne diesen Schritt
        #    stapelt sich bei jedem Lauf eine weitere Huelle - der Inhalt
        #    saehe dann in einer Karte in einer Karte in einer Karte aus.
        html = html.replace('<div class="inhalt">\n', '')
        html = html.replace('<div class="inhalt">', '')
        html = re.sub(r'</div>\s*(<footer)', r'\1', html)
        html = re.sub(r'</div>\s*</body>', '</body>', html)
    return html


def apply_theme(html: str, css_extra: str = '',
                insert_chrome: bool = True) -> str:
    """Haengt Design, Kopfzeile und Umschalt-Knopf in eine HTML-Seite ein.

    [css_extra] sind seiten-eigene Regeln, die VOR den gemeinsamen
    kommen - die gemeinsamen gewinnen dann, weil sie spaeter im
    Style-Block stehen.

    [insert_chrome] = False: nur das gemeinsame CSS, keine Kopfzeile
    und keine Inhalts-Huelle. Das braucht die Captcha-Seite
    (index.html): sie hat ZWEI Ansichten (Sicherheitscheck und
    Landing-Seite) und bringt ihre eigene Kopfzeile mit - die
    gemeinsame Huelle wuerde den Sicherheitscheck in eine Karte
    packen.
    """
    # Ein altes Design wird entfernt, damit die Seite nie zweimal
    # gestyled wird. Die Kopfzeile wird nur entfernt, wenn sie auch
    # automatisch eingefuegt wurde.
    html = strip_theme(html, remove_chrome=insert_chrome)

    # 1) Die alte :root-Zeile ersetzen (sie setzt nur color-scheme).
    alt_root = ':root { color-scheme: light dark; }'
    if alt_root in html:
        html = html.replace(alt_root, '', 1)
    elif '<style>' in html:
        html = html.replace('<style>', '<style>\n    :root {\n'
                             '      color-scheme: light dark;\n    }', 1)

    # 2) Die gemeinsamen Regeln an den Style-Block haengen.
    if '</style>' in html:
        html = html.replace('</style>', css_extra + THEME_CSS + '</style>', 1)
    else:
        html = html.replace('</head>',
                            '<style>%s</style></head>' % (css_extra + THEME_CSS),
                            1)

    # Ohne Chrome (Captcha-Seite) ist hier Schluss: die Seite hat ihre
    # eigene Kopfzeile und zwei Ansichten.
    if not insert_chrome:
        return html

    # 3) Kopfzeile direkt nach <body>, Inhalt in die Karte.
    kopf = KOPF_HTML + '\n<div class="inhalt">\n'
    if '<body>' in html:
        html = html.replace('<body>', '<body>\n' + kopf, 1)
    elif '<body ' in html:
        import re as _re
        html = _re.sub(r'(<body[^>]*>)', r'\1\n' + kopf, html, count=1)

    # 4) Die Karte schliessen - VOR dem Fuss, falls die Seite einen
    #    hat. Der Fuss steht dann auf dem Seitenhintergrund und nicht
    #    in der Karte (wie die Fusszeile der App unter der Karte).
    if '<footer' in html:
        i = html.index('<footer')
        html = html[:i] + '</div>\n' + html[i:]
    else:
        html = html.replace('</body>', '</div>\n</body>', 1)

    return html
