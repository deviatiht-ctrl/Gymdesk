import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'receipt_pdf.dart';

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

  /// Resi Otomatik: jenere PDF la, upload li, epi mete imèl la nan keu a.
  /// Silansye — pa janm leve erè (pa gen entènèt / mig. 24 manke / san email).
  /// Idempotent sou sèvè a: pa gen doublon. Bezwen apre chak peman reyisi.
  Future<void> autoEnqueue(ReceiptData data, String? logoPath) async {
    final email = data.memberEmail ?? '';
    if (!email.contains('@')) return;
    try {
      final logo = await logoBytes(logoPath);
      final pdf = await buildReceiptPdf(data.withLogo(logo), _defaultLabels);
      final path = await upload(data.paymentId, pdf);
      await enqueueEmailWithRetry(data.paymentId, path);
    } catch (_) {}
  }

  /// Le paiement est créé hors ligne puis synchronisé : tant qu'il n'est pas
  /// sur le serveur, l'RPC échoue. On réessaie (2 s, 4 s, 8 s…) au lieu
  /// d'abandonner en silence — c'est pourquoi certains reçus ne partaient pas.
  Future<String> enqueueEmailWithRetry(String paymentId, String path, {int attempts = 6}) async {
    for (var i = 0;; i++) {
      try {
        return await enqueueEmail(paymentId, path);
      } on PostgrestException {
        if (i >= attempts - 1) rethrow;
        await Future<void>.delayed(Duration(seconds: 2 << i));
      }
    }
  }

  static const _defaultLabels = <String, String>{
    'receipt': 'Reçu',
    'receipt_paid': 'PAYÉ',
    'receipt_plan': 'Formule',
    'receipt_period': 'Période',
    'receipt_amount': 'Montant dû',
    'receipt_received': 'Montant remis',
    'receipt_credited': 'Crédité sur la balance',
    'receipt_paid_by_balance': 'Payé avec la balance',
    'receipt_change': 'Monnaie rendue',
    'receipt_paid_in': 'Payé en',
    'received_by': 'Encaissé par',
    'receipt_balance': 'Balance restante',
    'receipt_reference': 'Référence',
    'receipt_signature': 'Signature',
    'receipt_thanks': 'Merci pour votre confiance !',
    'member_number': 'N° de membre',
    'payment_method': 'Mode de règlement',
    'date': 'Date',
    'method_cash': 'Espèces',
    'method_moncash': 'MonCash',
    'method_natcash': 'NatCash',
    'method_bank': 'Virement',
    'method_card': 'Carte',
    'method_cheque': 'Chèque',
    'method_other': 'Autre',
    'method_credit': 'Balance',
  };

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
