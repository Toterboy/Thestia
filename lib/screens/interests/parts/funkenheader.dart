// Der Teil '_FunkenHeader'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

/// Zentrierter Funken-Kopf: Symbol und Titel, kein Text daneben.
class _FunkenHeader extends StatelessWidget {
  const _FunkenHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // NEBENEINANDER statt untereinander (NUTZERWUNSCH 01.11.2026: "das
    // Funken Symbol und Funken zusammen untereinander etwas gross. Also
    // entweder irgendwie nebeneinander oder etwas kleiner machen").
    //
    // Beides: nebeneinander UND kleiner. Untereinander brauchte der
    // Kopf fast 100 px Hoehe - die Ueberschrift des Abschnitts war
    // groesser als die Ueberschriften der Listen darunter.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primaryContainer.withValues(alpha: 0.7),
          ),
          child: Icon(Icons.auto_awesome, size: 22, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        // Flexible: bei grosser Schriftgroesse waechst die Ueberschrift
        // ueber die Zeile hinaus (der Render-Test prueft 3,2-fache
        // Schriftgroesse) - ohne Flexible laeuft das Row ueber.
        Flexible(
          child: Text(
            L10n.t(context, 'interests.tabSparks'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
