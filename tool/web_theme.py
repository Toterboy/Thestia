#!/usr/bin/env python3
"""Gemeinsames Web-Design fuer alle Seiten in passkey-assets/.

ZWEI VORGABEN, die hier zusammenkommen:

1. NUTZERWUNSCH (27.10.2026): Dark- und Light-Mode mit einem kleinen
   Umschalt-Knopf, und alles abgerundet - die Seiten sollen zum Design
   der App passen (Radius 24 bei Karten).

2. PROJEKTREGEL: Die veroeffentlichten Seiten sind bewusst statisch.
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

    html:has(#modus-umschalter:checked) { --bg: #121212; ... }

Vorteile:
  * Die Checkbox bleibt fokussierbar und mit der Leertaste bedienbar -
    ein <label> allein waere fuer die Tastatur tot.
  * Der Klick auf das Label schaltet die Checkbox um, das Label ist der
    sichtbare Knopf.
  * Kein Skript, keine Speicherung, keine Anfrage.

Nachteil, ehrlich benannt: die Wahl ueberlebt das Neuladen NICHT (ohne
localStorage). Beim nächsten Besuch gilt wieder die Systemeinstellung.
Das ist der Preis fuer die Projektregel "statische Seite".

Browser ohne :has() (sehr alte Safari/Firefox) zeigen die Seite im
hellen Modus; `color-scheme: light dark` faerbt trotzdem die
Formularfelder und die Scrollleiste ein.
"""

# Die Variablen und das, was der Knopf braucht.
THEME_CSS = """
    /* modus-knopf (tool/web_theme.py) - Dark-/Light-Mode ohne JavaScript.
       Der Schalter ist eine echte Checkbox; die Pseudo-Klasse :has()
       schaltet die Variablen um. Siehe tool/web_theme.py. */
    :root {
      color-scheme: light dark;
      --bg: #ffffff;
      --fg: #2d2d2d;
      --muted: #6b6b74;
      --card: #f7f5f8;
      --card-fg: #2d2d2d;
      --line: #e3e0ea;
      --accent: #c4236c;
      --accent-fg: #ffffff;
      --shadow: 0 1px 3px rgba(0,0,0,.08);
    }
    html:has(#modus-umschalter:checked) {
      --bg: #121212;
      --fg: #ece8f0;
      --muted: #a8a4b0;
      --card: #1d1b20;
      --card-fg: #ece8f0;
      --line: #2f2c34;
      --accent: #ff8fab;
      --accent-fg: #121212;
      --shadow: 0 1px 3px rgba(0,0,0,.5);
    }
    body {
      background: var(--bg);
      color: var(--fg);
      transition: background .2s ease, color .2s ease;
    }
    a { color: var(--accent); }
    h1, h2, h3 { color: var(--fg); }
    p.lead, .klein, footer { color: var(--muted); }

    /* Tabellen als abgerundete Karten - passend zu den Karten der App
       (Radius 24) statt als Gitter aus harten Kanten. */
    table {
      border-collapse: separate;
      border-spacing: 0;
      width: 100%;
      margin: 1.1rem 0;
      font-size: 0.94rem;
      background: var(--card);
      color: var(--card-fg);
      border: 1px solid var(--line);
      border-radius: 16px;
      overflow: hidden;
      box-shadow: var(--shadow);
    }
    th, td { border: 0; padding: 0.6rem 0.7rem; text-align: left;
             vertical-align: top; }
    th { font-weight: 600; }
    tr + tr td { border-top: 1px solid var(--line); }
    thead th { border-bottom: 1px solid var(--line); }

    /* Der Umschalt-Knopf: kleine runde Flaeche oben rechts. Die
       Checkbox darueber ist unsichtbar, aber fokussierbar - deshalb
       liegt sie mit z-index ueber dem Label und faengt den Klick ab. */
    .modus-schalter {
      position: fixed;
      top: 12px; right: 12px;
      width: 38px; height: 38px;
      margin: 0;
      opacity: 0;
      z-index: 2;
      cursor: pointer;
    }
    .modus-knopf {
      position: fixed;
      top: 12px; right: 12px;
      width: 38px; height: 38px;
      display: flex; align-items: center; justify-content: center;
      border: 1px solid var(--line);
      border-radius: 999px;
      background: var(--card);
      color: var(--card-fg);
      box-shadow: var(--shadow);
      font-size: 1.05rem;
      line-height: 1;
      user-select: none;
      transition: transform .15s ease, background .2s ease;
    }
    .modus-knopf:hover { transform: scale(1.06); }
    .modus-schalter:focus-visible + .modus-knopf {
      outline: 2px solid var(--accent);
      outline-offset: 2px;
    }
    .modus-knopf .mond { display: none; }
    html:has(#modus-umschalter:checked) .modus-knopf .sonne { display: none; }
    html:has(#modus-umschalter:checked) .modus-knopf .mond { display: inline; }
"""

# Der Schalter und sein sichtbares Label.
#
# Die Checkbox kommt ZUERST: das Label greift ueber `for` auf sie zu und
# die CSS-Regel `.modus-schalter:focus-visible + .modus-knopf` braucht das
# Label als unmittelbar nachfolgenden Geschwister.
KNOPF_HTML = (
    '<input type="checkbox" id="modus-umschalter" class="modus-schalter" '
    'aria-label="Dark- und Light-Mode umschalten">\n'
    '<label for="modus-umschalter" class="modus-knopf" '
    'title="Dark- und Light-Mode umschalten">'
    '<span class="sonne" aria-hidden="true">&#9789;</span>'
    '<span class="mond" aria-hidden="true">&#9790;</span>'
    '</label>'
)

# Kurzname fuer den Generator, der bisher ein eigenes CSS hatte.
CSS = THEME_CSS

# Marker: daran erkennt apply_theme(), dass eine Seite schon bearbeitet
# wurde. Ohne ihn waere jeder Lauf ein zweiter Durchgang.
MARKER = '/* modus-knopf (tool/web_theme.py) */'


def apply_theme(html: str, css_extra: str = '') -> str:
    """Haengt Design und Umschalt-Knopf in eine HTML-Seite ein.

    [css_extra] sind seiten-eigene Regeln, die VOR den gemeinsamen
    kommen - die gemeinsamen gewinnen dann, weil sie spaeter im
    Style-Block stehen.
    """
    if MARKER in html:
        return html

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

    # 3) Schalter und Label direkt nach <body>.
    if '<body>' in html:
        html = html.replace('<body>', '<body>\n' + KNOPF_HTML, 1)
    elif '<body ' in html:
        import re as _re
        html = _re.sub(r'(<body[^>]*>)', r'\1\n' + KNOPF_HTML, html, count=1)

    return html
