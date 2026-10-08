import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../domain/gym_settings.dart';

class GymSettingsRepository {
  const GymSettingsRepository(this.client, this.db, this.session);
  final SupabaseClient client;
  final LocalDatabase db;
  final StaffSession session;
  static const _uuid = Uuid();

  Future<T> _request<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 60));
    } on StorageException catch (e) {
      throw SettingsFailure(
        e.statusCode.toString() == '403' ? 'access_denied' : 'network',
      );
    } on PostgrestException catch (e) {
      throw SettingsFailure(switch (e.code) {
        '42501' => 'access_denied',
        '40001' => 'conflict',
        '23505' => 'duplicate',
        '22023' || '22P02' =>
          e.message == 'invalid_logo' ? 'invalid_logo' : 'invalid_record',
        'PGRST301' || 'PGRST302' || 'PGRST303' => 'session_expired',
        _ => 'server_error',
      });
    } on AuthException {
      throw const SettingsFailure('session_expired');
    } on TimeoutException {
      throw const SettingsFailure('network');
    } on SettingsFailure {
      rethrow;
    } on SyncRejected catch (e) {
      throw SettingsFailure(e.code);
    } catch (_) {
      throw const SettingsFailure('network');
    }
  }

  Future<GymSettings> current() async {
    try {
      final local = await db.record(SyncEntity.gyms, session.gymId!);
      if (local != null) {
        return GymSettings(
          Map<String, dynamic>.from(jsonDecode(local.payload) as Map),
        );
      }
      if (session.gym != null) {
        return GymSettings(Map<String, dynamic>.from(session.gym!));
      }
      throw const SettingsFailure('missing_dependency');
    } on SettingsFailure {
      rethrow;
    } catch (_) {
      throw const SettingsFailure('local_storage');
    }
  }

  Future<void> save(GymSettings value, {required DateTime changedAt}) async {
    try {
      if (!{'owner', 'supervisor'}.contains(session.role) || value.id != session.gymId) {
        throw const SettingsFailure('access_denied');
      }
      _validate(value);
      await db.saveGym(
        value.row,
        changedAt: changedAt,
        baseVersion: value.updatedAt,
      );
    } on SettingsFailure {
      rethrow;
    } on SyncRejected catch (e) {
      throw SettingsFailure(e.code);
    } catch (_) {
      throw const SettingsFailure('local_storage');
    }
  }

  Future<String> uploadLogo(String fileName, Uint8List bytes) =>
      _request(() async {
        if (session.role != 'owner' || session.gymId == null) {
          throw const SettingsFailure('access_denied');
        }
        final extension = fileName.toLowerCase().split('.').last;
        final type = switch (extension) {
          'jpg' || 'jpeg' => 'image/jpeg',
          'png' => 'image/png',
          'webp' => 'image/webp',
          _ => null,
        };
        if (type == null || bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
          throw const SettingsFailure('invalid_logo');
        }
        final path = '${session.gymId}/logos/${_uuid.v4()}.$extension';
        await client.storage
            .from('gym-assets')
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: type, upsert: false),
            );
        return path;
      });

  Future<String?> signedLogoUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await client.storage
          .from('gym-assets')
          .createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> logoBytes(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await client.storage.from('gym-assets').download(path);
    } catch (_) {
      return null;
    }
  }

  void _validate(GymSettings gym) {
    final email = gym.email;
    if (gym.name.trim().length < 2 ||
        gym.name.trim().length > 120 ||
        !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(gym.accentColor) ||
        !{'HTG', 'USD'}.contains(gym.currency) ||
        gym.address.length > 500 ||
        gym.phone.length > 32 ||
        email.length > 254 ||
        (email.isNotEmpty &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))) {
      throw const SettingsFailure('invalid_record');
    }
    for (final entry in gym.settings.entries) {
      const numeric = {
        'offline_lease_hours',
        'auto_logout_minutes',
        'pin_lock_minutes',
        'grace_days',
        'entry_duplicate_seconds',
      };
      const boolean = {
        'allow_access_pending',
        'reception_see_all_payments',
        'scan_sound',
        'scan_vibrate',
      };
      const strings = {
        'doc_footer',
        'badge_theme',
        'badge_qr_style',
      };
      if (strings.contains(entry.key)) {
        if (entry.value is! String || (entry.value as String).length > 500) {
          throw const SettingsFailure('invalid_record');
        }
      } else if (entry.key == 'badge_positions' || entry.key == 'qr_defaults') {
        if (entry.value is! Map || jsonEncode(entry.value).length > 16384) {
          throw const SettingsFailure('invalid_record');
        }
      } else if (numeric.contains(entry.key)) {
        final value = entry.value;
        final limit = switch (entry.key) {
          'offline_lease_hours' => (1, 72),
          'auto_logout_minutes' => (0, 1440),
          'pin_lock_minutes' => (1, 60),
          'grace_days' => (0, 30),
          _ => (1, 10),
        };
        if (value is! int || value < limit.$1 || value > limit.$2) {
          throw const SettingsFailure('invalid_record');
        }
      } else if (boolean.contains(entry.key)) {
        if (entry.value is! bool) throw const SettingsFailure('invalid_record');
      } else {
        if (entry.value is String && (entry.value as String).length > 2000) {
          throw const SettingsFailure('invalid_record');
        }
      }
    }
  }
}
