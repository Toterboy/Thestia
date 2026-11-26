// Der Teil '_PublicProfileAvatarState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_detail_screen.dart';

class _PublicProfileAvatarState extends ConsumerState<_PublicProfileAvatar> {
  Future<Uint8List?>? _avatarFuture;

  /// Thumbnail-Futures nach Pfad cachen.
  ///
  /// Vorher wurde das Future der Thumbnails direkt in `build` erzeugt - jeder
  /// Rebuild (Scrollen, Provider-Update) startete für jedes Bild erneut
  /// einen match-media-Aufruf + HTTP-GET + compute-Entschlüsselung. Bei
  /// Fehlern wird nichts gecacht -> Endlos-Netz bei jedem Rebuild.
  final Map<String, Future<Uint8List?>> _thumbFutures = {};

  Future<Uint8List?> _thumbFuture(String path) => _thumbFutures[path] ??= ref
      .read(supabaseStorageServiceProvider)
      .loadPartnerAvatarBytes(targetUserId: widget.profile.id, path: path);

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  @override
  void didUpdateWidget(covariant _PublicProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Neues Bild (neue Referenz) -> neu laden.
    final oldRef = oldWidget.profile.photos.isNotEmpty
        ? oldWidget.profile.photos.first
        : null;
    final newRef = widget.profile.photos.isNotEmpty
        ? widget.profile.photos.first
        : null;
    if (oldRef != newRef) _loadAvatar();
  }

  void _loadAvatar() {
    _thumbFutures.clear();
    // 107: Pfade aus der View enthalten keine Schlüssel mehr - Fremd-
    // Bilder laufen über match-media (URL + Schlüssel, serverseitig
    // berechtigungsgeprüft). VOR dem Laden den Memory-Cache-Eintrag
    // verwerfen (NUTZERWUNSCH "Bild einfach nicht sichtbar"): Ein alter
    // Schlüssel-Cache könnte sonst permanent ein nicht entschlüsselbares
    // Bild liefern.
    final path = widget.profile.photos.isNotEmpty
        ? widget.profile.photos.first
        : null;
    if (path == null) {
      _avatarFuture = null;
      return;
    }
    final service = ref.read(supabaseStorageServiceProvider);
    service.invalidatePartnerAvatar(
      targetUserId: widget.profile.id,
      path: path,
    );
    _avatarFuture = service.loadPartnerAvatarBytes(
      targetUserId: widget.profile.id,
      path: path,
    );
  }

  @override
  Widget build(BuildContext context) {
    // v0.9.0: abgerundet-RECHTECKIG statt komplett rund + Thumbnails der
    // weiteren Bilder (max. 3, gleiche Verschlüsselung wie Avatare).
    final scheme = Theme.of(context).colorScheme;
    final others = widget.profile.photos
        .skip(1)
        .take(SupabaseStorageService.maxPhotos - 1)
        .toList();

    Widget mainImage;
    if (!widget.isPhotosVisible) {
      mainImage = const Center(child: Icon(Icons.visibility_off, size: 48));
    } else if (_avatarFuture == null) {
      mainImage = Icon(Icons.person, size: 56, color: scheme.onSurfaceVariant);
    } else {
      mainImage = FutureBuilder<Uint8List?>(
        future: _avatarFuture,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null) {
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              // LOAD-FIX: In Displaygröße dekodieren statt das
              // Multi-MB-Original (schnellere Anzeige, weniger RAM).
              cacheWidth: 148 * 3,
              width: double.infinity,
              height: double.infinity,
            );
          }
          // NUTZERWUNSCH "Bild einfach nicht sichtbar": Am Ende des
          // Futures NICHT still stehen bleiben - ein Retry nach kurzer
          // Wartezeit holt ggf. einen frischen match-media-Schlüssel
          // (Cache-bereinigt), ohne Endlos-Spinner.
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Icon(
                Icons.person,
                size: 56,
                color: scheme.onSurfaceVariant,
              ),
            );
          }
          return _AvatarRetryLoader(
            onRetry: () => setState(() => _loadAvatar()),
          );
        },
      );
    }

    return Column(
      children: [
        // Geburtstag des Gegenübers: Stil-Rahmen + Chip (Nutzerwunsch,
        // dezent; birthdayToday kommt serverseitig ohne Geburtsdatum).
        BirthdayStyleFrame(
          style: widget.profile.birthdayStyle,
          active: widget.profile.birthdayToday,
          borderRadius: 20,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 148,
              height: 188,
              color: scheme.primaryContainer,
              child: mainImage,
            ),
          ),
        ),
        if (widget.profile.birthdayToday) ...[
          const SizedBox(height: 8),
          const Center(child: BirthdayChip()),
        ],
        // NUTZERWUNSCH "Profilbild nicht sichtbar": Bei gesperrten Fotos
        // (Quiz noch nicht bestanden / kein Foto hochgeladen) steht hier
        // jetzt DER GRUND statt eines stummen Platzhalters.
        if (!widget.isPhotosVisible) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              L10n.t(context, 'profile.detail.photosLockedHint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        if (widget.isPhotosVisible && others.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final ref1 in others)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 72,
                      height: 92,
                      color: scheme.surfaceContainerHighest,
                      // FIX "Profilbilder von anderen nicht sichtbar":
                      // Fremd-Thumbnails laufen wie das Hauptbild über
                      // match-media (Schlüssel/IV kommen serverseitig).
                      // loadAvatarBytes wäre der EIGENE Pfad -> 403 ->
                      // nur Spinner, nie ein Bild.
                      child: FutureBuilder<Uint8List?>(
                        future: _thumbFuture(ref1),
                        builder: (context, snap) {
                          final b = snap.data;
                          if (b == null) {
                            return const Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          return Image.memory(
                            b,
                            fit: BoxFit.cover,
                            cacheWidth: 72 * 3,
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
