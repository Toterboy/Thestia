import 'package:thestia/utils/best_effort.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Kleine Fußzeile mit der App-Version, die ganz unten auf Screens angezeigt
/// wird. Lädt die Version plattformseitig via `package_info_plus`.
///
/// BEFUND (07.11.2026, Betreiber): "Aktuell ist bei Transit Spark bei der
/// Aussehen auswahl die Schrift noch immer in der Statusleiste. Sind die
/// APKs veraltet?"
///
/// Die zweite Hälfte der Frage war berechtigt - und die Antwort war
/// "ja". Getestet wurde eine Admin-APK, die noch Build 33 war, während
/// der Fix im Build 38 steckte. Beide heißen "v0.10.0" und sehen auf
/// dem Bildschirm gleich aus.
///
/// Deshalb steht jetzt die **Build-Nummer** in der Fußzeile. Sie ist
/// das, was den Build überhaupt unterscheidet: "0.10.0" sagen beide,
/// "38" und "33" nicht. Wer einen Fehler meldet, nennt damit den
/// genauen Stand.
class AppVersionFooter extends StatefulWidget {
  const AppVersionFooter({super.key, this.textAlign});

  final TextAlign? textAlign;

  @override
  State<AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<AppVersionFooter> {
  String _version = '';
  String _build = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Version bleibt leer – nicht kritisch.
    await bestEffort('setState', () async {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _build = info.buildNumber;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    // Ohne Build-Nummer (z. B. in einer Debug-Umgebung) bleibt die
    // alte Formulierung - eine leere Klammer sieht kaputt aus.
    final text = _build.isEmpty
        ? 'Version $_version'
        : 'Version $_version ($_build)';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Text(
        _version.isEmpty ? 'Version …' : text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        textAlign: widget.textAlign ?? TextAlign.center,
      ),
    );
  }
}
