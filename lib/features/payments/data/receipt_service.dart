import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sèvis resi: estoke PDF la nan bucket prive `receipts` la, bay yon lyen
/// siyen (WhatsApp), epi mete email resi a nan keu sèvè a.
class ReceiptService {
  const ReceiptService(this.client, this.gymId);
  final SupabaseClient client;
  final String gymId;

  static String pathFor(String gymId, String paymentId) =>
      '$gymId/receipts/$paymentId.pdf';

  /// Voye PDF la sou sèvè a. Retounen chemen an. Bezwen entènèt.
  Future<String> upload(String paymentId, Uint8List pdf) async {
    final path = pathFor(gymId, paymentId);
    await client.storage
        .from('receipts')
        .uploadBinary(
          path,
          pdf,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );
    return path;
  }

  /// Lyen siyen 1 an — itil pou WhatsApp.
  Future<String> signedUrl(String path) =>
      client.storage.from('receipts').createSignedUrl(path, 60 * 60 * 24 * 365);

  /// Mete resi a nan keu email la (voye pa worker la). Bezwen PDF la deja
  /// uploaded. Retounen 'queued' | 'already_queued' | 'no_email'.
  Future<String> enqueueEmail(String paymentId, String path) async {
    final result = await client.rpc(
      'enqueue_payment_receipt',
      params: {'p_payment': paymentId, 'p_receipt_path': path},
    );
    return result as String;
  }

  /// Telechaje logo gym la pou PDF la. `logo` = chemen `gym-assets/...`
  /// oswa yon URL https. Null si pa jwenn.
  Future<Uint8List?> logoBytes(String? logo) async {
    if (logo == null || logo.isEmpty) return null;
    try {
      if (logo.startsWith('http')) {
        final response = await http
            .get(Uri.parse(logo))
            .timeout(const Duration(seconds: 8));
        return response.statusCode == 200 ? response.bodyBytes : null;
      }
      final path = logo.startsWith('gym-assets/')
          ? logo.substring('gym-assets/'.length)
          : logo;
      return await client.storage.from('gym-assets').download(path);
    } catch (_) {
      return null;
    }
  }
}
