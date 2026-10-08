import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../data/settings_repository.dart';
import '../domain/gym_settings.dart';

class BrandingPage extends ConsumerStatefulWidget {
  const BrandingPage({super.key});
  @override
  ConsumerState<BrandingPage> createState() => _BrandingPageState();
}

class _BrandingPageState extends ConsumerState<BrandingPage> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final key in [
      'name',
      'accent_color',
      'timezone',
      'currency',
      'address',
      'phone',
      'email',
      'doc_footer',
      'offline_lease_hours',
      'auto_logout_minutes',
      'pin_lock_minutes',
      'grace_days',
      'entry_duplicate_seconds',
    ])
      key: TextEditingController(),
  };
  late final GymSettingsRepository _repository;
  GymSettings? _gym;
  String? _logoPath;
  String? _signedLogo;
  Uint8List? _logoPreview;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _booleans = {
    'allow_access_pending': false,
    'reception_see_all_payments': false,
    'scan_sound': true,
    'scan_vibrate': true,
  };

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = GymSettingsRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gym = await _repository.current();
      if (!mounted) return;
      setState(() {
        _gym = gym;
        _logoPath = gym.logoUrl;
        _logoPreview = null;
        for (final entry in _fields.entries) {
          entry.value.text = switch (entry.key) {
            'name' => gym.name,
            'accent_color' => gym.accentColor,
            'timezone' => gym.timezone,
            'currency' => gym.currency,
            'address' => gym.address,
            'phone' => gym.phone,
            'email' => gym.email,
            'doc_footer' => gym.settings['doc_footer'] as String? ?? '',
            'offline_lease_hours' =>
              '${gym.settings['offline_lease_hours'] ?? 24}',
            'auto_logout_minutes' =>
              '${gym.settings['auto_logout_minutes'] ?? 30}',
            'pin_lock_minutes' => '${gym.settings['pin_lock_minutes'] ?? 5}',
            'grace_days' => '${gym.settings['grace_days'] ?? 0}',
            _ => '${gym.settings['entry_duplicate_seconds'] ?? 3}',
          };
        }
        for (final key in _booleans.keys) {
          _booleans[key] = gym.settings[key] == true;
        }
        _loading = false;
      });
      _signedLogo = await _repository.signedLogoUrl(gym.logoUrl);
      if (mounted) setState(() {});
    } on SettingsFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.code;
          _loading = false;
        });
      }
    }
  }

  Future<void> _chooseLogo() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() => _busy = true);
      final path = await _repository.uploadLogo(file.name, bytes);
      if (!mounted) return;
      setState(() {
        _logoPath = path;
        _logoPreview = bytes;
        _signedLogo = null;
        _error = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.text('logo'))));
    } on SettingsFailure catch (e) {
      if (mounted) setState(() => _error = e.code);
    } catch (_) {
      if (mounted) setState(() => _error = 'invalid_logo');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validate(String key, String? value, AppStrings s) {
    final text = value?.trim() ?? '';
    if (!{'address', 'phone', 'email', 'doc_footer'}.contains(key) &&
        text.isEmpty) {
      return s.text('required');
    }
    if (key == 'name' && (text.length < 2 || text.length > 120)) {
      return s.text('invalid_record');
    }
    if (key == 'accent_color' && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text)) {
      return s.text('accent_hint');
    }
    if (key == 'timezone') {
      try {
        tz.getLocation(text);
      } on tz.LocationNotFoundException {
        return s.text('invalid_record');
      }
    }
    if (key == 'email' &&
        text.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return s.text('invalid_email');
    }
    if ({'address', 'doc_footer'}.contains(key) && text.length > 500) {
      return s.text('invalid_record');
    }
    if (key == 'phone' && text.length > 32) return s.text('invalid_record');
    const limits = {
      'offline_lease_hours': (1, 72),
      'auto_logout_minutes': (0, 1440),
      'pin_lock_minutes': (1, 60),
      'grace_days': (0, 30),
      'entry_duplicate_seconds': (1, 10),
    };
    if (limits.containsKey(key)) {
      final number = int.tryParse(text);
      if (number == null ||
          number < limits[key]!.$1 ||
          number > limits[key]!.$2) {
        return s.text('invalid_record');
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_busy || _gym == null || !_form.currentState!.validate()) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final runtime = ref.read(appRuntimeProvider);
      final settings = {
        ..._gym!.settings,
        'doc_footer': _fields['doc_footer']!.text.trim(),
        'offline_lease_hours': int.parse(_fields['offline_lease_hours']!.text),
        'auto_logout_minutes': int.parse(_fields['auto_logout_minutes']!.text),
        'pin_lock_minutes': int.parse(_fields['pin_lock_minutes']!.text),
        'grace_days': int.parse(_fields['grace_days']!.text),
        'entry_duplicate_seconds': int.parse(
          _fields['entry_duplicate_seconds']!.text,
        ),
        ..._booleans,
      };
      final changedAt =
          runtime.sync?.clock.correctedNow ?? DateTime.now().toUtc();
      final updated = _gym!.copy(
        name: _fields['name']!.text.trim(),
        accentColor: _fields['accent_color']!.text.trim(),
        timezone: _fields['timezone']!.text.trim(),
        currency: _fields['currency']!.text,
        address: _fields['address']!.text.trim(),
        phone: _fields['phone']!.text.trim(),
        email: _fields['email']!.text.trim().toLowerCase(),
        logoUrl: _logoPath,
        settings: settings,
      );
      await _repository.save(updated, changedAt: changedAt);
      runtime.applyLocalGym(updated.row);
      await runtime.sync?.synchronize();
      await HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text('branding_saved'))));
      }
    } on SettingsFailure catch (e) {
      if (mounted) setState(() => _error = e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final runtime = ref.watch(appRuntimeProvider);
    final gym = _gym;
    return Scaffold(
      appBar: AppBar(title: Text(s.text('gym_settings'))),
      body: SafeArea(
        child: _loading
            ? const Padding(padding: EdgeInsets.all(24), child: LoadingPanel())
            : gym == null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: MessagePanel(
                  message: s.text(_error ?? 'error'),
                  action: s.text('retry'),
                  onAction: _load,
                ),
              )
            : Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      s.text('gym_identity'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth >= 760
                            ? (constraints.maxWidth - 20) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 20,
                          runSpacing: 16,
                          children: [
                            for (final key in [
                              'name',
                              'accent_color',
                              'timezone',
                              'address',
                              'phone',
                              'email',
                            ])
                              SizedBox(
                                width: width,
                                child: key == 'timezone'
                                    ? TextFormField(
                                        controller: _fields[key],
                                        decoration: InputDecoration(
                                          labelText: s.text(key),
                                        ),
                                        validator: (v) => _validate(key, v, s),
                                      )
                                    : TextFormField(
                                        controller: _fields[key],
                                        decoration: InputDecoration(
                                          labelText: s.text(key),
                                        ),
                                        validator: (v) => _validate(key, v, s),
                                      ),
                              ),
                            SizedBox(
                              width: width,
                              child: DropdownButtonFormField<String>(
                                initialValue: gym.currency,
                                decoration: InputDecoration(
                                  labelText: s.text('currency'),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'HTG',
                                    child: Text('HTG'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'USD',
                                    child: Text('USD'),
                                  ),
                                ],
                                onChanged: _busy
                                    ? null
                                    : (value) =>
                                          _fields['currency']!.text = value!,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    Text(
                      s.text('logo'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(s.text('logo_online')),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xfff6f7f6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _logoPreview != null
                              ? Image.memory(_logoPreview!, fit: BoxFit.contain)
                              : _signedLogo != null
                              ? Image.network(_signedLogo!, fit: BoxFit.contain)
                              : const Icon(LucideIcons.image, size: 32),
                        ),
                        const SizedBox(width: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy || runtime.sync == null
                                  ? null
                                  : _chooseLogo,
                              icon: const Icon(LucideIcons.upload),
                              label: Text(s.text('choose_logo')),
                            ),
                            TextButton(
                              onPressed: _busy || _logoPath == null
                                  ? null
                                  : () => setState(() {
                                      _logoPath = null;
                                      _logoPreview = null;
                                      _signedLogo = null;
                                    }),
                              child: Text(s.text('remove_logo')),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      s.text('operational_settings'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth >= 760
                            ? (constraints.maxWidth - 20) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 20,
                          runSpacing: 16,
                          children: [
                            for (final key in [
                              'doc_footer',
                              'offline_lease_hours',
                              'auto_logout_minutes',
                              'pin_lock_minutes',
                              'grace_days',
                              'entry_duplicate_seconds',
                            ])
                              SizedBox(
                                width: width,
                                child: TextFormField(
                                  controller: _fields[key],
                                  maxLength: key == 'doc_footer' ? 500 : 4,
                                  keyboardType: key == 'doc_footer'
                                      ? TextInputType.multiline
                                      : TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: s.text(key),
                                    counterText: key == 'doc_footer'
                                        ? null
                                        : '',
                                  ),
                                  validator: (v) => _validate(key, v, s),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    for (final entry in _booleans.entries)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.text(entry.key)),
                        value: entry.value,
                        onChanged: _busy
                            ? null
                            : (value) =>
                                  setState(() => _booleans[entry.key] = value),
                      ),
                    if (_error != null) MessagePanel(message: s.text(_error!)),
                    if (runtime.sync != null)
                      ListenableBuilder(
                        listenable: runtime.sync!.state,
                        builder: (context, _) {
                          final pending =
                              runtime.sync!.state.value.pending +
                              runtime.sync!.state.value.failed;
                          return pending == 0
                              ? const SizedBox.shrink()
                              : MessagePanel(
                                  message: '${s.text('pending')}: $pending',
                                );
                        },
                      ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        child: Text(s.text('save')),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }
}
