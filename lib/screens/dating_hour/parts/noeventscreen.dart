// Der Teil '_NoEventScreen'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_event_screen.dart';

/// Hinweis, wenn kein Event verfügbar ist.
class _NoEventScreen extends StatelessWidget {
  const _NoEventScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'dh.event.title'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            L10n.t(context, 'dh.event.nonePlanned'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
