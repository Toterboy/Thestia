# ADR-0005: Blind Matching („Persönlichkeit zuerst") statt Bild-Swipe

- Status: angenommen
- Datum: 2026-08 (Build-Phase)

## Kontext

Klassische Swipe-Apps belohnen oberflächliche Auswahl und erzeugen
Selektionsdruck (Optimierung des eigenen Fotos). Beides soll Thestia
bewusst vermeiden – ohne Nutzer zu bevormunden.

## Entscheidung

- „Find your Match": Kandidaten erscheinen ohne Foto, dafür mit Text- UND
  Audio-Vorstellung (beide Pflicht beim ersten Öffnen).
- Fotos werden erst freigeschaltet, wenn beide ein Quiz über die Vorstellung
  des anderen bestanden haben (serverseitig erzwungen).
- Blind Mode ist Standard; Altersschutz regelt Sichtbarkeit gestuft.

## Konsequenzen

+ Differenzierungsmerkmal mit gesellschaftlichem Mehrwert (weniger
  Aussehen-Fokus, geringerer Anreiz für Catfishing/Fake-Profile).
+ Das Foto-Gate ist technisch mit dem E2E-Konzept vereinbar (Freigabe
  serverseitig, Inhalte weiterhin P2P).
− Höhere Hürde beim Start (Vorstellung aufnehmen) – akzeptierter Trade-off;
  Onboarding führt Schritt-für-Schritt hindurch.
