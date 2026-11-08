"""Selbsttest fuer tool/check_push_duplicates.py.

ZWECK: Ein Gate, das man nie rot gesehen hat, ist kein Gate. Dieser
Selbsttest baut absichtlich die vier Fehlerquellen nach und prueft, dass
das Gate sie jeweils meldet - und dass ein sauberer Baum durchgeht.

Der Selbsttest aendert NICHTS am Repository: er baut einen
temporaeren Baum und ruft das Gate mit --root darauf auf.
"""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
GATE = ROOT / "tool" / "check_push_duplicates.py"

GUTE_FUNKTION = """
const kind = body.kind;
if (kind === "likes") {
  return new Response(JSON.stringify({ ok: false, reason: "kind_server_only" }));
}
"""

SCHLECHTE_FUNKTION = """
const kind = body.kind;
"""

GUTE_MIGRATION = """
INSERT INTO public.likes (user_id, liked_user_id, source)
VALUES ('a', 'b', 'transit');
IF NEW.source IS DISTINCT FROM 'profile' THEN
  RETURN NEW;
END IF;
IF EXISTS (
  SELECT 1 FROM public.matches m
   WHERE (m.user_one_id = NEW.sender AND m.user_two_id = NEW.recipient)
) THEN
  RETURN NEW;
END IF;
-- notify_soft_ping_trigger und thestia_internal_secret
"""

SCHLECHTE_MIGRATION = """
INSERT INTO public.likes (user_id, liked_user_id)
VALUES ('a', 'b');
"""


def baue_baum(wurzel, mit_like_aufruf, mit_sperre, mit_regeln):
    lib = wurzel / "lib"
    (lib / "screens").mkdir(parents=True, exist_ok=True)
    funktion = wurzel / "supabase" / "functions" / "notify-user"
    funktion.mkdir(parents=True, exist_ok=True)
    migration = wurzel / "supabase" / "migrations"
    migration.mkdir(parents=True, exist_ok=True)

    aufruf = """
      await client.functions.invoke(
        'notify-user',
        body: {'kind': 'likes', 'target_user_id': partner.id},
      );
"""
    if not mit_like_aufruf:
        aufruf = "      // kein Like-Aufruf\n"

    (lib / "screens" / "test_screen.dart").write_text(
        "import 'package:flutter/material.dart';\n" + aufruf,
        encoding="utf-8")
    (funktion / "index.ts").write_text(
        GUTE_FUNKTION if mit_sperre else SCHLECHTE_FUNKTION,
        encoding="utf-8")
    (migration / "200_push_duplicate_fix.sql").write_text(
        GUTE_MIGRATION if mit_regeln else SCHLECHTE_MIGRATION,
        encoding="utf-8")


def gate(wurzel):
    ergebnis = subprocess.run(
        [sys.executable, str(GATE), "--root", str(wurzel)],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    return ergebnis.returncode, ergebnis.stdout


def main() -> int:
    fehler = 0
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="push_dupl_selftest_"))
    try:
        # 1) Der saubere Baum muss durchgehen: kein Client-Aufruf,
        #    Sperre vorhanden, Regeln vorhanden.
        baue_baum(tmp / "gut", False, True, True)
        code, ausgabe = gate(tmp / "gut")
        if code != 0:
            print("  X der saubere Baum wurde abgelehnt:")
            print("    " + ausgabe.strip().replace("\n", "\n    "))
            fehler += 1
        else:
            print("  OK  der saubere Baum geht durch.")

        # 2) Ein Client-Aufruf mit kind='likes' muss auffallen.
        baue_baum(tmp / "like", True, True, True)
        code, ausgabe = gate(tmp / "like")
        if code == 0:
            print("  X ein Client-Aufruf mit kind='likes' wurde NICHT gemeldet.")
            fehler += 1
        else:
            print("  OK  der Client-Aufruf mit kind='likes' wird gemeldet.")

        # 3) Fehlende Sperre in der Edge Function muss auffallen.
        baue_baum(tmp / "sperre", False, False, True)
        code, ausgabe = gate(tmp / "sperre")
        if code == 0:
            print("  X die fehlende Sperre wurde NICHT gemeldet.")
            fehler += 1
        else:
            print("  OK  die fehlende Sperre wird gemeldet.")

        # 4) Fehlende Regeln in der Migration müssen auffallen.
        baue_baum(tmp / "regeln", False, True, False)
        code, ausgabe = gate(tmp / "regeln")
        if code == 0:
            print("  X die fehlenden Regeln wurden NICHT gemeldet.")
            fehler += 1
        else:
            print("  OK  die fehlenden Regeln werden gemeldet.")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    if fehler:
        print("SELBSTTEST ROT: %d Fall(e)" % fehler)
        return 1
    print("SELBSTTEST GRUEN: der Pruefer findet alle vier Fehlerquellen.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
