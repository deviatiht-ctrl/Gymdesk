import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../domain/badge.dart';

class BadgesRepository {
  const BadgesRepository(this.client, this.db, this.session);

  final SupabaseClient client;
  final LocalDatabase db;
  final StaffSession session;

  Stream<List<BadgeItem>> watchBadges({String filter = 'all', String query = ''}) {
    return db.watchRecords(SyncEntity.badges, limit: 10000).map((rows) {
      final badges = rows
          .map((r) => BadgeItem(Map<String, dynamic>.from(jsonDecode(r.payload) as Map)))
          .where((b) {
            if (filter != 'all' && b.status != filter) return false;
            if (query.trim().isNotEmpty) {
              final q = query.trim().toLowerCase();
              final matchesNumber = b.badgeNumber.toString().contains(q) ||
                  b.formattedNumber.toLowerCase().contains(q);
              return matchesNumber;
            }
            return true;
          })
          .toList();

      badges.sort((a, b) => a.badgeNumber.compareTo(b.badgeNumber));
      return badges;
    });
  }

  Stream<List<BadgeBatch>> watchBatches() {
    return db.watchRecords(SyncEntity.badgeBatches, limit: 1000).map((rows) {
      final batches = rows
          .map((r) => BadgeBatch(Map<String, dynamic>.from(jsonDecode(r.payload) as Map)))
          .toList();
      batches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return batches;
    });
  }

  /// Quota de badges : toujours lu depuis le contrat/offre synchronisé
  /// (price_snapshot.config.badge_quota). En essai : 10. Aucune valeur
  /// commerciale n'est codée en dur ici.
  Stream<BadgeQuotaInfo> watchQuota() {
    return db.watchRecords(SyncEntity.badges, limit: 10000).asyncMap((rows) async {
      final badges = rows
          .map((r) => BadgeItem(Map<String, dynamic>.from(jsonDecode(r.payload) as Map)))
          .toList();

      final totalGenerated = badges.length;
      final totalBound = badges.where((b) => b.status == 'bound').length;
      final totalAvailable = badges.where((b) => b.status == 'unassigned').length;
      final totalBlocked = badges.where((b) => b.status == 'blocked').length;

      int quotaLimit = 100;
      final contracts = await db
          .watchRecords(SyncEntity.gymContracts, limit: 50)
          .first;
      Map<String, dynamic>? active;
      for (final row in contracts) {
        final data = jsonDecode(row.payload) as Map<String, dynamic>;
        if ({'trial', 'active', 'grace'}.contains(data['status'])) {
          active = data;
          break;
        }
      }
      if (active != null) {
        final snapshot = active['price_snapshot'];
        final config = snapshot is Map ? snapshot['config'] : null;
        final configuredQuota =
            config is Map ? (config['badge_quota'] as num?)?.toInt() : null;
        if (active['status'] == 'trial') {
          quotaLimit = configuredQuota ?? 10;
        } else {
          quotaLimit = configuredQuota ?? 100;
        }
      } else {
        quotaLimit = totalGenerated >= 10 ? (totalGenerated > 100 ? totalGenerated : 100) : 100;
      }

      return BadgeQuotaInfo(
        totalGenerated: totalGenerated,
        totalBound: totalBound,
        totalAvailable: totalAvailable,
        totalBlocked: totalBlocked,
        quotaLimit: quotaLimit,
      );
    });
  }

  Future<void> generateBatch(int quantity) async {
    if (!session.canManageGym && !session.isPlatformAdmin) {
      throw const SyncRejected('access_denied');
    }
    // Appel RPC serveur (qui applique la règle de quota stricte)
    await client.rpc('generate_badge_batch', params: {
      'p_gym': session.gymId,
      'p_quantity': quantity,
      'p_source': 'plan_allotment',
    });
  }

  Future<void> blockBadge(BadgeItem badge, {required String reason}) async {
    if (!session.canManageGym && !session.isPlatformAdmin) {
      throw const SyncRejected('access_denied');
    }
    final now = DateTime.now().toUtc();
    final updated = {
      ...badge.row,
      'status': 'blocked',
      'updated_at': now.toIso8601String(),
    };
    await db.save(SyncEntity.badges, updated, changedAt: now);
  }

  Future<void> releaseBadge(BadgeItem badge, {required String reason}) async {
    if (!session.isOwner && !session.isPlatformAdmin) {
      throw const SyncRejected('access_denied');
    }
    try {
      await client.rpc('release_badge', params: {
        'p_badge': badge.id,
        'p_reason': reason,
      });
    } catch (_) {
      // Offline fallback si non connecté
      final now = DateTime.now().toUtc();
      final updated = {
        ...badge.row,
        'status': 'unassigned',
        'member_id': null,
        'bound_at': null,
        'bound_by': null,
        'updated_at': now.toIso8601String(),
      };
      await db.save(SyncEntity.badges, updated, changedAt: now);
    }
  }

  Future<void> replaceBadge({
    required BadgeItem oldBadge,
    required BadgeItem newBadge,
    required String reason,
  }) async {
    if (!session.canManageGym && !session.isPlatformAdmin) {
      throw const SyncRejected('access_denied');
    }
    try {
      await client.rpc('replace_badge', params: {
        'p_old_badge': oldBadge.id,
        'p_new_badge': newBadge.id,
        'p_reason': reason,
      });
    } catch (_) {
      final now = DateTime.now().toUtc();
      // Bloquer l'ancien
      await db.save(SyncEntity.badges, {
        ...oldBadge.row,
        'status': 'blocked',
        'updated_at': now.toIso8601String(),
      }, changedAt: now);
      // Lier le nouveau
      await db.save(SyncEntity.badges, {
        ...newBadge.row,
        'status': 'bound',
        'member_id': oldBadge.memberId,
        'bound_at': now.toIso8601String(),
        'bound_by': session.staffId,
        'updated_at': now.toIso8601String(),
      }, changedAt: now);
    }
  }

  Future<List<BadgeItem>> getAvailableBadges() async {
    final rows = await db.watchRecords(SyncEntity.badges, limit: 10000).first;
    return rows
        .map((r) => BadgeItem(Map<String, dynamic>.from(jsonDecode(r.payload) as Map)))
        .where((b) => b.isAvailable)
        .toList()
      ..sort((a, b) => a.badgeNumber.compareTo(b.badgeNumber));
  }

  /// Badge actuellement lié au membre (via members.badge_id ou
  /// badges.member_id selon la fraîcheur des données synchronisées).
  Future<BadgeItem?> badgeForMember(String memberId, {String? badgeId}) async {
    if (badgeId != null) {
      final record = await db.record(SyncEntity.badges, badgeId);
      if (record != null) {
        return BadgeItem(
          Map<String, dynamic>.from(jsonDecode(record.payload) as Map),
        );
      }
    }
    final rows = await db.watchRecords(SyncEntity.badges, limit: 10000).first;
    for (final row in rows) {
      final badge = BadgeItem(
        Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
      );
      if (badge.memberId == memberId) return badge;
    }
    return null;
  }

  /// Réinitialisation du PIN membre (owner/supervisor, en ligne).
  /// Hors ligne : bascule locale en reset_required via MemberPinService.
  Future<void> resetMemberPin(String memberId) async {
    if (!session.canManageGym && !session.isPlatformAdmin) {
      throw const SyncRejected('access_denied');
    }
    await client.rpc('reset_member_pin', params: {'p_member': memberId});
  }
}
