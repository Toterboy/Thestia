/// Der Stand der elterlichen Aufsicht fuer dieses Konto.
///
/// Quelle: `get_my_guardian_status()` (Migration 165). Der Server
/// entscheidet - dieses Modell ist nur die Abbildung fuer die Anzeige.
library;

/// Der Stand der Freigabe und der Aufsicht.
class GuardianStatus {
  const GuardianStatus({
    this.consentState = 'none',
    this.supervised = false,
    this.status = 'none',
    this.age,
    this.guardianEmail,
    this.guardianEmailMasked,
    this.notifyEnabled = false,
    this.notifyFrequency = 'none',
    this.usageLimitEnabled = false,
    this.usageStartMin,
    this.usageEndMin,
    this.hasPin = false,
    this.accessPolicy = 'ended',
    this.accessUntil,
    this.emailDeletedAt,
    this.graceMonths,
    this.confirmedAt,
    this.revokedAt,
    this.transitionPending = false,
    this.loaded = false,
  });

  /// `none` | `pending` | `granted` | `revoked`
  final String consentState;

  /// Das Konto steht unter Aufsicht.
  final bool supervised;

  /// `none` | `pending` | `active` | `revoked` | `expired`
  final String status;

  /// Das Alter laut Server (verifiziert, sonst deklariert).
  final int? age;

  /// Die Adresse des Elternteils (die Jugendliche kennt sie - sie hat
  /// sie selbst eingetragen).
  final String? guardianEmail;

  /// Dieselbe Adresse maskiert (`a***@beispiel.de`).
  final String? guardianEmailMasked;

  /// Bekommt der Elternteil Nachrichten?
  final bool notifyEnabled;

  /// `daily` | `weekly` | `monthly` | `none`
  final String notifyFrequency;

  /// Ist die Nutzungszeit begrenzt?
  final bool usageLimitEnabled;

  /// Beginn des erlaubten Zeitfensters (Minuten seit Mitternacht).
  final int? usageStartMin;

  /// Ende des erlaubten Zeitfensters (Minuten seit Mitternacht).
  final int? usageEndMin;

  /// Ist eine PIN gesetzt? (Die PIN selbst kennt das Geraet nicht.)
  final bool hasPin;

  /// `until_18` | `grace` | `indefinite` | `ended`
  final String accessPolicy;

  /// Wann endet der Elternzugriff?
  final DateTime? accessUntil;

  /// Wie viele Monate Nachfrist bei `grace`?
  final int? graceMonths;

  /// Wann wurde die E-Mail-Adresse des Elternteils geloescht?
  ///
  /// Migration 180: Mit dem Ende der Freigabe verschwindet die Adresse
  /// des Elternteils. Die App sagt das dem Nutzer - aber nur, wenn der
  /// Server es bestaetigt. Deshalb kommt der Zeitpunkt von dort.
  final DateTime? emailDeletedAt;

  final DateTime? confirmedAt;
  final DateTime? revokedAt;

  /// Der Screen zum 18. Geburtstag steht an.
  final bool transitionPending;

  /// Wurde der Stand einmal vom Server gelesen?
  final bool loaded;

  /// Der Stand ist noch nicht bekannt (nicht: "es gibt nichts").
  bool get isUnknown => !loaded;

  /// Die Freigabe wartet auf die Bestaetigung des Elternteils.
  bool get isPending => status == 'pending';

  /// Die Freigabe ist aktiv.
  bool get isActive => status == 'active';

  /// Es gibt ueberhaupt eine Freigabe (aktiv oder wartend).
  bool get hasConsent => isActive || isPending;

  /// Die Freigabe ist beendet - widerrufen oder abgelaufen.
  ///
  /// Das ist ein eigener Zustand und nicht dasselbe wie "es gab nie
  /// eine Freigabe": Der Jugendliche soll sehen, dass die Freigabe
  /// existiert hat und dass sie endgueltig vorbei ist.
  bool get isEnded =>
      status == 'revoked' || status == 'expired';

  /// Die E-Mail-Adresse des Elternteils wurde geloescht.
  bool get isGuardianEmailDeleted => emailDeletedAt != null;

  /// Der Nutzer ist minderjaehrig (16 oder 17).
  bool get isMinor => (age ?? 0) > 0 && (age ?? 0) < 18;

  /// Der Nutzer ist gerade volljährig geworden.
  bool get justBecameAdult => (age ?? 0) >= 18;

  /// Liest den Stand aus der RPC-Antwort.
  factory GuardianStatus.fromJson(Map<String, dynamic> json) {
    int? minOf(Object? v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    DateTime? timeOf(Object? v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return GuardianStatus(
      consentState: json['consentState'] as String? ?? 'none',
      supervised: json['supervised'] == true,
      status: json['status'] as String? ?? 'none',
      age: minOf(json['age']),
      guardianEmail: json['guardianEmail'] as String?,
      guardianEmailMasked: json['guardianEmailMasked'] as String?,
      notifyEnabled: json['notifyEnabled'] == true,
      notifyFrequency: json['notifyFrequency'] as String? ?? 'none',
      usageLimitEnabled: json['usageLimitEnabled'] == true,
      usageStartMin: minOf(json['usageStartMin']),
      usageEndMin: minOf(json['usageEndMin']),
      hasPin: json['hasPin'] == true,
      accessPolicy: json['accessPolicy'] as String? ?? 'ended',
      accessUntil: timeOf(json['accessUntil']),
      emailDeletedAt: timeOf(json['emailDeletedAt']),
      graceMonths: minOf(json['graceMonths']),
      confirmedAt: timeOf(json['confirmedAt']),
      revokedAt: timeOf(json['revokedAt']),
      transitionPending: json['transitionPending'] == true,
      loaded: true,
    );
  }

  /// Der Stand, solange er nicht geladen ist.
  ///
  /// WICHTIG: `loaded` ist hier FALSCH. Ein unbekannter Stand ist nicht
  /// "keine Aufsicht" - wer daraus schliesst "ich darf", macht die
  /// Aufsicht unsichtbar. Die Aufrufer pruefen deshalb `isUnknown`.
  static const GuardianStatus unknown = GuardianStatus();
}

/// Das Ergebnis einer Aktion - mit einem maschinenlesbaren Code.
///
/// Die Codes kommen aus den Ausnahmemeldungen der RPCs
/// (`not_eligible`, `same_email`, `rate_limited`, ...). Sie werden im
/// Bildschirm uebersetzt.
class GuardianResult {
  const GuardianResult.ok() : code = null, message = null;
  const GuardianResult.failed(this.code, [this.message]);

  final String? code;
  final String? message;

  bool get isOk => code == null;
}
