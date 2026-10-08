import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/sync/clock_guard.dart';
import 'package:gym_desk/core/sync/sync_models.dart';

void main() {
  test('server offset uses request midpoint', () {
    final wall = DateTime.utc(2026, 10, 5, 12);
    final clock = ClockGuard(now: () => wall);
    clock.calibrate(
      wall.add(const Duration(seconds: 7)),
      wall,
      wall.add(const Duration(seconds: 4)),
    );
    expect(clock.offset, const Duration(seconds: 5));
    expect(clock.correctedNow, wall.add(const Duration(seconds: 5)));
  });

  test('clock moving backward is flagged', () {
    var wall = DateTime.utc(2026, 10, 5, 12);
    final clock = ClockGuard(now: () => wall);
    clock.calibrate(wall, wall, wall);
    wall = wall.subtract(const Duration(minutes: 11));
    clock.correctedNow;
    expect(clock.suspect, isTrue);
  });

  test('more than ten minutes forward drift is flagged', () {
    var wall = DateTime.utc(2026, 10, 5, 12);
    final clock = ClockGuard(now: () => wall);
    clock.calibrate(wall, wall, wall);
    wall = wall.add(const Duration(minutes: 11));
    clock.correctedNow;
    expect(clock.suspect, isTrue);
  });

  test('exponential backoff is bounded', () {
    expect(retryDelay(1), const Duration(seconds: 2));
    expect(retryDelay(4), const Duration(seconds: 16));
    expect(retryDelay(100), const Duration(seconds: 512));
  });

  test('cached authorization expires and never opens suspended gyms', () {
    final at = DateTime.utc(2026, 10, 5);
    final session = StaffSession(
      staff: {'active': true, 'role': 'owner'},
      gym: {'status': 'active'},
      verifiedAt: at,
    );
    expect(session.offlineAllowed(at.add(const Duration(hours: 23))), isTrue);
    expect(session.offlineAllowed(at.add(const Duration(hours: 24))), isFalse);
    expect(
      session.offlineAllowed(at.subtract(const Duration(hours: 1))),
      isFalse,
    );
    final suspended = StaffSession(
      staff: session.staff,
      gym: {'status': 'suspended'},
      verifiedAt: at,
    );
    expect(suspended.offlineAllowed(at), isFalse);
  });
}
