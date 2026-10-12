import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gymdesk_biometrics/gymdesk_biometrics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/biometrics/access_agent_client.dart';
import '../../../l10n/app_strings.dart';

class BiometricSettingsPage extends ConsumerStatefulWidget {
  const BiometricSettingsPage({super.key});

  @override
  ConsumerState<BiometricSettingsPage> createState() => _BiometricSettingsPageState();
}

class _BiometricSettingsPageState extends ConsumerState<BiometricSettingsPage> {
  String _accessMode = 'finger_only'; // 'off', 'badge_finger', 'finger_only'
  String _preferredVendor = 'suprema'; // 'suprema', 'digitalpersona', 'zkteco', 'secugen'
  String _relayMode = 'usb_serial_relay'; // 'none', 'usb_serial_relay', 'http_relay'
  final _relayPortController = TextEditingController(text: 'COM3');
  final _relayUrlController = TextEditingController(text: 'http://192.168.1.50/relay/0?turn=on');
  final _terminalIpController = TextEditingController(text: '192.168.1.41');
  double _pulseDurationSeconds = 3.0;

  bool _loading = true;
  bool _saving = false;
  bool _testingRelay = false;
  bool _testingTerminal = false;

  String? _terminalStatusText;

  @override
  void initState() {
    super.initState();
    _loadGymBiometricConfig();
  }

  Future<void> _loadGymBiometricConfig() async {
    final gymId = ref.read(appRuntimeProvider).session?.gymId;
    if (gymId == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final client = Supabase.instance.client;
      final gym = await client
          .from('gyms')
          .select('biometric_enabled, biometric_config')
          .eq('id', gymId)
          .maybeSingle();

      if (gym != null && mounted) {
        final cfg = Map<String, dynamic>.from(gym['biometric_config'] as Map? ?? {});
        setState(() {
          _accessMode = cfg['access_mode'] as String? ?? 'finger_only';
          _preferredVendor = cfg['vendor'] as String? ?? 'suprema';
          _relayMode = cfg['relay_mode'] as String? ?? 'terminal_bew2';
          _relayPortController.text = cfg['relay_port'] as String? ?? 'COM3';
          _relayUrlController.text = cfg['relay_url'] as String? ?? 'http://192.168.1.50/relay/0?turn=on';
          _terminalIpController.text = cfg['terminal_ip'] as String? ?? '192.168.1.41';
          _pulseDurationSeconds = (cfg['pulse_duration_seconds'] as num?)?.toDouble() ?? 3.0;
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveConfig() async {
    final gymId = ref.read(appRuntimeProvider).session?.gymId;
    if (gymId == null) return;

    setState(() => _saving = true);
    final s = AppStrings.of(context);

    try {
      final client = Supabase.instance.client;
      final config = {
        'access_mode': _accessMode,
        'vendor': _preferredVendor,
        'relay_mode': _relayMode,
        'relay_port': _relayPortController.text.trim(),
        'relay_url': _relayUrlController.text.trim(),
        'terminal_ip': _terminalIpController.text.trim(),
        'pulse_duration_seconds': _pulseDurationSeconds,
      };

      await client.from('gyms').update({
        'biometric_enabled': _accessMode != 'off',
        'biometric_config': config,
      }).eq('id', gymId);

      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.locale.languageCode == 'fr'
                ? 'Configuration biométrique et porte enregistrée !'
                : 'Konfigirasyon anrejistre avèk siksè !'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _testTerminalPing() async {
    setState(() {
      _testingTerminal = true;
      _terminalStatusText = null;
    });
    final isFr = AppStrings.of(context).locale.languageCode == 'fr';
    final client = AccessAgentClient();
    final ok = await client.pingTerminal(terminalIp: _terminalIpController.text.trim());
    if (mounted) {
      setState(() {
        _testingTerminal = false;
        _terminalStatusText = ok
            ? (isFr ? 'En ligne (BioEntry W2 détecté)' : 'Sou liy (BioEntry W2 detekte)')
            : (isFr ? 'Hors ligne ou injoignable' : 'Paka jwenn li sou rezo a');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? (isFr ? 'Terminal BioEntry W2 connecté avec succès !' : 'Terminal BioEntry W2 konekte avèk siksè !')
              : (isFr ? 'Impossible de joindre le terminal BioEntry W2.' : 'Paka konekte ak BioEntry W2 a.')),
          backgroundColor: ok ? const Color(0xFF059669) : Colors.red,
        ),
      );
    }
  }

  Future<void> _testTerminalDoorPulse() async {
    setState(() => _testingTerminal = true);
    final isFr = AppStrings.of(context).locale.languageCode == 'fr';
    final client = AccessAgentClient();
    final ok = await client.pulseTerminalRelay(terminalIp: _terminalIpController.text.trim());
    if (mounted) {
      setState(() => _testingTerminal = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? (isFr ? 'Impulsion envoyée au relais BioEntry W2 (Porte ouverte) !' : 'Enpilsyon voye nan relè BioEntry W2 (Pòt ouvri) !')
              : (isFr ? 'Échec de l\'impulsion porte BioEntry W2.' : 'Echèk enpilsyon pòt.')),
          backgroundColor: ok ? const Color(0xFF059669) : Colors.red,
        ),
      );
    }
  }

  Future<void> _testDoorRelay() async {
    setState(() => _testingRelay = true);
    final s = AppStrings.of(context);

    if (_relayMode == 'terminal_bew2') {
      await _testTerminalDoorPulse();
      if (mounted) setState(() => _testingRelay = false);
      return;
    }

    DoorController controller;
    if (_relayMode == 'usb_serial_relay') {
      controller = UsbSerialRelayDoorController(port: _relayPortController.text.trim());
    } else if (_relayMode == 'http_relay') {
      controller = HttpRelayDoorController(endpointUrl: _relayUrlController.text.trim());
    } else {
      controller = const NoopDoorController();
    }

    final success = await controller.openDoor(
      pulseDuration: Duration(seconds: _pulseDurationSeconds.round()),
    );

    if (mounted) {
      setState(() => _testingRelay = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? s.text('door_pulse_sent') : 'Relay trigger failed'),
          backgroundColor: success ? const Color(0xFF059669) : Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _relayPortController.dispose();
    _relayUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isFr = s.locale.languageCode == 'fr';
    final isEn = s.locale.languageCode == 'en';

    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('biometrics_settings')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Section 1 : Mode d'accès
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.shieldCheck, color: Color(0xFF0F766E), size: 26),
                            const SizedBox(width: 12),
                            Text(
                              isFr ? 'Mode de Contrôle d\'Accès' : isEn ? 'Access Control Mode' : 'Mòd Kontwòl Aksè',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        RadioListTile<String>(
                          title: Text(isFr ? 'Empreinte digitale seule (Recommandé)' : 'Anprent dwèt sèlman (Rekòmande)'),
                          subtitle: Text(isFr
                              ? 'Le membre pose simplement son doigt sur le capteur Suprema pour déverrouiller la porte.'
                              : 'Manm nan mete dwèt li sou lektè a pou ouvri pòt la dirèkteman.'),
                          value: 'finger_only',
                          groupValue: _accessMode,
                          onChanged: (val) => setState(() => _accessMode = val!),
                        ),
                        RadioListTile<String>(
                          title: Text(isFr ? 'Désactivé' : 'Dezaktive'),
                          subtitle: Text(isFr ? 'Aucun contrôle d\'accès biométrique actif.' : 'Pa gen kontwòl biometrik.'),
                          value: 'off',
                          groupValue: _accessMode,
                          onChanged: (val) => setState(() => _accessMode = val!),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Section 2 : Capteur biométrique & Outils
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.fingerprint, color: Color(0xFF0F766E), size: 26),
                            const SizedBox(width: 12),
                            Text(
                              isFr ? 'Lecteur Biométrique Actif' : isEn ? 'Active Biometric Sensor' : 'Lektè Biometrik Aktif',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _preferredVendor,
                          decoration: InputDecoration(
                            labelText: isFr ? 'Fabricant / SDK' : 'Fabrikan / SDK',
                            border: const OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'suprema', child: Text('Suprema (BioMini, BioMini Plus 2, Slim 2)')),
                            DropdownMenuItem(value: 'digitalpersona', child: Text('HID DigitalPersona (U.are.U 4500, 5160)')),
                            DropdownMenuItem(value: 'zkteco', child: Text('ZKTeco (Live20R, ZK4500)')),
                            DropdownMenuItem(value: 'secugen', child: Text('SecuGen (Hamster Pro 20)')),
                          ],
                          onChanged: (val) => setState(() => _preferredVendor = val ?? 'suprema'),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => context.push('/settings/biometrics/identify'),
                                icon: const Icon(LucideIcons.usb, size: 18),
                                label: Text(s.text('identify_reader')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => context.push('/settings/biometrics/diagnostic'),
                                icon: const Icon(LucideIcons.activity, size: 18),
                                label: Text(s.text('reader_diagnostic')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                 const SizedBox(height: 20),

                // Section 3 : Terminal d'Accès IP (Suprema BioEntry W2 - Contrôle de Porte)
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.router, color: Color(0xFF0F766E), size: 26),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isFr ? 'Terminal d\'Accès Porte IP (Suprema BioEntry W2)' : 'Tèminal Pòt IP (Suprema BioEntry W2)',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F766E).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Ethernet / LAN',
                                style: TextStyle(
                                  color: Color(0xFF0F766E),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isFr
                              ? 'Le terminal mural BioEntry W2 compare les empreintes et déclenche la gâche en autonome sans dépendre d\'un PC allumé en permanence. GymDesk synchronise les dates de validité et empreintes en arrière-plan.'
                              : 'Tèminal miral BioEntry W2 a verifye anpwent yo epi deklannche pòt la poukont li sou rezo lokal la san depann de òdinatè a.',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _terminalIpController,
                          decoration: InputDecoration(
                            labelText: isFr ? 'Adresse IP du Terminal BioEntry W2' : 'Adrès IP Tèminal la',
                            hintText: '192.168.1.41',
                            prefixIcon: const Icon(LucideIcons.network),
                            suffixText: 'Port: 51211',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        if (_terminalStatusText != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _terminalStatusText!.contains('ligne') || _terminalStatusText!.contains('liy')
                                  ? const Color(0xFF10B981).withOpacity(0.12)
                                  : Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _terminalStatusText!.contains('ligne') || _terminalStatusText!.contains('liy')
                                      ? LucideIcons.checkCircle2
                                      : LucideIcons.alertTriangle,
                                  size: 16,
                                  color: _terminalStatusText!.contains('ligne') || _terminalStatusText!.contains('liy')
                                      ? const Color(0xFF059669)
                                      : Colors.orange.shade800,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _terminalStatusText!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _terminalStatusText!.contains('ligne') || _terminalStatusText!.contains('liy')
                                          ? const Color(0xFF059669)
                                          : Colors.orange.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _testingTerminal ? null : _testTerminalPing,
                                icon: _testingTerminal
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(LucideIcons.activity, size: 16),
                                label: Text(isFr ? 'Tester Ping IP' : 'Tcheke Koneksyon'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _testingTerminal ? null : _testTerminalDoorPulse,
                                icon: const Icon(LucideIcons.doorOpen, size: 16),
                                label: Text(isFr ? 'Tester Relais Porte' : 'Teste Relè Pòt'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Section 4 : Contrôle de Porte & Relais
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.doorOpen, color: Color(0xFF0F766E), size: 26),
                            const SizedBox(width: 12),
                            Text(
                              isFr ? 'Relais de Porte & Gâche Électrique' : 'Relè Pòt & Gach Elektrik',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _relayMode,
                          decoration: InputDecoration(
                            labelText: isFr ? 'Type de Relais' : 'Tip Relè',
                            border: const OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'terminal_bew2', child: Text('Relais Suprema BioEntry W2 (Recommandé)')),
                            DropdownMenuItem(value: 'usb_serial_relay', child: Text('Relais USB Série (CH340 / FTDI / COM Port)')),
                            DropdownMenuItem(value: 'http_relay', child: Text('Relais IP / HTTP (Shelly, Sonoff, ESP32)')),
                            DropdownMenuItem(value: 'none', child: Text('Aucun relais (Simulation écran uniquement)')),
                          ],
                          onChanged: (val) => setState(() => _relayMode = val ?? 'terminal_bew2'),
                        ),
                        const SizedBox(height: 16),
                        if (_relayMode == 'usb_serial_relay')
                          TextField(
                            controller: _relayPortController,
                            decoration: const InputDecoration(
                              labelText: 'Port Série (ex: COM3, COM4)',
                              prefixIcon: Icon(LucideIcons.cable),
                              border: OutlineInputBorder(),
                            ),
                          )
                        else if (_relayMode == 'http_relay')
                          TextField(
                            controller: _relayUrlController,
                            decoration: const InputDecoration(
                              labelText: 'URL API Relais (HTTP)',
                              prefixIcon: Icon(LucideIcons.globe),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          '${isFr ? 'Durée de l\'impulsion' : 'Dire enpilsyon'}: ${_pulseDurationSeconds.toStringAsFixed(0)} ${s.text('seconds')}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Slider(
                          min: 1.0,
                          max: 10.0,
                          divisions: 9,
                          value: _pulseDurationSeconds,
                          onChanged: (val) => setState(() => _pulseDurationSeconds = val),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _testingRelay ? null : _testDoorRelay,
                            icon: _testingRelay
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(LucideIcons.zap),
                            label: Text(s.text('test_door_open')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Bouton Enregistrer
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saving ? null : _saveConfig,
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.save),
                    label: Text(
                      _saving ? s.text('saving') : s.text('save'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
