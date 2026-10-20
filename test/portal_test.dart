import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/features/portal/domain/portal_request.dart';

void main() {
  group('PortalRequest Domain & JSON', () {
    test('parses full JSON including joined plan fields', () {
      final json = {
        'id': 'req-123',
        'gym_id': 'gym-456',
        'plan_id': 'plan-789',
        'first_name': 'Jean',
        'last_name': 'Baptiste',
        'phone': '+50931234567',
        'email': 'jean@gmail.com',
        'kind': 'new_membership',
        'status': 'pending',
        'notes': 'Objectif perte de poids',
        'created_at': '2026-10-20T10:00:00Z',
        'updated_at': '2026-10-20T10:00:00Z',
        'plans': {
          'name': 'Mensuel VIP',
          'price': 2500,
          'currency': 'HTG',
        },
      };

      final req = PortalRequest.fromJson(json);

      expect(req.id, 'req-123');
      expect(req.gymId, 'gym-456');
      expect(req.planId, 'plan-789');
      expect(req.firstName, 'Jean');
      expect(req.lastName, 'Baptiste');
      expect(req.fullName, 'Jean Baptiste');
      expect(req.phone, '+50931234567');
      expect(req.email, 'jean@gmail.com');
      expect(req.kind, 'new_membership');
      expect(req.status, 'pending');
      expect(req.notes, 'Objectif perte de poids');
      expect(req.planName, 'Mensuel VIP');
      expect(req.planPrice, 2500.0);
      expect(req.planCurrency, 'HTG');
    });

    test('handles null optional fields gracefully', () {
      final json = {
        'id': 'req-999',
        'gym_id': 'gym-456',
        'first_name': 'Marie',
        'last_name': 'Clair',
        'phone': '38000000',
        'created_at': '2026-10-20T12:00:00Z',
        'updated_at': '2026-10-20T12:00:00Z',
      };

      final req = PortalRequest.fromJson(json);

      expect(req.id, 'req-999');
      expect(req.fullName, 'Marie Clair');
      expect(req.planId, isNull);
      expect(req.planName, isNull);
      expect(req.email, isNull);
      expect(req.notes, isNull);
      expect(req.status, 'pending');
      expect(req.kind, 'new_membership');
    });

    test('parses renewal request correctly', () {
      final json = {
        'id': 'req-renew-1',
        'gym_id': 'gym-456',
        'plan_id': 'plan-789',
        'first_name': 'Carlos',
        'last_name': 'Dupont',
        'phone': '36000000',
        'kind': 'renewal',
        'status': 'pending',
        'created_at': '2026-10-20T12:00:00Z',
        'updated_at': '2026-10-20T12:00:00Z',
      };

      final req = PortalRequest.fromJson(json);

      expect(req.id, 'req-renew-1');
      expect(req.kind, 'renewal');
      expect(req.fullName, 'Carlos Dupont');
    });
  });
}
