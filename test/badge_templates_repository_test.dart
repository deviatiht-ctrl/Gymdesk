import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/db/local_database.dart';
import 'package:gym_desk/core/sync/sync_models.dart';
import 'package:gym_desk/features/badges/data/badge_templates_repository.dart';
import 'package:gym_desk/features/badges/domain/badge_template.dart';

void main() {
  const gymId = '10000000-0000-4000-8000-000000000001';
  final now = DateTime.utc(2026, 1, 15, 12);
  StaffSession session(String role) => StaffSession(
    staff: {'id': 'staff-1', 'user_id': 'user-1', 'role': role, 'active': true},
    gym: {
      'id': gymId,
      'code': 'PWR',
      'status': 'active',
      'timezone': 'America/Port-au-Prince',
      'settings': <String, dynamic>{},
    },
    verifiedAt: now,
  );
  late LocalDatabase db;

  setUp(
    () => db = LocalDatabase.testing(NativeDatabase.memory(), gymId: gymId),
  );
  tearDown(() => db.close());

  test('badge template save is tenant-scoped and keeps one default', () async {
    final repository = BadgeTemplatesRepository(db, session('owner'));
    final first = await repository.save(
      const BadgeTemplateDraft(name: 'Standard', isDefault: true),
      changedAt: now,
    );
    final second = await repository.save(
      const BadgeTemplateDraft(
        name: 'Vertical',
        orientation: 'portrait',
        isDefault: true,
      ),
      changedAt: now.add(const Duration(minutes: 1)),
    );
    final rows = await db.watchRecords(SyncEntity.badgeTemplates).first;
    final templates = rows
        .map(
          (row) => BadgeTemplate(
            Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
          ),
        )
        .toList();
    expect(
      templates
          .where((template) => template.isDefault)
          .map((template) => template.id),
      [second.id],
    );
    expect(first.gymId, gymId);
    expect(
      (await db.pending()).map((operation) => operation.entity),
      everyElement('badge_templates'),
    );
  });

  test('reception cannot change badge templates', () async {
    final repository = BadgeTemplatesRepository(db, session('reception'));
    await expectLater(
      repository.save(
        const BadgeTemplateDraft(name: 'Standard'),
        changedAt: now,
      ),
      throwsA(isA<BadgeFailure>()),
    );
  });

  test('owner archives a badge template instead of hard-deleting it', () async {
    final repository = BadgeTemplatesRepository(db, session('owner'));
    final template = await repository.save(
      const BadgeTemplateDraft(name: 'Standard'),
      changedAt: now,
    );
    await repository.remove(
      template,
      changedAt: now.add(const Duration(minutes: 1)),
    );
    final saved =
        jsonDecode(
              (await db.record(
                SyncEntity.badgeTemplates,
                template.id,
              ))!.payload,
            )
            as Json;
    expect(saved['deleted_at'], isNotNull);
    expect((await db.pending()).last.operation, 'delete');
  });
}
