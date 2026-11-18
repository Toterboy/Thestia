import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as thumb;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/age_estimation_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/play_integrity_service.dart';
import 'package:thestia/services/verification_service.dart';
import 'package:thestia/services/location_verification_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/widgets/ai_badge.dart';
import 'package:thestia/utils/best_effort.dart';
import 'package:permission_handler/permission_handler.dart';

part 'parts/verificationinfoscreen.dart';
part 'parts/infobullet.dart';
part 'parts/verificationvideoscreen.dart';
part 'parts/verificationvideoscreenstate.dart';
part 'parts/blinkingdot.dart';
part 'parts/blinkingdotstate.dart';
part 'parts/verificationsuccessscreen.dart';
part 'parts/verificationsuccessscreenstate.dart';

/// Ergebnis der Verifizierung für den Abschluss-Screen (v0.9.1):
/// 'auto' = KI-Triage unauffällig, Badge sofort; 'pending' = manuelle
/// Prüfung durch den Support, Badge erst danach.
final verificationResultProvider = StateProvider<String?>((ref) => null);

/// Warum die KI-Triage die Verifizierung in die manuelle Queue gelegt hat
/// (L10n-Key, Diagnose für den Nutzer auf dem Abschluss-Screen).
final verificationPendingReasonProvider = StateProvider<String?>((ref) => null);

/// KI-Schätzabweichung in Jahren (für die Diagnose-Anzeige).
final verificationDeviationProvider = StateProvider<double?>((ref) => null);

/// Baut TextSpans aus **fett**-Markern. Ohne das stünden die Sterne
/// sichtbar im Text ("Wörter haben **xy**"-Bug).
List<InlineSpan> _boldSpans(String text, TextStyle? base) {
  final spans = <InlineSpan>[];
  final parts = text.split('**');
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    spans.add(
      TextSpan(
        text: parts[i],
        style: i.isOdd
            ? (base ?? const TextStyle()).copyWith(fontWeight: FontWeight.bold)
            : base,
      ),
    );
  }
  return spans;
}
