// Die Methoden '_EinrichtungNavigation'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_privacy_once_screen.dart';

extension _EinrichtungNavigation on _SettingsPrivacyOnceScreenState {
  /// Leert die Vorstellung, wenn der Schritt uebersprungen wurde.
  ///
  /// Ohne das bliebe eine halbfertige Aufnahme (Text ohne Ton oder
  /// Ton ohne Text) im Profil stehen, obwohl der Schritt nie
  /// abgeschlossen wurde.
  void _clearIntro() {
    if (_introText.isEmpty && _introAudioPath == null) return;
    _setzeState(() {
      _introText = '';
      _introAudioPath = null;
    });
    unawaited(
      ref
          .read(profileProvider.notifier)
          .update(introText: '', introAudioPath: null, clearIntroAudio: true),
    );
    if (SupabaseService.isInitialized) {
      unawaited(
        SupabaseDatabaseService(
          SupabaseService.client,
        ).updateOwnProfile({'intro_text': '', 'intro_audio_path': null}),
      );
    }
  }

  void _nextPage() {
    // Pflicht-Schritte (3 Profil, 4 Vorstellung): Grundangaben muessen
    // erledigt sein, bevor weitergeblaettert werden kann. Schritt 2
    // (Filter) hat sinnvolle Defaults und ist damit immer gueltig.
    if (_currentPage == _SettingsPrivacyOnceScreenState._profilePage) {
      if (_bioCtrl.text.trim().isEmpty) {
        _showStepHint(L10n.t(context, 'setup.hintBio'));
        return;
      }
      if (_selectedInterests.isEmpty) {
        _showStepHint(L10n.t(context, 'setup.hintInterests'));
        return;
      }
      unawaited(_saveProfileExtras());
    }
    if (_currentPage == _SettingsPrivacyOnceScreenState._introPage) {
      // OPTIONAL (v0.10.0). Vorher blockierte dieser Schritt die
      // Einrichtung: ohne 10 Sekunden Audio ging es nicht weiter, obwohl
      // der Schrittentext "du kannst diesen Schritt auch ueberspringen"
      // versprach. Jetzt: leer ist erlaubt, und was eingegeben wurde,
      // wird gespeichert.
      //
      // NUTZERWUNSCH (03.11.2026): "Kann man die Einrichtung abschliessen
      // ohne eine Sprachaufnahme bei der Vorstellung machen zu muessen?"
      //
      // Die Antwort war: der Schritt ist ueberspringbar - ABER wer Text
      // OHNE Audio eintippt, hat seinen Text verloren: isValid() verlangt
      // beides, dadurch wurde _clearIntro() gerufen und der getippte
      // Text verworfen. Das war die eigentliche Stolperfalle.
      //
      // Jetzt: Text allein wird gespeichert, Audio allein auch, beides
      // natuerlich auch. Nur ein vollstaendig leerer Schritt loescht.
      //
      // (09.11.2026): `isValid` verlangt inzwischen nur noch den TEXT -
      // die Aufnahme ist ueberall freiwillig. Der Betreiber: "Es kann
      // jedoch, wenn man sich vorstellt nur eine textliche Vorstellung
      // sein und die Audio kann man dann bei einem Funken hoeren. Das
      // bleibt freigestellt.")
      if (_introText.trim().isNotEmpty || _introAudioPath != null) {
        _saveIntro();
      } else {
        _clearIntro();
      }
    }
    if (_currentPage == _SettingsPrivacyOnceScreenState._birthdayPage) {
      unawaited(_saveBirthdayStyle());
    }
    if (_currentPage == _SettingsPrivacyOnceScreenState._musicPage) {
      unawaited(_saveMusicTaste());
    }
    if (_currentPage == _SettingsPrivacyOnceScreenState._habitudesPage) {
      unawaited(_saveHabitudes());
    }
    if (_currentPage < _SettingsPrivacyOnceScreenState._pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<bool> _onWillPop() async {
    final leave =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(L10n.t(ctx, 'setup.abortTitle')),
            content: Text(L10n.t(ctx, 'setup.abortBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'setup.abortContinue')),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'common.cancel')),
              ),
            ],
          ),
        ) ??
        false;
    return leave;
  }

  void _prevPage() {
    if (_currentPage == _SettingsPrivacyOnceScreenState._musicPage) {
      unawaited(_saveMusicTaste());
    }
    if (_currentPage == _SettingsPrivacyOnceScreenState._birthdayPage) {
      unawaited(_saveBirthdayStyle());
    }
    if (_currentPage == _SettingsPrivacyOnceScreenState._habitudesPage) {
      unawaited(_saveHabitudes());
    }
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showStepHint(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
