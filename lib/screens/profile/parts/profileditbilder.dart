// Die Methoden '_ProfilEditBilder'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_edit_screen.dart';

extension _ProfilEditBilder on _ProfileEditScreenState {
  /// Bild-Auswahl mit lokalem NSFW-Check (v0.8.0/0.8.1): Das Bild wird
  /// VOR dem Upload rein lokal geprüft - es verlässt bei Nichtbestehen
  /// das Gerät nicht. Rückgabe: freigegebene Bytes oder null (verworfen).
  Future<Uint8List?> _pickCheckedImage() async {
    var bytes = await pickAndCropAvatar(context);
    while (bytes != null) {
      // NSFW on-device (v0.8.0, Modell image-safety-classifier-xs):
      // Das Bild verlässt bei Nichtbestehen das Gerät nicht. Bei Befund
      // drei Wege (v0.8.1): verwerfen, anderes Bild oder Einspruch.
      final verdict = await ImageSafetyService.instance.classifyImage(bytes);
      if (verdict == null) break; // Lokal nicht verfügbar -> normal hochladen.

      if (!verdict.isFlagged) {
        // Bestanden -> kleines ✓-Popup, dann normal weiter.
        if (!mounted) return null;
        await _showPhotoOkDialog(context);
        break;
      }

      if (!mounted) return null;
      final action = await _showNsfwAppealDialog(context, verdict);
      if (!mounted) return null;
      if (action == 'appeal') {
        await _submitAppeal(bytes: bytes, verdict: verdict);
        return null; // Bild wird verworfen - kein Avatar-Upload.
      }
      if (action == 'other') {
        bytes = await pickAndCropAvatar(context);
        continue;
      }
      // null = Verstanden: verwerfen.
      return null;
    }
    return bytes;
  }

  /// Wählt ein ZUSÄTZLICHES Bild (Slot 1/2, v0.9.0 max. 3) - gleicher
  /// NSFW-Check wie beim primären Bild, gehalten bis zum Speichern.
  Future<void> _pickExtraImage(int slot) async {
    try {
      final bytes = await _pickCheckedImage();
      if (bytes == null || !mounted) return;
      _setzeState(() {
        _pendingExtraBytes[slot] = bytes;
        _removedPhotoSlots.remove(slot);
        _extraBytesFutures[slot] = Future.value(bytes);
      });
      _syncDirtyFlag();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'profile.edit.photoUploadError', {
                'error': e.toString(),
              }),
            ),
          ),
        );
      }
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final bytes = await _pickCheckedImage();
      if (bytes == null) return;

      // v0.8.1-Fix: NICHT sofort hochladen. Das Bild wird vorgehalten
      // (Vorschau) und der Dirty-Flag gesetzt - wie bei den anderen
      // Angaben erscheint die Speichern-Aufforderung, und der Upload
      // passiert erst mit dem Speichern. Dadurch kann ein versehentlich
      // gewähltes Bild per "Abbrechen" verworfen werden, ohne dass es
      // je den Server erreicht hat (NSFW-Check lief oben bereits).
      // Die Bildauswahl dauert real mehrere Hundert Millisekunden - der
      // Nutzer kann in dieser Zeit zurueckgehen. Dann waere das
      // setState ein Absturz ("_setzeState() called after dispose()").
      if (!mounted) return;
      _setzeState(() {
        _pendingAvatarBytes = bytes;
        // Slot 0 wird ersetzt -> Entfernen-Markierung hinfällig.
        _removedPhotoSlots.remove(0);
      });
      _syncDirtyFlag();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'profile.edit.photoUploadError', {
                'error': e.toString(),
              }),
            ),
          ),
        );
      }
    }
  }

  /// Markiert einen Slot zum Entfernen (vorhandenes Bild ODER pending
  /// Auswahl wird verworfen). Noch nicht am Server - passiert beim
  /// Speichern.
  void _removePhoto(int slot) {
    _setzeState(() {
      _removedPhotoSlots.add(slot);
      _pendingExtraBytes.remove(slot);
      if (slot == 0) {
        _pendingAvatarBytes = null;
        _avatarBytesFuture = null;
      } else {
        _extraBytesFutures.remove(slot);
      }
    });
    _syncDirtyFlag();
  }

  /// NSFW-Dialog (v0.8.1-Redesign): Bei Bestehen ein kleines ✓-Popup,
  /// bei Befund ein ✗ mit dem lokalen Befund und drei Möglichkeiten:
  /// Einspruch (Bild geht in die Admin-Prüfung, wird NICHT als Avatar
  /// hochgeladen), Anderes Bild wählen oder Verstanden (verwerfen).
  /// Rückgabe: 'appeal' | 'other' | null (verworfen).
  Future<String?> _showNsfwAppealDialog(
    BuildContext context,
    ImageSafetyResult verdict,
  ) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.cancel,
          color: Theme.of(ctx).colorScheme.error,
          size: 40,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text(L10n.t(ctx, 'profile.edit.photoNsfwTitle'))),
            const SizedBox(width: 8),
            AiBadge(languageCode: L10n.localeOf(ctx).languageCode),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L10n.t(ctx, 'profile.edit.photoNsfwBody')),
            const SizedBox(height: 8),
            Text(
              L10n.tf(ctx, 'profile.edit.photoNsfwVerdict', {
                'label': verdict.topLabel,
                'score': (verdict.criticalScore * 100).toStringAsFixed(0),
              }),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(L10n.t(ctx, 'profile.edit.photoNsfwNotUploaded')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(L10n.t(ctx, 'profile.edit.photoNsfwUnderstood')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('other'),
            child: Text(L10n.t(ctx, 'profile.edit.photoNsfwOther')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('appeal'),
            child: Text(L10n.t(ctx, 'profile.edit.photoNsfwAppeal')),
          ),
        ],
      ),
    );
  }

  /// Kleines ✓-Popup nach bestandener lokaler Prüfung (v0.8.1).
  Future<void> _showPhotoOkDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.check_circle,
          color: Theme.of(ctx).colorScheme.primary,
          size: 40,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text(L10n.t(ctx, 'profile.edit.photoOkTitle'))),
            const SizedBox(width: 8),
            AiBadge(languageCode: L10n.localeOf(ctx).languageCode),
          ],
        ),
        content: Text(L10n.t(ctx, 'profile.edit.photoOkBody')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'profile.edit.photoOkBtn')),
          ),
        ],
      ),
    );
  }

  /// Einspruch einreichen (v0.8.1): Das abgelehnte Bild wird in den
  /// geschützten Appeals-Ordner hochgeladen (NIEMALS als Avatar
  /// verwendet) und zur manuellen Admin-Prüfung registriert. Die
  /// Entscheidung erreicht den Nutzer per Push + In-App-Dialog.
  Future<void> _submitAppeal({
    required Uint8List bytes,
    required ImageSafetyResult verdict,
  }) async {
    try {
      if (!SupabaseService.isInitialized) {
        throw StateError('kein Server');
      }
      final storage = ref.read(supabaseStorageServiceProvider);
      final path = await storage.uploadAppealImage(bytes);
      await SupabaseDatabaseService(SupabaseService.client).submitPhotoAppeal(
        path: path,
        label: verdict.topLabel,
        score: verdict.criticalScore,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'profile.edit.appealSubmitted')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'profile.edit.appealFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
