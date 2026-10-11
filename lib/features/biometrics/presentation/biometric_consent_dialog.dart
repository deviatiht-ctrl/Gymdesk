import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_strings.dart';

class BiometricConsentDialog extends StatefulWidget {
  const BiometricConsentDialog({
    super.key,
    required this.memberName,
  });

  final String memberName;

  static Future<bool> show(BuildContext context, {required String memberName}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BiometricConsentDialog(memberName: memberName),
    );
    return result == true;
  }

  @override
  State<BiometricConsentDialog> createState() => _BiometricConsentDialogState();
}

class _BiometricConsentDialogState extends State<BiometricConsentDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final lang = s.locale.languageCode;
    final isFr = lang == 'fr';
    final isEn = lang == 'en';

    final title = isFr
        ? 'Consentement Biométrique Obligatoire'
        : isEn
            ? 'Mandatory Biometric Consent'
            : 'Konsantman Biometrik Obligatwa';

    final body = isFr
        ? 'Conformément aux normes internationales de protection des données personnelles :\n\n'
            '1. L’empreinte digitale de ${widget.memberName} sera convertie en gabarit mathématique chiffré (AES-256). Aucune image réelle de doigt n’est enregistrée.\n'
            '2. Les données sont stockées localement et utilisées exclusivement pour le contrôle d’accès de la salle.\n'
            '3. Le membre conserve le droit de révoquer ce consentement et de demander la suppression immédiate de ses données biométriques à tout moment.'
        : isEn
            ? 'In accordance with privacy and data protection standards:\n\n'
                '1. The fingerprint of ${widget.memberName} will be converted into an encrypted mathematical template (AES-256). No actual fingerprint image is stored.\n'
                '2. Data is kept locally and used solely for physical door access verification.\n'
                '3. The member may revoke this consent and request immediate deletion of their biometric data at any time.'
            : 'Dapre prensip legal pwoteksyon done pèsonèl yo :\n\n'
                '1. Anprent dwèt ${widget.memberName} ap tounen yon kòd matematik kode (AES-256). Okenn foto dwèt reyèl pa konsève nan aparèy la.\n'
                '2. Done sa yo rete lokal epi sèvi sèlman pou idantifikasyon nan pòt gym nan.\n'
                '3. Manm nan gen dwa mande pou efase tout anprent li nan sistèm nan nenpòt kilè li vle.';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(LucideIcons.shieldCheck, color: Color(0xFF0F766E), size: 28),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                body,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _accepted,
              onChanged: (val) => setState(() => _accepted = val ?? false),
              title: Text(
                isFr
                    ? 'Le membre et le responsable confirment ce consentement éclairé.'
                    : isEn
                        ? 'The member and staff confirm this informed consent.'
                        : 'Manm lan ak responsab la konfime konsantman sa a.',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.text('cancel')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: Colors.white,
          ),
          onPressed: _accepted ? () => Navigator.pop(context, true) : null,
          child: Text(isFr ? 'Valider le Consentement' : isEn ? 'Confirm Consent' : 'Valide Konsantman'),
        ),
      ],
    );
  }
}
