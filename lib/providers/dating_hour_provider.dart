import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/dating_hour_models.dart';
import 'package:thestia/services/dating_hour_service.dart';
import 'package:thestia/utils/constants.dart';

/// Liefert das aktuelle oder nächste Dating-Hour-Event inklusive eigener
/// Teilnahme-Information. Wird automatisch von Riverpod gecached und kann mit
/// `ref.invalidate(currentDatingHourEventProvider)` neu geladen werden.
///
/// V: Die eigene Teilnahme wird serverseitig über RLS geprüft; der Client kann
/// keine fremden Teilnehmer-IDs sehen. `activeParticipants` enthält daher im
/// MVP nur die eigene ID, falls der User opt-in hat.
final currentDatingHourEventProvider = FutureProvider<DatingHourEvent?>((ref) async {
  final service = ref.watch(datingHourServiceProvider);
  final event = await service.getCurrentOrNextEvent();
  if (event == null) return null;

  final participating = await service.isUserParticipating(event.id);
  event.currentUserParticipating = participating;
  event.activeParticipants = participating ? [AppConstants.currentUserId] : [];
  return event;
});

/// Liefert die aktive Dating-Hour-Session des aktuellen Users für ein Event.
final myActiveDatingHourSessionProvider =
    FutureProvider.family<DatingHourSession?, String>((ref, eventId) async {
  final service = ref.watch(datingHourServiceProvider);
  return service.getMyActiveSession(eventId);
});
