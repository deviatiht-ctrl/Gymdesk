import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fstw_access_control_service.dart';

/// Koute evenman Supabase Realtime pou senkronize FSTW F30 otomatikman
class FstwRealtimeListener {
  FstwRealtimeListener({
    required this.client,
    required this.fstwService,
  });

  final SupabaseClient client;
  final FstwAccessControlService fstwService;

  RealtimeChannel? _channel;
  String? _gymId;

  void start(String gymId) {
    if (_gymId == gymId && _channel != null) return;
    stop();

    _gymId = gymId;
    _channel = client
        .channel('fstw_door:$gymId')
        // 1. Koute tab members (INSERT / UPDATE)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gym_id',
            value: gymId,
          ),
          callback: (payload) => _handleMemberChange(payload),
        )
        // 2. Koute tab subscriptions (UPDATE)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'subscriptions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gym_id',
            value: gymId,
          ),
          callback: (payload) => _handleSubscriptionChange(payload),
        )
        // 3. Koute fstw_sync_queue pou trete sa k ap tann
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'fstw_sync_queue',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gym_id',
            value: gymId,
          ),
          callback: (_) => fstwService.processPendingQueue(),
        )
        .subscribe();

    debugPrint('[FSTW REALTIME] Abònman aktive sou gym $gymId');
  }

  Future<void> _handleMemberChange(PostgresChangePayload payload) async {
    final record = payload.newRecord;
    if (record.isEmpty) return;

    final memberId = record['id']?.toString();
    final status = record['status']?.toString() ?? 'active';
    final firstName = record['first_name']?.toString() ?? '';
    final lastName = record['last_name']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();
    final hasFingerprint = record['fingerprint_registered'] == true;
    final template = record['fingerprint_template']?.toString();
    final tempPin = record['temporary_pin']?.toString();
    final pinExpires = record['pin_expires_at']?.toString();

    if (memberId == null) return;

    debugPrint('[FSTW REALTIME] Member event: $memberId ($status)');

    if (status == 'active') {
      // Si manb lan gen anprent, voye l sou pòt la
      if (hasFingerprint && template != null && template.isNotEmpty) {
        await fstwService.sendUserFingerprint(memberId, template, fullName);
      }

      // Si manb lan gen PIN tanporè (pass 1 jou)
      if (tempPin != null && tempPin.isNotEmpty && pinExpires != null) {
        final expDate = DateTime.tryParse(pinExpires) ?? DateTime.now().add(const Duration(hours: 24));
        await fstwService.setTemporaryPin(memberId, tempPin, expDate);
      }
    } else if (['expired', 'inactive', 'suspended'].contains(status)) {
      // Efase nan tèminal pòt la
      await fstwService.deleteUser(memberId);
    }
  }

  Future<void> _handleSubscriptionChange(PostgresChangePayload payload) async {
    final record = payload.newRecord;
    if (record.isEmpty) return;

    final memberId = record['member_id']?.toString();
    final subStatus = record['status']?.toString();

    if (memberId == null) return;

    if (subStatus == 'expired' || subStatus == 'cancelled') {
      // Verifye si manb lan pa gen yon lòt abònman aktif anvan efase l
      try {
        final gymId = _gymId;
        if (gymId != null) {
          final activeSubs = await client
              .from('subscriptions')
              .select('id')
              .eq('gym_id', gymId)
              .eq('member_id', memberId)
              .eq('status', 'active')
              .gte('end_date', DateTime.now().toUtc().toIso8601String().substring(0, 10))
              .limit(1);

          if ((activeSubs as List).isEmpty) {
            debugPrint('[FSTW REALTIME] Manb $memberId pa gen okenn abònman aktif ankò -> efase sou pòt');
            await fstwService.deleteUser(memberId);
          }
        }
      } catch (e) {
        debugPrint('[FSTW REALTIME ERROR] $e');
      }
    }
  }

  void stop() {
    final channel = _channel;
    _channel = null;
    _gymId = null;
    if (channel != null) {
      client.removeChannel(channel);
    }
  }
}
