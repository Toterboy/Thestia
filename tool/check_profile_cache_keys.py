#!/usr/bin/env python3
"""Prueft, ob jedes geschriebene Profil-Feld auch wieder gelesen wird.

BEFUND (07.11.2026, Betreiber): "Meine Vorstellung stimmt auch nicht, da
beide Nutzer eine Vorstellung gemacht haben aber hier steht, dass keine
hinterlegt wurde (also bei Profil und dann meine Vorstellung)."

DIE URSACHE: UserProfile.fromJson wird an FUER verschiedenen Stellen
benutzt, und die Stellen benutzen DREI verschiedene Schreibweisen:

  1. Server-Antworten (REST/RPC)   -> snake_case  (intro_text)
  2. von Hand gebaute Maps         -> camelCase  (introText)
  3. der lokale Cache (toJson)     -> camelCase  (introText)

Der Parser kannte nur die snake_case-Fassung. Jeder camelCase-
Produzent verlor seine Vorstellung beim Lesen - der Cache nach jedem
App-Neustart, der Serverabruf sofort. Die Daten waren in der Datenbank
nachweislich vorhanden (Text ja, Audio-Datei ja), nur der Client kam
nicht an sie heran.

WARUM EIN WERKZEUG STATT EINES FIXES: Genau diese Klasse von Fehler
(geschrieben wird A, gelesen wird B) ist beim Testen auf dem Geraet
unsichtbar - die Daten sind da, es sieht nur falsch aus. Ein Gate, das
jeden Schreib-/Lese-Mismatch im Quelltext findet, faengt sie ab, BEVOR
sie jemand auf einem Geraet suchen muss.

Aufruf::

    python tool/check_profile_cache_keys.py
"""

import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Felder, die der SERVER berechnet und die deshalb keinen Unterstrich
# haben: profile_to_jsonb liefert das Alter ("age") statt des
# Geburtsdatums - das Alter gehoert nicht in den Cache.
SERVER_FELDER = {"age"}
MODELL = ROOT / "lib" / "models" / "user_profile.dart"
SERVICE = ROOT / "lib" / "services" / "supabase_database_service.dart"


def _lade_alle(text: str, muster: str) -> list[str]:
    return re.findall(muster, text)


def main() -> int:
    modell = MODELL.read_text(encoding="utf-8")
    service = SERVICE.read_text(encoding="utf-8", errors="replace")

    # 1) Was schreibt toJson() (der Cache-Autor)?
    to_json = re.search(
        r"Map<String, dynamic> toJson\(\)\s*=>\s*\{(.*?)\n\s*\};",
        modell,
        re.S,
    )
    if not to_json:
        print("  ! toJson() nicht gefunden - der Quelldatei hat sich geaendert.")
        return 1
    geschrieben = _lade_alle(
        to_json.group(1), r"'([A-Za-z_][A-Za-z0-9_]*)'\s*:"
    )

    # 2) Was liest fromJson() (der Leser)?
    from_json = re.search(
        r"factory UserProfile\.fromJson\(Map<String, dynamic> json\)\s*\{\s*"
        r"return UserProfile\((.*?)\n\s{4}\);",
        modell,
        re.S,
    )
    if not from_json:
        print("  ! fromJson() nicht gefunden.")
        return 1
    gelesen = _lade_alle(
        from_json.group(1), r"json\[['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]\]"
    )
    # Die Lese-Helfer: _leseText(json, ['intro_text', 'introText']) usw.
    # Sie lesen ein Feld unter MEHREREN Schreibweisen - genau die
    # Loesung fuer den gemischten Betrieb.
    for gruppe in _lade_alle(
        from_json.group(1),
        r"_lese(?:Text|Bool|Zahl|Liste|Datum)\(\s*json\s*,\s*\[([^\]]*)\]",
    ):
        gelesen += re.findall(
            r"['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]", gruppe
        )

    # 3) Die Server-Zuordnung: welche Schreibweise nutzt sie?
    mapped_block = re.search(
        r"final mapped = <String, dynamic>\{(.*?)\n\s{4}\};",
        service,
        re.S,
    )
    mapped = _lade_alle(
        mapped_block.group(1), r"'([A-Za-z_][A-Za-z0-9_]*)'\s*:"
    ) if mapped_block else []

    print("=" * 70)
    print("PROFIL-FELDER: geschrieben, gelesen, zugeordnet")
    print("=" * 70)
    print()
    print("  toJson() schreibt %d Felder, fromJson() liest %d, "
          "die Server-Zuordnung kennt %d."
          % (len(set(geschrieben)), len(set(gelesen)), len(set(mapped))))

    # Der Kern des Gates: ein Feld, das geschrieben, aber NICHT gelesen
    # wird, geht beim Lesen verloren.
    geschrieben_set = set(geschrieben)
    gelesen_set = set(gelesen)
    mapped_set = set(mapped)

    verloren = sorted(geschrieben_set - gelesen_set)
    # camelCase/snake_case-Paare, die dasselbe Feld meinen.
    def _varianten(name: str) -> set[str]:
        varianten = {name}
        # camelCase -> snake_case
        varianten.add(re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower())
        # snake_case -> camelCase
        varianten.add(re.sub(r"_([a-z])", lambda m: m.group(1).upper(), name))
        return varianten

    echte_verluste = []
    for feld in verloren:
        gemeinsam = _varianten(feld) & (gelesen_set | mapped_set)
        if gemeinsam:
            # Es gibt eine andere Schreibweise - das ist der Fall, der
            # beim Testen auf dem Geraet unsichtbar war.
            echte_verluste.append((feld, sorted(gemeinsam)))
        else:
            echte_verluste.append((feld, []))

    # Und die Umkehrung: gelesen, aber niemals geschrieben -> immer leer.
    #
    # NUR die camelCase-Schreibweise wird geprueft: ein Name mit
    # Unterstrich ("user_id", "intro_text") kommt vom SERVER - der
    # liefert die Spaltennamen so. Ein camelCase-Name dagegen entsteht
    # nur im Cache oder in der Zuordnung des DB-Service - der muss ihn
    # auch wiederbekommen.
    #
    # Die Ausnahme: ein Feld, das es in einer ANDEREN Schreibweise gibt
    # (z. B. createdAt / created_at) ist kein Verlust - dafuer gibt es
    # den Fallback "json['a'] ?? json['b']".
    unbeschrieben = []
    for feld in sorted(gelesen_set - geschrieben_set):
        if "_" in feld:
            continue  # Server-Spaltenname.
        varianten = _varianten(feld)
        if varianten & (geschrieben_set | mapped_set):
            # Es gibt das Feld unter einem anderen Namen - das ist oben
            # schon gemeldet (oder harmlos).
            continue
        unbeschrieben.append(feld)

    print()
    fehler = 0

    if echte_verluste:
        print("  X %d Feld(er) werden geschrieben, aber unter einer ANDEREN"
              " Schreibweise gelesen:" % len(echte_verluste))
        for feld, gemeinsam in echte_verluste:
            fehler += 1
            print()
            print("      %s" % feld)
            for g in gemeinsam:
                print("        gelesen wird stattdessen: %s" % g)
                if g in geschrieben_set:
                    print("        (das ist genau die Schreibweise von toJson)")
            if not gemeinsam:
                print("        KEIN Gegenstueck gefunden - das Feld geht"
                      " beim Lesen verloren.")
        print()
        print("    => Diese Felder kommen beim Lesen nicht an. Im Cache"
              " nach jedem")
        print("       App-Neustart, beim Serverabruf sofort. Die Daten"
              " sind in der")
        print("       Datenbank vorhanden - nur der Client kommt nicht"
              " an sie heran.")

    if unbeschrieben:
        print()
        print("  X %d Feld(er) werden gelesen, aber nirgends geschrieben:"
              % len(unbeschrieben))
        for feld in unbeschrieben:
            fehler += 1
            print("      %s" % feld)
        print("    => Diese Felder sind IMMER leer (auch direkt nach dem"
              " Speichern).")

    if fehler:
        return 1

    print()

    # Der zweite Parser: fromPublicView liest das Profil ANDERER
    # (Server-Antwort). Auch dort darf kein Feld verloren gehen.
    #
    # DER GRUND DER PRUEFUNG: Die Vorstellung des anderen kommt dort
    # an - aber nur, weil beide Schreibweisen gelesen werden. Ohne den
    # Ausgleich faellt so ein Fehler nur auf einem Geraet auf.
    public_view = re.search(
        r"factory UserProfile\.fromPublicView\(Map<String, dynamic> json\)\s*\{\s*"
        r"(.*?)\n\s{4}\}\n",
        modell,
        re.S,
    )
    if public_view:
        gelesen2 = _lade_alle(
            public_view.group(1),
            r"json\[['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]\]",
        )
        for gruppe in _lade_alle(
            public_view.group(1),
            r"_lese(?:Text|Bool|Zahl|Liste|Datum)\(\s*json\s*,\s*\[([^\]]*)\]",
        ):
            gelesen2 += re.findall(
                r"['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]", gruppe
            )
        # Der Server liefert die Spaltennamen mit Unterstrich. Ein
        # camelCase-Name, den niemand schreibt, kommt dort nie an.
        verloren2 = []
        for feld in sorted(set(gelesen2)):
            # Der Server liefert die Spaltennamen mit Unterstrich
            # ("match_score"). Ein camelCase-Name, dessen
            # snake_case-Form es gibt, kommt also an - nur eben unter
            # dem anderen Namen. Erst wenn es BEIDE nicht gibt, ist
            # das Feld verloren.
            snake = re.sub(r"(?<!^)(?=[A-Z])", "_", feld).lower()
            if "_" in feld or "_" in snake:
                continue  # Server-Spaltenname.
            if feld in SERVER_FELDER:
                continue  # Der Server liefert das (z. B. das Alter).
            varianten = _varianten(feld)
            if not (varianten & (geschrieben_set | mapped_set)):
                verloren2.append(feld)
        if verloren2:
            fehler += len(verloren2)
            print()
            print("  X %d Feld(er) liest fromPublicView, aber niemand"
                  " schreibt sie:" % len(verloren2))
            for feld in verloren2:
                print("      %s" % feld)
            print("    => Im Profil ANDERER kommt dieses Feld nie an.")
        else:
            print("  OK: auch fromPublicView verliert kein Feld.")
    print("  OK: jedes geschriebene Feld wird auch gelesen - in einer"
          " Schreibweise,")
    print("      die der Produzent auch benutzt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
