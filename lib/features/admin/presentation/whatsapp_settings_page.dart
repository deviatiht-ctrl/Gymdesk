import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/whatsapp/whatsapp_client.dart';
import '../../../core/whatsapp/whatsapp_notification_service.dart';
import '../../../l10n/app_strings.dart';

/// Panèl Jesyon WhatsApp (whatsapp-web.js)
/// 1. Pèmèt admin nan konekte WhatsApp fasilman ak yon kòd QR
/// 2. Chanje oswa mete nimewo de sekou si WhatsApp ta bloke
/// 3. Pwoteksyon Anti-Spam ak delè sekirite ant mesaj yo
/// 4. Pou Super Admin: bay aksè pou chak gym, mete peryòd (dat debi, dat fen, 1 mwa, plis mwa), sispann, oswa renouvle
class WhatsAppSettingsPage extends ConsumerStatefulWidget {
  const WhatsAppSettingsPage({super.key});

  @override
  ConsumerState<WhatsAppSettingsPage> createState() => _WhatsAppSettingsPageState();
}

class _WhatsAppSettingsPageState extends ConsumerState<WhatsAppSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _gatewayUrlController = TextEditingController(text: 'http://127.0.0.1:47812');
  final _validNumberController = TextEditingController(text: '50932986751');
  final _backupNumberController = TextEditingController();
  final _countryCodeController = TextEditingController(text: '509');
  final _testNumberController = TextEditingController(text: '50932986751');
  final _testMessageController = TextEditingController(
    text: '🏋️ Bonjou ! Sa a se yon tès mesaj WhatsApp depi sistèm jesyon SecurGYM nan.',
  );
  final _gymSearchController = TextEditingController();

  int _selectedTabIndex = 0; // 0: Konfigirasyon & Nimewo, 1: Aksè Gym yo, 2: Contrôle des messages

  bool _autoSendWelcome = true;
  bool _autoSendReceipts = true;
  bool _autoSendReminders = true;

  WhatsAppState _state = const WhatsAppState(status: WhatsAppStatus.initializing);
  WhatsAppAccessCheckResult? _myGymAccess;

  bool _loading = true;
  bool _saving = false;
  bool _sendingTest = false;
  Timer? _pollTimer;

  // Super Admin: Lis aksè WhatsApp pou chak gym & Contrôle des messages
  bool _loadingGyms = false;
  List<GymWhatsAppAccess> _gymsAccessList = [];
  List<WhatsAppAccountInfo> _accountsList = [];

  bool _loadingControl = false;
  bool _dispatchingControlBatch = false;
  bool _controlAutoVerifyEnabled = true;
  Map<String, dynamic>? _controlData;
  Timer? _controlAutoTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialConfig();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controlAutoTimer?.cancel();
    _gatewayUrlController.dispose();
    _validNumberController.dispose();
    _backupNumberController.dispose();
    _countryCodeController.dispose();
    _testNumberController.dispose();
    _testMessageController.dispose();
    _gymSearchController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _checkStatusSilently();
      if (mounted) _loadAccountsList();
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
        final backup = cfg['backup_number']?.toString();
        final cc = cfg['default_country_code']?.toString();
        final receipts = cfg['auto_send_receipts'] as bool?;
        final reminders = cfg['auto_send_reminders'] as bool?;
        final welcome = cfg['auto_send_welcome'] as bool?;

        if (gateway != null && gateway.isNotEmpty) _gatewayUrlController.text = gateway;
        if (valid != null && valid.isNotEmpty) {
          _validNumberController.text = valid;
          _testNumberController.text = valid;
        }
        if (backup != null && backup.isNotEmpty) {
          _backupNumberController.text = backup;
        }
        if (cc != null && cc.isNotEmpty) _countryCodeController.text = cc;
        if (receipts != null) _autoSendReceipts = receipts;
        if (reminders != null) _autoSendReminders = reminders;
        if (welcome != null) _autoSendWelcome = welcome;
      }
    } catch (_) {}

    // 2. Tcheke aksè abònman gym aktyèl la
    await _checkCurrentGymAccess();

    // 3. Tcheke estati sèvis WhatsApp lokal la
    await _checkStatus();
    await _loadAccountsList();

    // 4. Si se Super Admin, chaje lis gym yo
    final runtime = ref.read(appRuntimeProvider);
    if (runtime.session?.isPlatformAdmin == true) {
      await _loadGymsAccessList();
    }

    setState(() => _loading = false);
  }

  Future<void> _checkCurrentGymAccess() async {
    try {
      final gymId = ref.read(appRuntimeProvider).session?.gymId;
      final access = await ref
          .read(whatsAppNotificationServiceProvider)
          .checkGymAccess(gymId: gymId);
      if (mounted) {
        setState(() => _myGymAccess = access);
      }
    } catch (_) {}
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
      if (state.backupNumber.isNotEmpty && _backupNumberController.text.isEmpty) {
        _backupNumberController.text = state.backupNumber;
      }
      if (state.defaultCountryCode.isNotEmpty) {
        _countryCodeController.text = state.defaultCountryCode;
      }
      _autoSendWelcome = state.autoSendWelcome;
      _autoSendReceipts = state.autoSendReceipts;
      _autoSendReminders = state.autoSendReminders;
    });

    if (state.status == WhatsAppStatus.scanQr ||
        state.status == WhatsAppStatus.initializing ||
        state.status == WhatsAppStatus.error) {
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
        state.rawQr != _state.rawQr ||
        state.lastError != _state.lastError) {
      setState(() => _state = state);
      if (state.status == WhatsAppStatus.ready) {
        _stopPolling();
        final s = AppStrings.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.text('whatsapp_connected')),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _loadGymsAccessList() async {
    setState(() => _loadingGyms = true);
    try {
      final res = await Supabase.instance.client.rpc('platform_whatsapp_gym_access_list');
      if (res != null && res is List) {
        final list = res
            .map((e) => GymWhatsAppAccess.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (mounted) {
          setState(() {
            _gymsAccessList = list;
            _loadingGyms = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('[WhatsApp] Erè chaje lis gym: $e');
    }

    // Fallback: Si RPC pa pare, chaje tab gyms dirèkteman
    try {
      final gymsRes = await Supabase.instance.client
          .from('gyms')
          .select('id, name, code, phone')
          .isFilter('deleted_at', null)
          .order('name');
      final list = (gymsRes as List).map((g) {
        final m = g as Map<String, dynamic>;
        return GymWhatsAppAccess(
          gymId: m['id']?.toString() ?? '',
          gymName: m['name']?.toString() ?? 'Gym',
          gymCode: m['code']?.toString() ?? '',
          gymPhone: m['phone']?.toString() ?? '',
          isEnabled: false,
          status: 'inactive',
          daysRemaining: 0,
          isValid: false,
        );
      }).toList();
      if (mounted) {
        setState(() {
          _gymsAccessList = list;
          _loadingGyms = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingGyms = false);
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;
    final s = AppStrings.of(context);
    setState(() => _saving = true);

    final gateway = _gatewayUrlController.text.trim();
    final validNumber = _validNumberController.text.trim();
    final backupNumber = _backupNumberController.text.trim();
    final cc = _countryCodeController.text.trim();

    try {
      // 1. Sove nan sèvis lokal WhatsApp Node.js la
      final client = WhatsAppClient(baseUrl: gateway);
      await client.saveConfig(
        validNumber: validNumber,
        backupNumber: backupNumber,
        defaultCountryCode: cc,
        autoSendWelcome: _autoSendWelcome,
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
          'p_auto_send_welcome': _autoSendWelcome,
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

  Future<void> _switchAccount() async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('whatsapp_switch_account_title')),
        content: Text(s.text('whatsapp_switch_account_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.text('whatsapp_switch_account_btn')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    final client = WhatsAppClient(baseUrl: _gatewayUrlController.text.trim());
    await client.switchAccount(
      backupNumber: _backupNumberController.text.trim(),
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    await _checkStatus();
    _startPolling();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sendTestMessage() async {
    final s = AppStrings.of(context);
    final to = _testNumberController.text.trim();
    final msg = _testMessageController.text.trim();

    // Verifye si gym nan gen aksè
    final isSuper = ref.read(appRuntimeProvider).session?.isPlatformAdmin == true;
    if (!isSuper && _myGymAccess != null && !_myGymAccess!.hasAccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ ${_myGymAccess!.message}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

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

  Future<void> _resetSession() async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('whatsapp_reset_title')),
        content: Text(s.text('whatsapp_reset_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.text('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.text('whatsapp_reset_btn')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    final client = WhatsAppClient(baseUrl: _gatewayUrlController.text.trim());
    await client.resetSession();
    await Future<void>.delayed(const Duration(seconds: 3));
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

  // --- SUPER ADMIN: Aksyon sou Aksè WhatsApp Gym yo ---

  Future<void> _showEditGymAccessDialog(GymWhatsAppAccess gym) async {
    final s = AppStrings.of(context);
    bool enabled = gym.isEnabled;
    String status = gym.status == 'inactive' ? 'active' : gym.status;
    DateTime startDate = gym.startDate ?? DateTime.now();
    DateTime endDate = gym.endDate ?? DateTime.now().add(const Duration(days: 30));
    final backupCtrl = TextEditingController(text: gym.backupPhone);
    final notesCtrl = TextEditingController(text: gym.notes);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final df = DateFormat('dd/MM/yyyy');
          final daysDiff = endDate.difference(DateTime.now()).inDays;

          return AlertDialog(
            title: Row(
              children: [
                const Icon(LucideIcons.shieldCheck, color: Color(0xFF0F766E), size: 22),
                const SizedBox(width: 10),
                Expanded(child: Text('${s.text('whatsapp_grant_access_btn')} : ${gym.gymName}')),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text('whatsapp_enable_service_label')),
                    subtitle: Text(enabled ? s.text('whatsapp_access_open') : s.text('whatsapp_access_closed')),
                    value: enabled,
                    onChanged: (val) => setDlgState(() => enabled = val),
                  ),
                  const Divider(),
                  const SizedBox(height: 8),

                  Text(s.text('whatsapp_quick_period_label'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: Text(s.text('whatsapp_period_1m')),
                        onPressed: () {
                          setDlgState(() {
                            enabled = true;
                            status = 'active';
                            startDate = DateTime.now();
                            endDate = DateTime.now().add(const Duration(days: 30));
                          });
                        },
                      ),
                      ActionChip(
                        label: Text(s.text('whatsapp_period_3m')),
                        onPressed: () {
                          setDlgState(() {
                            enabled = true;
                            status = 'active';
                            startDate = DateTime.now();
                            endDate = DateTime.now().add(const Duration(days: 90));
                          });
                        },
                      ),
                      ActionChip(
                        label: Text(s.text('whatsapp_period_6m')),
                        onPressed: () {
                          setDlgState(() {
                            enabled = true;
                            status = 'active';
                            startDate = DateTime.now();
                            endDate = DateTime.now().add(const Duration(days: 180));
                          });
                        },
                      ),
                      ActionChip(
                        label: Text(s.text('whatsapp_period_1y')),
                        onPressed: () {
                          setDlgState(() {
                            enabled = true;
                            status = 'active';
                            startDate = DateTime.now();
                            endDate = DateTime.now().add(const Duration(days: 365));
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Dat Debi ak Dat Fen
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final pick = await showDatePicker(
                              context: ctx,
                              initialDate: startDate,
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2035),
                            );
                            if (pick != null) setDlgState(() => startDate = pick);
                          },
                          icon: const Icon(LucideIcons.calendar, size: 16),
                          label: Text('${s.text('whatsapp_start_date_label')} ${df.format(startDate)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final pick = await showDatePicker(
                              context: ctx,
                              initialDate: endDate.isAfter(DateTime.now()) ? endDate : DateTime.now().add(const Duration(days: 30)),
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2035),
                            );
                            if (pick != null) setDlgState(() => endDate = pick);
                          },
                          icon: const Icon(LucideIcons.calendarCheck, size: 16),
                          label: Text('${s.text('whatsapp_end_date_label')} ${df.format(endDate)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.text('whatsapp_days_remaining_label').replaceAll('{0}', '$daysDiff'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: daysDiff > 0 ? Colors.green.shade800 : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Estati (Aktif vs Sispann)
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: InputDecoration(
                      labelText: s.text('whatsapp_subscription_status_label'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: 'active', child: Text(s.text('whatsapp_status_active_opt'))),
                      DropdownMenuItem(value: 'suspended', child: Text(s.text('whatsapp_status_suspended_opt'))),
                      DropdownMenuItem(value: 'inactive', child: Text(s.text('whatsapp_status_inactive_opt'))),
                    ],
                    onChanged: (val) {
                      if (val != null) setDlgState(() => status = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Nimewo sekou pou gym sa a
                  TextFormField(
                    controller: backupCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: s.text('whatsapp_backup_number_opt_label'),
                      hintText: '50937001122',
                      prefixIcon: const Icon(LucideIcons.phoneForwarded),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Nòt
                  TextFormField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: s.text('whatsapp_notes_label'),
                      hintText: s.text('whatsapp_notes_hint'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('cancel'))),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.text('save')),
              ),
            ],
          );
        },
      ),
    );

    if (updated != true) return;

    setState(() => _loadingGyms = true);
    try {
      await Supabase.instance.client.rpc('platform_whatsapp_gym_access_set', params: {
        'p_gym_id': gym.gymId,
        'p_is_enabled': enabled,
        'p_status': status,
        'p_start_date': startDate.toIso8601String(),
        'p_end_date': endDate.toIso8601String(),
        'p_backup_phone': backupCtrl.text.trim(),
        'p_notes': notesCtrl.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${gym.gymName} : ${s.text('whatsapp_access_updated')}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadGymsAccessList();
      await _checkCurrentGymAccess();
      if (enabled && status == 'active') {
        _triggerExpirationCheckForGym(gym.gymId, gym.gymName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erè: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGyms = false);
    }
  }

  Future<void> _quickToggleSuspend(GymWhatsAppAccess gym) async {
    final s = AppStrings.of(context);
    final newStatus = gym.status == 'suspended' ? 'active' : 'suspended';
    
    setState(() => _loadingGyms = true);
    try {
      await Supabase.instance.client.rpc('platform_whatsapp_gym_access_set', params: {
        'p_gym_id': gym.gymId,
        'p_is_enabled': gym.isEnabled,
        'p_status': newStatus,
        'p_start_date': (gym.startDate ?? DateTime.now()).toIso8601String(),
        'p_end_date': (gym.endDate ?? DateTime.now().add(const Duration(days: 30))).toIso8601String(),
        'p_backup_phone': gym.backupPhone,
        'p_notes': gym.notes,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${gym.gymName} : ${s.text('whatsapp_access_updated')}'),
            backgroundColor: newStatus == 'active' ? Colors.green : Colors.orange.shade800,
          ),
        );
      }
      await _loadGymsAccessList();
      await _checkCurrentGymAccess();
      if (newStatus == 'active') {
        _triggerExpirationCheckForGym(gym.gymId, gym.gymName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erè: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGyms = false);
    }
  }

  Future<void> _quickRenewMonth(GymWhatsAppAccess gym) async {
    final s = AppStrings.of(context);
    final now = DateTime.now();
    final currentEnd = gym.endDate;
    final baseDate = (currentEnd != null && currentEnd.isAfter(now)) ? currentEnd : now;
    final newEndDate = baseDate.add(const Duration(days: 30));

    setState(() => _loadingGyms = true);
    try {
      await Supabase.instance.client.rpc('platform_whatsapp_gym_access_set', params: {
        'p_gym_id': gym.gymId,
        'p_is_enabled': true,
        'p_status': 'active',
        'p_start_date': (gym.startDate ?? now).toIso8601String(),
        'p_end_date': newEndDate.toIso8601String(),
        'p_backup_phone': gym.backupPhone,
        'p_notes': gym.notes,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 ${gym.gymName} : ${s.text('whatsapp_renew_success')}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadGymsAccessList();
      await _checkCurrentGymAccess();
      _triggerExpirationCheckForGym(gym.gymId, gym.gymName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erè: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGyms = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final runtime = ref.watch(appRuntimeProvider);
    final isSuperAdmin = runtime.session?.isPlatformAdmin == true;

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
            onPressed: _loading ? null : () async {
              await _checkStatus();
              await _checkCurrentGymAccess();
              if (isSuperAdmin) await _loadGymsAccessList();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Si se Super Admin, ofri chwa ant de onglet yo
          if (isSuperAdmin) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(s.text('whatsapp_tab_settings')),
                      selected: _selectedTabIndex == 0,
                      onSelected: (val) {
                        _controlAutoTimer?.cancel();
                        setState(() => _selectedTabIndex = 0);
                      },
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      label: Text(s.text('whatsapp_tab_super_admin')),
                      selected: _selectedTabIndex == 1,
                      onSelected: (val) {
                        _controlAutoTimer?.cancel();
                        setState(() => _selectedTabIndex = 1);
                        _loadGymsAccessList();
                      },
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      label: Text(s.text('whatsapp_tab_message_control')),
                      selected: _selectedTabIndex == 2,
                      onSelected: (val) {
                        setState(() => _selectedTabIndex = 2);
                        _loadControlOverview();
                        _startControlAutoLoop();
                        if (_controlAutoVerifyEnabled) {
                          _runControlDispatchBatch(
                            includeMissed: true,
                            includeRenewals: true,
                            retryFailed: false,
                            silent: true,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],

          Expanded(
            child: _selectedTabIndex == 2 && isSuperAdmin
                ? _buildControlOverviewView(s, theme)
                : _selectedTabIndex == 1 && isSuperAdmin
                    ? _buildSuperAdminGymsView(s, theme)
                    : _buildSettingsView(s, theme),
          ),
        ],
      ),
    );
  }

  /// Onglet 1: Konfigirasyon, Koneksyon Kòd QR, Nimewo de Sekou, ak Tès
  Widget _buildSettingsView(AppStrings s, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        // 0. BANYÈ ESTATI ABÒNMAN GYM NAN
        _buildGymSubscriptionBanner(s, theme),
        const SizedBox(height: 16),

        // Nòt Pwoteksyon Anti-Spam
        _buildAntiSpamProtectionCard(s, theme),
        const SizedBox(height: 20),

        // 1. KAT ESTATI AK ESKANE KÒD QR
        _buildClusterAccountsCard(s, theme),
        const SizedBox(height: 24),

        // 2. KAT KONFIGIRASYON (NIMEWO PRENSIPAL, NIMEWO SEKOU, KÒD PEYI)
        _buildConfigurationCard(s, theme),
        const SizedBox(height: 24),

        // 3. KAT TÈS VOYE MESAJ
        _buildTestMessageCard(s, theme),
        const SizedBox(height: 40),
      ],
    );
  }

  /// Banyè ki montre si abònman WhatsApp gym nan aktif oswa ekspire
  Widget _buildGymSubscriptionBanner(AppStrings s, ThemeData theme) {
    final access = _myGymAccess;
    if (access == null) return const SizedBox.shrink();

    final isSuper = ref.read(appRuntimeProvider).session?.isPlatformAdmin == true;
    final hasAccess = isSuper || access.hasAccess;
    final df = DateFormat('dd/MM/yyyy');

    if (hasAccess) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade400),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.shieldCheck, color: Colors.green, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.text('whatsapp_subscription_active_banner'),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    access.endDate != null
                        ? s.text('whatsapp_subscription_active_desc')
                            .replaceAll('{0}', df.format(access.endDate!))
                            .replaceAll('{1}', '${access.daysRemaining}')
                        : s.text('whatsapp_service_ready_desc'),
                    style: TextStyle(color: Colors.green.shade900, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade400, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.shieldAlert, color: Colors.red, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.text('whatsapp_subscription_expired_banner'),
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  access.message.isNotEmpty
                      ? access.message
                      : s.text('whatsapp_subscription_expired_msg'),
                  style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  s.text('whatsapp_contact_support_renew'),
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Kat Pwoteksyon Anti-Spam
  Widget _buildAntiSpamProtectionCard(AppStrings s, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E).withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0F766E).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.shield, color: Color(0xFF0F766E), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.text('whatsapp_anti_spam_pacing_note'),
              style: TextStyle(fontSize: 12, color: Colors.teal.shade900),
            ),
          ),
        ],
      ),
    );
  }

  /// Kat pou montre estati ak Kòd QR eskanè a
  Widget _buildConnectionCard(AppStrings s, ThemeData theme) {
    final isReady = _state.isReady;
    final isWaitingQr = _state.isWaitingForQr;
    final isOffline = _state.isOffline;
    final isError = _state.isError;
    final isInitializing = _state.isInitializing;

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
    } else if (isError) {
      cardBorder = Colors.red.shade400;
      statusBadgeColor = Colors.red.shade700;
      statusTitle = s.text('whatsapp_status_error');
      statusIcon = LucideIcons.alertCircle;
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
                          '${s.text('whatsapp_connected_phone')} +${_state.connectedPhone} ${_state.pushName != null ? "(${_state.pushName})" : ""}',
                          style: theme.textTheme.bodySmall,
                        ),
                      if (_state.isCloudBridge)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.cloud, size: 14, color: Colors.teal),
                              const SizedBox(width: 4),
                              Text(
                                'Cloud Bridge Aktif (Senkronize ak sèvis PC a)',
                                style: TextStyle(color: Colors.teal.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (isReady) ...[
                      // Bouton Chanje / Dekonekte pou lòt nimewo
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(foregroundColor: Colors.orange.shade900),
                        onPressed: _switchAccount,
                        icon: const Icon(LucideIcons.phoneForwarded, size: 16),
                        label: Text(s.text('whatsapp_switch_account_btn')),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: _logout,
                        icon: const Icon(LucideIcons.logOut, size: 16),
                        label: Text(s.text('whatsapp_disconnect_btn')),
                      ),
                    ] else ...[
                      FilledButton.tonalIcon(
                        onPressed: _reconnect,
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
                        label: Text(s.text('whatsapp_reconnect_btn')),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade800),
                        onPressed: _resetSession,
                        icon: const Icon(LucideIcons.rotateCcw, size: 16),
                        label: Text(s.text('whatsapp_reset_btn')),
                      ),
                    ],
                  ],
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
                                  errorBuilder: (context, error, stackTrace) => const SizedBox(
                                    width: 220,
                                    height: 220,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      s.text('whatsapp_qr_auto_refresh_hint'),
                      style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],

            // Si gen yon erè nan inisyalizasyon an
            if (isError) ...[
              const Divider(height: 32),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.alertTriangle, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          s.text('whatsapp_error_details'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      _state.lastError ?? 'Erè inisyalizasyon enkoni.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: Colors.red.shade900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      s.text('whatsapp_error_reset_hint'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],

            // Si n ap inisyalize (in progress)
            if (isInitializing) ...[
              const Divider(height: 32),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        s.text('whatsapp_initializing_hint'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
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
                        s.text('whatsapp_offline_guide'),
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

  /// Kat pou mete nimewo prensipal, nimewo de sekou ak konfigirasyon
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

              // Chan Nimewo Prensipal Valid
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
                  if (val.isEmpty) return null;
                  final digits = val.replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 8) return s.text('whatsapp_invalid_number');
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Chan Nimewo de Sekou (Backup Phone)
              TextFormField(
                controller: _backupNumberController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: s.text('whatsapp_backup_number_label'),
                  helperText: s.text('whatsapp_backup_number_helper'),
                  hintText: '50938002233',
                  prefixIcon: const Icon(LucideIcons.phoneForwarded, color: Colors.orange),
                  border: const OutlineInputBorder(),
                ),
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
                title: Text(s.text('whatsapp_auto_welcome_title')),
                subtitle: Text(s.text('whatsapp_auto_welcome_desc')),
                value: _autoSendWelcome,
                onChanged: (val) => setState(() => _autoSendWelcome = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.text('whatsapp_auto_reminders_title')),
                subtitle: Text(s.text('whatsapp_auto_reminders_desc')),
                value: _autoSendReminders,
                onChanged: (val) => setState(() => _autoSendReminders = val),
              ),
              if (_autoSendReminders) ...[
                const SizedBox(height: 14),
                _buildAutomationStatusWidget(s, theme),
              ],

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
                onPressed: _sendingTest || (!_state.isReady && !_accountsList.any((a) => a.isReady)) ? null : _sendTestMessage,
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

  // --- ONGLET 2: SUPER ADMIN - JESYON AKSÈ WHATSAPP POU GYM YO ---

  Widget _buildSuperAdminGymsView(AppStrings s, ThemeData theme) {
    final query = _gymSearchController.text.trim().toLowerCase();
    final filteredGyms = _gymsAccessList.where((g) {
      if (query.isEmpty) return true;
      return g.gymName.toLowerCase().contains(query) ||
          g.gymCode.toLowerCase().contains(query) ||
          g.gymPhone.toLowerCase().contains(query);
    }).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        Row(
          children: [
            const Icon(LucideIcons.crown, color: Colors.amber, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.text('whatsapp_gym_access_title'),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.text('whatsapp_gym_access_desc'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Search Bar
        TextField(
          controller: _gymSearchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: s.text('whatsapp_search_gym_hint'),
            prefixIcon: const Icon(LucideIcons.search),
            suffixIcon: _gymSearchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => setState(() => _gymSearchController.clear()),
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),

        if (_loadingGyms)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          )
        else if (filteredGyms.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                s.text('whatsapp_no_gyms_found'),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              ),
            ),
          )
        else
          ...filteredGyms.map((g) => _buildGymAccessCard(g, s, theme)),
      ],
    );
  }

  Widget _buildGymAccessCard(GymWhatsAppAccess gym, AppStrings s, ThemeData theme) {
    final df = DateFormat('dd/MM/yyyy');
    final isSuspended = gym.status == 'suspended';
    final isActive = gym.status == 'active' && gym.isValid;
    final isExpired = gym.status == 'expired';

    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (isActive) {
      badgeColor = Colors.green;
      badgeText = '${s.text('whatsapp_status_active')} (${gym.daysRemaining}j)';
      badgeIcon = LucideIcons.circleCheck;
    } else if (isSuspended) {
      badgeColor = Colors.orange.shade800;
      badgeText = s.text('whatsapp_status_suspended');
      badgeIcon = LucideIcons.pauseCircle;
    } else if (isExpired) {
      badgeColor = Colors.red;
      badgeText = s.text('whatsapp_status_expired');
      badgeIcon = LucideIcons.clock;
    } else {
      badgeColor = Colors.grey;
      badgeText = s.text('whatsapp_status_inactive');
      badgeIcon = LucideIcons.circleOff;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive ? Colors.green.shade300 : (isSuspended ? Colors.orange.shade300 : theme.dividerColor),
          width: isActive || isSuspended ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            gym.gymName,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              gym.gymCode,
                              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                            ),
                          ),
                        ],
                      ),
                      if (gym.gymPhone.isNotEmpty)
                        Text(
                          '${s.text('whatsapp_contact_label')} ${gym.gymPhone}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                        ),
                      if (gym.backupPhone.isNotEmpty)
                        Text(
                          '${s.text('whatsapp_backup_number_opt_label')}: ${gym.backupPhone}',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: badgeColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, color: badgeColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        badgeText,
                        style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Peryòd valab
            if (gym.startDate != null && gym.endDate != null) ...[
              Row(
                children: [
                  const Icon(LucideIcons.calendar, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    '${s.text('whatsapp_period_display')} ${df.format(gym.startDate!)} → ${df.format(gym.endDate!)}',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Aksyon sou gym nan
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Bouton Bay Aksè / Modifye
                FilledButton.tonalIcon(
                  onPressed: () => _showEditGymAccessDialog(gym),
                  icon: const Icon(LucideIcons.edit3, size: 15),
                  label: Text(s.text('whatsapp_grant_access_btn')),
                ),

                // Bouton Sispann / Relanse
                if (gym.isEnabled) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isSuspended ? Colors.green : Colors.orange.shade800,
                      side: BorderSide(color: isSuspended ? Colors.green : Colors.orange.shade800),
                    ),
                    onPressed: () => _quickToggleSuspend(gym),
                    icon: Icon(isSuspended ? LucideIcons.play : LucideIcons.pause, size: 15),
                    label: Text(isSuspended ? s.text('whatsapp_resume_btn') : s.text('whatsapp_suspend_btn')),
                  ),
                ],

                // Bouton Renouvle +1 Mwa
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                  onPressed: () => _quickRenewMonth(gym),
                  icon: const Icon(LucideIcons.plusCircle, size: 15),
                  label: Text(s.text('whatsapp_renew_1m_btn')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutomationStatusWidget(AppStrings s, ThemeData theme) {
    final notifService = ref.watch(whatsAppNotificationServiceProvider);
    final lastCheck = notifService.lastAutoCheckTime;
    final lastCount = notifService.lastAutoSentCount;
    final isChecking = notifService.isAutoChecking;
    final dfTime = DateFormat('HH:mm');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E).withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0F766E).withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.bot, color: Color(0xFF0F766E), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.text('whatsapp_auto_reminders_active'),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E), fontSize: 13),
                      ),
                    ),
                    if (isChecking)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F766E)),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  s.text('whatsapp_auto_reminders_desc_active'),
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.teal.shade900),
                ),
                if (lastCheck != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${s.text('whatsapp_last_auto_check')} ${dfTime.format(lastCheck)} ($lastCount ${s.text('whatsapp_reminders_sent_badge')})',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _checkingExpirations ? null : _runManualExpirationCheck,
                  icon: _checkingExpirations
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(LucideIcons.refreshCw, size: 14),
                  label: Text(_checkingExpirations ? 'V\u00e9rification en cours...' : 'V\u00e9rifier & Mettre en file d\'attente'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F766E),
                    side: const BorderSide(color: Color(0xFF0F766E)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  bool _checkingExpirations = false;
  Future<void> _runManualExpirationCheck() async {
    if (_checkingExpirations) return;
    setState(() => _checkingExpirations = true);
    final s = AppStrings.of(context);
    try {
      final res = await ref.read(whatsAppClientProvider).triggerExpirationCheck();
      if (res != null && mounted) {
        final queued = (res['queued_count'] as num?)?.toInt() ?? 0;
        final gyms = (res['gyms_processed'] as num?)?.toInt() ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verifikasyon fini : ' + queued.toString() + ' rap\u00e8l anrejistre pou ' + gyms.toString() + ' gym.'),
            backgroundColor: Colors.teal.shade800,
          ),
        );
        await _checkStatus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Er\u00e8: ' + e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingExpirations = false);
    }
  }

  Future<void> _triggerExpirationCheckForGym(String gymId, String gymName) async {
    try {
      final res = await ref.read(whatsAppClientProvider).triggerExpirationCheck(targetGymId: gymId);
      if (res != null && mounted) {
        final queued = (res['queued_count'] as num?)?.toInt() ?? 0;
        if (queued > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(queued.toString() + ' nouvo rap\u00e8l d\'\u00e9ch\u00e9ance prepare pou manm ' + gymName + ' yo!'),
              backgroundColor: Colors.teal.shade700,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[WhatsApp] Er\u00e8 cron check: ' + e.toString());
    }
  }


  Future<void> _loadAccountsList() async {
    try {
      final list = await ref.read(whatsAppClientProvider).fetchAccountsList();
      if (mounted) {
        setState(() => _accountsList = list);
      }
    } catch (_) {}
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildClusterAccountsCard(AppStrings s, ThemeData theme) {
    final totalLines = _accountsList.length;
    final readyLines = _accountsList.where((a) => a.isReady).length;
    final restrictedLines = _accountsList.where((a) => a.isRestricted).length;
    final totalSentToday = _accountsList.fold<int>(0, (sum, a) => sum + a.sentToday);
    final totalDailyCapacity = _accountsList.where((a) => a.isReady).fold<int>(0, (sum, a) => sum + a.dailyLimit);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.network, color: Color(0xFF1EBE5D), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Cluster WhatsApp Multi-Liy',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.blue.shade300),
                            ),
                            child: Text(
                              'Anti-Bann & Distribisyon',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Distribye mesaj yo sou plizyè nimewo avèk delè sekirite (25s-50s) pou evite WhatsApp bloke nimewo.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showAddAccountDialog,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Ajoute Liy WhatsApp'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F766E),
                    side: const BorderSide(color: Color(0xFF0F766E)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Summary Stats Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _buildStatItem('Liy Aktif', '$readyLines / $totalLines', readyLines > 0 ? Colors.green.shade700 : Colors.orange.shade800),
                  const SizedBox(width: 24),
                  _buildStatItem('Liy Restreint (24h)', '$restrictedLines', restrictedLines > 0 ? Colors.red.shade700 : Colors.grey.shade600),
                  const SizedBox(width: 24),
                  _buildStatItem('Mesaj Voye Jodi a', '$totalSentToday', Colors.blue.shade700),
                  const SizedBox(width: 24),
                  _buildStatItem('Kapasite Sekirize / Jou', readyLines > 0 ? 'Jouk $totalDailyCapacity msg' : '0 msg', Colors.teal.shade800),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Lis Chak Liy
            if (_accountsList.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Column(
                children: _accountsList.map((acc) => _buildSingleAccountCard(acc, s, theme)).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleAccountCard(WhatsAppAccountInfo acc, AppStrings s, ThemeData theme) {
    final isReady = acc.isReady;
    final isWaitingQr = acc.isWaitingForQr;
    final isRestricted = acc.isRestricted;
    final isError = acc.isError;
    final isDisconnected = acc.isDisconnected;

    Color cardBorder;
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (isRestricted) {
      cardBorder = Colors.red.shade400;
      badgeColor = Colors.red.shade700;
      badgeText = '🔴 Restreint (24h)';
      badgeIcon = LucideIcons.shieldAlert;
    } else if (isReady) {
      cardBorder = Colors.green.shade400;
      badgeColor = Colors.green.shade700;
      badgeText = '🟢 Konekte & Pare';
      badgeIcon = LucideIcons.circleCheck;
    } else if (isWaitingQr) {
      cardBorder = Colors.amber.shade600;
      badgeColor = Colors.amber.shade800;
      badgeText = '📷 Eskane Kòd QR';
      badgeIcon = LucideIcons.qrCode;
    } else if (isError) {
      cardBorder = Colors.red.shade300;
      badgeColor = Colors.red.shade800;
      badgeText = '❌ Erè Koneksyon';
      badgeIcon = LucideIcons.alertTriangle;
    } else if (isDisconnected) {
      cardBorder = Colors.grey.shade400;
      badgeColor = Colors.grey.shade700;
      badgeText = '⚪ Dekonekte';
      badgeIcon = LucideIcons.powerOff;
    } else {
      cardBorder = Colors.blue.shade300;
      badgeColor = Colors.blue.shade700;
      badgeText = '⏳ Ap inisyalize...';
      badgeIcon = LucideIcons.loader;
    }

    String? remainingText;
    if (isRestricted && acc.restrictedUntil != null) {
      final diff = acc.restrictedUntil!.difference(DateTime.now());
      if (diff.isNegative) {
        remainingText = 'Restriksyon fini';
      } else {
        remainingText = '${diff.inHours}h ${diff.inMinutes % 60}m k ap rete';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRestricted
            ? Colors.red.shade50.withOpacity(0.4)
            : isReady
                ? Colors.green.shade50.withOpacity(0.3)
                : isWaitingQr
                    ? Colors.amber.shade50.withOpacity(0.3)
                    : isError
                        ? Colors.red.shade50.withOpacity(0.25)
                        : isDisconnected
                            ? Colors.grey.shade100.withOpacity(0.5)
                            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(badgeIcon, color: badgeColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'Liy ${acc.accountIndex} : ${acc.label}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (acc.phoneNumber != null && acc.phoneNumber!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          acc.phoneNumber!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: badgeColor.withOpacity(0.4)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: badgeColor),
                ),
              ),
            ],
          ),

          // 1. KONT RESTREINT (24H)
          if (isRestricted) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade100.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.alertCircle, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'WhatsApp te limite nimewo sa a pou 24h. Sistèm nan mete l sou kote pou l pa voye mesaj sou li jiskaske peryòd la fini ($remainingText). Tout rès mesaj yo ap voye sou lòt liy aktif yo.',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final ok = await ref.read(whatsAppClientProvider).unrestrictAccount(acc.accountIndex);
                      if (ok) {
                        await _loadAccountsList();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Liy ${acc.accountIndex} debloke manyèlman.'), backgroundColor: Colors.teal),
                          );
                        }
                      }
                    },
                    child: const Text('Debloke Manyèlman', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],

          // 2. ERÈ KONEKSYON
          if (isError) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade100.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.alertOctagon, color: Colors.red, size: 16),
                      const SizedBox(width: 6),
                      const Text(
                        'Koneksyon an te rankontre yon pwoblèm :',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    acc.lastError ?? 'Sesyon WhatsApp sa a bezwen netwaye oswa rekonekte.',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          await ref.read(whatsAppClientProvider).resetAccountSession(acc.accountIndex);
                          await _loadAccountsList();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Sesyon Liy ${acc.accountIndex} netwaye. Nouvo QR ap prepare...'), backgroundColor: Colors.teal),
                            );
                          }
                        },
                        icon: const Icon(LucideIcons.refreshCw, size: 13),
                        label: const Text('Reyinisyalize & Eskane Nouvo QR'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await ref.read(whatsAppClientProvider).restartAccount(acc.accountIndex);
                          await _loadAccountsList();
                        },
                        icon: const Icon(LucideIcons.play, size: 13),
                        label: const Text('Re-eseye'),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // 3. DEKONEKTE (Disponib pou konekte)
          if (isDisconnected) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.smartphone, color: Colors.grey, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Liy sa a pare pou konekte yon nimewo WhatsApp. Klike sou bouton an pou w ka eskane yon kòd QR.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () async {
                      await ref.read(whatsAppClientProvider).restartAccount(acc.accountIndex);
                      await _loadAccountsList();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Liy ${acc.accountIndex} ap demare pou prepare kòd QR la...'), backgroundColor: Colors.teal),
                        );
                      }
                    },
                    icon: const Icon(LucideIcons.qrCode, size: 14),
                    label: const Text('Kòmanse & Eskane QR'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1EBE5D),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 4. AFICHAJ KÒD QR LA DIRÈKTEMAN SOU KAT LA SI L AP TANN ESKANÈ!
          if (isWaitingQr) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade500, width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 150,
                    height: 150,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: acc.qrCode != null && acc.qrCode!.contains(',')
                        ? Image.memory(
                            base64Decode(acc.qrCode!.split(',')[1]),
                            fit: BoxFit.contain,
                          )
                        : (acc.qrCode != null && acc.qrCode!.isNotEmpty)
                            ? QrImageView(
                                data: acc.qrCode!,
                                version: QrVersions.auto,
                                size: 140,
                                gapless: false,
                              )
                            : const Center(child: CircularProgressIndicator()),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.qrCode, color: Color(0xFF1EBE5D), size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Kòd QR pou ${acc.label}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '1. Louvri WhatsApp sou telefòn ou.\n2. Klike 3 pwen anlè a > "Aparèy Konekte".\n3. Verifye ou pa gen plis pase 4 aparèy konekte deja.\n4. Klike "Konekte yon aparèy" epi vize kamera a sou kòd sa a.',
                          style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _showQrDialog(acc),
                              icon: const Icon(LucideIcons.expand, size: 13),
                              label: const Text('Agrandi'),
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await ref.read(whatsAppClientProvider).restartAccount(acc.accountIndex);
                                await _loadAccountsList();
                              },
                              icon: const Icon(LucideIcons.refreshCw, size: 13),
                              label: const Text('Rafrechi QR'),
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await ref.read(whatsAppClientProvider).resetAccountSession(acc.accountIndex);
                                await _loadAccountsList();
                              },
                              icon: const Icon(LucideIcons.trash2, size: 13, color: Colors.red),
                              label: const Text('Netwaye', style: TextStyle(color: Colors.red)),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                side: BorderSide(color: Colors.red.shade200),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Action row
          Row(
            children: [
              Text(
                'Voye jodi a: ${acc.sentToday} / ${acc.dailyLimit} msg  •  Total: ${acc.totalSent}',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (isReady) ...[
                FilledButton.tonalIcon(
                  onPressed: () => _showExpandedChatDialog(acc),
                  icon: const Icon(LucideIcons.maximize2, size: 13),
                  label: const Text('Agrandir'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await ref.read(whatsAppClientProvider).restartAccount(acc.accountIndex);
                    if (ok) {
                      await _loadAccountsList();
                    }
                  },
                  icon: const Icon(LucideIcons.refreshCw, size: 12),
                  label: const Text('Rekonekte'),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('Reyinisyalize Liy ${acc.accountIndex} ?'),
                        content: const Text('Sa pral dekonekte nimewo sa a pou w ka eskane yon lòt nimewo ak yon nouvo kòd QR.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anile')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Wi, Reyinisyalize')),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(whatsAppClientProvider).resetAccountSession(acc.accountIndex);
                      await _loadAccountsList();
                    }
                  },
                  icon: const Icon(LucideIcons.power, size: 12, color: Colors.red),
                  label: const Text('Chanje Nimewo', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                ),
              ] else if (!isWaitingQr && !isError && !isDisconnected) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(whatsAppClientProvider).restartAccount(acc.accountIndex);
                    await _loadAccountsList();
                  },
                  icon: const Icon(LucideIcons.refreshCw, size: 12),
                  label: const Text('Rafrechi'),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showQrDialog(WhatsAppAccountInfo account) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final liveAcc = _accountsList.firstWhere(
            (a) => a.accountIndex == account.accountIndex,
            orElse: () => account,
          );

          return AlertDialog(
            title: Row(
              children: [
                const Icon(LucideIcons.qrCode, color: Color(0xFF1EBE5D)),
                const SizedBox(width: 10),
                Text('Eskane Kòd QR - ${liveAcc.label}'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Louvri WhatsApp sou telefòn ou > Klike sou 3 pwen anlè a > Aparèy Konekte > Konekte yon aparèy',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: liveAcc.qrCode != null && liveAcc.qrCode!.contains(',')
                      ? Image.memory(
                          base64Decode(liveAcc.qrCode!.split(',')[1]),
                          width: 220,
                          height: 220,
                        )
                      : (liveAcc.qrCode != null && liveAcc.qrCode!.isNotEmpty)
                          ? QrImageView(
                              data: liveAcc.qrCode!,
                              version: QrVersions.auto,
                              size: 220,
                              gapless: false,
                            )
                          : const SizedBox(
                              width: 220,
                              height: 220,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                ),
                const SizedBox(height: 12),
                if (liveAcc.isReady) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(LucideIcons.circleCheck, color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Text('Konekte avèk siksè !', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ] else ...[
                  const Text('Kòd la ap rafrechi otomatikman si w pa eskane l.', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fèmen'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddAccountDialog() {
    final labelCtrl = TextEditingController(text: 'Liy ' + (_accountsList.length + 1).toString());
    final limitCtrl = TextEditingController(text: '40');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(LucideIcons.plusCircle, color: Color(0xFF0F766E)),
            SizedBox(width: 10),
            Text('Ajoute yon Liy WhatsApp'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chak nouvo liy WhatsApp pèmèt ou ogmante kapasite voye mesaj ou chak jou san risk pou nimewo w bloke.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Non / Tit Liy la',
                hintText: 'Egz: JL Telefòn Sekretè, Telefòn 2...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: limitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Limit Mesaj Sekirite pa Jou',
                hintText: '40',
                helperText: '40 mesaj rekòmande pou evite restriksyon WhatsApp.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anile'),
          ),
          FilledButton(
            onPressed: () async {
              final label = labelCtrl.text.trim();
              final limit = int.tryParse(limitCtrl.text.trim()) ?? 40;
              Navigator.pop(ctx);
              final ok = await ref.read(whatsAppClientProvider).createAccountSlot(
                    label: label.isNotEmpty ? label : 'Liy ' + (_accountsList.length + 1).toString(),
                    dailyLimit: limit,
                  );
              if (ok) {
                await _loadAccountsList();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Nouvo liy WhatsApp kreye! Sèvis la ap prepare kòd QR la.'),
                    backgroundColor: Colors.teal,
                  ),
                );
              }
            },
            child: const Text('Kreye Liy la'),
          ),
        ],
      ),
    );
  }

  // --- ONGLET 3: SUPER ADMIN - KONTRÒL MESAJ YO (ANTI-DOUBLON & J-7/J-2 OTOMATIK) ---

  Future<void> _loadControlOverview({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingControl = true);
    }
    final data = await ref.read(whatsAppClientProvider).fetchControlOverview();
    if (!mounted) return;
    setState(() {
      if (data != null) _controlData = data;
      _loadingControl = false;
    });
  }

  void _startControlAutoLoop() {
    _controlAutoTimer?.cancel();
    _controlAutoTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted || _selectedTabIndex != 2) return;
      if (_controlAutoVerifyEnabled && !_dispatchingControlBatch) {
        await _runControlDispatchBatch(
          includeMissed: true,
          includeRenewals: true,
          retryFailed: false,
          silent: true,
        );
      } else {
        await _loadControlOverview(silent: true);
      }
    });
  }

  Future<void> _runControlDispatchBatch({
    required bool includeMissed,
    required bool includeRenewals,
    required bool retryFailed,
    bool silent = false,
  }) async {
    if (_dispatchingControlBatch) return;
    if (mounted) setState(() => _dispatchingControlBatch = true);
    try {
      final res = await ref.read(whatsAppClientProvider).dispatchControlBatch(
            includeMissedRegistrations: includeMissed,
            includeRenewals: includeRenewals,
            retryFailed: retryFailed,
          );
      await _loadControlOverview(silent: true);
      if (!mounted || silent || res == null) return;
      final qw = (res['queued_welcome'] as num?)?.toInt() ?? 0;
      final qr = (res['queued_renewals'] as num?)?.toInt() ?? 0;
      final rf = (res['retried_failed'] as num?)?.toInt() ?? 0;
      final sk = (res['skipped_duplicates'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Vérification anti-doublon : $qw bienvenue, $qr rappels J-7/J-2, $rf relances ($sk doublons évités).',
          ),
          backgroundColor: const Color(0xFF0F766E),
        ),
      );
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erè : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _dispatchingControlBatch = false);
    }
  }

  Widget _buildControlOverviewView(AppStrings s, ThemeData theme) {
    final data = _controlData;
    final summary = data != null && data['summary'] is Map
        ? Map<String, dynamic>.from(data['summary'] as Map)
        : const <String, dynamic>{};
    final gyms = (data?['subscribed_gyms'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final priority = (data?['priority_queue'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final missed = (data?['missed_registrations'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final renewals = (data?['renewal_candidates'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final recent = (data?['recent_logs'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final subscribedCount = (summary['subscribed_gyms_count'] as num?)?.toInt() ?? gyms.length;
    final readyLines = (summary['ready_lines'] as num?)?.toInt() ??
        _accountsList.where((a) => a.isReady).length;
    final pendingCount = (summary['pending_outbox'] as num?)?.toInt() ?? 0;
    final failedCount = (summary['failed_outbox'] as num?)?.toInt() ?? 0;
    final missedCount = (summary['missed_registrations_count'] as num?)?.toInt() ?? missed.length;
    final renewalCount = (summary['renewal_candidates_count'] as num?)?.toInt() ?? renewals.length;
    final sent24h = (summary['sent_24h'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      onRefresh: () => _loadControlOverview(silent: false),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: [
          // Header Intelligence Automatique
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: const Color(0xFF0F766E).withOpacity(0.35), width: 1.5),
            ),
            color: const Color(0xFF0F766E).withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.bot, color: Color(0xFF0F766E), size: 24),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Contrôle Intelligent des Messages (Anti-Doublon · J-7 & J-2)',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_loadingControl || _dispatchingControlBatch)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Surveille les salles abonnées, récupère les inscriptions faites hors ligne et envoie strictement les rappels J-7 et J-2. '
                    'Vérifie automatiquement les journaux et la file avant chaque envoi : aucun numéro ne reçoit 2 fois le même message '
                    '(seul un J-7 suivi d\'un J-2 à l\'approche du renouvellement est autorisé).',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        selected: _controlAutoVerifyEnabled,
                        avatar: const Icon(LucideIcons.sparkles, size: 15),
                        label: Text(
                          _controlAutoVerifyEnabled
                              ? 'Intelligence Auto : ACTIVE (20s)'
                              : 'Intelligence Auto : Pause',
                        ),
                        onSelected: (v) {
                          setState(() => _controlAutoVerifyEnabled = v);
                          if (v) {
                            _runControlDispatchBatch(
                              includeMissed: true,
                              includeRenewals: true,
                              retryFailed: false,
                              silent: false,
                            );
                          }
                        },
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                        onPressed: _dispatchingControlBatch
                            ? null
                            : () => _runControlDispatchBatch(
                                  includeMissed: true,
                                  includeRenewals: true,
                                  retryFailed: true,
                                ),
                        icon: const Icon(LucideIcons.send, size: 15),
                        label: const Text('Tout Analyser & Envoyer en Groupe'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loadingControl ? null : () => _loadControlOverview(silent: false),
                        icon: const Icon(LucideIcons.refreshCw, size: 15),
                        label: const Text('Rafraîchir'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // KPI Chips Grid
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _controlKpiCard('Salles abonnées', '$subscribedCount', LucideIcons.building2, Colors.teal),
              _controlKpiCard('Lignes prêtes', '$readyLines', LucideIcons.smartphone, readyLines > 0 ? Colors.green : Colors.red),
              _controlKpiCard('En attente', '$pendingCount', LucideIcons.clock, Colors.amber.shade800),
              _controlKpiCard('Échecs à relancer', '$failedCount', LucideIcons.alertTriangle, failedCount > 0 ? Colors.red : Colors.grey),
              _controlKpiCard('Inscriptions ratées', '$missedCount', LucideIcons.userPlus, Colors.indigo),
              _controlKpiCard('Renouvellements J-7 / J-2', '$renewalCount', LucideIcons.calendarClock, Colors.deepOrange),
              _controlKpiCard('Envoyés (24h)', '$sent24h', LucideIcons.checkCheck, Colors.green.shade700),
            ],
          ),
          const SizedBox(height: 22),

          // 1. Inscriptions hors ligne sans message de bienvenue
          _controlSectionHeader(
            icon: LucideIcons.userPlus,
            color: Colors.indigo,
            title: 'Inscriptions récentes sans message ($missedCount)',
            subtitle: 'Membres inscrits pendant que le PC était éteint — vérifiés anti-doublon.',
            action: missed.isNotEmpty
                ? FilledButton.tonalIcon(
                    onPressed: _dispatchingControlBatch
                        ? null
                        : () => _runControlDispatchBatch(
                              includeMissed: true,
                              includeRenewals: false,
                              retryFailed: false,
                            ),
                    icon: const Icon(LucideIcons.send, size: 14),
                    label: Text('Envoyer Bienvenue (${missed.length})'),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          if (missed.isEmpty)
            _emptyInfoCard('Toutes les inscriptions récentes ont déjà reçu ou sont en file pour leur message de bienvenue.')
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.dividerColor),
              ),
              child: Column(
                children: [
                  for (final m in missed.take(25))
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.indigo.withOpacity(0.12),
                        child: const Icon(LucideIcons.userCheck, size: 15, color: Colors.indigo),
                      ),
                      title: Text('${m['member_name'] ?? 'Membre'} (${m['member_number'] ?? ''})',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text('${m['gym_name'] ?? ''} · +${m['clean_phone'] ?? ''}'),
                      trailing: Chip(
                        label: const Text('Bienvenue en attente', style: TextStyle(fontSize: 11)),
                        backgroundColor: Colors.indigo.withOpacity(0.08),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 22),

          // 2. Renouvellements STRICTEMENT J-7 et J-2
          _controlSectionHeader(
            icon: LucideIcons.calendarClock,
            color: Colors.deepOrange,
            title: 'Renouvellements à envoyer — J-7 & J-2 uniquement ($renewalCount)',
            subtitle: 'Jamais J-0 ni J-1. Un numéro notifié à J-7 ne reçoit ensuite que J-2 (pas de doublon).',
            action: renewals.isNotEmpty
                ? FilledButton.tonalIcon(
                    onPressed: _dispatchingControlBatch
                        ? null
                        : () => _runControlDispatchBatch(
                              includeMissed: false,
                              includeRenewals: true,
                              retryFailed: false,
                            ),
                    icon: const Icon(LucideIcons.bellRing, size: 14),
                    label: Text('Envoyer J-7 / J-2 (${renewals.length})'),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          if (renewals.isEmpty)
            _emptyInfoCard('Aucun membre à J-7 ou J-2 en attente d\'envoi.')
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.dividerColor),
              ),
              child: Column(
                children: [
                  for (final r in renewals.take(30))
                    ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (r['days_left'] == 2 ? Colors.red : Colors.amber.shade800).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'J-${r['days_left']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: r['days_left'] == 2 ? Colors.red.shade800 : Colors.amber.shade900,
                          ),
                        ),
                      ),
                      title: Text('${r['member_name'] ?? 'Membre'} · ${r['plan_name'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text('${r['gym_name'] ?? ''} · +${r['clean_phone'] ?? ''} · Fin : ${r['end_date'] ?? ''}'),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 22),

          // 3. Messages en priorité / en attente / en échec
          _controlSectionHeader(
            icon: LucideIcons.listOrdered,
            color: Colors.amber.shade800,
            title: 'File prioritaire & Échecs (${priority.length})',
            subtitle: 'Messages à envoyer en priorité dès que la passerelle PC est allumée.',
            action: failedCount > 0
                ? OutlinedButton.icon(
                    onPressed: _dispatchingControlBatch
                        ? null
                        : () => _runControlDispatchBatch(
                              includeMissed: false,
                              includeRenewals: false,
                              retryFailed: true,
                            ),
                    icon: const Icon(LucideIcons.rotateCcw, size: 14),
                    label: Text('Relancer échecs ($failedCount)'),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          if (priority.isEmpty)
            _emptyInfoCard('File d\'attente vide : aucun message bloqué ou en échec.')
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.dividerColor),
              ),
              child: Column(
                children: [
                  for (final p in priority.take(30))
                    ListTile(
                      dense: true,
                      leading: Icon(
                        p['status'] == 'failed'
                            ? LucideIcons.alertCircle
                            : p['status'] == 'processing'
                                ? LucideIcons.loader
                                : LucideIcons.clock,
                        color: p['status'] == 'failed'
                            ? Colors.red
                            : p['status'] == 'processing'
                                ? Colors.blue
                                : Colors.amber.shade800,
                        size: 18,
                      ),
                      title: Text(
                        '[${(p['kind'] ?? 'manual').toString().toUpperCase()}] +${p['to_phone'] ?? ''} · ${p['gym_name'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      subtitle: Text(
                        p['status'] == 'failed' && (p['error_message']?.toString().isNotEmpty ?? false)
                            ? '${p['error_message']}'
                            : '${p['message_preview'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: p['status'] == 'failed'
                          ? TextButton(
                              onPressed: () async {
                                final ok = await ref.read(whatsAppClientProvider).retryOutboxItem(p['id'].toString());
                                if (ok) await _loadControlOverview(silent: true);
                              },
                              child: const Text('Relancer'),
                            )
                          : Text(
                              p['has_pdf'] == true ? 'PDF' : '${p['status']}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 22),

          // 4. Liste des salles abonnées à WhatsApp
          _controlSectionHeader(
            icon: LucideIcons.building2,
            color: Colors.teal,
            title: 'Salles avec abonnement WhatsApp (${gyms.length})',
            subtitle: 'État de l\'abonnement et compteurs de messages par salle.',
          ),
          const SizedBox(height: 8),
          if (gyms.isEmpty)
            _emptyInfoCard('Aucune salle configurée dans les abonnements WhatsApp.')
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.dividerColor),
              ),
              child: Column(
                children: [
                  for (final g in gyms)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        g['is_valid'] == true ? LucideIcons.circleCheck : LucideIcons.pauseCircle,
                        color: g['is_valid'] == true ? Colors.green : Colors.red.shade600,
                        size: 18,
                      ),
                      title: Text('${g['gym_name'] ?? ''} (${g['gym_code'] ?? ''})',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text(
                        '${g['status'] == 'active' ? 'Actif (${g['days_remaining']}j)' : g['status']} · En attente: ${g['pending_count'] ?? 0} · Échecs: ${g['failed_count'] ?? 0}',
                      ),
                      trailing: Text(
                        '${g['sent_today_count'] ?? 0} / 24h',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 22),

          // 5. Derniers envois confirmés
          _controlSectionHeader(
            icon: LucideIcons.history,
            color: Colors.grey.shade700,
            title: 'Historique récent anti-doublon (${recent.length})',
            subtitle: 'Numéros déjà notifiés (utilisé pour bloquer tout envoi en double).',
          ),
          const SizedBox(height: 8),
          if (recent.isEmpty)
            _emptyInfoCard('Aucun envoi enregistré pour le moment.')
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.dividerColor),
              ),
              child: Column(
                children: [
                  for (final r in recent.take(20))
                    ListTile(
                      dense: true,
                      leading: const Icon(LucideIcons.checkCheck, color: Colors.green, size: 16),
                      title: Text('${r['recipient_name'] ?? r['recipient_phone']} (+${r['recipient_phone']})',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      subtitle: Text('${r['gym_name'] ?? ''} · ${r['kind'] ?? ''}'),
                      trailing: Text(
                        _formatIsoShort(r['created_at']?.toString()),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _controlKpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                Text(label, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlSectionHeader({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        ?action,
      ],
    );
  }

  Widget _emptyInfoCard(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    );
  }

  String _formatIsoShort(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return DateFormat('dd/MM HH:mm').format(dt);
  }

  void _showExpandedChatDialog(WhatsAppAccountInfo account) {
    showDialog(
      context: context,
      builder: (ctx) => _WhatsAppChatViewerDialog(
        account: account,
        client: WhatsAppClient(baseUrl: _gatewayUrlController.text.trim()),
      ),
    );
  }

}

/// Fenêtre Agrandie Interactive pou wè ak reponn mesaj WhatsApp dirèkteman sou liy konekte a
class _WhatsAppChatViewerDialog extends StatefulWidget {
  const _WhatsAppChatViewerDialog({
    required this.account,
    required this.client,
  });

  final WhatsAppAccountInfo account;
  final WhatsAppClient client;

  @override
  State<_WhatsAppChatViewerDialog> createState() => _WhatsAppChatViewerDialogState();
}

class _WhatsAppChatViewerDialogState extends State<_WhatsAppChatViewerDialog> {
  final _searchCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<WhatsAppChatSummary> _chats = [];
  WhatsAppChatSummary? _selectedChat;
  List<WhatsAppChatMessage> _messages = [];
  bool _loadingChats = true;
  bool _loadingMessages = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    setState(() {
      _loadingChats = true;
      _error = null;
    });
    try {
      final list = await widget.client.fetchAccountChats(widget.account.accountIndex);
      if (!mounted) return;
      setState(() {
        _chats = list;
        _loadingChats = false;
      });
      if (_selectedChat == null && list.isNotEmpty) {
        await _selectChat(list.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingChats = false;
        _error = '$e';
      });
    }
  }

  Future<void> _selectChat(WhatsAppChatSummary chat) async {
    setState(() {
      _selectedChat = chat;
      _loadingMessages = true;
      _error = null;
    });
    try {
      final msgs = await widget.client.fetchChatMessages(widget.account.accountIndex, chat.id);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loadingMessages = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMessages = false;
        _error = '$e';
      });
    }
  }

  void _openPhoneDirect(String rawPhone) {
    final clean = WhatsAppClient.normalizePhone(rawPhone);
    if (clean.length < 8) return;
    final temp = WhatsAppChatSummary(
      id: '$clean@c.us',
      name: '+$clean',
      phone: clean,
    );
    _selectChat(temp);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendReply() async {
    final chat = _selectedChat;
    final text = _msgCtrl.text.trim();
    if (chat == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await widget.client.sendChatMessage(widget.account.accountIndex, chat.id, text);
      if (!mounted) return;
      _msgCtrl.clear();
      setState(() {
        _sending = false;
        if (sent != null) {
          _messages = [..._messages, sent];
        }
      });
      _scrollToBottom();
      // Refresh messages shortly for sync consistency
      final refreshed = await widget.client.fetchChatMessages(widget.account.accountIndex, chat.id);
      if (mounted && refreshed.isNotEmpty) {
        setState(() => _messages = refreshed);
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec envoi : $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context).size;
    final width = (mq.width * 0.9).clamp(340.0, 1080.0);
    final height = (mq.height * 0.85).clamp(420.0, 760.0);
    final isCompact = width < 700;

    final query = _searchCtrl.text.trim().toLowerCase();
    final filteredChats = _chats.where((c) {
      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query) ||
          c.phone.toLowerCase().contains(query) ||
          c.lastMessageBody.toLowerCase().contains(query);
    }).toList();
    final queryDigits = WhatsAppClient.normalizePhone(_searchCtrl.text.trim());

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            // Top bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF0F766E),
              child: Row(
                children: [
                  const Icon(LucideIcons.messageSquare, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WhatsApp Web — Liy ${widget.account.accountIndex} : ${widget.account.label}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (widget.account.phoneNumber != null)
                          Text(
                            '+${widget.account.phoneNumber} ${widget.account.pushName ?? ''}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rafraîchir',
                    icon: const Icon(LucideIcons.refreshCw, color: Colors.white, size: 18),
                    onPressed: _loadChats,
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    icon: const Icon(LucideIcons.x, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: Colors.red.shade50,
                child: Text(_error!, style: TextStyle(color: Colors.red.shade900, fontSize: 12)),
              ),

            Expanded(
              child: isCompact
                  ? (_selectedChat == null
                      ? _buildChatSidebar(theme, filteredChats, queryDigits)
                      : Column(
                          children: [
                            ListTile(
                              dense: true,
                              leading: const Icon(LucideIcons.arrowLeft, size: 18),
                              title: Text('Conversations (${_chats.length})'),
                              onTap: () => setState(() => _selectedChat = null),
                            ),
                            const Divider(height: 1),
                            Expanded(child: _buildMessagePane(theme)),
                          ],
                        ))
                  : Row(
                      children: [
                        SizedBox(
                          width: 310,
                          child: _buildChatSidebar(theme, filteredChats, queryDigits),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildMessagePane(theme)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatSidebar(ThemeData theme, List<WhatsAppChatSummary> filteredChats, String queryDigits) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Rechercher nom ou numéro...',
              prefixIcon: const Icon(LucideIcons.search, size: 16),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, size: 14),
                      onPressed: () => setState(() => _searchCtrl.clear()),
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (queryDigits.length >= 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _openPhoneDirect(queryDigits),
                icon: const Icon(LucideIcons.messageCircle, size: 15),
                label: Text('Écrire au +$queryDigits'),
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: _loadingChats
              ? const Center(child: CircularProgressIndicator())
              : filteredChats.isEmpty
                  ? const Center(child: Text('Aucune conversation trouvée.', style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      itemCount: filteredChats.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final c = filteredChats[i];
                        final selected = _selectedChat?.id == c.id;
                        return ListTile(
                          selected: selected,
                          selectedTileColor: const Color(0xFF0F766E).withOpacity(0.1),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF25D366).withOpacity(0.18),
                            child: Text(
                              c.name.isNotEmpty ? c.name[0].toUpperCase() : '#',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                              if (c.unreadCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF25D366),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${c.unreadCount}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            c.lastMessageHasMedia && c.lastMessageBody.isEmpty
                                ? '📎 Document / Média'
                                : '${c.lastMessageFromMe ? 'Vous : ' : ''}${c.lastMessageBody}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () => _selectChat(c),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildMessagePane(ThemeData theme) {
    final chat = _selectedChat;
    if (chat == null) {
      return const Center(
        child: Text('Sélectionnez une conversation à gauche ou tapez un numéro.', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF0F766E).withOpacity(0.15),
                child: const Icon(LucideIcons.user, size: 16, color: Color(0xFF0F766E)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chat.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (chat.phone.isNotEmpty)
                      Text('+${chat.phone}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Actualiser les messages',
                onPressed: _loadingMessages ? null : () => _selectChat(chat),
                icon: const Icon(LucideIcons.refreshCw, size: 16),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loadingMessages
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? const Center(child: Text('Aucun message dans cette discussion.', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(14),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, idx) {
                        final m = _messages[idx];
                        final ts = m.timestamp > 0
                            ? DateFormat('dd/MM HH:mm').format(
                                DateTime.fromMillisecondsSinceEpoch(m.timestamp * 1000).toLocal(),
                              )
                            : '';
                        return Align(
                          alignment: m.fromMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            constraints: const BoxConstraints(maxWidth: 480),
                            decoration: BoxDecoration(
                              color: m.fromMe
                                  ? const Color(0xFF0F766E).withOpacity(0.15)
                                  : theme.colorScheme.surfaceVariant.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: m.fromMe
                                    ? const Color(0xFF0F766E).withOpacity(0.35)
                                    : theme.dividerColor,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (m.hasMedia)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '📎 Pièce jointe / Média',
                                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.teal),
                                    ),
                                  ),
                                SelectableText(
                                  m.body.isNotEmpty ? m.body : (m.hasMedia ? '(Média)' : ''),
                                  style: const TextStyle(fontSize: 13),
                                ),
                                if (ts.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(ts, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendReply(),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Écrire une réponse WhatsApp...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                onPressed: _sending ? null : _sendReply,
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.send, size: 15),
                label: const Text('Envoyer'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

