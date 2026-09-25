import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/services/supabase_service.dart';

/// Service für Standort-Prüfungen via Supabase Edge Functions.
///
/// Ruft die Edge Function `process-location-check` auf, sobald ein Nutzer
/// seinen Standort in den Profileinstellungen aktualisiert.
///
/// Der Supabase-Client sendet den aktuellen Session-Token automatisch im
/// Authorization-Header, sodass die serverseitige JWT-Prüfung greift.
class LocationCheckService {
  LocationCheckService(this._client);

  final SupabaseClient _client;

  static const String _functionName = 'process-location-check';

  /// Prüft den neuen Standort eines Nutzers serverseitig.
  ///
  /// [userId] ist die Supabase Auth User-ID.
  /// [newLatitude] und [newLongitude] sind die neuen Koordinaten.
  ///
  /// Gibt die Antwort der Edge Function zurück oder `null`, falls der Aufruf
  /// fehlschlägt.
  Future<Map<String, dynamic>?> processLocationCheck({
    required String userId,
    required double newLatitude,
    required double newLongitude,
  }) async {
    try {
      final response = await _client.functions.invoke(
        _functionName,
        body: {
          'userId': userId,
          'newLatitude': newLatitude,
          'newLongitude': newLongitude,
        },
      );

      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        log('[LocationCheckService] Edge Function error: $e');
      }
      return null;
    }
  }
}

/// Provider für den [LocationCheckService].
final locationCheckServiceProvider = Provider<LocationCheckService>((ref) {
  final client = SupabaseService.isInitialized ? SupabaseService.client : null;
  if (client == null) {
    throw StateError(
      'LocationCheckService erfordert initialisiertes Supabase.',
    );
  }
  return LocationCheckService(client);
});
