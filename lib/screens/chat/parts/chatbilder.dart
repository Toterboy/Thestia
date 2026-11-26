// Die Methoden '_ChatBilder'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unverändert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

extension _ChatBilder on _ChatDetailScreenState {
  /// E: Bild aus Galerie/Kamera auswählen und E2E-verschlüsselt
  /// über den P2P-DataChannel senden.
  Future<void> _pickImage() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'chat.imageSend')),
        content: Text(L10n.t(context, 'chat.imageSourcePrompt')),
        // v0.9.0-Feedback: Buttons volle Breite, untereinander,
        // Abbrechen ganz unten (vorher qütschten sie sich in eine Reihe).
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop('camera'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(L10n.t(ctx, 'chat.camera')),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop('gallery'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(L10n.t(ctx, 'chat.gallery')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    final match = _match;
    if (match == null) return;

    _setzeState(() => _uploadingImage = true);
    try {
      final picker = ImagePicker();
      final source = choice == 'camera'
          ? ImageSource.camera
          : ImageSource.gallery;
      final picked = await picker.pickImage(
        source: source,
        // Bounds wie Avatare (2048 px): Vollauflösung vom Gallery-Pick
        // würde Speicher sprengen und den DataChannel verstopfen.
        // Angezeigt wird max. 0.8 Bildschirmbreite - mehr braucht niemand.
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 70, // Kompression für DataChannel
      );
      if (picked == null) {
        if (mounted) _setzeState(() => _uploadingImage = false);
        return;
      }

      final rawBytes = await File(picked.path).readAsBytes();

      // Audit M-21: EXIF (GPS, Geräteinfos) VOR Versand entfernen -
      // fail-closed, wenn das Bild nicht re-encodierbar ist.
      //
      // KEIN automatischer NSFW-Scan beim Senden (Betreiber-Entscheidung):
      // Chat-Bilder bleiben unangetastet E2E. Prüfung ausschließlich
      // melde-basiert (showImageReportDialog -> Edge Function report-image).
      final bytes = await stripImageMetadata(
        Uint8List.fromList(rawBytes),
        jpegQuality: 70,
      );
      if (bytes == null) {
        if (mounted) _setzeState(() => _uploadingImage = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'chat.imagePrepareFailed')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Bild-Hash serverseitig registrieren (Migration 068): Nur der
      // SHA-256-Hash - niemals das Bild. Damit kann eine spätere Meldung
      // dieses Bildes NACHGEWIESEN werden (Edge Function `report-image`
      // lehnt Bilder ohne Registrierung ab).
      // Best effort - Senden darf daran nicht scheitern.
      await bestEffort('convert.toString', () async {
        final imageHash = sha256.convert(bytes).toString();
        unawaited(
          SupabaseService.client.rpc(
            'register_chat_image_hash',
            params: {
              'p_receiver_id': match.partner.id,
              'p_photo_hash': imageHash,
            },
          ),
        );
      });

      // E2E-verschlüsselt über den DataChannel senden.
      await _p2p?.sendBinary(
        Uint8List.fromList(bytes),
        contentType: 'image/jpeg',
      );

      // Lokale Vorschau anzeigen.
      final localMsg = Message(
        id: Message.newId('local_img'),
        senderId: _myUserId ?? AppConstants.currentUserId,
        receiverId: match.partner.id,
        text: '',
        timestamp: DateTime.now(),
        mediaUrl: 'data:image/jpeg;base64,${base64Encode(bytes)}',
        type: MessageType.image,
      );
      ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
      if (mounted) _setzeState(() => _uploadingImage = false);
    } catch (e) {
      if (mounted) {
        _setzeState(() => _uploadingImage = false);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Text(L10n.t(ctx, 'chat.imageSendFailed')),
              ],
            ),
            content: Text(
              L10n.tf(ctx, 'chat.imageSendFailedBody', {'error': '$e'}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(L10n.t(ctx, 'common.cancel')),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _pickImage();
                },
                child: Text(L10n.t(ctx, 'chat.retry')),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Meldet ein einzelnes Bild als unangemessenen Inhalt.
  ///
  /// Chat-Bilder werden bewusst NICHT beim Senden gescannt (E2E). Erst
  /// die Meldung durch den Empfänger löst die Prüfung aus: Die KI prüft
  /// das Bild automatisch, der Meldende sieht das Ergebnis sofort und
  /// kann bei Widerspruch der KI eine manuelle Team-Prüfung veranlassen
  /// (Bild + Report + KI-Ergebnis gehen ans Team, siehe
  /// [showImageReportDialog] und Edge Function `report-image`).
  void _reportImage(Message msg) {
    final match = _match;
    if (match == null) return;
    // Letzte 3 Textnachrichten als Kontext für das Moderations-Team
    // (v0.8.0). Das gemeldete Bild selbst wird separat übertragen.
    final contextMessages = ref
        .read(chatProvider.notifier)
        .messagesFor(match.id)
        .where(
          (m) =>
              m.id != msg.id &&
              m.text.trim().isNotEmpty &&
              m.type == MessageType.text,
        )
        .map((m) => m.text.trim())
        .toList()
        .reversed
        .take(3)
        .toList()
        .reversed
        .toList();
    showImageReportDialog(
      context: context,
      ref: ref,
      message: msg,
      reportedUserId: match.partner.id,
      reportedUserName: match.partner.name,
      contextMessages: contextMessages,
    );
  }
}
