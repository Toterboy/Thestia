// Der Teil '_PhotoSlotsRow'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_edit_screen.dart';

/// Bild-Slots für "Profil bearbeiten" (v0.9.0): bis zu 3 Bilder,
/// ABGERUNDET-RECHTECKIG statt rund. Slot 0 = primäres Bild (größer),
/// Slots 1/2 = zusätzliche Bilder. Leere Slots sind Klick-Ziele zum
/// Hinzufügen; jeder belegte Slot hat einen Entfernen-Knopf (die
/// Änderung wird erst beim Speichern am Server wirksam).
class _PhotoSlotsRow extends StatelessWidget {
  const _PhotoSlotsRow({
    required this.pendingPrimary,
    required this.primaryFuture,
    required this.pendingExtra,
    required this.existingExtraFutures,
    required this.removedSlots,
    required this.existingPhotos,
    required this.onPickPrimary,
    required this.onPickExtra,
    required this.onRemove,
  });

  final Uint8List? pendingPrimary;
  final Future<Uint8List?>? primaryFuture;
  final Map<int, Uint8List> pendingExtra;
  final Map<int, Future<Uint8List?>?> existingExtraFutures;
  final Set<int> removedSlots;
  final List<String> existingPhotos;
  final VoidCallback onPickPrimary;
  final ValueChanged<int> onPickExtra;
  final ValueChanged<int> onRemove;

  bool _slotHasContent(int slot) {
    if (slot == 0) {
      return pendingPrimary != null ||
          (!removedSlots.contains(0) && existingPhotos.isNotEmpty);
    }
    return pendingExtra.containsKey(slot) ||
        (!removedSlots.contains(slot) && existingPhotos.length > slot);
  }

  Widget _imageOrPlaceholder({
    required BuildContext context,
    Uint8List? pendingBytes,
    Future<Uint8List?>? future,
    required IconData placeholderIcon,
  }) {
    if (pendingBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        // Die Fotos kommen mit 2048 px aus dem Crop. Fuer eine ~110-px-
        // Kachel reichen 300 px - ohne cacheWidth waeren es bis zu 16 MB
        // dekodierte Bitmap pro Slot (4 Slots = ~64 MB Peak).
        child: Image.memory(pendingBytes, fit: BoxFit.cover, cacheWidth: 300),
      );
    }
    if (future == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: Icon(
            placeholderIcon,
            size: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (bytes == null || snapshot.hasError) {
          return Center(
            child: Icon(
              placeholderIcon,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 300);
      },
    );
  }

  Widget _slot(BuildContext context, int slot, {required bool isPrimary}) {
    final scheme = Theme.of(context).colorScheme;
    final removed = removedSlots.contains(slot);
    final hasContent = _slotHasContent(slot);
    final IconData placeholderIcon = slot == 0
        ? Icons.person
        : Icons.add_a_photo;

    Widget content;
    if (slot == 0) {
      content = _imageOrPlaceholder(
        context: context,
        pendingBytes: pendingPrimary,
        future: (!removed && existingPhotos.isNotEmpty) ? primaryFuture : null,
        placeholderIcon: placeholderIcon,
      );
    } else {
      content = _imageOrPlaceholder(
        context: context,
        pendingBytes: pendingExtra[slot],
        future: pendingExtra.containsKey(slot)
            ? null
            : (!removed && existingPhotos.length > slot
                  ? (existingExtraFutures[slot] ?? Future.value(null))
                  : null),
        placeholderIcon: placeholderIcon,
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: content,
          ),
        ),
        // Leere/entfernte Slots: Tap zum Hinzufügen.
        if (!hasContent)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: slot == 0 ? onPickPrimary : () => onPickExtra(slot),
                child: Center(
                  child: Icon(
                    slot == 0 ? Icons.camera_alt : Icons.add,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        // Primärer Slot: Kamera-Ersetzen-Knopf.
        if (slot == 0 && hasContent)
          Positioned(
            right: 4,
            bottom: 4,
            child: IconButton.filled(
              onPressed: onPickPrimary,
              icon: const Icon(Icons.camera_alt, size: 18),
            ),
          ),
        // Belegter Slot: Entfernen-Knopf.
        if (hasContent)
          Positioned(
            left: 4,
            top: 4,
            child: SizedBox(
              width: 28,
              height: 28,
              child: IconButton.filledTonal(
                padding: EdgeInsets.zero,
                iconSize: 16,
                onPressed: () => onRemove(slot),
                icon: const Icon(Icons.close, size: 16),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Die Slots teilen sich die verfügbare Breite im Verhaeltnis
    // 132:96:96 (gross:zwei klein). Feste Breiten liefen auf
    // schmalen Geraeten ueber (RenderFlex-Overflow, 16 px bei 360 dp),
    // weil 132+96+96+20 = 344 px > 328 px waren.
    //
    // Das ConstrainedBox begrenzt die Zeile nach oben: auf breiten
    // Geraeten (Tablet) wachsen die Slots sonst bis zur Bildschirm-
    // breite. Die Naturgroesse bleibt 132/96/96 px.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 344),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              flex: 132,
              child: AspectRatio(
                aspectRatio: 132 / 176,
                child: _slot(context, 0, isPrimary: true),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              flex: 96,
              child: AspectRatio(
                aspectRatio: 96 / 128,
                child: _slot(context, 1, isPrimary: false),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              flex: 96,
              child: AspectRatio(
                aspectRatio: 96 / 128,
                child: _slot(context, 2, isPrimary: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
