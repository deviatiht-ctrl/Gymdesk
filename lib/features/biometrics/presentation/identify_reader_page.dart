import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gymdesk_biometrics/gymdesk_biometrics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/biometrics/access_agent_client.dart';
import '../../../l10n/app_strings.dart';

class IdentifyReaderPage extends ConsumerStatefulWidget {
  const IdentifyReaderPage({super.key});

  @override
  ConsumerState<IdentifyReaderPage> createState() => _IdentifyReaderPageState();
}

class _IdentifyReaderPageState extends ConsumerState<IdentifyReaderPage> {
  final _agentClient = AccessAgentClient();
  final _registry = ReaderRegistry.instance;
  bool _scanning = false;
  List<Map<String, dynamic>> _detectedDevices = [];

  @override
  void initState() {
    super.initState();
    _scanDevices();
  }

  Future<void> _scanDevices() async {
    setState(() => _scanning = true);
    try {
      final devices = await _agentClient.listUsbDevices();
      if (mounted) {
        setState(() {
          _detectedDevices = devices;
          _scanning = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _detectedDevices = [];
          _scanning = false;
        });
      }
    }
  }

  void _copyReport(AppStrings s) {
    final buffer = StringBuffer();
    buffer.writeln('=== SECURGYM RAPPORT MATÉRIEL USB BIOMÉTRIQUE ===');
    buffer.writeln('Date : ${DateTime.now().toIso8601String()}');
    buffer.writeln('Nombre d\'appareils détectés : ${_detectedDevices.length}');
    buffer.writeln('--------------------------------------------------');
    for (final dev in _detectedDevices) {
      final vid = dev['vid'] ?? '';
      final pid = dev['pid'] ?? '';
      final isSupported = _registry.isKnownSupported(vid, pid);
      buffer.writeln('Modèle  : ${dev['product']}');
      buffer.writeln('Fabricant: ${dev['vendor']}');
      buffer.writeln('VID/PID : $vid:$pid');
      buffer.writeln('Supporté: ${isSupported ? 'OUI (Officiel)' : 'Générique'}');
      buffer.writeln('--------------------------------------------------');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.text('copy_report')),
        backgroundColor: const Color(0xFF059669),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('identify_reader')),
        actions: [
          IconButton(
            tooltip: s.text('sync'),
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _scanning ? null : _scanDevices,
          ),
          IconButton(
            tooltip: s.text('copy_report'),
            icon: const Icon(LucideIcons.copy),
            onPressed: _detectedDevices.isEmpty ? null : () => _copyReport(s),
          ),
        ],
      ),
      body: _scanning
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Card(
                  color: const Color(0xFFF0FDF4),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.usb, color: Color(0xFF047857), size: 32),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            s.locale.languageCode == 'fr'
                                ? 'Détection automatique Plug & Play des capteurs branchés en USB (Suprema, DigitalPersona, ZKTeco, SecuGen).'
                                : s.locale.languageCode == 'en'
                                    ? 'Automatic Plug & Play detection for USB biometric readers (Suprema, DigitalPersona, ZKTeco, SecuGen).'
                                    : 'Deteksyon otomatik Plug & Play pou tout lektè anprent USB (Suprema, DigitalPersona, ZKTeco, SecuGen).',
                            style: const TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '${_detectedDevices.length} ${s.locale.languageCode == 'fr' ? 'lecteur(s) détecté(s)' : s.locale.languageCode == 'en' ? 'reader(s) detected' : 'lektè detekte'}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ..._detectedDevices.map((dev) {
                  final vid = (dev['vid'] ?? '').toString();
                  final pid = (dev['pid'] ?? '').toString();
                  final isSupported = _registry.isKnownSupported(vid, pid);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isSupported ? const Color(0xFF059669) : Colors.grey.shade300,
                        width: isSupported ? 1.5 : 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: isSupported ? const Color(0xFFDCFCE7) : Colors.grey.shade200,
                            child: Icon(
                              LucideIcons.fingerprint,
                              color: isSupported ? const Color(0xFF15803D) : Colors.grey.shade700,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        dev['product']?.toString() ?? 'Lecteur USB',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ),
                                    Chip(
                                      label: Text(
                                        isSupported
                                            ? (s.locale.languageCode == 'fr' ? 'Compatible Officiel' : 'Supported')
                                            : 'Générique',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isSupported ? const Color(0xFF065F46) : Colors.grey.shade800,
                                        ),
                                      ),
                                      backgroundColor: isSupported ? const Color(0xFFD1FAE5) : Colors.grey.shade200,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${dev['vendor']} · VID: $vid | PID: $pid',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                ),
                                if (dev['serial'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'S/N: ${dev['serial']}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _copyReport(s),
                  icon: const Icon(LucideIcons.copy, size: 18),
                  label: Text(s.text('copy_report')),
                ),
              ],
            ),
    );
  }
}
