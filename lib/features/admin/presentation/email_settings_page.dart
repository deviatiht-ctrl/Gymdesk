import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../l10n/app_strings.dart';

/// Console super admin : configuration du fournisseur d'emails (Brevo).
/// La clé API est en écriture seule : le serveur ne renvoie qu'un indice.
class EmailSettingsPage extends ConsumerStatefulWidget {
  const EmailSettingsPage({super.key});
  @override
  ConsumerState<EmailSettingsPage> createState() => _EmailSettingsPageState();
}

class _EmailSettingsPageState extends ConsumerState<EmailSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _apiKey = TextEditingController();
  final _senderEmail = TextEditingController();
  final _senderName = TextEditingController();
  final _dailyLimit = TextEditingController();
  Map<String, dynamic> _config = const {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _senderEmail.dispose();
    _senderName.dispose();
    _dailyLimit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Supabase.instance.client.rpc('platform_email_config_get');
      final config = Map<String, dynamic>.from(result as Map);
      if (!mounted) return;
      setState(() {
        _config = config;
        _senderEmail.text = config['sender_email']?.toString() ?? '';
        _senderName.text = config['sender_name']?.toString() ?? 'GymDesk';
        _dailyLimit.text = '${config['daily_limit'] ?? 300}';
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'network';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc('platform_email_config_set', params: {
        'p_sender_email': _senderEmail.text.trim(),
        'p_sender_name': _senderName.text.trim(),
        'p_daily_limit': int.parse(_dailyLimit.text.trim()),
        'p_api_key': _apiKey.text.trim(),
      });
      _apiKey.clear();
      messenger.showSnackBar(SnackBar(content: Text(s.text('email_config_saved'))));
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'email_config_save_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
      );
    }
    final counts = Map<String, dynamic>.from(_config['counts'] as Map? ?? const {});
    final hasKey = _config['has_key'] == true;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(s.text('email_settings_title'), style: theme.textTheme.headlineMedium),
            IconButton(onPressed: _busy ? null : _load, icon: const Icon(LucideIcons.refreshCw)),
          ],
        ),
        const SizedBox(height: 8),
        Text(s.text('email_settings_hint'), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Chip(
              avatar: Icon(hasKey ? LucideIcons.circleCheck : LucideIcons.circleX, size: 16),
              label: Text(hasKey ? '${s.text('email_key_set')} ${_config['key_hint'] ?? ''}' : s.text('email_key_missing')),
            ),
            for (final status in ['pending', 'sent', 'failed', 'uncertain'])
              Chip(label: Text('${s.text('email_$status')} : ${counts[status] ?? 0}')),
            if (_config['paused_until'] != null)
              Chip(
                avatar: const Icon(LucideIcons.pause, size: 16),
                label: Text('${s.text('email_pause_until')} : ${_config['paused_until']} (${_config['last_error'] ?? ''})'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(s.text(_error!), style: TextStyle(color: theme.colorScheme.error)),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _apiKey,
                  obscureText: true,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: s.text('email_api_key'),
                    helperText: hasKey ? s.text('email_api_key_keep') : null,
                    prefixIcon: const Icon(LucideIcons.key),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return hasKey ? null : s.text('required');
                    return value.length < 20 ? s.text('invalid_record') : null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _senderEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: s.text('email_sender_email'),
                    helperText: s.text('email_sender_email_hint'),
                    prefixIcon: const Icon(LucideIcons.atSign),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v?.trim() ?? '') ? null : s.text('invalid_email'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _senderName,
                  decoration: InputDecoration(
                    labelText: s.text('email_sender_name'),
                    helperText: s.text('email_sender_name_hint'),
                    prefixIcon: const Icon(LucideIcons.building),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => (v?.trim().length ?? 0) >= 2 ? null : s.text('required'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _dailyLimit,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: s.text('email_daily_limit'),
                    prefixIcon: const Icon(LucideIcons.gauge),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    return n != null && n >= 1 && n <= 1000000 ? null : s.text('invalid_record');
                  },
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(LucideIcons.save),
                  label: Text(s.text('save')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
