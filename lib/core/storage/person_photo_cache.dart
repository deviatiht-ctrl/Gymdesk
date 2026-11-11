import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/local_database.dart';
import '../sync/sync_models.dart';

/// Cache mémoire partagé (LRU) pour les photos de membres et d'employés.
/// Résout dans l'ordre :
/// 1) photo locale en file d'upload (`db.photoForMember(personId)`)
/// 2) bytes déjà en cache mémoire pour `photoUrl` ou `personId`
/// 3) chemin Storage Supabase privé `member-photos` (ou URL http(s))
class PersonPhotoCache {
  PersonPhotoCache._();

  static const int _maxEntries = 180;
  static final LinkedHashMap<String, Uint8List> _bytes = LinkedHashMap();
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  static void invalidate(String? personId, {String? photoUrl}) {
    if (personId != null && personId.isNotEmpty) {
      _bytes.remove('id:$personId');
    }
    if (photoUrl != null && photoUrl.isNotEmpty) {
      _bytes.remove('url:$photoUrl');
    }
  }

  static void put(String? personId, String? photoUrl, Uint8List bytes) {
    if (bytes.isEmpty) return;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      _insert('url:$photoUrl', bytes);
    }
    if (personId != null && personId.isNotEmpty) {
      _insert('id:$personId', bytes);
    }
  }

  static void _insert(String key, Uint8List value) {
    _bytes.remove(key);
    _bytes[key] = value;
    while (_bytes.length > _maxEntries) {
      _bytes.remove(_bytes.keys.first);
    }
  }

  static Uint8List? peek({String? personId, String? photoUrl}) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      final hit = _bytes['url:$photoUrl'];
      if (hit != null) {
        _insert('url:$photoUrl', hit);
        return hit;
      }
    }
    if (personId != null && personId.isNotEmpty) {
      final hit = _bytes['id:$personId'];
      if (hit != null) {
        _insert('id:$personId', hit);
        return hit;
      }
    }
    return null;
  }

  static Future<Uint8List?> resolve({
    String? personId,
    String? photoUrl,
    LocalDatabase? db,
    SupabaseClient? client,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    // 1. Toujours vérifier d'abord la photo locale non encore synchronisée.
    if (personId != null && personId.isNotEmpty && db != null) {
      try {
        final pending = await db.photoForMember(personId);
        if (pending != null && pending.bytes.isNotEmpty) {
          put(personId, photoUrl, pending.bytes);
          return pending.bytes;
        }
      } catch (_) {}
    }

    // 2. Hit cache mémoire rapide.
    final cached = peek(personId: personId, photoUrl: photoUrl);
    if (cached != null && cached.isNotEmpty) return cached;

    // 3. Compléter `photoUrl` depuis Drift si manquant dans l'événement temps réel.
    var resolvedUrl = photoUrl?.trim();
    if ((resolvedUrl == null || resolvedUrl.isEmpty) &&
        personId != null &&
        personId.isNotEmpty &&
        db != null) {
      try {
        final memberRec = await db.record(SyncEntity.members, personId);
        if (memberRec != null) {
          resolvedUrl = (jsonDecode(memberRec.payload) as Map)['photo_url']?.toString();
        }
        if (resolvedUrl == null || resolvedUrl.isEmpty) {
          final empRec = await db.record(SyncEntity.employees, personId);
          if (empRec != null) {
            resolvedUrl = (jsonDecode(empRec.payload) as Map)['photo_url']?.toString();
          }
        }
      } catch (_) {}
      final hit2 = peek(personId: personId, photoUrl: resolvedUrl);
      if (hit2 != null && hit2.isNotEmpty) return hit2;
    }

    if (resolvedUrl == null || resolvedUrl.isEmpty) return null;

    final flightKey = '${personId ?? ''}|$resolvedUrl';
    final existingFlight = _inFlight[flightKey];
    if (existingFlight != null) return existingFlight;

    final future = _fetchAndCache(
      personId: personId,
      resolvedUrl: resolvedUrl,
      client: client,
      timeout: timeout,
    );
    _inFlight[flightKey] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(flightKey);
    }
  }

  static Future<Uint8List?> _fetchAndCache({
    String? personId,
    required String resolvedUrl,
    SupabaseClient? client,
    required Duration timeout,
  }) async {
    try {
      if (resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://')) {
        final res = await http.get(Uri.parse(resolvedUrl)).timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 300 && res.bodyBytes.isNotEmpty) {
          put(personId, resolvedUrl, res.bodyBytes);
          return res.bodyBytes;
        }
        return null;
      }

      final supa = client ?? _safeSupabaseClient();
      if (supa == null) return null;

      try {
        final bytes = await supa.storage
            .from('member-photos')
            .download(resolvedUrl)
            .timeout(timeout);
        if (bytes.isNotEmpty) {
          put(personId, resolvedUrl, bytes);
          return bytes;
        }
      } catch (_) {
        // Repli via URL signée si download direct échoue.
        try {
          final signed = await supa.storage
              .from('member-photos')
              .createSignedUrl(resolvedUrl, 3600)
              .timeout(timeout);
          final res = await http.get(Uri.parse(signed)).timeout(timeout);
          if (res.statusCode >= 200 && res.statusCode < 300 && res.bodyBytes.isNotEmpty) {
            put(personId, resolvedUrl, res.bodyBytes);
            return res.bodyBytes;
          }
        } catch (_) {}
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static SupabaseClient? _safeSupabaseClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
