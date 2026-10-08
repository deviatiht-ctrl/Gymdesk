import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/features/gyms/domain/gym.dart';

void main() {
  final row = <String, dynamic>{
    'id': 'gym',
    'name': 'Test',
    'code': 'TST',
    'status': 'active',
    'updated_at': '2026-10-05T12:00:00Z',
    'timezone': 'America/Port-au-Prince',
    'currency': 'HTG',
    'accent_color': '#1F6F4A',
  };

  test('gym keeps exact server version for optimistic concurrency', () {
    final gym = Gym.fromJson(row);
    expect(gym.updatedAt, row['updated_at']);
    expect(gym.archived, isFalse);
  });

  test('archived status is derived from tombstone, not only suspension', () {
    expect(Gym.fromJson({...row, 'status': 'suspended'}).archived, isFalse);
    expect(
      Gym.fromJson({...row, 'deleted_at': '2026-10-05T13:00:00Z'}).archived,
      isTrue,
    );
  });

  test('platform statistics expose only aggregate counts', () {
    final stats = PlatformStatistics.fromJson({
      'gyms': 2,
      'active_gyms': 1,
      'members': 450,
      'entries_today': 32,
    });
    expect(stats.gyms, 2);
    expect(stats.activeGyms, 1);
    expect(stats.members, 450);
    expect(stats.entriesToday, 32);
  });

  test('create command retains client ids across retries', () {
    final command = CreateGymCommand(
      requestId: 'request',
      gymId: 'gym',
      staffId: 'staff',
      gym: row,
      ownerEmail: 'owner@example.invalid',
      ownerName: 'Test Owner',
      ownerPassword: 'Test-only-password-42',
    );
    expect(command.toJson(), command.toJson());
    expect(command.toJson()['request_id'], 'request');
    expect(command.toJson()['action'], 'create');
  });
}
