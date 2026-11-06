import 'dart:convert';

import 'dart:io';

/// Repariert ANSI-Fehldekodierung: Jeder Char <= 0xFF wird als Byte
/// interpretiert; gueltige UTF-8-Sequenzen werden zu echten Zeichen
/// kollabiert. Bereits korrekte Zeichen (>0xFF) bleiben unberuehrt.
/// CP1252-Sonderzeichen zurueck auf ihr Byte gemappt.
const Map<int, int> _cp1252High = {
  0x20AC: 0x80,
  0x201A: 0x82,
  0x0192: 0x83,
  0x201E: 0x84,
  0x2026: 0x85,
  0x2020: 0x86,
  0x2021: 0x87,
  0x02C6: 0x88,
  0x2030: 0x89,
  0x0160: 0x8A,
  0x2039: 0x8B,
  0x0152: 0x8C,
  0x017D: 0x8E,
  0x2018: 0x91,
  0x2019: 0x92,
  0x201C: 0x93,
  0x201D: 0x94,
  0x2022: 0x95,
  0x2013: 0x96,
  0x2014: 0x97,
  0x02DC: 0x98,
  0x2122: 0x99,
  0x0161: 0x9A,
  0x203A: 0x9B,
  0x0153: 0x9C,
  0x017E: 0x9E,
  0x0178: 0x9F,
};

int? _charToByte(int c) {
  if (c <= 0xFF) return c;
  return _cp1252High[c];
}

String _repair(String input) {
  final out = StringBuffer();
  var i = 0;
  while (i < input.length) {
    final firstByte = _charToByte(input.codeUnitAt(i));
    if (firstByte != null && firstByte >= 0xC2) {
      // Moegliche UTF-8-Sequenz einsammeln (max 4 Bytes).
      final bytes = <int>[firstByte];
      final len = firstByte >= 0xF0
          ? 4
          : firstByte >= 0xE0
          ? 3
          : 2;
      var valid = true;
      for (var j = 1; j < len; j++) {
        if (i + j >= input.length) {
          valid = false;
          break;
        }
        final b = _charToByte(input.codeUnitAt(i + j));
        if (b == null || (b & 0xC0) != 0x80) {
          valid = false;
          break;
        }
        bytes.add(b);
      }
      if (valid) {
        try {
          out.write(utf8.decode(bytes));
          i += len;
          continue;
        } on FormatException {
          // fall through
        }
      }
    }
    out.writeCharCode(input.codeUnitAt(i));
    i++;
  }
  return out.toString();
}

const files = [
  'lib/screens/quiz/quiz_screen.dart',
  'lib/screens/onboarding/onboarding_screen.dart',
  'lib/screens/home/home_screen.dart',
  'lib/screens/dating_hour/dating_hour_how_it_works_screen.dart',
  'lib/screens/chat/chat_detail_screen.dart',
  'lib/screens/interests/interessen_screen.dart',
  'lib/screens/spice/spice_questions_screen.dart',
  'lib/screens/dating_hour/dating_hour_chat_screen.dart',
  'lib/screens/settings/settings_screen.dart',
  'lib/screens/dating_hour/dating_hour_event_screen.dart',
  'lib/models/app_settings.dart',
  'lib/providers/settings_provider.dart',
  'lib/providers/auth_provider.dart',
  'lib/theme/app_theme.dart',
  'lib/routing/app_router.dart',
  'lib/utils/constants.dart',
  'lib/services/auth_service.dart',
  'lib/services/app_auth_service.dart',
  'lib/services/unified_push_service.dart',
];

/// Zusaetzlich: rekursiv alle Dart-Dateien in lib/ und tool/ pruefen.
List<String> collectAll() {
  final list = <String>[...files];
  for (final dir in ['lib', 'tool']) {
    Directory(dir).listSync(recursive: true).forEach((entity) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final normalized = entity.path.replaceAll('\\', '/');
        if (!list.contains(normalized)) list.add(normalized);
      }
    });
  }
  return list;
}

void main() {
  var fixed = 0;
  for (final path in collectAll()) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final original = f.readAsStringSync();
    final repaired = _repair(original);
    if (repaired != original) {
      f.writeAsStringSync(repaired);
      stdout.writeln('repariert: $path');
      fixed++;
    }
  }
  stdout.writeln('Dateien repariert: $fixed');
}
