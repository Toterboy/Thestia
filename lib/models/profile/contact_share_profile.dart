import 'dart:convert';

/// Ein Eintrag, über den andere die Person außerhalb von Thestia erreichen.
///
/// [app] ist ein stabiler Schlüssel (`signal`, `threema`, `instagram`,
/// `snapchat`, `discord` oder `custom`). Bei eigenen Apps steht der
/// Anzeigename in [label].
class ContactShareEntry {
  const ContactShareEntry({
    required this.app,
    required this.label,
    required this.handle,
    this.recommended = false,
    this.custom = false,
  });

  final String app;
  final String label;
  final String handle;

  /// Sichere Messenger (Signal, Threema) werden in der UI empfohlen.
  final bool recommended;

  /// Vom Nutzer selbst angelegte App.
  final bool custom;

  bool get isValid => label.trim().isNotEmpty && handle.trim().isNotEmpty;

  ContactShareEntry copyWith({
    String? app,
    String? label,
    String? handle,
    bool? recommended,
    bool? custom,
  }) {
    return ContactShareEntry(
      app: app ?? this.app,
      label: label ?? this.label,
      handle: handle ?? this.handle,
      recommended: recommended ?? this.recommended,
      custom: custom ?? this.custom,
    );
  }

  Map<String, dynamic> toJson() => {
    'app': app,
    'label': label,
    'handle': handle,
    'recommended': recommended,
    'custom': custom,
  };

  static ContactShareEntry? fromJson(Map<String, dynamic> json) {
    final app = json['app'];
    final label = json['label'];
    final handle = json['handle'];
    if (app is! String || label is! String || handle is! String) return null;
    if (app.trim().isEmpty || label.trim().isEmpty) return null;
    return ContactShareEntry(
      app: app,
      label: label,
      handle: handle,
      recommended: json['recommended'] == true,
      custom: json['custom'] == true,
    );
  }
}

/// Lokal gespeicherte Kontaktdaten für "Connect to others".
///
/// DATENSCHUTZ: Diese Daten verlassen das Gerät ausschließlich, wenn die
/// Person aktiv auf "Teilen"/"Kopieren" tippt. Es gibt keine Server-
/// Synchronisierung. Gespeichert wird ausschließlich im verschlüsselten
/// Keystore/Keychain (siehe `SecureContactShareStore`).
class ContactShareProfile {
  const ContactShareProfile({this.phone = '', this.entries = const []});

  final String phone;
  final List<ContactShareEntry> entries;

  bool get isEmpty => phone.trim().isEmpty && entries.isEmpty;

  /// Normalisiert eine Telefonnummer für die Anzeige/Weitergabe.
  ///
  /// Erlaubt Ziffern, Leerzeichen, `+ - ( ) /`. Es müssen mindestens
  /// sechs Ziffern vorhanden sein, damit ein Tippfehler nicht als
  /// Kontakt geteilt wird.
  static String normalizePhone(String input) {
    final trimmed = input.trim();
    if (!RegExp(r'^[0-9+()/\-\s]+$').hasMatch(trimmed)) return '';
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6 || digits.length > 15) return '';
    return trimmed;
  }

  static bool isValidPhone(String input) => normalizePhone(input).isNotEmpty;

  ContactShareProfile copyWith({
    String? phone,
    List<ContactShareEntry>? entries,
  }) {
    return ContactShareProfile(
      phone: phone ?? this.phone,
      entries: entries ?? this.entries,
    );
  }

  String toJsonString() => jsonEncode({
    'phone': phone,
    'entries': entries.map((e) => e.toJson()).toList(),
  });

  /// Liest den gespeicherten Stand.
  ///
  /// Fail-safe: Ein kaputter oder leerer Stand liefert ein leeres
  /// Profil statt einer Exception. Sonst koennte ein defekter
  /// Speichereintrag den ganzen Bildschirm blockieren - und die
  /// Angaben sind freiwillig, also geht nichts verloren, wenn sie
  /// neu eingegeben werden.
  static ContactShareProfile fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const ContactShareProfile();
      }
      return fromJson(decoded);
    } catch (_) {
      return const ContactShareProfile();
    }
  }

  static ContactShareProfile fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    final entries = <ContactShareEntry>[];
    if (rawEntries is List) {
      for (final raw in rawEntries) {
        if (raw is Map<String, dynamic>) {
          final entry = ContactShareEntry.fromJson(raw);
          if (entry != null) entries.add(entry);
        }
      }
    }
    final phone = json['phone'];
    return ContactShareProfile(
      phone: phone is String ? phone : '',
      entries: List.unmodifiable(entries),
    );
  }
}
