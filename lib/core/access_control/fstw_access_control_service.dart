import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Import kondisyonèl pou dart:io (pou sipòte Windows, Android, macOS, Linux san kras sou Web)
import 'fstw_socket_adapter.dart';

/// Eta koneksyon tèminal FSTW F30
enum FstwDeviceState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Modèl travay nan file d'attente rezilyans
class FstwSyncJob {
  const FstwSyncJob({
    required this.id,
    required this.gymId,
    required this.memberId,
    required this.action,
    required this.payload,
    this.status = 'pending',
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final String gymId;
  final String memberId;
  final String action; // 'sync_user', 'delete_user', 'set_pin'
  final Map<String, dynamic> payload;
  final String status;
  final int attempts;
  final String? lastError;

  factory FstwSyncJob.fromMap(Map<String, dynamic> map) {
    return FstwSyncJob(
      id: map['id']?.toString() ?? '',
      gymId: map['gym_id']?.toString() ?? '',
      memberId: map['member_id']?.toString() ?? '',
      action: map['action']?.toString() ?? 'sync_user',
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
      status: map['status']?.toString() ?? 'pending',
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      lastError: map['last_error']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'gym_id': gymId,
    'member_id': memberId,
    'action': action,
    'payload': payload,
    'status': status,
    'attempts': attempts,
    'last_error': lastError,
  };
}

/// Sèvis Kominikasyon TCP/IP FSTW F30 avèk jesyon rezilyans & retry
class FstwAccessControlService {
  FstwAccessControlService({
    SupabaseClient? client,
    FstwSocketAdapter? socketAdapter,
  })  : _client = client,
        _socketAdapter = socketAdapter ?? createFstwSocketAdapter() {
    _startRetryLoop();
  }

  final SupabaseClient? _client;
  final FstwSocketAdapter _socketAdapter;

  String? _currentIp;
  int _currentPort = 5005;
  String? _currentGymId;

  final ValueNotifier<FstwDeviceState> state =
      ValueNotifier<FstwDeviceState>(FstwDeviceState.disconnected);

  Timer? _retryTimer;
  bool _isProcessingQueue = false;

  bool get isConnected => state.value == FstwDeviceState.connected;
  String? get currentIp => _currentIp;
  int get currentPort => _currentPort;

  void configure({
    required String gymId,
    required String ip,
    int port = 5005,
  }) {
    _currentGymId = gymId;
    _currentIp = ip.trim();
    _currentPort = port > 0 ? port : 5005;
  }

  /// 1. connectDevice(ip, port) : Etabli koneksyon socket ak FSTW F30
  Future<bool> connectDevice(String ip, int port) async {
    _currentIp = ip.trim();
    _currentPort = port;
    state.value = FstwDeviceState.connecting;

    try {
      final success = await _socketAdapter.connect(
        ip: _currentIp!,
        port: _currentPort,
        timeout: const Duration(seconds: 4),
      );

      if (success) {
        state.value = FstwDeviceState.connected;
        debugPrint('[FSTW] Konekte avèk siksè sou tèminal F30 ($_currentIp:$_currentPort)');
        // Vide file d'attente la le pli vit ke aparèy la konekte
        unawaited(processPendingQueue());
        return true;
      } else {
        state.value = FstwDeviceState.disconnected;
        debugPrint('[SYNC FAILED] Retrying... (Pa ka konekte sou $ip:$port)');
        return false;
      }
    } catch (e) {
      state.value = FstwDeviceState.error;
      debugPrint('[SYNC FAILED] Retrying... (Erè socket: $e)');
      return false;
    }
  }

  /// 2. sendUserFingerprint(userId, template, name) : Enskri oswa mete ajou anprent
  Future<bool> sendUserFingerprint(
    String userId,
    String template,
    String name,
  ) async {
    final payload = {
      'cmd': 'set_user',
      'user_id': userId,
      'name': name,
      'template': template,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      final connected = await _ensureConnected();
      if (!connected) {
        throw Exception('Aparèy FSTW F30 pa disponib');
      }

      final frame = _buildFrame('SET_USER', payload);
      final response = await _socketAdapter.sendAndReceive(
        frame,
        timeout: const Duration(seconds: 5),
      );

      if (_isSuccessResponse(response)) {
        debugPrint('[SYNC SUCCESS] User ID synced to door ($userId - $name)');
        return true;
      } else {
        throw Exception('Repons tèminal pa valide: $response');
      }
    } catch (e) {
      debugPrint('[SYNC FAILED] Retrying... (Erè sendUserFingerprint pou $userId: $e)');
      await _enqueueSyncJob(
        memberId: userId,
        action: 'sync_user',
        payload: payload,
        error: e.toString(),
      );
      return false;
    }
  }

  /// 3. deleteUser(userId) : Retire itilizatè nan memwa FSTW F30
  Future<bool> deleteUser(String userId) async {
    final payload = {
      'cmd': 'delete_user',
      'user_id': userId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      final connected = await _ensureConnected();
      if (!connected) {
        throw Exception('Aparèy FSTW F30 pa disponib');
      }

      final frame = _buildFrame('DELETE_USER', payload);
      final response = await _socketAdapter.sendAndReceive(
        frame,
        timeout: const Duration(seconds: 5),
      );

      if (_isSuccessResponse(response)) {
        debugPrint('[SYNC SUCCESS] User ID synced to door (deleteUser $userId)');
        return true;
      } else {
        throw Exception('Repons efasman pa valide: $response');
      }
    } catch (e) {
      debugPrint('[SYNC FAILED] Retrying... (Erè deleteUser pou $userId: $e)');
      await _enqueueSyncJob(
        memberId: userId,
        action: 'delete_user',
        payload: payload,
        error: e.toString(),
      );
      return false;
    }
  }

  /// 4. setTemporaryPin(userId, pinCode, expirationDateTime) : Kòd PIN tanporè (pass 1 jou)
  Future<bool> setTemporaryPin(
    String userId,
    String pinCode,
    DateTime expirationDateTime,
  ) async {
    final payload = {
      'cmd': 'set_temporary_pin',
      'user_id': userId,
      'pin': pinCode,
      'expires_at': expirationDateTime.toUtc().toIso8601String(),
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      final connected = await _ensureConnected();
      if (!connected) {
        throw Exception('Aparèy FSTW F30 pa disponib');
      }

      final frame = _buildFrame('SET_PIN', payload);
      final response = await _socketAdapter.sendAndReceive(
        frame,
        timeout: const Duration(seconds: 5),
      );

      if (_isSuccessResponse(response)) {
        debugPrint('[SYNC SUCCESS] User ID synced to door (Temporary PIN pou $userId)');
        return true;
      } else {
        throw Exception('Repons PIN tanporè pa valide: $response');
      }
    } catch (e) {
      debugPrint('[SYNC FAILED] Retrying... (Erè setTemporaryPin pou $userId: $e)');
      await _enqueueSyncJob(
        memberId: userId,
        action: 'set_pin',
        payload: payload,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Asire koneksyon socket la louvri anvan voye kòmand
  Future<bool> _ensureConnected() async {
    if (_socketAdapter.isConnected) return true;
    final ip = _currentIp;
    if (ip == null || ip.isEmpty) return false;
    return connectDevice(ip, _currentPort);
  }

  /// Bati trame done JSON oswa ASCII delimite pou FSTW F30
  Uint8List _buildFrame(String action, Map<String, dynamic> payload) {
    final jsonStr = jsonEncode(payload);
    // Framing estanda: STX (0x02) + JSON Payload + ETX (0x03) + Newline (\n)
    final bodyBytes = utf8.encode(jsonStr);
    final packet = BytesBuilder();
    packet.addByte(0x02); // STX
    packet.add(bodyBytes);
    packet.addByte(0x03); // ETX
    packet.addByte(0x0A); // \n
    return packet.toBytes();
  }

  /// Analize si repons tèminal la pozitif (ACK oswa result = true / ok)
  bool _isSuccessResponse(String? response) {
    if (response == null || response.isEmpty) return false;
    final clean = response.trim().toLowerCase();
    if (clean.contains('ack') || clean.contains('success') || clean.contains('ok') || clean.contains('"result":true') || clean.contains('"status":"ok"')) {
      return true;
    }
    // Si se repons jenerik FSTW
    return clean.contains('true') || clean.contains('200');
  }

  /// Anrejistre yon travay ki echwe nan tab fstw_sync_queue nan Supabase
  Future<void> _enqueueSyncJob({
    required String memberId,
    required String action,
    required Map<String, dynamic> payload,
    String? error,
  }) async {
    final client = _client;
    final gymId = _currentGymId;
    if (client == null || gymId == null) return;

    try {
      await client.from('fstw_sync_queue').insert({
        'gym_id': gymId,
        'member_id': memberId,
        'action': action,
        'payload': payload,
        'status': 'pending',
        'attempts': 1,
        'last_error': error,
      });
      debugPrint('[FSTW QUEUE] Kòmand $action anrejistre nan file d\'attente pou $memberId');
    } catch (err) {
      debugPrint('[FSTW QUEUE ERROR] Pa ka anrejistre nan fstw_sync_queue: $err');
    }
  }

  /// Vide file d'attente rezilyans la (egzekite kòmand an atant yo)
  Future<void> processPendingQueue() async {
    if (_isProcessingQueue) return;
    final client = _client;
    final gymId = _currentGymId;
    if (client == null || gymId == null) return;

    _isProcessingQueue = true;
    try {
      final rows = await client
          .from('fstw_sync_queue')
          .select()
          .eq('gym_id', gymId)
          .eq('status', 'pending')
          .order('created_at', ascending: true)
          .limit(50);

      final jobs = (rows as List)
          .map((r) => FstwSyncJob.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();

      if (jobs.isEmpty) {
        _isProcessingQueue = false;
        return;
      }

      debugPrint('[FSTW QUEUE] ${jobs.length} kòmand ap retantte...');

      for (final job in jobs) {
        bool ok = false;
        switch (job.action) {
          case 'sync_user':
            final t = job.payload['template']?.toString() ?? '';
            final n = job.payload['name']?.toString() ?? 'Member';
            ok = await _directExecute('SET_USER', job.payload);
            break;
          case 'delete_user':
            ok = await _directExecute('DELETE_USER', job.payload);
            break;
          case 'set_pin':
            ok = await _directExecute('SET_PIN', job.payload);
            break;
        }

        if (ok) {
          debugPrint('[SYNC SUCCESS] User ID synced to door (${job.memberId} soti nan queue)');
          await client.from('fstw_sync_queue').update({
            'status': 'completed',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', job.id);
        } else {
          debugPrint('[SYNC FAILED] Retrying... (${job.memberId} toujou echwe)');
          await client.from('fstw_sync_queue').update({
            'attempts': job.attempts + 1,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', job.id);
          // Si aparèy la pa reponn, kanpe boucle la pou kounye a
          break;
        }
      }
    } catch (e) {
      debugPrint('[FSTW QUEUE ERROR] Erè pandan processPendingQueue: $e');
    } finally {
      _isProcessingQueue = false;
    }
  }

  /// Egzekisyon dirèk sou socket la san re-enqueue si echèk
  Future<bool> _directExecute(String cmd, Map<String, dynamic> payload) async {
    try {
      final connected = await _ensureConnected();
      if (!connected) return false;

      final frame = _buildFrame(cmd, payload);
      final response = await _socketAdapter.sendAndReceive(
        frame,
        timeout: const Duration(seconds: 4),
      );
      return _isSuccessResponse(response);
    } catch (_) {
      return false;
    }
  }

  /// Kòmanse boucle retry background (egzekite chak 20 segonn)
  void _startRetryLoop() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      final ip = _currentIp;
      if (ip == null || ip.isEmpty) return;

      // Si aparèy la te dekonekte, verifye si li retounen an liy
      if (!_socketAdapter.isConnected) {
        final reconnected = await connectDevice(ip, _currentPort);
        if (reconnected) {
          debugPrint('[FSTW] Tèminal F30 retounen an liy! Ap vide kòmand an atant yo...');
          await processPendingQueue();
        }
      } else {
        await processPendingQueue();
      }
    });
  }

  void dispose() {
    _retryTimer?.cancel();
    _socketAdapter.disconnect();
    state.dispose();
  }
}
