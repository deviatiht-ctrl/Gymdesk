import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../domain/badge_template.dart';

class BadgeTemplatesRepository {
  const BadgeTemplatesRepository(this.db, this.session);
  final LocalDatabase db;
  final StaffSession session;
  static const _uuid = Uuid();

  Future<T> _local<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on BadgeFailure {
      rethrow;
    } on SyncRejected catch (e) {
      throw BadgeFailure(e.code);
    } catch (_) {
      throw const BadgeFailure('local_storage');
    }
  }

  Stream<List<BadgeTemplate>> watch() =>
      db.watchRecords(SyncEntity.badgeTemplates, limit: 500).map((rows) {
        final templates = rows
            .map(
              (row) => BadgeTemplate(
                Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
              ),
            )
            .toList();
        templates.sort(
          (a, b) => a.isDefault != b.isDefault
              ? (a.isDefault ? -1 : 1)
              : a.name.compareTo(b.name),
        );
        return templates;
      });

  BadgeTemplate effective(List<BadgeTemplate> templates) =>
      templates.firstWhere(
        (template) => template.isDefault,
        orElse: () => templates.isEmpty
            ? BadgeTemplate.fallback(session.gymId!)
            : templates.first,
      );

  Future<BadgeTemplate> save(
    BadgeTemplateDraft draft, {
    BadgeTemplate? existing,
    required DateTime changedAt,
  }) => _local(() async {
    if (!{'owner', 'supervisor'}.contains(session.role)) {
      throw const BadgeFailure('access_denied');
    }
    _validate(draft);
    final id = existing?.id ?? _uuid.v4();
    if (draft.isDefault) await _clearDefaults(id, changedAt);
    final row = {
      ...(existing?.row ?? {}),
      'id': id,
      'gym_id': session.gymId,
      'name': draft.name.trim(),
      'layout': draft.layout,
      'is_default': draft.isDefault,
      'created_at':
          existing?.row['created_at'] ?? changedAt.toUtc().toIso8601String(),
      'updated_at': changedAt.toUtc().toIso8601String(),
      'deleted_at': null,
    };
    await db.save(SyncEntity.badgeTemplates, row, changedAt: changedAt);
    return BadgeTemplate(row);
  });

  Future<void> setDefault(
    BadgeTemplate template, {
    required DateTime changedAt,
  }) => _local(() async {
    if (!{'owner', 'supervisor'}.contains(session.role)) {
      throw const BadgeFailure('access_denied');
    }
    await _clearDefaults(template.id, changedAt);
    await db.save(
      SyncEntity.badgeTemplates,
      template.updated(isDefault: true),
      changedAt: changedAt,
    );
  });

  Future<void> remove(BadgeTemplate template, {required DateTime changedAt}) =>
      _local(() async {
        if (session.role != 'owner') throw const BadgeFailure('access_denied');
        await db.save(
          SyncEntity.badgeTemplates,
          template.row,
          changedAt: changedAt,
          deleting: true,
        );
      });

  Future<void> _clearDefaults(String exceptId, DateTime changedAt) async {
    final rows = await db
        .watchRecords(SyncEntity.badgeTemplates, limit: 500)
        .first;
    for (final row in rows) {
      final template = BadgeTemplate(
        Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
      );
      if (template.id != exceptId && template.isDefault) {
        await db.save(
          SyncEntity.badgeTemplates,
          template.updated(isDefault: false),
          changedAt: changedAt,
        );
      }
    }
  }

  void _validate(BadgeTemplateDraft draft) {
    if (draft.name.trim().length < 2 ||
        draft.name.length > 80 ||
        !{'landscape', 'portrait'}.contains(draft.orientation) ||
        (draft.accentColor.isNotEmpty &&
            !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(draft.accentColor))) {
      throw const BadgeFailure('invalid_record');
    }
  }
}
