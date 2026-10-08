import '../../plans/domain/plan.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import 'member.dart';

class EnrollmentTerms {
  const EnrollmentTerms._(
    this.price,
    this.openingCredit,
    this.paymentAmount,
    this.end,
    this.kind,
  );

  final double price;
  final double openingCredit;
  final double paymentAmount;
  final DateTime end;
  final String kind;
  String get status =>
      openingCredit + paymentAmount >= price - 0.001 ? 'active' : 'pending';

  factory EnrollmentTerms.create({
    required GymPlan plan,
    required bool existing,
    required bool canManage,
    required DateTime start,
    DateTime? end,
    required double paid,
  }) {
    if (existing && !canManage) throw const MemberFailure('access_denied');
    final price = existing ? plan.price : plan.registrationPrice;
    if (!price.isFinite ||
        price < 0 ||
        !paid.isFinite ||
        paid < 0 ||
        paid > price ||
        plan.durationDays < 1) {
      throw const MemberFailure('invalid_record');
    }
    if (existing &&
        (end == null || dateOnly(end).isBefore(dateOnly(start)) || paid != 0)) {
      throw const MemberFailure('invalid_record');
    }
    return EnrollmentTerms._(
      price,
      existing ? price : 0,
      existing ? 0 : paid,
      existing
          ? dateOnly(end!)
          : subscriptionEnd(dateOnly(start), plan.durationDays),
      existing ? 'import' : 'registration',
    );
  }
}
