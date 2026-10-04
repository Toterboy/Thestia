#!/usr/bin/env python3
"""Erzeugt die Datenschutzerklaerung in zwei Formaten aus einer Quelle.

Google Play verlangt die Erklaerung an zwei getrennten Stellen:

1. als **Link oder Text innerhalb der App selbst**, und
2. als **aktiv erreichbare oeffentliche URL** (ausdruecklich keine PDF).

Beide muessen denselben Inhalt haben. Also gibt es hier eine Quelle,
docs/DATENSCHUTZ.md, und zwei Ableitungen:

* ``lib/generated/privacy_policy_de.dart`` - strukturierte Bloecke fuer
  den Text-Bildschirm in der App. Bewusst *strukturiert* und nicht als
  Markdown-String: die App soll das Markdown nicht zur Laufzeit
  zerlegen, und der Bildschirm soll Absaetze, Listen und Tabellen
  lesbar darstellen koennen.
* ``site/datenschutz.html`` - eine einzelne, statische HTML-Datei fuer
  den Store-Eintrag. Ohne JavaScript, ohne externe Requests, ohne
  Tracking: die Datei ist das gesamte Dokument.

Beide Dateien werden erzeugt und nicht gepflegt. Aenderungen gehoeren
in docs/DATENSCHUTZ.md, danach::

    python tool/make_privacy_policy.py

Deterministisch: gleiche Eingabe ergibt gleiche Ausgabe, ohne
Zeitstempel. Sonst wuerde jede Erzeugung einen Diff erzeugen.
"""

import html
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'docs', 'DATENSCHUTZ.md')
DART_OUT = os.path.join(
    ROOT, 'lib', 'generated', 'privacy_policy_de.dart')
HTML_OUT = os.path.join(ROOT, 'site', 'datenschutz.html')
INDEX_OUT = os.path.join(ROOT, 'site', 'index.html')

CSS = """
    :root { color-scheme: light dark; }
    body {
      font-family: system-ui, -apple-system, "Segoe UI", Roboto,
                   Helvetica, Arial, sans-serif;
      line-height: 1.65;
      max-width: 46rem;
      margin: 0 auto;
      padding: 1.5rem 1.1rem 4rem;
    }
    h1 { font-size: 1.7rem; line-height: 1.25; }
    h2 { font-size: 1.25rem; margin-top: 2.4rem; line-height: 1.3; }
    h3 { font-size: 1.05rem; margin-top: 1.6rem; }
    p  { margin: 0.85rem 0; }
    li { margin: 0.3rem 0; }
    table { border-collapse: collapse; width: 100%; margin: 0.9rem 0;
            font-size: 0.94rem; }
    th, td { border: 1px solid #8888; padding: 0.45rem 0.55rem;
             text-align: left; vertical-align: top; }
    th { font-weight: 600; }
    footer { margin-top: 3rem; font-size: 0.85rem; opacity: 0.75; }
"""

FOOTER_DE = (
    'Verantwortliche Stelle im Sinne der DSGVO ist Thestia. Kontakt '
    'über das In-App-Bug-Report-Formular oder das Issue-Tracker des '
    'öffentlichen Projekt-Repositorys.')


# --------------------------------------------------------------------------
# Markdown -> Bloecke
# --------------------------------------------------------------------------

def parse(md_lines):
    """Zerlegt das Markdown in Bloecke.

    Blockarten: h1, h2, h3, p (Absatz), li (Listenpunkt),
    table (Zelle einer Tabellenzeile).
    """
    blocks = []
    i = 0
    n = len(md_lines)

    while i < n:
        stripped = md_lines[i].strip()

        if not stripped:
            i += 1
            continue

        m = re.match(r'^(#{1,3})\s+(.*)$', stripped)
        if m:
            blocks.append({'kind': 'h%d' % len(m.group(1)),
                           'text': m.group(2).strip()})
            i += 1
            continue

        if stripped.startswith('|'):
            cells = [c.strip() for c in stripped.strip('|').split('|')]
            # Trennzeile |---|---| oder |---:|:---:
            if all(re.match(r'^:?-{2,}:?$', c) for c in cells if c):
                i += 1
                continue
            # Die erste Zeile einer Tabelle ist die Kopfzeile. Sie wird
            # als eigener Block gefuehrt, damit die App die
            # Spaltenbezeichnungen verwenden kann, statt sie zu raten.
            head = not (blocks and blocks[-1]['kind'].startswith('table'))
            blocks.append({
                'kind': 'table_head' if head else 'table',
                'cells': cells,
            })
            i += 1
            continue

        m = re.match(r'^[-*]\s+(.*)$', stripped)
        if m:
            # Umbrochene Folgezeilen mitnehmen. In diesem Dokument sind
            # die Listenpunkte hart umbrochen (z. B. "**lokal auf dem
            #   Gerät** per ONNX-Modell..."). Ohne das wuerde jede
            # Folgezeile ein eigener Absatz und der Satz zerfiele
            # mitten im Wort - die Erklaerung waere unlesbar.
            item = [m.group(1).strip()]
            i += 1
            while i < n:
                nxt = md_lines[i].strip()
                if (not nxt or nxt.startswith('#') or nxt.startswith('|')
                        or re.match(r'^[-*]\s+', nxt)):
                    break
                item.append(nxt)
                i += 1
            blocks.append({'kind': 'li', 'text': ' '.join(item)})
            continue

        # Absatz: Folgezeilen anhaengen, bis ein anderer Block beginnt.
        para = [stripped]
        i += 1
        while i < n:
            nxt = md_lines[i].strip()
            if (not nxt or nxt.startswith('#') or nxt.startswith('|')
                    or re.match(r'^[-*]\s+', nxt)):
                break
            para.append(nxt)
            i += 1
        blocks.append({'kind': 'p', 'text': ' '.join(para)})

    return blocks


def group_tables(blocks):
    """Fasst eine Kopfzeile und die folgenden Tabellenzeilen zusammen.

    Ergebnis: ein Block ``table_rows`` mit ``head`` (oder ``None``) und
    ``rows``. Ohne Kopfzeile bleibt ``head`` leer - dann werden alle
    Zeilen als Datenzeilen gerendert.
    """
    out = []
    i = 0
    n = len(blocks)

    while i < n:
        kind = blocks[i]['kind']

        if kind not in ('table_head', 'table'):
            out.append(blocks[i])
            i += 1
            continue

        head = blocks[i]['cells'] if kind == 'table_head' else None
        if kind == 'table_head':
            i += 1

        rows = []
        while i < n and blocks[i]['kind'] == 'table':
            rows.append(blocks[i]['cells'])
            i += 1

        out.append({'kind': 'table_rows', 'head': head, 'rows': rows})

    return out


def _inline_html(text):
    """Maskiert HTML und wandelt **fett** in <strong>."""
    s = html.escape(text, quote=False)
    return re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', s)


# --------------------------------------------------------------------------
# Dart
# --------------------------------------------------------------------------

def dart_quote(s):
    """Dart-String-Literal.

    Dart kennt kein rohes Mehrzeilen-Literal, deshalb wird jeder
    Zeilenumbruch zu \\n im normalen String. Entscheidend: KEIN
    Zeilenumbruch innerhalb eines Literals - genau daran ist
    app_strings.dart gescheitert, deshalb prueft main() das auch.
    """
    out = s.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n')
    return "'" + out + "'"


def render_dart(blocks):
    lines = [
        '// GENERIERTE DATEI - NICHT VON HAND AENDERN.',
        '// Quelle: docs/DATENSCHUTZ.md',
        '// Neu erzeugen mit: python tool/make_privacy_policy.py',
        '',
        '/// Ein Abschnitt der Datenschutzerklaerung fuer die Anzeige in der',
        '/// App.',
        '///',
        '/// Google Play verlangt die Erklaerung nicht nur als Link im Store,',
        '/// sondern ausdruecklich auch als Text innerhalb der App selbst.',
        '/// Deshalb steht sie hier und wird im Privacy-Screen gelesen, statt',
        '/// nur verlinkt zu werden - eine URL kann falsch oder nicht erreichbar',
        '/// sein, dieser Text nicht.',
        'class PrivacyBlock {',
        '  const PrivacyBlock(this.kind, this.text, {this.cells});',
        '',
        "  /// h1, h2, h3, p, li oder table.",
        '  final String kind;',
        '',
        '  /// Fliesstext bzw. Ueberschrift. Fuer [kind] == \'table\' leer.',
        '  final String text;',
        '',
        '  /// Zellen einer Tabellenzeile. Nur bei [kind] == \'table\' gesetzt.',
        '  final List<String>? cells;',
        '}',
        '',
        '/// Die vollstaendige Datenschutzerklaerung als Bloecke, in der',
        '/// Reihenfolge von docs/DATENSCHUTZ.md.',
        'const List<PrivacyBlock> kPrivacyPolicyDe = <PrivacyBlock>[',
    ]

    for b in blocks:
        if b['kind'] in ('table', 'table_head'):
            cells = ', '.join(dart_quote(c) for c in b['cells'])
            # Kein 'const' vor dem Element: die Liste ist bereits const,
            # die Elemente sind damit implizit const. Ein zusaetzliches
            # 'const' ist nur ein Lint-Fund.
            lines.append("  PrivacyBlock('%s', '', "
                         'cells: <String>[%s]),' % (b['kind'], cells))
        else:
            lines.append("  PrivacyBlock('%s', %s),"
                         % (b['kind'], dart_quote(b['text'])))

    lines.append('];')
    lines.append('')
    return '\n'.join(lines)


# --------------------------------------------------------------------------
# HTML
# --------------------------------------------------------------------------

def render_html(blocks):
    """Eine einzige statische Datei. Kein JavaScript, keine Requests."""
    grouped = group_tables(blocks)

    out = ['<!DOCTYPE html>', '<html lang="de">', '<head>',
           '<meta charset="utf-8">',
           '<meta name="viewport" content="width=device-width, '
           'initial-scale=1">',
           '<title>Datenschutzerklärung für Thestia</title>',
           '<style>%s</style>' % CSS,
           '</head>', '<body>']

    table_open = False

    skip_until = 0

    for idx, b in enumerate(grouped):
        # Punkte, die bereits in eine Liste aufgenommen wurden, nicht
        # noch einmal verarbeiten. Sonst wird jeder Punkt der zweiten
        # und folgenden Folge noch mal als eigene <ul> ausgegeben.
        if idx < skip_until:
            continue

        kind = b['kind']

        if kind == 'table_rows':
            rows = b['rows']
            head = b.get('head')
            if head:
                out.append('<table>')
                out.append('<thead><tr>%s</tr></thead>'
                           % ''.join('<th>%s</th>' % _inline_html(c)
                                     for c in head))
                out.append('<tbody>')
            else:
                out.append('<table><tbody>')
            for r in rows:
                out.append('<tr>%s</tr>'
                           % ''.join('<td>%s</td>' % _inline_html(c)
                                     for c in r))
            out.append('</tbody>')
            out.append('</table>')
            continue

        if kind in ('h1', 'h2', 'h3'):
            out.append('<%s>%s</%s>'
                       % (kind, _inline_html(b['text']), kind))
        elif kind == 'li':
            # Aufeinanderfolgende Listenpunkte zu EINER Liste
            # zusammenfassen. Sonst bekommt jeder Punkt eine eigene
            # <ul> mit eigenem Abstand - sieht aus wie 21
            # Einzelauzaehlungen statt einer Liste.
            items = [b['text']]
            j = idx + 1
            while j < len(grouped) and grouped[j]['kind'] == 'li':
                items.append(grouped[j]['text'])
                j += 1
            out.append('<ul>%s</ul>'
                       % ''.join('<li>%s</li>' % _inline_html(t)
                                 for t in items))
            skip_until = j
            continue

        out.append('<p>%s</p>' % _inline_html(b['text']))

    out.append('<footer>%s</footer>' % html.escape(FOOTER_DE, quote=False))
    out.append('</body>')
    out.append('</html>')

    return '\n'.join(out) + '\n'


def render_index():
    """Startseite fuer www.thestia.de.

    Netlify zeigt ohne index.html "Page Not Found" auf /. Das ist
    technisch harmlos - Google Play ruft nur /datenschutz ab, nicht die
    Wurzel. Eine leere 404-Seite auf der eigenen Domain ist aber genau
    das, was einen Besucher (oder ein pruefendes Auge) als "unfertig"
    einstuft, und die Domain steht im Impressum.

    Deshalb eine schlichte Seite mit dem App-Namen und einem Link zur
    Datenschutzerklaerung. KEIN Redirect auf /datenschutz: wer die
    Domain eintippt, will nicht ausgerechnet das Impressum sehen.
    """
    return '\n'.join([
        '<!DOCTYPE html>',
        '<html lang="de">',
        '<head>',
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, '
        'initial-scale=1">',
        '<meta name="robots" content="noindex">',
        '<title>Thestia</title>',
        '<style>%s</style>' % CSS,
        '</head>',
        '<body>',
        '<main>',
        '  <h1>Thestia</h1>',
        '  <p>Datenschutzerklärung</p>',
        '  <p><a href="/datenschutz">Zur Datenschutzerklärung</a></p>',
        '</main>',
        '</body>',
        '</html>',
        '',
    ])


# --------------------------------------------------------------------------

def main():
    if not os.path.exists(SOURCE):
        print('FEHLER: Quelle fehlt: %s' % SOURCE)
        return 1

    with io.open(SOURCE, encoding='utf-8') as fh:
        blocks = parse(fh.read().split('\n'))

    if not blocks:
        print('FEHLER: keine Bloecke aus %s' % SOURCE)
        return 1

    # Kein Block darf einen Zeilenumbruch im Dart-Literal erzeugen. Genau
    # daran ist app_strings.dart gescheitert, deshalb wird es hier
    # abgesichert und nicht erst beim Analysieren des Dart-Codes.
    for b in blocks:
        texts = [b.get('text', '')] + list(b.get('cells') or [])
        for t in texts:
            if '\n' in t:
                print('FEHLER: Block enthaelt einen Zeilenumbruch: %r' % t[:60])
                return 1

    os.makedirs(os.path.dirname(DART_OUT), exist_ok=True)
    with io.open(DART_OUT, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(render_dart(blocks))

    os.makedirs(os.path.dirname(HTML_OUT), exist_ok=True)
    with io.open(HTML_OUT, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(render_html(blocks))

    with io.open(INDEX_OUT, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(render_index())

    kinds = {}
    for b in blocks:
        kinds[b['kind']] = kinds.get(b['kind'], 0) + 1

    print('Datenschutzerklaerung erzeugt: %d Bloecke' % len(blocks))
    for k in sorted(kinds):
        print('  %-6s %d' % (k, kinds[k]))
    print('  -> %s' % os.path.relpath(DART_OUT, ROOT))
    print('  -> %s' % os.path.relpath(HTML_OUT, ROOT))
    print('  -> %s' % os.path.relpath(INDEX_OUT, ROOT))
    return 0


if __name__ == '__main__':
    sys.exit(main())