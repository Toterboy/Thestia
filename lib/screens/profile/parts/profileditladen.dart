// Die Methoden '_ProfilEditLaden'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_edit_screen.dart';

extension _ProfilEditLaden on _ProfileEditScreenState {
  /// Lädt die Vorschaubilder für BESTEHENDE Zusatz-Slots (1/2, v0.9.0).
  ///
  /// Slots mit ausstehender Auswahl ([_pendingExtraBytes]) werden NICHT
  /// angefasst; entfernte Slots ([_removedPhotoSlots]) ebenfalls nicht.
  /// Ohne Supabase (Tests/Demo) landen Platzhalter-Futures - der Screen
  /// darf NIEMALS am Storage-Provider scheitern.
  void _loadExtraFutures(List<String> photos, {bool skipPending = false}) {
    SupabaseStorageService? storage;
    try {
      storage = ref.read(supabaseStorageServiceProvider);
    } catch (_) {
      storage = null;
    }
    final s = storage;
    for (final slot in const [1, 2]) {
      if (skipPending && _pendingExtraBytes.containsKey(slot)) continue;
      if (_removedPhotoSlots.contains(slot)) continue;
      _extraBytesFutures[slot] = (s != null && photos.length > slot)
          ? s.loadAvatarBytes(photos[slot])
          : Future.value(null);
    }
  }

  /// Entscheidungs-Verarbeitung für einen eingereichten Einspruch
  /// (v0.8.1): approved = Bild aus dem Prüfungsort holen, clientseitig
  /// verschlüsseln und als Profilbild übernehmen (nach Nutzer-Bestätigung).
  /// rejected = Meldung + Aufräumen der Appeals-Datei. Danach wird die
  /// Entscheidung serverseitig als 'notified' quittiert.
  Future<void> _resolvePendingAppeal() async {
    try {
      if (!SupabaseService.isInitialized) return;
      final db = SupabaseDatabaseService(SupabaseService.client);
      final appeal = await db.getMyPhotoAppeal();
      if (appeal == null) return;
      final id = appeal['id'] as String?;
      final status = appeal['status'] as String?;
      final path = appeal['storagePath'] as String?;
      if (id == null || status == null) return;

      if (status == 'approved') {
        if (!mounted) return;
        final use = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(
              Icons.check_circle,
              color: Theme.of(ctx).colorScheme.primary,
              size: 40,
            ),
            title: Text(L10n.t(ctx, 'profile.appeal.approvedTitle')),
            content: Text(L10n.t(ctx, 'profile.appeal.approvedBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'profile.appeal.useBtn')),
              ),
            ],
          ),
        );
        await db.acknowledgePhotoAppeal(id);
        if (use != true || !mounted) return;
        final storage = ref.read(supabaseStorageServiceProvider);
        final raw = await storage.downloadAppealImage(path ?? '');
        if (raw == null || !mounted) return;
        final encryptedRef = await storage.uploadAvatar(raw);
        await ref.read(profileProvider.notifier).update(photos: [encryptedRef]);
        if (SupabaseService.isInitialized) {
          await SupabaseDatabaseService(
            SupabaseService.client,
          ).updateSetupFlagsAndVerify({
            'photos': [encryptedRef],
          });
        }
        if (!mounted) return;
        _setzeState(() {
          _pendingAvatarBytes = null;
          _avatarBytesFuture = storage.loadAvatarBytes(encryptedRef);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'profile.appeal.applied')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (status == 'rejected') {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(
              Icons.cancel,
              color: Theme.of(ctx).colorScheme.error,
              size: 40,
            ),
            title: Text(L10n.t(ctx, 'profile.appeal.rejectedTitle')),
            content: Text(L10n.t(ctx, 'profile.appeal.rejectedBody')),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(L10n.t(ctx, 'profile.appeal.okBtn')),
              ),
            ],
          ),
        );
        await db.acknowledgePhotoAppeal(id);
        // Appeals-Bild aufräumen (Owner-Policy erlaubt Delete).
        if (path != null && path.isNotEmpty) {
          await ref.read(supabaseStorageServiceProvider).deleteOwnObject(path);
        }
      }
    } catch (e) {
      debugPrint('[ProfileEdit] Appeal-Verarbeitung fehlgeschlagen: ');
    }
  }
}
