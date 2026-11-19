"""Zugriff auf die App-Texte (L10n).

DIE TEXTE LIEGEN NACH THEMEN GETRENNT: `lib/l10n/app_strings.dart` ist nur
noch die Zusammenfuehrung - die Texte selbst stehen je Thema in einer
Datei unter `lib/l10n/strings/`. Das ist der Grund, warum es diesen
Helfer gibt: die Werkzeuge, die die Texte pruefen, sollen nicht wissen
muessen, wie sie verteilt sind.

Aufruf:
    python tool/helpers/l10n_texts.py          # nur zeigen, was da ist
"""
from __future__ import annotations

import pathlib

#: Der Ordner mit den Textdateien (je Thema eine Datei).
ORDNER = pathlib.Path("lib/l10n/strings")


def text_dateien() -> list[pathlib.Path]:
    """Alle Textdateien (nach Namen sortiert)."""
    if not ORDNER.exists():
        raise FileNotFoundError(
            "Der Ordner lib/l10n/strings/ fehlt - die Texte wurden "
            "verschoben?"
        )
    return sorted(ORDNER.glob("*.dart"))


def lies_sprachen() -> tuple[str, str]:
    """Die deutschen und die englischen Texte (jeweils zusammengefuegt).

    DER GRUND FUER DAS ZUSAMMENFUEHREN: Die Werkzeuge vergleichen DE und
    EN keyweise. In den Dateien stehen beide Sprachen nebeneinander -
    hier kommen sie getrennt heraus.
    """
    de: list[str] = []
    en: list[str] = []
    for datei in text_dateien():
        src = datei.read_text(encoding="utf-8")
        de_marker = src.index("  'de': {")
        en_marker = src.index("  'en': {")
        de.append(src[src.index("\n", de_marker) + 1 : en_marker])
        en.append(src[src.index("\n", en_marker) + 1 :])
    return "\n".join(de), "\n".join(en)


def lies_alle() -> str:
    """Alle Texte zusammen (fuer Werkzeuge, die nur nach Schluesseln suchen)."""
    return "\n".join(d.read_text(encoding="utf-8") for d in text_dateien())


if __name__ == "__main__":
    de, en = lies_sprachen()
    print("Textdateien: %d" % len(text_dateien()))
    print("DE: %d Zeichen, EN: %d Zeichen" % (len(de), len(en)))
