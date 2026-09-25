import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/services/supabase_service.dart';

/// Service für den Versand von Bug-Reports per E-Mail über Brevo.
///
/// Sendet den Report an die Supabase Edge Function `send-bug-report`,
/// die ihrerseits die Brevo-API aufruft. Der Brevo-API-Key bleibt
/// serverseitig und ist nicht im App-Code enthalten.
class BrevoBugReportService {
  BrevoBugReportService._();

  /// Sendet einen Bug-Report an die Edge Function.
  ///
  /// [summary] wird nur verwendet, falls [description] leer ist.
  /// [base64Images] sind optionale, base64-kodierte Screenshots
  /// (maximal 5, serverseitig zusätzlich erzwungen).
  Future<bool> submitBugReport({
    required String summary,
    String? description,
    List<String>? base64Images,
  }) async {
    try {
      final desc = (description?.trim() ?? '').isNotEmpty
          ? description!.trim()
          : summary.trim();

      if (desc.length > 5000) {
        debugPrint('[BREVO] Bug-Report abgelehnt: Beschreibung zu lang.');
        return false;
      }
      final images = base64Images?.take(5).toList() ?? const <String>[];

      final deviceInfo = _collectDeviceInfo();
      final userId = SupabaseService.currentUser?.id;

      final body = <String, dynamic>{
        'description': desc,
        'deviceInfo': deviceInfo,
      };

      if (userId != null) {
        body['userId'] = userId;
      }
      if (images.isNotEmpty) {
        body['images'] = [
          for (var i = 0; i < images.length; i++)
            {
              'name': 'screenshot_${i + 1}.jpg',
              'content': images[i],
            },
        ];
      }

      final response = await SupabaseService.client.functions.invoke(
        'send-bug-report',
        body: body,
      );

      if (response.status == 200) {
        debugPrint('[BREVO] Bug-Report akzeptiert.');
        return true;
      }

      final error = response.data is Map
          ? (response.data as Map)['error'] ?? 'Unbekannter Fehler'
          : response.status;
      debugPrint('[BREVO] Bug-Report abgelehnt: $error');
      return false;
    } catch (e) {
      debugPrint('[BREVO] Bug-Report fehlgeschlagen: $e');
      return false;
    }
  }

  /// Sammelt grundlegende Geräteinformationen für den Report.
  String _collectDeviceInfo() {
    final buffer = StringBuffer();
    if (kIsWeb) {
      buffer.writeln('Plattform: Web');
    } else {
      try {
        buffer.writeln('Plattform: ${Platform.operatingSystem}');
      } catch (_) {
        buffer.writeln('Plattform: unbekannt');
      }
    }
    return buffer.toString().trim();
  }
}

/// Provider für den Brevo Bug-Report-Service.
final brevoBugReportServiceProvider =
    Provider<BrevoBugReportService>((ref) {
  return BrevoBugReportService._();
});
