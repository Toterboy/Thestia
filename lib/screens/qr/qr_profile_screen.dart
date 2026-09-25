import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/services/supabase_storage_service.dart';
import 'package:thestia/widgets/qr_profile.dart';
import 'package:thestia/utils/constants.dart';

/// Entschlüsselte Bild-Bytes des eigenen Avatars (Speicher-Cache im
/// Storage-Service macht dies nach dem ersten Laden sofort verfügbar).
final _qrAvatarBytesProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>((ref, ref1) async {
  try {
    return await ref
        .read(supabaseStorageServiceProvider)
        .loadAvatarBytes(ref1);
  } catch (_) {
    return null;
  }
});

/// Zeigt den eigenen QR-Code und den teilbaren Nutzer-Code an.
///
/// Andere Nutzer können diesen Code scannen (via Kamera-App oder
/// in der Thestia-App) um das Profil zu finden und einen Chat zu starten.
class QrProfileScreen extends ConsumerWidget {
  const QrProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final userId = AppConstants.currentUserId;
    final userCode = generateUserCode(userId);
    final photoRef =
        profile.photos.isNotEmpty ? profile.photos.first : null;
    final avatarBytes = photoRef == null
        ? null
        : ref.watch(_qrAvatarBytesProvider(photoRef)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'qr.myCode')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Profil-Info (v0.8.1-Fix: echtes Profilbild statt nur
                // Anfangsbuchstabe - "beim Teilen per QR Code" war das
                // Bild vorher nicht sichtbar).
                CircleAvatar(
                  radius: 36,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  backgroundImage:
                      avatarBytes != null ? MemoryImage(avatarBytes) : null,
                  child: avatarBytes != null
                      ? null
                      : Text(
                          profile.name.isNotEmpty
                              ? profile.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 28,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Text(
                  profile.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 32),

                // QR-Code
                QrProfileWidget(userId: userId),

                const SizedBox(height: 24),

                // Teilbarer Nutzer-Code
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              L10n.t(context, 'qr.yourCode'),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              userCode,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: L10n.t(context, 'qr.copyTooltip'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: userCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(L10n.t(context, 'qr.copied')),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Text(
                  L10n.t(context, 'qr.shareHint'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
