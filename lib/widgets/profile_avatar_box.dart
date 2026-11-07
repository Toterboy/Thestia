import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:thestia/widgets/birthday_style.dart';

/// Das Profilbild-Feld - bewusst EIN Baustein fuer alle Stellen.
///
/// BEFUND (07.11.2026, Betreiber):
///   * "Die Profilvorschau soll dem entsprechen, was auch andere
///     wirklich sehen koennen."
///   * "doppeltes Profilbild"
///
/// DER GRUND: Das Profilbild wurde an mehreren Stellen nachgebaut.
/// Die eine zeichnete einen Kreis (112 px), die andere ein abgerundetes
/// Rechteck (118 x 152) - die Vorschau sah also anders aus als das
/// Original. Zwei getrennte Nachbauten sind der Grund fuer solche
/// Abweichungen: sie laufen auseinander, sobald eine Stelle geaendert
/// wird.
///
/// Deshalb gibt es diesen Baustein. Eigene Profil, Vorschau und
/// Fremdprofil benutzen dieselbe Form - die Vorschau kann damit gar
/// nicht mehr von dem abweichen, was andere sehen.
///
/// Der Geburtstags-Rahmen [BirthdayStyleFrame] gehoert dazu: er ist
/// Teil dessen, was andere am Geburtstag sehen.
class ProfileAvatarBox extends StatelessWidget {
  const ProfileAvatarBox({
    required this.bytes,
    super.key,
    this.width = 118,
    this.height = 152,
    this.radius = 20,
    this.birthdayStyle,
    this.isBirthday = false,
    this.placeholderIcon,
    this.backgroundColor,
  });

  /// Die entschlüsselten Bild-Bytes (null = noch nicht geladen oder
  /// gar kein Bild hinterlegt).
  final Uint8List? bytes;

  final double width;
  final double height;
  final double radius;

  /// Der Geburtstagsstil (null = kein Geburtstag).
  final String? birthdayStyle;

  /// Ob heute Geburtstag ist.
  final bool isBirthday;

  /// Das Symbol, das ohne Bild erscheint.
  final IconData? placeholderIcon;

  /// Die Hintergrundfarbe des Kastens.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inhalt = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        color: backgroundColor ?? scheme.primaryContainer,
        alignment: Alignment.center,
        child: bytes != null
            ? Image.memory(
                bytes!,
                fit: BoxFit.cover,
                // In Displaygroesse dekodieren (2x DPR) statt das
                // Multi-MB-Original voll aufzuloesen - deutlich schneller
                // sichtbar und weniger RAM.
                cacheWidth: (width * 3).round(),
                width: width,
                height: height,
              )
            : (placeholderIcon == null
                  ? const SizedBox.shrink()
                  : Icon(
                      placeholderIcon,
                      size: height * 0.4,
                      color: scheme.onSurfaceVariant,
                    )),
      ),
    );

    final stil = birthdayStyle;
    if (!isBirthday || stil == null) return inhalt;

    return BirthdayStyleFrame(
      style: stil,
      active: true,
      borderRadius: radius,
      child: inhalt,
    );
  }
}
