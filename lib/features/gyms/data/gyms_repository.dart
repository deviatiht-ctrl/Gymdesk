import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/gym.dart';

class GymsRepository {
  const GymsRepository(this.client);
  final SupabaseClient client;
  static const pageSize = 30;

  Future<T> _request<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 60));
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error'] : null;
      const safe = {
        'access_denied',
        'duplicate_code',
        'owner_exists',
        'duplicate',
        'conflict',
        'invalid_record',
        'weak_password',
        'rate_limited',
        'reset_not_configured',
        'owner_missing',
        'request_mismatch',
        'provision_failed',
        'network',
        'origin_denied',
      };
      throw PlatformFailure(
        code is String && safe.contains(code) ? code : 'provision_failed',
      );
    } on PostgrestException catch (e) {
      throw PlatformFailure(switch (e.code) {
        '42501' => 'access_denied',
        '40001' => 'conflict',
        '23505' => 'duplicate',
        '22023' => 'invalid_record',
        _ => 'server_error',
      });
    } on AuthException {
      throw const PlatformFailure('session_expired');
    } on TimeoutException {
      throw const PlatformFailure('network');
    } on PlatformFailure {
      rethrow;
    } catch (_) {
      throw const PlatformFailure('network');
    }
  }

  Future<GymPage> load({int page = 0, bool archived = false}) =>
      _request(() async {
        if (page < 0) throw const PlatformFailure('invalid_record');
        final query = client.from('gyms').select();
        final filtered = archived
            ? query.not('deleted_at', 'is', null)
            : query.isFilter('deleted_at', null);
        final results = await Future.wait<dynamic>([
          filtered
              .order('created_at', ascending: false)
              .order('id')
              .range(page * pageSize, (page + 1) * pageSize),
          client.rpc('platform_statistics'),
          if (!archived)
            client
                .rpc('platform_gym_overview')
                .then<List>(
                  (value) => value is List ? value : const [],
                  onError: (_) => const [],
                )
          else
            Future.value(const []),
        ]);
        final rows = (results[0] as List)
            .map((e) => Gym.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final overviews = <String, GymOverview>{
          for (final e in results[2] as List)
            (e as Map)['gym_id'] as String: GymOverview.fromJson(
              Map<String, dynamic>.from(e),
            ),
        };
        return GymPage(
          rows.take(pageSize).toList(),
          PlatformStatistics.fromJson(
            Map<String, dynamic>.from(results[1] as Map),
          ),
          rows.length > pageSize,
          overviews: overviews,
        );
      });

  Future<List<PlatformOffer>> loadOffers({bool includeInactive = false}) => _request(() async {
    try {
      var query = client.from('platform_offers').select();
      if (!includeInactive) {
        query = query.eq('active', true);
      }
      final rows = await query.order('price');
      final loaded = [
        for (final e in (rows as List))
          PlatformOffer.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      final officialPlanIds = {'plan_basic', 'plan_medium', 'plan_pro', 'plan_enterprise'};
      final hasOfficial = loaded.any((o) => officialPlanIds.contains(o.id));
      if (!hasOfficial) {
        return PlatformOffer.defaultAnnualPlans;
      }
      return loaded;
    } catch (_) {
      return PlatformOffer.defaultAnnualPlans;
    }
  });

  /// Inisyalize 4 plan ofisyèl yo nan baz Supabase la (Super Admin)
  Future<void> seedDefaultAnnualPlans() => _request(() async {
    for (final plan in PlatformOffer.defaultAnnualPlans) {
      await saveOffer(plan);
    }
    for (final oldId in ['per_member', 'tiered', 'unlimited_annual']) {
      try {
        await deleteOffer(oldId);
      } catch (_) {}
    }
  });

  /// Kreye oswa modifye yon plan nan katalòg la (Super Admin)
  Future<void> saveOffer(PlatformOffer offer) => _request(() async {
    await client.from('platform_offers').upsert({
      'id': offer.id,
      'name': offer.name,
      'description': offer.description,
      'billing_period': offer.billingPeriod,
      'price': offer.price,
      'currency': offer.currency,
      'config': offer.config,
      'active': true,
    });
  });

  /// Dezaktive oswa efase yon plan nan katalòg la
  Future<void> deleteOffer(String offerId) => _request(() async {
    await client.from('platform_offers').update({'active': false}).eq('id', offerId);
  });

  /// Encaissement caisse (super admin) : crée le contrat lié à
  /// l'offre, approuve la déclaration et active la salle quand
  /// [paid] est vrai.
  Future<void> registerPayment({
    required String gymId,
    required String offerId,
    required double amount,
    String currency = 'USD',
    String method = 'cash',
    String? reference,
    String? note,
    bool paid = true,
  }) => _request(() async {
    await client.rpc(
      'platform_register_payment',
      params: {
        'p_gym': gymId,
        'p_offer': offerId,
        'p_amount': amount,
        'p_currency': currency,
        'p_method': method,
        'p_reference': reference,
        'p_note': note,
        'p_paid': paid,
      },
    );
  });

  Future<Gym> create(CreateGymCommand command) => _request(() async {
    final response = await client.functions.invoke(
      'create_gym_owner',
      body: command.toJson(),
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['gym'] is! Map) throw const PlatformFailure('provision_failed');
    return Gym.fromJson(Map<String, dynamic>.from(data['gym'] as Map));
  });

  Future<Gym> changeStatus(Gym gym, String action, {String? confirmation}) =>
      _request(() async {
        final response = await client.rpc(
          'platform_change_gym',
          params: {
            'p_gym': gym.id,
            'p_action': action,
            'p_version': gym.updatedAt,
            'p_confirmation': confirmation,
          },
        );
        return Gym.fromJson(Map<String, dynamic>.from(response as Map));
      });

  Future<void> resetOwnerPassword(Gym gym) => _request(() async {
    await client.functions.invoke(
      'create_gym_owner',
      body: {'action': 'reset_owner', 'gym_id': gym.id},
    );
  });
}
