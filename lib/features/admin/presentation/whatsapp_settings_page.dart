import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/whatsapp/whatsapp_client.dart';
import '../../../l10n/app_strings.dart';

/// Panèl Jesyon WhatsApp (whatsapp-web.js)
/// Pèmèt admin nan konekte WhatsApp fasilman ak yon kòd QR,
/// anrejistre nimewo valid la, epi teste voye mesaj.
class WhatsAppSettingsPage extends ConsumerStatefulWidget {
  const WhatsAppSettingsPage({super.key});

  @override
  ConsumerState<WhatsAppSettingsPage> createState() => _WhatsAppSettingsPageState();
}

class _WhatsAppSettingsPageState extends ConsumerState<WhatsAppSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _gatewayUrlController = TextEditingController(text: 'http://127.0.0.1:47812');
  final _validNumberController = TextEditingController();
  final _countryCodeController = TextEditingController(text: '509');
  final _testNumberController = TextEditingController();
  final _testMessageController = TextEditingController(
    text: '🏋️ Bonjou ! Sa a se yon tès mesaj WhatsApp depi sistèm jesyon GymDesk / SecurGYM nan.',
  );

  bool _autoSendReceipts = true;
  bool _autoSendReminders = true;

  WhatsAppState _state = const WhatsAppState(status: WhatsAppStatus.initializing);
  bool _loading = true;
  bool _saving = false;
  bool _sendingTest = false;
  String? _statusMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialConfig();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _gatewayUrlController.dispose();
    _validNumberController.dispose();
    _countryCodeController.dispose();
    _testNumberController.dispose();
    _testMessageController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _checkStatusSilently();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _loadInitialConfig() async {
    setState(() => _loading = true);

    // 1. Chaje konfigirasyon nan Supabase si disponib
    try {
      final res = await Supabase.instance.client.rpc('platform_whatsapp_config_get');
      if (res != null && res is Map) {
        final cfg = Map<String, dynamic>.from(res);
        final gateway = cfg['gateway_url']?.toString();
        final valid = cfg['valid_number']?.toString();
        final cc = cfg['default_country_code']?.toString();
        final receipts = cfg['auto_send_receipts'] as bool?;
        final reminders = cfg['auto_send_reminders'] as bool?;

        if (gateway != null && gateway.isNotEmpty) _gatewayUrlController.text = gateway;
        if (valid != null && valid.isNotEmpty) {
          _validNumberController.text = valid;
          _testNumberController.text = valid;
        }
        if (cc != null && cc.isNotEmpty) _countryCodeController.text = cc;
        if (receipts != null) _autoSendReceipts = receipts;
        if (reminders != null) _autoSendReminders = reminders;
      }
    } catch (_) {
      // Offline oswa RPC pa prezan ankò
    }

    // 2. Tcheke estati sèvis la
    await _checkStatus();
    setState(() => _loading = false);
  }

  Future<void> _checkStatus() async {
    final client = WhatsAppClient(baseUrl: _gatewayUrlController.text.trim());
    final state = await client.checkStatus(validNumberFallback: _validNumberController.text.trim());
    if (!mounted) return;

    setState(() {
      _state = state;
      if (state.validNumber.isNotEmpty && _validNumberController.text.isEmpty) {
        _validNumberController.text = state.validNumber;
        _testNumberController.text = state.validNumber;
      }
      if (state.defaultCountryCode.isNotEmpty) {
        _countryCodeController.text = state.defaultCountryCode;
      }
      _autoSendReceipts = state.autoSendReceipts;
      _autoSendReminders = state.autoSendReminders;
    });

    if (state.status == WhatsAppStatus.scanQr || state.status == WhatsAppStatus.initializing) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  Future<void> _checkStatusSilently() async {
    final client = WhatsAppClient(baseUrl: _gatewayUrlController.text.trim());
    final state = await client.checkStatus(validNumberFallback: _validNumberController.text.trim());
    if (!mounted) return;

    if (state.status != _state.status ||
        state.connectedPhone != _state.connectedPhone ||
        state.rawQr != _state.rawQr) {
      setState(() => _state = state);
      if (state.status == WhatsAppStatus.ready) {
        _stopPolling();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 WhatsApp konekte avèk siksè !'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;
    final s = AppStrings.of(context);
    setState(() => _saving = true);

    final gateway = _gatewayUrlController.text.trim();
    final validNumber = _validNumberController.text.trim();
    final cc = _countryCodeController.text.trim();

    try {
      // 1. Sove nan sèvis lokal WhatsApp Node.js la
      final client = WhatsAppClient(baseUrl: gateway);
      await client.saveConfig(
        validNumber: validNumber,
        defaultCountryCode: cc,
        autoSendReceipts: _autoSendReceipts,
        autoSendReminders: _autoSendReminders,
      );

      // 2. Sove nan Supabase
      try {
        await Supabase.instance.client.rpc('platform_whatsapp_config_set', params: {
          'p_gateway_url': gateway,
          'p_valid_number': validNumber,
          'p_default_country_code': cc,
          'p_auto_send_receipts': _autoSendReceipts,
          'p_auto_send_reminders': _autoSendReminders,
        });
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.text('whatsapp_config_saved'))),
        );
      }
      await _checkStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erè: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTestMessage() async {
    final s = AppStrings.of(context);
    final to = _testNumberController.text.trim();
    final msg = _testMessageController.text.trim();

    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.text('whatsapp_enter_number'))),
      );
      return;
    }
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.text('whatsapp_enter_message'))),
      );
      return;
    }

    setState(() => _sendingTest = true);
    final client = WhatsAppClient(baseUrl: _gatewayUrlController.text.trim());
    final result = await client.sendTestMessage(to: to, message: msg);
    if (!mounted) return;
    setState(() => _sendingTest = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${s.text('whatsapp_test_sent')} (${result.to ?? to})'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Echèk: ${result.error ?? 'Erè enkoni'}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _reconnect() async {
    setState(() => _loading = true);
    final client = WhatsAppClient(baseUrl: _gatewayUrlController.text.trim());
    await client.reconnect();
    await Future<void>.delayed(const Duration(seconds: 2));
    await _checkStatus();
    _startPolling();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _logout() async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('whatsapp_disconnect_title')),
        content: Text(s.text('whatsapp_disconnect_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.text('disconnect')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    final client = WhatsAppClient(baseUrl: _gatewayUrlController.text.trim());
    await client.logout(clearSession: true);
    await Future<void>.delayed(const Duration(seconds: 1));
    await _checkStatus();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(LucideIcons.messageSquare, size: 22, color: Colors.green),
            const SizedBox(width: 10),
            Text(s.text('whatsapp_admin_title')),
          ],
        ),
        actions: [
          IconButton(
            tooltip: s.text('refresh'),
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _loading ? null : _checkStatus,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: [
          Text(
            s.text('whatsapp_admin_subtitle'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 20),

          // 1. KAT ESTATI AK ESKANE KÒD QR
          _buildConnectionCard(s, theme),
          const SizedBox(height: 24),

          // 2. KAT KONFIGIRASYON (NIMEWO VALID AK KÒD PEYI)
          _buildConfigurationCard(s, theme),
          const SizedBox(height: 24),

          // 3. KAT TÈS VOYE MESAJ
          _buildTestMessageCard(s, theme),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Kat pou montre estati ak Kòd QR eskanè a
  Widget _buildConnectionCard(AppStrings s, ThemeData theme) {
    final isReady = _state.isReady;
    final isWaitingQr = _state.isWaitingForQr;
    final isOffline = _state.isOffline;

    Color cardBorder;
    Color statusBadgeColor;
    String statusTitle;
    IconData statusIcon;

    if (isReady) {
      cardBorder = Colors.green.shade400;
      statusBadgeColor = Colors.green;
      statusTitle = s.text('whatsapp_connected');
      statusIcon = LucideIcons.circleCheck;
    } else if (isWaitingQr) {
      cardBorder = Colors.amber.shade600;
      statusBadgeColor = Colors.amber.shade700;
      statusTitle = s.text('whatsapp_waiting_scan');
      statusIcon = LucideIcons.qrCode;
    } else if (isOffline) {
      cardBorder = Colors.red.shade300;
      statusBadgeColor = Colors.red;
      statusTitle = s.text('whatsapp_service_offline');
      statusIcon = LucideIcons.wifiOff;
    } else {
      cardBorder = Colors.blue.shade300;
      statusBadgeColor = Colors.blue;
      statusTitle = s.text('whatsapp_initializing');
      statusIcon = LucideIcons.loader;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cardBorder, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusBadgeColor, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: statusBadgeColor,
                        ),
                      ),
                      if (isReady && _state.connectedPhone != null)
                        Text(
                          'Nimewo konekte: +${_state.connectedPhone} ${_state.pushName != null ? "(${_state.pushName})" : ""}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (isReady)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: _logout,
                    icon: const Icon(LucideIcons.logOut, size: 16),
                    label: Text(s.text('whatsapp_disconnect_btn')),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _reconnect,
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: Text(s.text('whatsapp_reconnect_btn')),
                  ),
              ],
            ),

            // Si n ap tann eskanè Kòd QR
            if (isWaitingQr) ...[
              const Divider(height: 32),
              Center(
                child: Column(
                  children: [
                    Text(
                      s.text('whatsapp_scan_prompt'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Text(
                        s.text('whatsapp_scan_instructions'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Afichaj Kòd QR la
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _state.rawQr != null && _state.rawQr!.isNotEmpty
                          ? QrImageView(
                              data: _state.rawQr!,
                              version: QrVersions.auto,
                              size: 220,
                              gapless: false,
                            )
                          : _state.qrDataUrl != null && _state.qrDataUrl!.contains(',')
                              ? Image.memory(
                                  base64Decode(_state.qrDataUrl!.split(',')[1]),
                                  width: 220,
                                  height: 220,
                                )
                              : Image.network(
                                  '${_gatewayUrlController.text.trim()}/api/qr.png',
                                  width: 220,
                                  height: 220,
                                  errorBuilder: (_, __, ___) => const SizedBox(
                                    width: 220,
                                    height: 220,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Kòd sa a ap rafrechi otomatikman. Eskane l avèk WhatsApp sou telefòn ou.',
                      style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],

            // Si sèvis la pa reponn (offline)
            if (isOffline) ...[
              const Divider(height: 32),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.info, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sèvis WhatsApp la poko kòmanse sou machin sa a.\n'
                        '👉 Pou demare l: Ale nan dosye "tools\\whatsapp_service" la epi fè yon doub klik sou fichye "LANCER_WHATSAPP.bat".\n'
                        'Depi l demare, klike sou bouton "Rafrechi" anwo a pou konekte l.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Kat pou mete nimewo valid la ak konfigirasyon
  Widget _buildConfigurationCard(AppStrings s, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.settings2, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    s.text('whatsapp_config_title'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                s.text('whatsapp_config_desc'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 20),

              // Chan Nimewo Valid (Admin / Tès)
              TextFormField(
                controller: _validNumberController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: s.text('whatsapp_valid_number_label'),
                  helperText: s.text('whatsapp_valid_number_helper'),
                  hintText: '50937001122 oswa 50948001122',
                  prefixIcon: const Icon(LucideIcons.phone),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return null; // Opsyonèl men rekòmande
                  final digits = val.replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 8) return s.text('whatsapp_invalid_number');
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Kòd peyi ak URL sèvis
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _countryCodeController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.text('whatsapp_country_code_label'),
                        helperText: 'Egz: 509 (Ayiti)',
                        prefixIcon: const Icon(LucideIcons.globe),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _gatewayUrlController,
                      decoration: InputDecoration(
                        labelText: s.text('whatsapp_gateway_url_label'),
                        helperText: 'Pa defo: http://127.0.0.1:47812',
                        prefixIcon: const Icon(LucideIcons.server),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Toggles pou voye otomatik
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.text('whatsapp_auto_receipts_title')),
                subtitle: Text(s.text('whatsapp_auto_receipts_desc')),
                value: _autoSendReceipts,
                onChanged: (val) => setState(() => _autoSendReceipts = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.text('whatsapp_auto_reminders_title')),
                subtitle: Text(s.text('whatsapp_auto_reminders_desc')),
                value: _autoSendReminders,
                onChanged: (val) => setState(() => _autoSendReminders = val),
              ),

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveConfig,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.save, size: 16),
                  label: Text(s.text('save_config_btn')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kat pou teste voye mesaj WhatsApp dirèk
  Widget _buildTestMessageCard(AppStrings s, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.send, size: 20, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  s.text('whatsapp_test_title'),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.text('whatsapp_test_desc'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _testNumberController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: s.text('whatsapp_test_target_label'),
                hintText: '50937001122',
                prefixIcon: const Icon(LucideIcons.phoneCall),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _testMessageController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: s.text('whatsapp_test_message_label'),
                prefixIcon: const Icon(LucideIcons.messageCircle),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _sendingTest || !_state.isReady ? null : _sendTestMessage,
                icon: _sendingTest
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.send, size: 16),
                label: Text(s.text('whatsapp_send_test_btn')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
