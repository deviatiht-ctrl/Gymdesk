import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/features/gyms/domain/gym.dart';

void main() {
  group('Platform Offers & 3-Installment Payments', () {
    test('Default annual plans include all 4 updated official tiers', () {
      final plans = PlatformOffer.defaultAnnualPlans;
      expect(plans.length, 4);

      final basic = plans.firstWhere((p) => p.id == 'plan_basic');
      final medium = plans.firstWhere((p) => p.id == 'plan_medium');
      final pro = plans.firstWhere((p) => p.id == 'plan_pro');
      final enterprise = plans.firstWhere((p) => p.id == 'plan_enterprise');

      // 1. Basic Plan
      expect(basic.maxMembers, 150);
      expect(basic.price, 950.0);
      expect(basic.isOneTime, isTrue);
      expect(basic.billingPeriod, 'one_time');
      expect(basic.badgeQuota, 0);
      expect(basic.includesTablet, isFalse);
      expect(basic.installationIncluded, isFalse);
      expect(basic.biometricSupported, isTrue);
      expect(basic.includesDoorAccess, isTrue);
      expect(basic.installmentsAllowed, isTrue);
      expect(basic.installment1, 550.0);
      expect(basic.installment2, 200.0);
      expect(basic.installment3, 200.0);
      expect(basic.installment1 + basic.installment2 + basic.installment3, basic.price);

      // 2. Medium Plan
      expect(medium.maxMembers, 500);
      expect(medium.price, 1450.0);
      expect(medium.isOneTime, isTrue);
      expect(medium.badgeQuota, 0);
      expect(medium.includesTablet, isFalse);
      expect(medium.installationIncluded, isFalse);
      expect(medium.biometricSupported, isTrue);
      expect(medium.includesDoorAccess, isTrue);
      expect(medium.installmentsAllowed, isTrue);
      expect(medium.installment1, 850.0);
      expect(medium.installment2, 300.0);
      expect(medium.installment3, 300.0);
      expect(medium.installment1 + medium.installment2 + medium.installment3, medium.price);

      // 3. Pro Plan
      expect(pro.maxMembers, 1000);
      expect(pro.price, 2200.0);
      expect(pro.isOneTime, isTrue);
      expect(pro.badgeQuota, 0);
      expect(pro.includesTablet, isFalse);
      expect(pro.installationIncluded, isFalse);
      expect(pro.biometricSupported, isTrue);
      expect(pro.installmentsAllowed, isTrue);
      expect(pro.installment1, 1300.0);
      expect(pro.installment2, 450.0);
      expect(pro.installment3, 450.0);
      expect(pro.installment1 + pro.installment2 + pro.installment3, pro.price);

      // 4. Enterprise Plan
      expect(enterprise.maxMembers, 0); // Unlimited
      expect(enterprise.price, 3200.0);
      expect(enterprise.isOneTime, isTrue);
      expect(enterprise.badgeQuota, 0);
      expect(enterprise.includesTablet, isFalse);
      expect(enterprise.installationIncluded, isFalse);
      expect(enterprise.biometricSupported, isTrue);
      expect(enterprise.installmentsAllowed, isTrue);
      expect(enterprise.installment1, 1800.0);
      expect(enterprise.installment2, 700.0);
      expect(enterprise.installment3, 700.0);
      expect(enterprise.installment1 + enterprise.installment2 + enterprise.installment3, enterprise.price);
    });

    test('All plans are one-time purchase with no badges and paid hardware/installation', () {
      for (final plan in PlatformOffer.defaultAnnualPlans) {
        expect(plan.isOneTime, isTrue);
        expect(plan.badgeQuota, 0);
        expect(plan.includesTablet, isFalse);
        expect(plan.installationIncluded, isFalse);
        expect(plan.installment1, greaterThan(plan.price * 0.50));
        expect(plan.doorHardwareKit, contains('FSTW F30'));
      }
    });
  });
}
