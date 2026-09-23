import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/widgets/music_taste_widgets.dart';

void main() {
  group('Musik-Genre-Katalog', () {
    test('Slugs sind eindeutig und nicht leer', () {
      final slugs = kMusicGenres.map((g) => g.slug).toList();
      expect(slugs, everyElement(isNotEmpty));
      expect(slugs.toSet().length, slugs.length);
    });

    test('Labels sind eindeutig und nicht leer', () {
      final labels = kMusicGenres.map((g) => g.label).toList();
      expect(labels, everyElement(isNotEmpty));
      expect(labels.toSet().length, labels.length);
    });

    test('Instrumental ist Pflichtbestandteil (Roadmap)', () {
      expect(kMusicGenres.any((g) => g.slug == 'instrumental'), isTrue);
    });

    test('sinnvolle Mindestabdeckung', () {
      expect(kMusicGenres.length, greaterThanOrEqualTo(20));
    });
  });

  group('musicGenreLabel', () {
    test('liefert das Label für bekannte Slugs', () {
      expect(musicGenreLabel('pop'), 'Pop');
      expect(musicGenreLabel('instrumental'), 'Instrumental');
    });

    test('unbekannte Slugs fallen auf den Slug zurück', () {
      expect(musicGenreLabel('gibts_nicht'), 'gibts_nicht');
      expect(musicGenreLabel(''), '');
    });
  });
}
