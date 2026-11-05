import 'package:thestia/utils/best_effort.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Kleine Fußzeile mit der App-Version, die ganz unten auf Screens angezeigt
/// wird. Lädt die Version plattformseitig via `package_info_plus`.
class AppVersionFooter extends StatefulWidget {
  const AppVersionFooter({super.key, this.textAlign});

  final TextAlign? textAlign;

  @override
  State<AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<AppVersionFooter> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
        // Version bleibt leer – nicht kritisch.
await bestEffort('setState', () async {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: _version.isEmpty
          ? Text(
              'Version …',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
              textAlign: widget.textAlign ?? TextAlign.center,
            )
          : Text(
              'Version $_version',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
              textAlign: widget.textAlign ?? TextAlign.center,
            ),
    );
  }
}
