/// Gruppierung von Chat-Nachrichten (Nutzerwunsch Transparenz):
///
/// - Jede Nachricht bleibt in ihrer EIGENEN Bubble.
/// - Der Absendername steht EINMAL über einer Gruppe: bei Senderwechsel,
///   bei > 3 Minuten Abstand oder nach max. 3 direkt aufeinanderfolgenden
///   Nachrichten desselben Absenders (dann beginnt eine neue Gruppe mit
///   Namens-Header).
/// - Jede Bubble trägt eine kleine Zeitanzeige (HH:mm).
library;

import 'package:wisp/models/message.dart';

/// Gruppier-Fenster: Nachrichten desselben Absenders innerhalb von
/// [groupWindow] gehören (bis [maxPerGroup]) zu einer Gruppe.
const Duration chatGroupWindow = Duration(minutes: 3);

/// Max. Nachrichten pro Gruppe, danach neuer Namens-Header.
const int chatMaxPerGroup = 3;

/// Berechnet pro Nachricht (Liste ÄLTESTE zuerst), ob Namens-Header und
/// Zeit angezeigt werden. Rückgabe parallel zur Eingabeliste.
List<({bool showName, bool showTime})> computeBubbleGroups(
    List<Message> oldestFirst) {
  final out = <({bool showName, bool showTime})>[];
  var runSender = '';
  var runCount = 0;
  DateTime? runStart;
  for (var i = 0; i < oldestFirst.length; i++) {
    final msg = oldestFirst[i];
    final sameSender = msg.senderId == runSender;
    final gapOk = runStart != null &&
        msg.timestamp.difference(runStart).abs() <= chatGroupWindow;
    var showName = false;
    if (!sameSender) {
      // Senderwechsel (oder erste Nachricht): neue Gruppe mit Name.
      runSender = msg.senderId;
      runCount = 1;
      runStart = msg.timestamp;
      showName = true;
    } else if (!gapOk) {
      // Mehr als 3 Minuten seit Gruppenstart: neue Gruppe mit Name.
      runCount = 1;
      runStart = msg.timestamp;
      showName = true;
    } else if (runCount >= chatMaxPerGroup) {
      // Mehr als 3 am Stück: neue Gruppe mit Name.
      runCount = 1;
      runStart = msg.timestamp;
      showName = true;
    } else {
      runCount++;
    }
    out.add((showName: showName, showTime: true));
  }
  return out;
}
