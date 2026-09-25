import 'package:flutter/foundation.dart';

import 'package:thestia/services/server_time_service.dart';

/// Zentrale Altersberechnung für die gesamte App.
///
/// Berechnet das Alter IMMER anhand der **Serverzeit** (via [ServerTimeService]),
/// NICHT anhand der lokalen Gerätezeit (DateTime.now()), da diese vom Nutzer
/// manipulierbar ist. Das ist sicherheitskritisch für Jugendschutz & Altersprüfungen.
int? calculateAge(DateTime? birthDate) {
  if (birthDate == null) {
    if (kDebugMode) debugPrint('[AGE_CALCULATOR] birthDate is null, returning null');
    return null;
  }
  final now = ServerTimeService.instance.now;
  if (birthDate.isAfter(now)) {
    if (kDebugMode) debugPrint('[AGE_CALCULATOR] birthDate=$birthDate is in the future, returning null');
    return null;
  }
  var age = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
     age--;
  }
  if (kDebugMode) debugPrint('[AGE_CALCULATOR] birthDate=$birthDate, now=$now, calculatedAge=$age');
  return age;
}