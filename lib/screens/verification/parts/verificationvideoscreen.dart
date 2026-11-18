// Der Teil 'VerificationVideoScreen'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../verification_flow.dart';

/// Screen für Video Verifizierung (Aufnahme).
class VerificationVideoScreen extends ConsumerStatefulWidget {
  const VerificationVideoScreen({super.key});

  @override
  ConsumerState<VerificationVideoScreen> createState() =>
      _VerificationVideoScreenState();
}
