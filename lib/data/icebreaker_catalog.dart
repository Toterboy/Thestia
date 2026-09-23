import 'package:flutter/material.dart';

/// Lokaler Eisbrecher-Fragenkatalog (v0.9.1).
///
/// Reine Auswahl zum Kopieren - kein Beantworten, kein Server. 10 Kategorien
/// mit je 6 Fragen (60 insgesamt), jeweils Deutsch + Englisch.
class IcebreakerQuestion {
  const IcebreakerQuestion({required this.de, required this.en});

  final String de;
  final String en;

  String textFor(String languageCode) =>
      languageCode == 'en' ? en : de;
}

class IcebreakerCategory {
  const IcebreakerCategory({
    required this.id,
    required this.de,
    required this.en,
    required this.icon,
    required this.questions,
  });

  final String id;
  final String de;
  final String en;
  final IconData icon;
  final List<IcebreakerQuestion> questions;

  String titleFor(String languageCode) =>
      languageCode == 'en' ? en : de;
}

const List<IcebreakerCategory> icebreakerCatalog = [
  IcebreakerCategory(
    id: 'kennenlernen',
    de: 'Kennenlernen',
    en: 'Getting to know',
    icon: Icons.favorite_outline,
    questions: [
      IcebreakerQuestion(
        de: 'Was war das Beste, das dir diese Woche passiert ist?',
        en: 'What was the best thing that happened to you this week?',
      ),
      IcebreakerQuestion(
        de: 'Wofür begeisterst du dich so richtig?',
        en: 'What are you really passionate about?',
      ),
      IcebreakerQuestion(
        de: 'Was würden deine Freunde als deine Superkraft beschreiben?',
        en: 'What would your friends describe as your superpower?',
      ),
      IcebreakerQuestion(
        de: 'Was hast du zuletzt zum ersten Mal gemacht?',
        en: 'What did you do for the first time recently?',
      ),
      IcebreakerQuestion(
        de: 'Morgenmensch oder Nachteule - und warum?',
        en: 'Early bird or night owl - and why?',
      ),
      IcebreakerQuestion(
        de: 'Was bringt dich immer zum Lachen?',
        en: 'What always makes you laugh?',
      ),
    ],
  ),
  IcebreakerCategory(
    id: 'hobbys',
    de: 'Hobbys',
    en: 'Hobbies',
    icon: Icons.palette_outlined,
    questions: [
      IcebreakerQuestion(
        de: 'Womit verbringst du am liebsten deine freie Zeit?',
        en: 'How do you most like to spend your free time?',
      ),
      IcebreakerQuestion(
        de: 'Gibt es ein Hobby, das du schon immer mal anfangen wolltest?',
        en: 'Is there a hobby you have always wanted to start?',
      ),
      IcebreakerQuestion(
        de: 'Sportlich unterwegs oder eher Couch-Profi?',
        en: 'Sporty and active or more of a couch pro?',
      ),
      IcebreakerQuestion(
        de: 'Welches Spiel (Brett, Karten oder Video) magst du am liebsten?',
        en: 'What is your favorite game (board, cards or video)?',
      ),
      IcebreakerQuestion(
        de: 'Bastelst, baust oder werkelst du gerne?',
        en: 'Do you like crafting, building or tinkering?',
      ),
      IcebreakerQuestion(
        de: 'Was war dein schönstes Hobby-Erlebnis bisher?',
        en: 'What has been your nicest hobby experience so far?',
      ),
    ],
  ),
  IcebreakerCategory(
    id: 'essen',
    de: 'Essen & Trinken',
    en: 'Food & Drinks',
    icon: Icons.restaurant_outlined,
    questions: [
      IcebreakerQuestion(
        de: 'Was ist dein Lieblingsessen - und kannst du es kochen?',
        en: 'What is your favorite food - and can you cook it?',
      ),
      IcebreakerQuestion(
        de: 'Kaffee oder Tee - und wie dazu?',
        en: 'Coffee or tea - and how do you take it?',
      ),
      IcebreakerQuestion(
        de: 'Welches Restaurant würdest du mir sofort empfehlen?',
        en: 'Which restaurant would you recommend to me right away?',
      ),
      IcebreakerQuestion(
        de: 'Süß oder salzig - für was schlägt dein Herz?',
        en: 'Sweet or salty - what does your heart beat for?',
      ),
      IcebreakerQuestion(
        de: 'Gibt es ein Gericht aus deiner Kindheit, das du liebst?',
        en: 'Is there a childhood dish that you love?',
      ),
      IcebreakerQuestion(
        de: 'Pizza: klassisch oder experimentell belegt?',
        en: 'Pizza: classic toppings or experimental?',
      ),
    ],
  ),
  IcebreakerCategory(
    id: 'reisen',
    de: 'Reisen',
    en: 'Travel',
    icon: Icons.flight_outlined,
    questions: [
      IcebreakerQuestion(
        de: 'Welche Stadt möchtest du unbedingt mal besuchen?',
        en: 'Which city do you definitely want to visit someday?',
      ),
      IcebreakerQuestion(
        de: 'Was war deine schönste Reise bisher?',
        en: 'What has been your most beautiful trip so far?',
      ),
      IcebreakerQuestion(
        de: 'Strand, Berge oder Städtetrip?',
        en: 'Beach, mountains or city trip?',
      ),
      IcebreakerQuestion(
        de: 'Reist du lieber geplant oder spontan?',
        en: 'Do you prefer to travel planned or spontaneous?',
      ),
      IcebreakerQuestion(
        de: 'Fenster oder Gang im Flugzeug?',
        en: 'Window or aisle on the plane?',
      ),
      IcebreakerQuestion(
        de: 'Wohin ging dein letzter Wochenendausflug?',
        en: 'Where did your last weekend trip take you?',
      ),
    ],
  ),
  IcebreakerCategory(
    id: 'technik',
    de: 'Technik',
    en: 'Tech',
    icon: Icons.computer_outlined,
    questions: [
      IcebreakerQuestion(
        de: 'Welche App nutzt du täglich - und könntest nicht mehr ohne?',
        en: 'Which app do you use daily - and could not live without?',
      ),
      IcebreakerQuestion(
        de: 'Team Android oder Team iPhone?',
        en: 'Team Android or Team iPhone?',
      ),
      IcebreakerQuestion(
        de: 'Gibt es ein Gadget, das dir den Alltag rettet?',
        en: 'Is there a gadget that saves your everyday life?',
      ),
      IcebreakerQuestion(
        de: 'Hörst du Podcasts - wenn ja, welche?',
        en: 'Do you listen to podcasts - and which ones?',
      ),
      IcebreakerQuestion(
        de: 'KI: praktisch oder unheimlich?',
        en: 'AI: useful or creepy?',
      ),
      IcebreakerQuestion(
        de: 'Was war dein erstes Handy?',
        en: 'What was your first mobile phone?',
      ),
    ],
  ),
  IcebreakerCategory(
    id: 'zukunft',
    de: 'Zukunft & Träume',
    en: 'Future & Dreams',
    icon: Icons.rocket_launch_outlined,
    questions: [
      IcebreakerQuestion(
        de: 'Wo siehst du dich in fünf Jahren?',
        en: 'Where do you see yourself in five years?',
      ),
      IcebreakerQuestion(
        de: 'Was steht ganz oben auf deiner Wunschliste fürs Leben?',
        en: 'What is at the very top of your life bucket list?',
      ),
      IcebreakerQuestion(
        de: 'Wenn Geld keine Rolle spielte: was würdest du tun?',
        en: 'If money did not matter: what would you do?',
      ),
      IcebreakerQuestion(
        de: 'Stadtleben oder Landleben in Zukunft?',
        en: 'City life or country life in the future?',
      ),
      IcebreakerQuestion(
        de: 'Gibt es einen Traum, den du dir bald erfüllen willst?',
        en: 'Is there a dream you want to fulfill soon?',
      ),
      IcebreakerQuestion(
        de: 'Was möchtest du dieses Jahr noch lernen?',
        en: 'What do you want to learn this year?',
      ),
    ],
  ),
  IcebreakerCategory(
    id: 'alltag',
    de: 'Alltag',
    en: 'Everyday life',
    icon: Icons.wb_sunny_outlined,
    questions: [
      IcebreakerQuestion(
        de: 'Wie sieht dein perfekter Sonntag aus?',
        en: 'What does your perfect Sunday look like?',
      ),
      IcebreakerQuestion(
        de: 'Was war heute dein kleines Glück?',
        en: 'What was your small moment of happiness today?',
      ),
      IcebreakerQuestion(
        de: 'Was hilft dir wirklich beim Abschalten?',
        en: 'What really helps you switch off?',
      ),
      IcebreakerQuestion(
        de: 'Frühstück: ausführlich oder schnell im Gehen?',
        en: 'Breakfast: long and relaxed or quick on the go?',
      ),
      IcebreakerQuestion(
        de: 'Bist du eher ordentlich oder kreativ-chaotisch?',
        en: 'Are you more tidy or creatively chaotic?',
      ),
      IcebreakerQuestion(
        de: 'Was machst du nach einem langen Tag am liebsten?',
        en: 'What do you most like to do after a long day?',
      ),
    ],
  ),
  IcebreakerCategory(
    id: 'musik',
    de: 'Musik & Kultur',
    en: 'Music & Culture',
    icon: Icons.music_note_outlined,
    questions: [
      IcebreakerQuestion(
        de: 'Welcher Song läuft bei dir gerade in Dauerschleife?',
        en: 'Which song is currently on repeat for you?',
      ),
      IcebreakerQuestion(
        de: 'Warst du schon mal auf einem richtig guten Konzert?',
        en: 'Have you ever been to a really great concert?',
      ),
      IcebreakerQuestion(
        de: 'Filmabend: Komödie, Drama oder Doku?',
        en: 'Movie night: comedy, drama or documentary?',
      ),
      IcebreakerQuestion(
        de: 'Liest du gerne - und wenn ja, was?',
        en: 'Do you like reading - and if so, what?',
      ),
      IcebreakerQuestion(
        de: 'Spielst du ein Instrument oder würdest gerne eines lernen?',
        en: 'Do you play an instrument or would you like to learn one?',
      ),
      IcebreakerQuestion(
        de: 'Museum oder Freizeitpark?',
        en: 'Museum or amusement park?',
      ),
    ],
  ),
  IcebreakerCategory(
    id: 'natur',
    de: 'Natur & Draußen',
    en: 'Nature & Outdoors',
    icon: Icons.park_outlined,
    questions: [
      IcebreakerQuestion(
        de: 'Gehst du gerne spazieren oder wandern?',
        en: 'Do you like going for walks or hikes?',
      ),
      IcebreakerQuestion(
        de: 'Sonnenaufgang oder Sonnenuntergang?',
        en: 'Sunrise or sunset?',
      ),
      IcebreakerQuestion(
        de: 'Hast du ein Lieblingstier?',
        en: 'Do you have a favorite animal?',
      ),
      IcebreakerQuestion(
        de: 'Garten, Balkon oder Fensterbank - wo wächst bei dir was?',
        en: 'Garden, balcony or windowsill - where does something grow at your place?',
      ),
      IcebreakerQuestion(
        de: 'Fahrrad, zu Fuß oder Öffis in der Stadt?',
        en: 'Bike, on foot or public transport in the city?',
      ),
      IcebreakerQuestion(
        de: 'Was ist dein liebster Ort in der Natur?',
        en: 'What is your favorite place in nature?',
      ),
    ],
  ),
  IcebreakerCategory(
    id: 'spass',
    de: 'Spaß & Fantasie',
    en: 'Fun & Imagination',
    icon: Icons.celebration_outlined,
    questions: [
      IcebreakerQuestion(
        de: 'Wenn du für einen Tag unsichtbar wärst: was würdest du tun?',
        en: 'If you were invisible for a day: what would you do?',
      ),
      IcebreakerQuestion(
        de: 'Welche Superkraft hättest du gerne?',
        en: 'Which superpower would you like to have?',
      ),
      IcebreakerQuestion(
        de: 'Mit wem (tot oder lebendig) würdest du gerne essen gehen?',
        en: 'Who (dead or alive) would you like to have dinner with?',
      ),
      IcebreakerQuestion(
        de: 'Was ist dein verborgenes Talent?',
        en: 'What is your hidden talent?',
      ),
      IcebreakerQuestion(
        de: 'Wenn du morgen irgendwo aufwachen könntest: wo?',
        en: 'If you could wake up anywhere tomorrow: where?',
      ),
      IcebreakerQuestion(
        de: 'Was ist dein liebstes "Guilty Pleasure"?',
        en: 'What is your favorite "guilty pleasure"?',
      ),
    ],
  ),
];
