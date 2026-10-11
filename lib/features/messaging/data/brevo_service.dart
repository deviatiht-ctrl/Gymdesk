import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class BrevoConfig {
  const BrevoConfig({
    required this.apiKey,
    required this.senderEmail,
    required this.senderName,
  });

  final String apiKey;
  final String senderEmail;
  final String senderName;

  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      senderEmail.trim().isNotEmpty &&
      senderEmail.contains('@');

  BrevoConfig copyWith({
    String? apiKey,
    String? senderEmail,
    String? senderName,
  }) {
    return BrevoConfig(
      apiKey: apiKey ?? this.apiKey,
      senderEmail: senderEmail ?? this.senderEmail,
      senderName: senderName ?? this.senderName,
    );
  }
}

class BrevoSendProgress {
  const BrevoSendProgress({
    required this.current,
    required this.total,
    required this.successCount,
    required this.failCount,
    this.currentRecipient = '',
    this.errorMessage,
    this.isDone = false,
  });

  final int current;
  final int total;
  final int successCount;
  final int failCount;
  final String currentRecipient;
  final String? errorMessage;
  final bool isDone;
}

class BrevoService {
  BrevoService({FlutterSecureStorage? storage, http.Client? client})
      : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client();

  final FlutterSecureStorage _storage;
  final http.Client _client;

  static const _keyApiKey = 'gymdesk:brevo_api_key';
  static const _keySenderEmail = 'gymdesk:brevo_sender_email';
  static const _keySenderName = 'gymdesk:brevo_sender_name';

  Future<BrevoConfig> loadConfig() async {
    try {
      final apiKey = await _storage.read(key: _keyApiKey) ?? '';
      final senderEmail = await _storage.read(key: _keySenderEmail) ?? '';
      final senderName = await _storage.read(key: _keySenderName) ?? 'GymDesk';
      return BrevoConfig(
        apiKey: apiKey,
        senderEmail: senderEmail,
        senderName: senderName,
      );
    } catch (_) {
      return const BrevoConfig(apiKey: '', senderEmail: '', senderName: 'GymDesk');
    }
  }

  Future<void> saveConfig(BrevoConfig config) async {
    await _storage.write(key: _keyApiKey, value: config.apiKey.trim());
    await _storage.write(key: _keySenderEmail, value: config.senderEmail.trim());
    await _storage.write(key: _keySenderName, value: config.senderName.trim());
  }

  Future<Map<String, dynamic>> testConnection(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw Exception('La clé API Brevo ne peut pas être vide.');
    }

    final url = Uri.parse('https://api.brevo.com/v3/account');
    final response = await _client.get(
      url,
      headers: {
        'api-key': key,
        'accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': true,
        'email': data['email'] ?? '',
        'company': data['companyName'] ?? '',
        'plan': (data['plan'] as List?)?.isNotEmpty == true ? data['plan'][0]['type'] : 'Standard',
      };
    } else {
      final err = jsonDecode(response.body) as Map<String, dynamic>?;
      final msg = err?['message'] ?? 'Erreur HTTP ${response.statusCode}';
      throw Exception(msg);
    }
  }

  String generateHtmlEmail({
    required String title,
    required String bodyText,
    required String recipientName,
    required String gymName,
    String? logoUrl,
    String? accentColor,
    String? ctaText,
    String? ctaUrl,
  }) {
    final color = accentColor != null && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(accentColor)
        ? accentColor
        : '#0F766E';
    final showCta = ctaText != null && ctaText.trim().isNotEmpty;
    final buttonText = ctaText ?? '';
    final buttonUrl = ctaUrl ?? 'https://gymdesk.app';

    // Remplacer les retours à la ligne par des balises <p>
    final paragraphs = bodyText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => '<p style="margin: 0 0 16px; font-size: 16px; line-height: 1.6; color: #334155;">$line</p>')
        .join('');

    final logoHtml = (logoUrl != null && logoUrl.startsWith('http'))
        ? '<img src="$logoUrl" alt="$gymName" width="80" style="display:block;max-width:80px;max-height:80px;object-fit:contain;margin:0 auto 16px;border-radius:12px;" />'
        : '';

    return '''<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title</title>
</head>
<body style="margin:0;padding:24px 12px;background:#F8FAFC;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1E293B;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
    <tr>
      <td align="center">
        <table role="presentation" width="600" cellspacing="0" cellpadding="0" style="width:100%;max-width:600px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #E2E8F0;box-shadow:0 4px 6px -1px rgba(0,0,0,0.05);">
          <tr><td style="height:6px;background:$color;"></td></tr>
          <tr>
            <td style="padding:28px 28px 16px;text-align:center;">
              $logoHtml
              <span style="display:inline-block;padding:4px 14px;background:#F0FDFA;color:#0F766E;border-radius:999px;font-size:12px;font-weight:700;letter-spacing:0.5px;text-transform:uppercase;margin-bottom:12px;">$gymName</span>
              <h1 style="margin:8px 0 16px;font-size:22px;font-weight:800;color:#0F172A;line-height:1.3;">$title</h1>
            </td>
          </tr>
          <tr>
            <td style="padding:0 28px 20px;">
              <p style="margin:0 0 16px;font-size:16px;font-weight:600;color:#0F172A;">Bonjour $recipientName,</p>
              $paragraphs
            </td>
          </tr>
          ${showCta ? '''<tr>
            <td align="center" style="padding:10px 28px 30px;">
              <table role="presentation" cellspacing="0" cellpadding="0">
                <tr>
                  <td align="center" style="border-radius:10px;background:$color;">
                    <a href="$buttonUrl" target="_blank" style="display:inline-block;padding:14px 32px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;border-radius:10px;letter-spacing:0.5px;">$buttonText</a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>''' : '''<tr><td style="height:12px;"></td></tr>'''}
          <tr>
            <td style="background:#F8FAFC;padding:24px 32px;border-top:1px solid #E2E8F0;text-align:center;">
              <p style="margin:0 0 6px;font-size:13px;font-weight:600;color:#64748B;">$gymName — Votre Espace Forme & Santé</p>
              <p style="margin:0;font-size:12px;color:#94A3B8;">Vous recevez cet email car vous êtes inscrit comme membre de notre salle de sport.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>''';
  }

  Future<bool> sendSingleEmail({
    required BrevoConfig config,
    required String toEmail,
    required String toName,
    required String subject,
    required String htmlContent,
    String? textContent,
    List<String>? tags,
  }) async {
    final url = Uri.parse('https://api.brevo.com/v3/smtp/email');
    final payload = <String, dynamic>{
      'sender': {
        'name': config.senderName,
        'email': config.senderEmail,
      },
      'to': [
        {'email': toEmail, 'name': toName}
      ],
      'replyTo': {
        'name': config.senderName,
        'email': config.senderEmail,
      },
      'subject': subject,
      'htmlContent': htmlContent,
      if (textContent != null && textContent.trim().isNotEmpty)
        'textContent': textContent.trim(),
      'tags': tags ?? ['gymdesk', 'transactional'],
    };

    final response = await _client.post(
      url,
      headers: {
        'api-key': config.apiKey,
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 15));

    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Stream<BrevoSendProgress> sendBatchCampaign({
    required BrevoConfig config,
    required List<Map<String, dynamic>> recipients,
    required String title,
    required String subjectTemplate,
    required String bodyTemplate,
    required String gymName,
    String? logoUrl,
    String? accentColor,
  }) async* {
    final total = recipients.length;
    var successCount = 0;
    var failCount = 0;

    for (var i = 0; i < total; i++) {
      final recipient = recipients[i];
      final name = recipient['name']?.toString() ?? 'Membre';
      final email = recipient['email']?.toString() ?? '';

      yield BrevoSendProgress(
        current: i + 1,
        total: total,
        successCount: successCount,
        failCount: failCount,
        currentRecipient: '$name ($email)',
      );

      if (email.isEmpty || !email.contains('@')) {
        failCount++;
        continue;
      }

      // Personnaliser le sujet et le corps
      final personalizedSubject = subjectTemplate
          .replaceAll('{nom}', name)
          .replaceAll('{non}', name)
          .replaceAll('{name}', name)
          .replaceAll('{gym}', gymName);

      final personalizedBody = bodyTemplate
          .replaceAll('{nom}', name)
          .replaceAll('{non}', name)
          .replaceAll('{name}', name)
          .replaceAll('{gym}', gymName);

      final html = generateHtmlEmail(
        title: title,
        bodyText: personalizedBody,
        recipientName: name,
        gymName: gymName,
        logoUrl: logoUrl,
        accentColor: accentColor,
      );

      try {
        final ok = await sendSingleEmail(
          config: config,
          toEmail: email,
          toName: name,
          subject: personalizedSubject,
          htmlContent: html,
          textContent: personalizedBody,
          tags: ['gymdesk', 'campaign'],
        );

        if (ok) {
          successCount++;
        } else {
          failCount++;
        }
      } catch (e) {
        failCount++;
      }

      // Petit délai pour respecter les limites d'envoi Brevo
      if (i < total - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }

    yield BrevoSendProgress(
      current: total,
      total: total,
      successCount: successCount,
      failCount: failCount,
      isDone: true,
    );
  }
}
