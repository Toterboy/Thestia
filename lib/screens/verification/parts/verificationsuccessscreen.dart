// Der Teil 'VerificationSuccessScreen'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../verification_flow.dart';

/// Erfolgs-Screen nach Verifizierung (v0.9.1: zwei Varianten).
class VerificationSuccessScreen extends ConsumerStatefulWidget {
  const VerificationSuccessScreen({super.key});

  @override
  ConsumerState<VerificationSuccessScreen> createState() =>
      _VerificationSuccessScreenState();
}
