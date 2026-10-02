"""Prueft, dass die GitHub-Workflows gültiges YAML sind.

Anlass: am 30.09.2026 war `ci.yml` durch einen Doppelpunkt mit
Leerzeichen in einem unquotierten Schrittnamen ungültig. Die Folge war
der schlimmste denkbare CI-Fehler: GitHub parst die Datei nicht und
zeigt **gar keine Checks** an - nicht einmal einen roten. Der Build
wirkt erfolgreich, es läuft nur nichts.

Diesen Fehler findet kein Workflow-Check, weil der Workflow, der ihn
finden soll, selbst die kaputte Datei ist. Er muss von aussen
kommen - lokaler Aufruf vor dem Push.

Geprüft wird:
  1. Datei ist gültiges YAML.
  2. Sie enthält `on:` - ein Workflow ohne Trigger läuft nie.
  3. Jeder Job hat `runs-on` und mindestens einen `steps`-Eintrag.
  4. Jeder Schritt mit `run:` hat auch ein `uses:` oder `run:` und umgekehrt.
  5. Schrittnamen mit `: ` sind quotiert (die konkrete Fehlerklasse).

Aufruf:
    python tool/check_workflows.py

Exit 1 bei Befund. Fehlt PyYAML, meldet das Skript das als SKIP mit
Exit 0 - die Fehlerklasse ist dann aber nicht mehr abgesichert, und das
gehoert in die Meldung.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / '.github' / 'workflows'

try:
    import yaml
except ImportError:                                    # pragma: no cover
    print('SKIP: PyYAML fehlt (pip install pyyaml).')
    print('  Ohne diese Pruefung faellt die gueltigste Fehlerklasse in')
    print('  ci.yml wieder unentdeckt.')
    sys.exit(0)


def main():
    if not WORKFLOWS.is_dir():
        sys.exit(f'{WORKFLOWS} fehlt - keine Workflows?')

    files = sorted(WORKFLOWS.glob('*.yml')) + \
        sorted(WORKFLOWS.glob('*.yaml'))
    if not files:
        sys.exit('Keine Workflow-Dateien gefunden.')

    problems = []

    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding='utf-8')

        # (5) Zuerst die Fehlerklasse, die zur Invaliditaet fuehrt. Die
        # Meldung ist sonst nur "ScannerError bei Zeile N".
        for i, line in enumerate(raw.splitlines(), start=1):
            stripped = line.strip()
            if not stripped.startswith('- name:'):
                continue
            value = stripped[len('- name:'):].strip()
            if not value:
                continue
            if (value[0] in '"\'' and value[-1] == value[0]):
                continue
            if ': ' in value:
                problems.append(
                    f'{rel}:{i}: Schrittname "{value}" enthaelt ": " und ist '
                    f'nicht quotiert. YAML liest das als Schluessel und '
                    f'macht die Datei ungueltig - GitHub zeigt dann gar '
                    f'keine Checks an. Name in Anfuehrungszeichen setzen.')

        try:
            doc = yaml.safe_load(raw)
        except yaml.YAMLError as e:
            problems.append(f'{rel}: ungültiges YAML - {e}')
            continue

        if not isinstance(doc, dict):
            problems.append(f'{rel}: keine YAML-Mapping-Struktur')
            continue

        # YAML 1.1 liest das Schlüsselwort "on" als Boolean. PyYAML
        # liefert deshalb den Schluessel True statt der Zeichenkette
        # "on". Ohne diesen Hinweis meldet der Checker hier einen Fehler,
        # den es nicht gibt, und man faengt an, die Workflow-Datei zu
        # "reparieren".
        triggers = doc.get('on', doc.get(True))
        if triggers is None:
            problems.append(f'{rel}: kein "on:" - der Workflow startet nie')

        jobs = doc.get('jobs') or {}
        if not jobs:
            problems.append(f'{rel}: keine Jobs')
            continue

        for job_name, job in jobs.items():
            if not isinstance(job, dict):
                problems.append(f'{rel}: Job "{job_name}" ist kein Mapping')
                continue
            if 'runs-on' not in job:
                problems.append(f'{rel}: Job "{job_name}" hat kein runs-on')
            steps = job.get('steps') or []
            if not steps:
                problems.append(f'{rel}: Job "{job_name}" hat keine Schritte')
            for s in steps:
                if not isinstance(s, dict):
                    problems.append(
                        f'{rel}: Schritt in Job "{job_name}" ist kein Mapping')
                    continue
                if 'run' not in s and 'uses' not in s:
                    problems.append(
                        f'{rel}: Schritt "{s.get("name", "?")}" in Job '
                        f'"{job_name}" hat weder run: noch uses:')
                if 'run' in s and 'uses' in s:
                    problems.append(
                        f'{rel}: Schritt "{s.get("name", "?")}" in Job '
                        f'"{job_name}" hat run: UND uses: - erlaubt ist '
                        f'nur eines')

    print('=' * 70)
    print('GITHUB-WORKFLOWS')
    print('=' * 70)
    for path in files:
        print(f'  geprüft: {path.relative_to(ROOT).as_posix()}')
    print()

    if problems:
        print('FEHLER:')
        for p in problems:
            print('  X', p)
        print()
        print('Eine ungültige Workflow-Datei ist der stillste CI-Fehler:')
        print('GitHub zeigt gar keine Checks an, statt rot zu werden.')
        sys.exit(1)

    print(f'OK  {len(files)} Workflow(s): YAML gültig, Trigger vorhanden, '
          f'Jobs vollständig.')


if __name__ == '__main__':
    main()