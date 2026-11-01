"""
tool/check_gitignore_selftest.py
=================================
Prueft, dass `check_gitignore.py` FEHLER meldet, wenn er fehlschlagen
muss - und dass er nach einem Lauf mit gebuendelten git-Aufrufen
genauso viel sieht wie vorher.

ANLASS (01.11.2026): Beim Umschreiben des Checkers auf gebuendelte
git-Aufrufe (`git check-ignore -z --stdin`) wurde die Ausgabe falsch
gelesen. Das Format mit -z ist VIERFELDERIG:

    <quelle>\\0<zeilennummer>\\0<muster>\\0<pfad>\\0

und nicht "<quelle>:<nummer>:<muster>" in einem Feld. Der Checker
meldete danach KEINE Inkonsistenz mehr - und niemand haette es
gemerkt, weil "0 Beanstandungen" nach wie vor gruen aussieht.

Genau das ist der Grund fuer diesen Selbsttest: ein Checker, der
nichts findet, sieht aus wie ein Checker, der sauber ist. Das ist
kein theoretisches Risiko - es ist genau so eingetreten.

Aufruf:
    python tool/check_gitignore_selftest.py

Exit 0 = alle Negativfaelle wurden erkannt.
"""

import importlib.util
import io
import pathlib
import shutil
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGET = ROOT / 'tool' / 'check_gitignore.py'

spec = importlib.util.spec_from_file_location('cgi', TARGET)
cgi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cgi)


def git(cwd, *args):
    return subprocess.run(['git', *args], cwd=cwd, capture_output=True,
                          text=True, encoding='utf-8', errors='replace')


def make_repo(tmp: pathlib.Path, ignore_text: str) -> pathlib.Path:
    """Legt ein Git-Repo mit .gitignore an."""
    repo = tmp / 'repo'
    repo.mkdir()
    (repo / '.gitignore').write_text(ignore_text, encoding='utf-8')
    git(repo, 'init', '-q')
    git(repo, 'config', 'user.email', 'test@example.invalid')
    git(repo, 'config', 'user.name', 'Selbsttest')
    return repo


def run_checker(repo: pathlib.Path):
    """Fuehrt main() im Test-Repo aus. Liefert (exit_code, ausgabe)."""
    buf = io.StringIO()
    old_root = cgi.ROOT
    old_out = cgi.OUT
    out_file = repo / '_bericht.txt'
    try:
        cgi.ROOT = repo
        cgi.OUT = out_file
        with redirect_stdout(buf):
            code = cgi.main()
    finally:
        cgi.ROOT = old_root
        cgi.OUT = old_out
    bericht = out_file.read_text(encoding='utf-8') if out_file.exists() else ''
    return code, buf.getvalue() + bericht


CASES = []


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


@case('Geheimdatei, die NICHT ignoriert ist -> Beanstandung')
def _c1(tmp):
    repo = make_repo(tmp, '*.pem\nbuild/\n')
    (repo / 'GoogleService-Info.plist').write_text('x', encoding='utf-8')

    code, out = run_checker(repo)
    assert code != 0, 'muss fehlschlagen'
    assert 'NICHT IGNORIERT' in out, out[-500:]
    assert 'GoogleService-Info.plist' in out, out[-500:]


@case('Geheimdatei, die ignoriert ist -> KEINE Beanstandung')
def _c2(tmp):
    repo = make_repo(tmp, '*.pem\nbuild/\n')
    (repo / 'geheim.pem').write_text('x', encoding='utf-8')

    code, out = run_checker(repo)
    assert code == 0, f'muss sauber sein, kam {code}: {out[-500:]}'


@case('versionierte Datei unter einer Ignore-Regel -> Inkonsistenz')
def _c3(tmp):
    repo = make_repo(tmp, 'ignoriert/\n')
    ordner = repo / 'ignoriert'
    ordner.mkdir()
    (ordner / 'datei.txt').write_text('x', encoding='utf-8')
    # Mit -f versionieren: genau so entsteht die Inkonsistenz in der
    # Praxis (eine Datei wird aus einer ignorierten Ecke heraus
    # ausnahmsweise aufgenommen).
    git(repo, 'add', '-f', 'ignoriert/datei.txt')

    code, out = run_checker(repo)
    assert 'Inkonsistenz' in out, out[-500:]
    assert 'ignoriert/datei.txt' in out, out[-500:]
    assert 'ignoriert/' in out, f'die Regel muss genannt werden: {out[-500:]}'


@case('gebündelter Ignore-Aufruf == einzelner Aufruf')
def _c4(tmp):
    repo = make_repo(tmp, '*.pem\nbuild/\n')
    (repo / 'a.pem').write_text('x', encoding='utf-8')
    (repo / 'b.pem').write_text('x', encoding='utf-8')
    (repo / 'c.txt').write_text('x', encoding='utf-8')

    alt_root = cgi.ROOT
    try:
        cgi.ROOT = repo
        gebuendelt = cgi.ignored_batch(
            ['a.pem', 'b.pem', 'c.txt', 'gibtsnicht.txt'])
    finally:
        cgi.ROOT = alt_root

    assert gebuendelt == {'a.pem', 'b.pem'}, gebuendelt


@case('die verbose-Variante liefert Quelle, Nummer und Muster')
def _c5(tmp):
    repo = make_repo(tmp, 'ignoriert/\n')
    ordner = repo / 'ignoriert'
    ordner.mkdir()
    (ordner / 'datei.txt').write_text('x', encoding='utf-8')
    git(repo, 'add', '-f', 'ignoriert/datei.txt')

    alt_root = cgi.ROOT
    try:
        cgi.ROOT = repo
        regeln = cgi.check_ignore_verbose(['ignoriert/datei.txt'])
    finally:
        cgi.ROOT = alt_root

    assert 'ignoriert/datei.txt' in regeln, regeln
    quelle, nummer, muster = regeln['ignoriert/datei.txt']
    assert quelle.endswith('.gitignore'), quelle
    assert nummer.isdigit(), nummer
    assert muster.strip() == 'ignoriert/', muster


@case('Build-Ordner wird nicht ausgewertet, aber auch nicht verwechselt')
def _c6(tmp):
    repo = make_repo(tmp, 'build/\n')
    build = repo / 'build'
    build.mkdir()
    (build / 'lib.so').write_text('x', encoding='utf-8')

    code, out = run_checker(repo)
    # Die Datei ist ignoriert - also kein Befund.
    assert code == 0, f'muss sauber sein, kam {code}: {out[-500:]}'


def main():
    failures = []
    print('=' * 70)
    print('SELBSTTEST check_gitignore.py')
    print('=' * 70)
    for name, fn in CASES:
        tmp = pathlib.Path(tempfile.mkdtemp(prefix='cgi_selftest_'))
        try:
            fn(tmp)
            print(f'  OK    {name}')
        except AssertionError as e:
            failures.append((name, str(e)))
            print(f'  FEHL  {name}')
            print(f'        {e}')
        except Exception as e:                       # noqa: BLE001
            failures.append((name, f'{type(e).__name__}: {e}'))
            print(f'  FEHL  {name}  ({type(e).__name__}: {e})')
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    print()
    if failures:
        print(f'{len(failures)} von {len(CASES)} Negativfaellen NICHT erkannt.')
        print('Der Checker ist dann nicht vertrauenswuerdig.')
        sys.exit(1)
    print(f'OK  alle {len(CASES)} Negativfaelle erkannt.')


if __name__ == '__main__':
    main()
