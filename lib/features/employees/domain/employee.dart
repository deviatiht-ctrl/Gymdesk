import '../../../core/sync/sync_models.dart';

/// Anplwaye sal la (antrenè, resepsyon, netwayaj...): aksè pòt pa anprent,
/// san kont pou konekte nan app la.
class Employee {
  const Employee(this.row);
  final Json row;

  static const jobTypes = [
    'coach',
    'reception',
    'cleaning',
    'security',
    'manager',
    'maintenance',
    'other',
  ];

  String get id => row['id'] as String;
  String get firstName => row['first_name'] as String? ?? '';
  String get lastName => row['last_name'] as String? ?? '';
  String get fullName => '$firstName $lastName'.trim();
  String? get phone => row['phone'] as String?;
  String? get email => row['email'] as String?;
  String get jobType => row['job_type'] as String? ?? 'other';
  String? get jobTitle => row['job_title'] as String?;
  String? get notes => row['notes'] as String?;
  bool get active => row['active'] != false;
  DateTime? get hiredOn => DateTime.tryParse(row['hired_on'] as String? ?? '');

  /// Kapti anprent yo (fòma natif Suprema). Plizyè kapti menm dwèt la
  /// bay tèminal W2 a 2 template diferan — pi bon rekonesans.
  List<String> get fingerprintTemplates {
    final list = [
      for (final t in (row['fingerprint_templates'] as List? ?? const []))
        if (t is String && t.isNotEmpty) t,
    ];
    final main = row['fingerprint_template'] as String?;
    if (list.isEmpty && main != null && main.isNotEmpty) list.add(main);
    return list;
  }

  bool get fingerprintRegistered => fingerprintTemplates.isNotEmpty;
}
