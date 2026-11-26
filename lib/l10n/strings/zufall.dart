// Die Texte des Themas 'zufall' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fügt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsZufall = {
  'de': {
    'fymb.categories': 'Interessen',
    'fymb.choiceCategory': 'Nach Kategorie',
    'fymb.choiceCategoryDesc':
        'Stöbern in den Interessen: Musik, Sport, Gaming, Reisen und '
        'mehr.',
    'fymb.choiceRandom': 'Zufallsvorstellung',
    'fymb.choiceRandomDesc':
        'Eine Person nach der anderen - ohne Filter, aber nur mit '
        'Vorstellung.',
    'fymb.choiceTitle': 'Wie willst du jemanden kennenlernen?',
    'fymb.empty':
        'In dieser Kategorie ist gerade niemand. Vielleicht eine andere '
        'Altersspanne?',
    'fymb.emptyNoOne': 'Gerade ist niemand da - schau später nochmal vorbei.',
    'fymb.emptyOther':
        'In der Kategorie „{kategorie}" ist gerade niemand. In diesen '
        'Kategorien sind Menschen: {liste}.',
    'fymb.like': 'Gefällt mir',
    'fymb.noCategories': 'Zur Zeit gibt es niemanden zum Stöbern.',
    'fymb.reload': 'Neu laden',
    'fymb.switchMode': 'Andere Art wählen',
    'fymb.title': 'Nach Kategorien',
    'random.backToDiscover': 'Zurück zu Entdecken',
    'random.connectFailed': 'Verbindung zum Partner fehlgeschlagen: {error}',
    'random.connecting': 'Partner gefunden! Verbinde verschlüsselt…',
    'random.endTooltip': 'Chat beenden',
    'random.endedTitle': 'Chat beendet',
    'random.errorEnded': 'Der Zufallschat wurde beendet.',
    'random.errorNoPartner':
        'Zufallschat konnte nicht gestartet werden. Möglicherweise sind '
        'gerade keine anderen Nutzer online. Bitte versuche es später '
        'erneut.',
    'random.errorOffline':
        'Der Zufallschat ist ohne Verbindung nicht verfügbar.',
    'random.errorUnavailable': 'Zufallschat nicht verfügbar.',
    'random.fallbackPartnerName': 'Zufallspartner',
    'random.fallbackTitle': 'Zufallschat',
    'random.hello': 'Sag {name} hallo! 🙂',
    'random.helloDefault': 'deinem Partner',
    'random.hint': 'Nachricht …',
    'random.leaveBody':
        'Der Chat wird beendet und die Verbindung getrennt. Du kannst '
        'jederzeit einen neuen Zufallschat starten.',
    'random.leaveConfirm': 'Beenden',
    'random.leaveTitle': 'Zufallschat beenden?',
    'random.likeSentWaiting':
        'Gefällt-Markierung gesendet! Der Funke entsteht, sobald ihr '
        'gegenseitig geliked habt.',
    'random.likeTooltip': 'Liken',
    'random.notLoggedIn': 'Nicht eingeloggt - Zufallschat nicht verfügbar.',
    'random.partnerLeft':
        'Dein Gesprächspartner hat den Zufallschat verlassen.',
    'random.relayNoDirect':
        'Direktverbindung vom Netzwerk blockiert (typisch: AP-Isolation im '
        'Router oder Mobilfunk). Nachrichten kommen sicher über den '
        'Server (E2E-verschlüsselt) an.',
    'random.relayStatus':
        'E2E über Server (verschlüsselt, kein direkter Kanal)',
    'random.searching': 'Suche nach einer Person…',
    'random.searchingSub':
        'Sobald jemand anderes den Zufallschat startet, werdet ihr '
        'verbunden.',
    'random.sendFailed': 'Nachricht konnte nicht gesendet werden.',
    'random.waitingForPartner':
        'Warte auf das Partner-Gerät (Schlüssel werden dort vorbereitet). '
        'Die Verbindung stellt sich automatisch her - schreib ruhig schon '
        'mal etwas.',
  },
  'en': {
    'fymb.categories': 'Interests',
    'fymb.choiceCategory': 'By category',
    'fymb.choiceCategoryDesc':
        'Browse the interests: music, sports, gaming, travel and more.',
    'fymb.choiceRandom': 'Random introduction',
    'fymb.choiceRandomDesc':
        'One person after another - no filter, but only people with an '
        'introduction.',
    'fymb.choiceTitle': 'How do you want to meet someone?',
    'fymb.empty':
        'Nobody is around in this category right now. Maybe try a '
        'different age range?',
    'fymb.emptyNoOne': 'Nobody is around right now - check back later.',
    'fymb.emptyOther':
        'Right now there is nobody in the category \u201e{kategorie}\u201c. '
        'There are people in these categories: {liste}.',
    'fymb.like': 'Like',
    'fymb.noCategories': 'Nobody to browse right now.',
    'fymb.reload': 'Reload',
    'fymb.switchMode': 'Choose another way',
    'fymb.title': 'Browse by category',
    'random.backToDiscover': 'Back to Discover',
    'random.connectFailed': 'Connection to partner failed: {error}',
    'random.connecting': 'Partner found! Connecting encrypted…',
    'random.endTooltip': 'End chat',
    'random.endedTitle': 'Chat ended',
    'random.errorEnded': 'The random chat has ended.',
    'random.errorNoPartner':
        'Random chat could not be started. Possibly no other users are '
        'online right now. Please try again later.',
    'random.errorOffline': 'Random chat is not available without connection.',
    'random.errorUnavailable': 'Random chat not available.',
    'random.fallbackPartnerName': 'Random partner',
    'random.fallbackTitle': 'Random chat',
    'random.hello': 'Say hello to {name}! 🙂',
    'random.helloDefault': 'your partner',
    'random.hint': 'Message …',
    'random.leaveBody':
        'The chat will be ended and the connection closed. You can start '
        'a new random chat anytime.',
    'random.leaveConfirm': 'End',
    'random.leaveTitle': 'End random chat?',
    'random.likeSentWaiting':
        'Like sent! The spark appears as soon as you both like each '
        'other.',
    'random.likeTooltip': 'Like',
    'random.notLoggedIn': 'Not logged in - random chat unavailable.',
    'random.partnerLeft': 'Your random chat partner has left.',
    'random.relayNoDirect':
        'Direct connection blocked by the network (typically AP isolation '
        'on the router or mobile data). Messages arrive securely via the '
        'server (E2E encrypted).',
    'random.relayStatus': 'E2E via server (encrypted, no direct channel)',
    'random.searching': 'Searching for a person…',
    'random.searchingSub':
        'Once someone else starts random chat, you will be connected.',
    'random.sendFailed': 'Message could not be sent.',
    'random.waitingForPartner':
        'Waiting for the partner device (keys are being prepared there). '
        'The connection establishes automatically - feel free to write '
        'already.',
  },
};
