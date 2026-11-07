import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/utils/chat_backgrounds.dart';
import 'package:thestia/utils/best_effort.dart';

/// Dateiname des eigenen Hintergrundbildes im App-Verzeichnis.
const String _customFileName = 'chat_bg_custom.jpg';

/// Auswahl-Kachel für Chat-Hintergründe (v0.9.1).
///
/// Wird in den Einstellungen UND in der Einrichtung verwendet und schreibt
/// direkt in den [settingsProvider]: vorgefertigte Muster, "Kein
/// Hintergrund" oder ein eigenes Bild (Galerie, lokal unter
/// `chat_bg_custom.jpg` im App-Verzeichnis abgelegt).
class ChatBackgroundPicker extends ConsumerWidget {
  const ChatBackgroundPicker({super.key, this.festeBreite});

  /// Feste Breite in Logik-Pixeln - fuer die Verwendung in einem
  /// AlertDialog.
  ///
  /// WARUM (06.11.2026): Flutter packt den Inhalt eines AlertDialog in
  /// ein IntrinsicWidth und fragt damit die intrinsische Breite der
  /// Kinder ab. Eine Liste (GridView/ListView) kann die nicht liefern -
  /// Flutter wirft dann "RenderViewport does not support returning
  /// intrinsic dimensions" und der Dialog bleibt leer.
  ///
  /// Mit einer festen Breite liefert der SizedBox die Breite, und der
  /// Dialog muss die Liste nicht mehr fragen.
  final double? festeBreite;

  static final ImagePicker _picker = ImagePicker();

  /// Harte Obergrenze für das Hintergrundbild: 8 MB. Darüber werden
  /// weder Datei noch Bitmap-Speicher akzeptiert – ein decompression-Bomb
  /// (winzige Datei, riesige Bitmap) würde sonst beim Rendern den
  /// Speicher des Geräts sprengen.
  static const int _maxBytes = 8 * 1024 * 1024;

  /// Ziel-Kantenlänge beim Import. 1600 px reichen für jedes Display
  /// (auch 4K) und begrenzen den Bitmap-Speicher auf ~10 MB.
  static const int _targetPx = 1600;

  /// Bild auf Zielgroesse bringen und als JPEG speichern.
  ///
  /// Laeuft im Isolate (compute). Top-Level-Funktion, weil compute()
  /// keine Methode mit Zustand der Klasse aufrufen kann.
  ///
  /// Gibt null zurueck, wenn das Bild nicht lesbar war.
  static Uint8List? _bildAufbereiten(Uint8List bytes) {
    final decoded = img.decodePng(bytes) ?? img.decodeJpg(bytes);
    if (decoded == null) return null;

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
    return img.encodeJpg(scaled, quality: 88);
  }

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
      // AKKU (03.11.2026): Die Bildverarbeitung laeuft im Hintergrund-
      // Isolate (compute). Ohne das blockiert das Dekodieren eines
      // grossen Fotos den UI-Thread - der Bildschirm haengt sichtbar
      // (und die App kann in der Zeit keine Eingaben verarbeiten).
      final jpeg = await compute(_bildAufbereiten, bytes);
      if (!context.mounted) return;
      if (jpeg == null || jpeg.isEmpty) {
        _toast(context, 'chatbg.badImage');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final target = File('${dir.path}/$_customFileName');
      await target.writeAsBytes(jpeg);
      // Pfad + Auswahl in einem Schritt: spart einen kompletten
      // JSON-Encode und einen Keystore-Write.
      await ref
          .read(settingsProvider.notifier)
          .setCustomChatBackground(target.path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'common.errorWith', {'error': '$e'}),
            ),
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
    await ref.read(settingsProvider.notifier).setCustomChatBackground(null);
    await bestEffort('delete', () async {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$_customFileName');
      if (await f.exists()) await f.delete();
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final ids = [
      ChatBackgrounds.none,
      ...ChatBackgrounds.presets,
      ChatBackgrounds.custom,
    ];
    // WICHTIG (06.11.2026): Das Grid darf NICHT shrink-wrappen, wenn es
    // in einem scrollbaren AlertDialog steht. Flutter wirft dann
    // "RenderShrinkWrappingViewport does not support returning intrinsic
    // dimensions" - der Dialog bleibt leer und der Chat-Bildschirm ist
    // damit unbrauchbar (live im Emulator gesehen: der Dialog ist beim
    // ersten Chat-Besuch mit einem leeren Bildschirm gestorben).
    //
    // Die Loesung ist die, die Flutter selbst nennt: dem Viewport
    // lockere Constraints geben statt die intrinsic dimensions zu
    // messen. Das Grid bekommt eine feste Hoehe und scrollt intern -
    // so sind alle Hintergruende erreichbar und der Dialog muss nicht
    // selbst zu scrollen.
    final raster = GridView.builder(
      physics: const BouncingScrollPhysics(),
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
          onTap: () async {
            if (id == ChatBackgrounds.custom &&
                settings.chatBackgroundPath == null) {
              await _pickCustom(context, ref);
            } else {
              // BEFUND (07.11.2026, Betreiber): "Der Hintergrund, den
              // man auswaehlt, wird nicht gespeichert." Das Schreiben
              // in den Keystore kann scheitern - dann zeigt die App
              // zwar sofort den neuen Hintergrund, beim naechsten Start
              // ist er aber weg. Deshalb wird der Fehler hier
              // GEMELDET, statt ihn zu schlucken.
              final notifier = ref.read(settingsProvider.notifier);
              await notifier.setChatBackground(id);
              if (notifier.persistFehlgeschlagen != null && context.mounted) {
                _toast(context, notifier.persistFehlgeschlagen!);
              }
            }
          },
          onDelete:
              id == ChatBackgrounds.custom &&
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

    // Die Hoehe richtet sich nach dem, was tatsaechlich gebraucht wird.
    //
    // BEFUND (07.11.2026, Betreiber): "Das mit Chat Hintergrund, dass man
    // da scrollen muss ist nur so mittel gut bei den Einstellungen."
    //
    // Vorher stand hier ein festes SizedBox(height: 280). Bei sieben
    // Mustern (ohne + fuenf Vorgaenge + eigenes) sind das drei Reihen -
    // und 280 Pixel zeigen nur zwei. Man musste also scrollen, um den
    // letzten Hintergrund zu sehen.
    //
    // Die Hoehe wird jetzt aus der Kachelgroesse berechnet: so viele
    // Reihen, wie Muster da sind, und keine mehr. Auf einem kleinen
    // Bildschirm nimmt die Dialog hoehe den verfuegbaren Platz
    // (60 Prozent) - dort wird gescrollt, weil es nicht anders geht.
    final bildschirm = MediaQuery.sizeOf(context);
    final breite = festeBreite ?? bildschirm.width * 0.72;
    const spalten = 3;
    const abstand = 8.0;
    const seitenverhaeltnis = 0.85;
    final kachelBreite = (breite - abstand * (spalten - 1)) / spalten;
    final kachelHoehe = kachelBreite / seitenverhaeltnis;
    final reihen = (ids.length / spalten).ceil();
    final noetigeHoehe = reihen * kachelHoehe + (reihen - 1) * abstand;
    final hoehe = noetigeHoehe.clamp(160.0, bildschirm.height * 0.6);

    return SizedBox(height: hoehe, width: festeBreite, child: raster);
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
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant,
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
                      child: Icon(
                        Icons.check,
                        size: 14,
                        color: scheme.onPrimary,
                      ),
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
                        child: Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: scheme.onErrorContainer,
                        ),
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
    // Die Datei ist bis zu 1600 px breit (~10 MB Bitmap). Fuer eine ~120-px-
    // Vorschaukachel reicht ein Bruchteil - ohne cacheWidth landet das
    // Originalbild dauerhaft im globalen ImageCache.
    return Image.file(
      File(path!),
      fit: BoxFit.cover,
      cacheWidth: 240,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image)),
    );
  }
}
