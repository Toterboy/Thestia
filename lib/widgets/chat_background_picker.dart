import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/utils/chat_backgrounds.dart';

/// Dateiname des eigenen Hintergrundbildes im App-Verzeichnis.
const String _customFileName = 'chat_bg_custom.jpg';

/// Auswahl-Kachel für Chat-Hintergründe (v0.9.1).
///
/// Wird in den Einstellungen UND in der Einrichtung verwendet und schreibt
/// direkt in den [settingsProvider]: vorgefertigte Muster, "Kein
/// Hintergrund" oder ein eigenes Bild (Galerie, lokal unter
/// `chat_bg_custom.jpg` im App-Verzeichnis abgelegt).
class ChatBackgroundPicker extends ConsumerWidget {
  const ChatBackgroundPicker({super.key});

  static final ImagePicker _picker = ImagePicker();

  /// Harte Obergrenze für das Hintergrundbild: 8 MB. Darüber werden
  /// weder Datei noch Bitmap-Speicher akzeptiert – ein decompression-Bomb
  /// (winzige Datei, riesige Bitmap) würde sonst beim Rendern den
  /// Speicher des Geräts sprengen.
  static const int _maxBytes = 8 * 1024 * 1024;

  /// Ziel-Kantenlänge beim Import. 1600 px reichen für jedes Display
  /// (auch 4K) und begrenzen den Bitmap-Speicher auf ~10 MB.
  static const int _targetPx = 1600;

  Future<void> _pickCustom(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !context.mounted) return;
      final bytes = await picked.readAsBytes();
      if (!context.mounted) return;
      if (bytes.isEmpty || bytes.length > _maxBytes) {
        _toast(context, 'chatbg.tooLarge');
        return;
      }
      final decoded = img.decodePng(bytes) ?? img.decodeJpg(bytes);
      if (decoded == null) {
        _toast(context, 'chatbg.badImage');
        return;
      }
      // Auf Zielgröße bringen (Aspect-Ratio bleibt erhalten) und als
      // JPEG speichern: verkleinert die Datei und vereinheitlicht das
      // Format – ein laterales Dekodieren ist so günstig wie möglich.
      final scaled = decoded.width > _targetPx || decoded.height > _targetPx
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height
                  ? _targetPx
                  : (decoded.width * _targetPx / decoded.height).round(),
              height: decoded.height >= decoded.width
                  ? _targetPx
                  : (decoded.height * _targetPx / decoded.width).round(),
              interpolation: img.Interpolation.average,
            )
          : decoded;
      final dir = await getApplicationDocumentsDirectory();
      final target = File('${dir.path}/$_customFileName');
      await target.writeAsBytes(img.encodeJpg(scaled, quality: 88));
      final notifier = ref.read(settingsProvider.notifier);
      await notifier.setChatBackgroundPath(target.path);
      await notifier.setChatBackground(ChatBackgrounds.custom);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tf(context, 'common.errorWith', {
              'error': '$e',
            })),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _toast(BuildContext context, String key) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t(context, key)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _removeCustom(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.setChatBackground(ChatBackgrounds.none);
    await notifier.setChatBackgroundPath(null);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$_customFileName');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final ids = [
      ChatBackgrounds.none,
      ...ChatBackgrounds.presets,
      ChatBackgrounds.custom,
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: ids.length,
      itemBuilder: (context, i) {
        final id = ids[i];
        final selected = settings.chatBackground == id;
        return _Tile(
          selected: selected,
          label: L10n.t(context, ChatBackgrounds.labelKey(id)),
          onTap: () {
            if (id == ChatBackgrounds.custom &&
                settings.chatBackgroundPath == null) {
              _pickCustom(context, ref);
            } else {
              ref.read(settingsProvider.notifier).setChatBackground(id);
            }
          },
          onDelete: id == ChatBackgrounds.custom &&
                  settings.chatBackgroundPath != null
              ? () => _removeCustom(context, ref)
              : null,
          preview: id == ChatBackgrounds.custom
              ? _CustomPreview(path: settings.chatBackgroundPath)
              : SizedBox.expand(
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: ChatBackgroundView(backgroundId: id),
                  ),
                ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.selected,
    required this.label,
    required this.preview,
    required this.onTap,
    this.onDelete,
  });

  final bool selected;
  final String label;
  final Widget preview;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? scheme.primary : scheme.outlineVariant,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    // Expliziter Clip (statt Container-clipBehavior):
                    // garantiert sauber abgerundete Vorschaubilder.
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: preview,
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: scheme.primary,
                      child: Icon(Icons.check,
                          size: 14, color: scheme.onPrimary),
                    ),
                  ),
                if (onDelete != null)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: InkWell(
                      onTap: onDelete,
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: scheme.errorContainer,
                        child: Icon(Icons.delete_outline,
                            size: 14, color: scheme.onErrorContainer),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CustomPreview extends StatelessWidget {
  const _CustomPreview({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: const Center(child: Icon(Icons.add_photo_alternate_outlined)),
      );
    }
    return Image.file(
      File(path!),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image)),
    );
  }
}
