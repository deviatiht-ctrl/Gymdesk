import 'package:timezone/timezone.dart' as tz;

import '../../../core/sync/sync_models.dart';
import '../../members/domain/member.dart';
import 'gym_subscription.dart';

DateTime dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

DateTime gymDate(DateTime instant, String timezone) {
  final location = tz.getLocation(timezone);
  final local = tz.TZDateTime.from(instant.toUtc(), location);
  return DateTime.utc(local.year, local.month, local.day);
}

String ymd(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime subscriptionEnd(DateTime start, int durationDays) =>
    dateOnly(start).add(Duration(days: durationDays - 1));

class MemberValidity {
  const MemberValidity({
    required this.valid,
    required this.reason,
    this.subscriptionId,
    this.endDate,
    this.daysLeft,
  });
  final bool valid;
  final String reason;
  final String? subscriptionId;
  final DateTime? endDate;
  final int? daysLeft;
}

MemberValidity memberValidity(
  Member member,
  List<GymSubscription> subscriptions,
  Json settings,
  DateTime at,
  String timezone,
) {
  if (member.status != 'active') {
    return MemberValidity(valid: false, reason: member.status);
  }
  final date = gymDate(at, timezone);
  final grace = ((settings['grace_days'] as num?)?.toInt() ?? 0)
      .clamp(0, 365)
      .toInt();
  final allowPending = settings['allow_access_pending'] == true;
  final usable =
      subscriptions
          .where((s) => s.deletedAt == null && s.status != 'cancelled')
          .toList()
        ..sort(
          (a, b) => a.endDate != b.endDate
              ? b.endDate.compareTo(a.endDate)
              : b.id.compareTo(a.id),
        );
  final pending = usable.where((s) => s.status == 'pending').toList();
  for (final subscription in usable.where(
    (s) => s.status != 'pending' || allowPending,
  )) {
    if (!subscription.startDate.isAfter(date) &&
        !subscription.endDate.add(Duration(days: grace)).isBefore(date)) {
      return MemberValidity(
        valid: true,
        reason: 'ok',
        subscriptionId: subscription.id,
        endDate: subscription.endDate,
        daysLeft: subscription.endDate
            .difference(date)
            .inDays
            .clamp(0, 36500)
            .toInt(),
      );
    }
  }
  for (final subscription in pending) {
    if (!subscription.startDate.isAfter(date) &&
        !subscription.endDate.add(Duration(days: grace)).isBefore(date)) {
      return MemberValidity(
        valid: false,
        reason: 'pending_payment',
        subscriptionId: subscription.id,
        endDate: subscription.endDate,
        daysLeft: subscription.endDate
            .difference(date)
            .inDays
            .clamp(0, 36500)
            .toInt(),
      );
    }
  }
  for (final subscription in usable) {
    if (subscription.endDate.isBefore(date)) {
      return MemberValidity(
        valid: false,
        reason: 'expired',
        subscriptionId: subscription.id,
        endDate: subscription.endDate,
        daysLeft: 0,
      );
    }
  }
  return const MemberValidity(valid: false, reason: 'no_subscription');
}
