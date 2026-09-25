import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/photo_moderation_models.dart';
import 'package:thestia/services/huggingface_service.dart';
import 'package:thestia/utils/constants.dart';

/// Service für Foto-Moderation (NSFW via Hugging Face, FaceMatch Mock).
class PhotoModerationService {
  PhotoModerationService(this._supabase);

  final SupabaseClient _supabase;

  static const int _maxViolationsIn24h = 3;
  static const Duration _violationWindow = Duration(hours: 24);

  /// Prüft ein Bild auf Nacktinhalt.
  ///
  /// Feature-Flag (Betreiber-Entscheidung): Ist die NSFW-Moderation
  /// deaktiviert (AppConstants.nsfwModerationEnabled = false), wird das
  /// Bild sofort freigegeben – OHNE Prüfung und OHNE photo_moderation-
  /// DB-Eintrag (keine Admin-Warteschlange, keine Datenhoarder-Einträge).
  Future<ModerationResult> checkNudityContent({
    required String userId,
    required Uint8List imageBytes,
  }) async {
    if (!AppConstants.nsfwModerationEnabled) {
      return const ModerationResult(approved: true);
    }

    final hash = sha256.convert(imageBytes).toString();

    final result = await HuggingFaceService.checkImage(imageBytes);

    // In Supabase persistieren.
    try {
      await _supabase.from('photo_moderation').insert({
        'user_id': userId,
        'photo_hash': hash,
        'status': result.isSafe ? 'approved' : (result.needsReview ? 'pending_review' : 'rejected'),
        'hf_categories': jsonEncode(result.categories),
        'hf_label': result.label,
      });
    } catch (e) {
      debugPrint('[PhotoModeration] DB-Insert fehlgeschlagen: $e');
    }

    if (result.isSafe) {
      return const ModerationResult(approved: true);
    }

    if (result.needsReview) {
      return const ModerationResult(
        approved: false,
        needsReview: true,
        reason: 'Moderation temporär nicht verfügbar, Foto wird geprüft.',
        type: PhotoModerationType.otherViolation,
      );
    }

    // NSFW erkannt → Verwarnung zählen.
    final shouldBan = await _recordViolation(userId);

    if (shouldBan) {
      return const ModerationResult(
        approved: false,
        reason: 'Wiederholter Verstoß: Konto gesperrt.',
        type: PhotoModerationType.nudityContent,
      );
    }

    return const ModerationResult(
      approved: false,
      reason: 'Unangemessener Inhalt erkannt. Bei wiederholten Verstößen wird dein Konto gesperrt.',
      type: PhotoModerationType.nudityContent,
    );
  }

  /// Zählt einen Verstoß und prüft, ob Auto-Bann greift (3× in 24h).
  Future<bool> _recordViolation(String userId) async {
    final now = DateTime.now();
    final cutoff = now.subtract(_violationWindow);

    try {
      final response = await _supabase
          .from('photo_moderation')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'rejected')
          .gte('created_at', cutoff.toIso8601String());

      final violationCount = (response as List<dynamic>).length + 1;
      return violationCount >= _maxViolationsIn24h;
    } catch (e) {
      debugPrint('[PhotoModeration] Violation-Count fehlgeschlagen: $e');
      return false;
    }
  }

  // =========================================================================
  // FaceMatch (noch nicht implementiert)
  // =========================================================================

  /// NICHT IMPLEMENTIERT: FaceMatch benötigt FaceNet/ArcFace + Embedding-DB
  /// und ist ein eigenständiges Projekt. Kein Hugging-Face-Modell bietet
  /// Face-Matching als Hosted-Service an.
  ///
  /// Fail-closed (Audit M9): Gibt `false` zurück, bis eine echte
  /// Implementierung existiert. Der frühere Mock (`return true`) hätte
  /// eine nicht vorhandene Verifizierung vorgetäuscht.
  Future<bool> checkFaceMatch({
    required String userId,
    required String photoUrl,
    required String verificationVideoPath,
  }) async {
    return false; // Kein automatisches Bestehen ohne echte Prüfung.
  }

  // =========================================================================
  // Admin-Funktionen
  // =========================================================================

  /// Holt alle pending-review-Einträge für den Admin.
  Future<List<Map<String, dynamic>>> fetchPendingReviews() async {
    try {
      final response = await _supabase
          .from('photo_moderation')
          .select('*, user:profiles(name)')
          .eq('status', 'pending_review')
          .order('created_at', ascending: false)
          .limit(50);

      return (response as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[PhotoModeration] Admin-Fetch fehlgeschlagen: $e');
      return [];
    }
  }

  /// Admin: Foto genehmigen.
  Future<void> approvePhoto(int moderationId, String adminUserId) async {
    await _supabase
        .from('photo_moderation')
        .update({
          'status': 'approved',
          'reviewed_at': DateTime.now().toIso8601String(),
          'reviewed_by': adminUserId,
        })
        .eq('id', moderationId);
  }

  /// Admin: Foto ablehnen.
  Future<void> rejectPhoto(int moderationId, String adminUserId) async {
    await _supabase
        .from('photo_moderation')
        .update({
          'status': 'rejected',
          'reviewed_at': DateTime.now().toIso8601String(),
          'reviewed_by': adminUserId,
        })
        .eq('id', moderationId);
  }
}

/// Ergebnis einer Moderations-Prüfung.
class ModerationResult {
  final bool approved;
  final bool needsReview; // Timeout → pending_review, kein sofortiger Send
  final String? reason;
  final PhotoModerationType? type;

  const ModerationResult({
    required this.approved,
    this.needsReview = false,
    this.reason,
    this.type,
  });
}

/// Provider für den PhotoModerationService.
final photoModerationServiceProvider = Provider<PhotoModerationService>((ref) {
  return PhotoModerationService(Supabase.instance.client);
});
