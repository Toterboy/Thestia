import 'package:hive/hive.dart';

part 'report_models.g.dart';

/// Typ eines Reports.
@HiveType(typeId: 30)
enum ReportType {
  @HiveField(0)
  harassment('Belästigung / Beleidigungen'),
  @HiveField(1)
  inappropriateContent('Unangemessene Inhalte (Bilder/Nachrichten)'),
  @HiveField(2)
  spam('Spam / Werbung'),
  @HiveField(3)
  fakeProfile('Fake Profil / Identitätsmissbrauch'),
  @HiveField(4)
  other('Sonstiges'),
  @HiveField(5)
  wrongAge('Falsches Alter / Alter stimmt nicht');

  const ReportType(this.label);
  final String label;

  /// L10n-Schlüssel für die Anzeige (Dialoge, Admin-Liste).
  String get labelKey => 'report.type.$name';

  /// Technischer Schlüssel für die Serverseitige Ablage (submit_report-RPC).
  String get value => name;
}

/// Model für einen Nutzer-Report.
@HiveType(typeId: 31)
class UserReport extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String reporterId;

  @HiveField(2)
  final String reportedUserId;

  @HiveField(3)
  final ReportType type;

  @HiveField(4)
  final String? description;

  @HiveField(5)
  final DateTime createdAt;

  @HiveField(6)
  String status; // 'pending', 'reviewed', 'action_taken', 'dismissed'

  @HiveField(7)
  String? moderatorNote;

  @HiveField(8)
  DateTime? resolvedAt;

  UserReport({
    required this.id,
    required this.reporterId,
    required this.reportedUserId,
    required this.type,
    this.description,
    required this.createdAt,
    this.status = 'pending',
    this.moderatorNote,
    this.resolvedAt,
  });

  UserReport copyWith({
    String? id,
    String? reporterId,
    String? reportedUserId,
    ReportType? type,
    String? description,
    DateTime? createdAt,
    String? status,
    String? moderatorNote,
    DateTime? resolvedAt,
  }) {
    return UserReport(
      id: id ?? this.id,
      reporterId: reporterId ?? this.reporterId,
      reportedUserId: reportedUserId ?? this.reportedUserId,
      type: type ?? this.type,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      moderatorNote: moderatorNote ?? this.moderatorNote,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'reporterId': reporterId,
        'reportedUserId': reportedUserId,
        'type': type.label,
        'description': description ?? '',
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'moderatorNote': moderatorNote ?? '',
        'resolvedAt': resolvedAt?.toIso8601String(),
      };
}
