import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/contact_share_profile.dart';
import 'package:thestia/services/secure_contact_share_store.dart';

/// Verschlüsselter Store für die lokalen Kontaktdaten.
final contactShareStoreProvider = Provider<SecureContactShareStore>((ref) {
  return SecureContactShareStore();
});

/// Lädt die Kontaktdaten aus dem Keystore und stellt sie der UI bereit.
///
/// Der Zustand ist bewusst [AsyncValue], damit die Oberfläche während des
/// Entschlüsselns einen Ladezustand zeigen kann und ein Keystore-Fehler
/// nicht als leerer Datensatz missverstanden wird.
class ContactShareNotifier
    extends StateNotifier<AsyncValue<ContactShareProfile>> {
  ContactShareNotifier(this._store) : super(const AsyncLoading()) {
    _load();
  }

  final SecureContactShareStore _store;

  Future<void> _load() async {
    try {
      final profile = await _store.load();
      if (!mounted) return;
      state = AsyncData(profile);
    } catch (e, stack) {
      if (!mounted) return;
      state = AsyncError(e, stack);
    }
  }

  /// Speichert die Kontaktdaten. Gibt `false` zurück, wenn die
  /// Telefonnummer offensichtlich ungültig ist (die UI zeigt dann einen
  /// Hinweis und behält die Eingaben).
  Future<bool> save(ContactShareProfile profile) async {
    final rawPhone = profile.phone.trim();
    final normalizedPhone = rawPhone.isEmpty
        ? ''
        : ContactShareProfile.normalizePhone(rawPhone);
    if (rawPhone.isNotEmpty && normalizedPhone.isEmpty) return false;

    final cleaned = ContactShareProfile(
      phone: normalizedPhone,
      entries: List.unmodifiable(
        profile.entries
            .where((entry) => entry.isValid)
            .map(
              (entry) => entry.copyWith(
                label: entry.label.trim(),
                handle: entry.handle.trim(),
              ),
            ),
      ),
    );

    try {
      await _store.save(cleaned);
      if (mounted) state = AsyncData(cleaned);
      return true;
    } catch (e) {
      debugPrint('[ContactShare] Speichern fehlgeschlagen: $e');
      return false;
    }
  }
}

final contactShareProvider =
    StateNotifierProvider<
      ContactShareNotifier,
      AsyncValue<ContactShareProfile>
    >((ref) => ContactShareNotifier(ref.read(contactShareStoreProvider)));
