import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/transit_encounter_service.dart';

void main() {
  group('Transit-Token (BLE-Paketgrenzen)', () {
    test('generateToken liefert 20 Hex-Zeichen (10 Byte)', () {
      final token = TransitEncounterService.generateToken();
      expect(token.length, 20);
      expect(RegExp(r'^[0-9a-f]{20}$').hasMatch(token), isTrue);
    });

    test('Tokens sind (praktisch) eindeutig', () {
      final tokens = {
        for (var i = 0; i < 200; i++)
          TransitEncounterService.generateToken(),
      };
      expect(tokens.length, 200);
    });

    test('Marker + Token passt garantiert in ein Legacy-Advertisement', () {
      // 31 B Paket - 3 B Flags - 2 B AD-Header - 2 B Company-ID = 24 B.
      expect(TransitEncounterService.maxBlePayloadBytes, 24);
      expect(TransitEncounterService.bleMarker, 'WST1');
      expect(
        TransitEncounterService.blePayloadFits(
            TransitEncounterService.generateToken()),
        isTrue,
      );
      // Das alte 32-Zeichen-Format hätte NIE funktioniert (36 > 24).
      expect(
        TransitEncounterService.blePayloadFits('a' * 32),
        isFalse,
        reason: '32-Zeichen-Token = ADVERTISE_FAILED_DATA_TOO_LARGE',
      );
      expect(TransitEncounterService.blePayloadFits('abc'), isTrue);
    });

    test('Token-Format erfüllt Server-Regex ([0-9a-fA-F-]{8,64})', () {
      final token = TransitEncounterService.generateToken();
      expect(
        RegExp(r'^[0-9a-fA-F-]{8,64}$').hasMatch(token),
        isTrue,
      );
    });
  });

  group('RPC-Signatur-Fehlmatch (PGRST202/203)', () {
    test('PGRST202 und Funktions-nicht-gefunden steigen ab', () {
      expect(
        SupabaseDatabaseService.isRpcSignatureMismatch(
            Exception('PGRST202 Could not find the function')),
        isTrue,
      );
      expect(
        SupabaseDatabaseService.isRpcSignatureMismatch(
            'function public.match_proximity_spark does not exist'),
        isTrue,
      );
    });

    test('PGRST203 Mehrdeutigkeit steigt ab (Best-Candidate-Fix)', () {
      expect(
        SupabaseDatabaseService.isRpcSignatureMismatch(
          Exception(
              'PGRST203 Could not choose the best candidate function between '
              'public.match_proximity_spark(text[]), '
              'public.match_proximity_spark(text[], text[], text)'),
        ),
        isTrue,
      );
    });

    test('echte Fachfehler steigen NICHT ab (Rate-Limit etc.)', () {
      expect(
        SupabaseDatabaseService.isRpcSignatureMismatch(
            Exception('Kurz durchatmen: Bitte kurz warten.')),
        isFalse,
      );
      expect(
        SupabaseDatabaseService.isRpcSignatureMismatch(
            Exception('Kein Profil')),
        isFalse,
      );
      expect(
        SupabaseDatabaseService.isRpcSignatureMismatch(
            Exception('PGRST301 JWT expired')),
        isFalse,
      );
    });
  });
}
