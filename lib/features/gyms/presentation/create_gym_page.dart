import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../app/providers.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../data/gyms_repository.dart';
import '../data/provision_draft_store.dart';
import '../domain/gym.dart';

class CreateGymPage extends ConsumerStatefulWidget {
  const CreateGymPage({super.key});
  @override
  ConsumerState<CreateGymPage> createState() => _CreateGymPageState();
}

class _CreateGymPageState extends ConsumerState<CreateGymPage> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final key in [
      'name',
      'code',
      'accent_color',
      'timezone',
      'currency',
      'address',
      'phone',
      'email',
      'owner_name',
      'owner_email',
      'owner_password',
    ])
      key: TextEditingController(),
  };
  late final GymsRepository _repository;
  late final ProvisionDraftStore _store;
  Json? _draft;
  bool _loading = true;
  bool _busy = false;
  bool _loadFailed = false;
  String? _error;
  List<PlatformOffer> _offers = const [];
  bool _offersFailed = false;
  String? _offerId;
  final _amount = TextEditingController();
  String _method = 'cash';
  bool _paid = true;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = GymsRepository(runtime.client);
    _store = ProvisionDraftStore(runtime.namespace, runtime.session!.userId);
    _fields['accent_color']!.text = '#1F6F4A';
    _fields['timezone']!.text = 'America/Port-au-Prince';
    _fields['currency']!.text = 'HTG';
    _loadOffers();
    _restore();
  }

  Future<void> _loadOffers() async {
    try {
      final offers = await _repository.loadOffers();
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _offersFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _offersFailed = true);
    }
  }

  PlatformOffer? get _selectedOffer {
    for (final offer in _offers) {
      if (offer.id == _offerId) return offer;
    }
    return null;
  }

  void _pickOffer(String? id) {
    setState(() {
      _offerId = id;
      final offer = _selectedOffer;
      if (offer != null && _amount.text.isEmpty) {
        _amount.text = offer.price % 1 == 0
            ? offer.price.toStringAsFixed(0)
            : offer.price.toStringAsFixed(2);
      }
    });
  }

  Future<void> _restore() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final saved = await _store.read();
      if (!mounted) return;
      if (saved != null) {
        _draft = saved;
        final gym = saved['gym'] as Map;
        for (final key in _fields.keys.where(
          (key) => !key.startsWith('owner_'),
        )) {
          _fields[key]!.text = gym[key] as String? ?? '';
        }
        _fields['owner_name']!.text = saved['owner_name'] as String;
        _fields['owner_email']!.text = saved['owner_email'] as String;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'local_storage';
          _loadFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.text('new_gym')),
        content: Text(s.text('create_owner_confirmation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('create_gym')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = _draft;
    final command = CreateGymCommand(
      requestId: draft?['request_id'] as String? ?? const Uuid().v4(),
      gymId: draft?['gym_id'] as String? ?? const Uuid().v4(),
      staffId: draft?['staff_id'] as String? ?? const Uuid().v4(),
      gym: {
        for (final key in _fields.keys.where(
          (key) => !key.startsWith('owner_'),
        ))
          key: key == 'code'
              ? _fields[key]!.text.trim().toUpperCase()
              : _fields[key]!.text.trim(),
      },
      ownerName: _fields['owner_name']!.text.trim(),
      ownerEmail: _fields['owner_email']!.text.trim().toLowerCase(),
      ownerPassword: _fields['owner_password']!.text,
    );
    try {
      await _store.save(command);
      _draft = command.toJson()..remove('owner_password');
      final gym = await _repository.create(command);
      final offer = _selectedOffer;
      if (offer != null) {
        final amount =
            double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;
        try {
          await _repository.registerPayment(
            gymId: gym.id,
            offerId: offer.id,
            amount: amount,
            currency: offer.currency,
            method: _method,
            paid: _paid,
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.text('payment_registration_failed'))),
            );
          }
        }
      }
      await _store.clear();
      _fields['owner_password']!.clear();
      await HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context, true);
    } on PlatformFailure catch (e) {
      if ({'owner_exists', 'duplicate_code'}.contains(e.code)) {
        try {
          await _store.clear();
          _draft = null;
        } catch (_) {
          _error = 'local_storage';
        }
      }
      if (mounted) setState(() => _error ??= e.code);
    } catch (_) {
      if (mounted) setState(() => _error = 'local_storage');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _offerCard(PlatformOffer offer, AppStrings s, double width) {
    final theme = Theme.of(context);
    final selected = _offerId == offer.id;
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: _busy || _draft != null ? null : () => _pickOffer(offer.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        offer.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(
                        LucideIcons.circleCheck,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${offer.price % 1 == 0 ? offer.price.toStringAsFixed(0) : offer.price.toStringAsFixed(2)} ${offer.currency} ${s.text(offer.isAnnual ? 'per_year' : 'per_month')}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (offer.description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(
                    offer.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '${s.text('badge_quota')} : ${offer.badgeQuota} (Opsyonèl)',
                  style: theme.textTheme.bodySmall,
                ),
                if (offer.includesDoorAccess || offer.biometricSupported) ...[
                  const SizedBox(height: 6),
                  Text(
                    '✅ Sistèm Pòt Byometrik FSTW F30 Enkli',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                if (offer.installmentsAllowed) ...[
                  const SizedBox(height: 4),
                  Text(
                    '💳 Peman an 3 Fwa : Akonpt ${offer.installment1.toStringAsFixed(0)} ${offer.currency}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _validate(String key, String? value, AppStrings s) {
    final text = value?.trim() ?? '';
    if (!{'address', 'phone', 'email'}.contains(key) && text.isEmpty) {
      return s.text('required');
    }
    if (key == 'owner_password') {
      return (value?.length ?? 0) < 12 || (value?.length ?? 0) > 128
          ? s.text('weak_password')
          : null;
    }
    if (key == 'code' && !RegExp(r'^[A-Za-z]{3,4}$').hasMatch(text)) {
      return s.text('code_hint');
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
    if (key.contains('email') &&
        text.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return s.text('invalid_email');
    }
    if ({'name', 'owner_name'}.contains(key) &&
        (text.length < 2 || text.length > 120)) {
      return s.text('invalid_record');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(s.text('new_gym'))),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: LoadingPanel(),
                    )
                  : _loadFailed
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: MessagePanel(
                        message: s.text(_error!),
                        action: s.text('retry'),
                        onAction: _restore,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _form,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final theme = Theme.of(context);
                            final width = constraints.maxWidth >= 650
                                ? (constraints.maxWidth - 20) / 2
                                : constraints.maxWidth;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.text('choose_plan'),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(s.text('choose_plan_hint')),
                                const SizedBox(height: 16),
                                if (_offersFailed)
                                  MessagePanel(
                                    message: s.text('error'),
                                    action: s.text('retry'),
                                    onAction: _loadOffers,
                                  )
                                else if (_offers.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: LoadingPanel(rows: 1),
                                  )
                                else
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      for (final offer in _offers)
                                        _offerCard(offer, s, width),
                                    ],
                                  ),
                                if (_selectedOffer != null) ...[
                                  if (_selectedOffer!.installmentsAllowed) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primaryContainer.withAlpha(90),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(LucideIcons.creditCard, size: 16, color: theme.colorScheme.primary),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Opsyon Peman an 3 Fwa (Akonpt Materyèl/Enstalasyon)',
                                                style: theme.textTheme.labelMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: theme.colorScheme.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 8,
                                            children: [
                                              ActionChip(
                                                avatar: const Icon(LucideIcons.checkCheck, size: 14),
                                                label: Text('Tout Kòb la (100%) : ${_selectedOffer!.price.toStringAsFixed(0)} ${_selectedOffer!.currency}'),
                                                onPressed: _busy || _draft != null ? null : () {
                                                  setState(() {
                                                    _amount.text = _selectedOffer!.price.toStringAsFixed(0);
                                                  });
                                                },
                                              ),
                                              ActionChip(
                                                avatar: const Icon(LucideIcons.wrench, size: 14),
                                                label: Text('Tranche 1 (Akonpt Materyèl) : ${_selectedOffer!.installment1.toStringAsFixed(0)} ${_selectedOffer!.currency}'),
                                                onPressed: _busy || _draft != null ? null : () {
                                                  setState(() {
                                                    _amount.text = _selectedOffer!.installment1.toStringAsFixed(0);
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      s.text('payment_received_now'),
                                    ),
                                    subtitle: Text(
                                      s.text('payment_cash_hint'),
                                    ),
                                    value: _paid,
                                    onChanged: _busy || _draft != null
                                        ? null
                                        : (value) =>
                                              setState(() => _paid = value),
                                  ),
                                  if (_paid) ...[
                                    Wrap(
                                      spacing: 20,
                                      runSpacing: 20,
                                      children: [
                                        SizedBox(
                                          width: width,
                                          child: TextFormField(
                                            controller: _amount,
                                            enabled:
                                                !_busy && _draft == null,
                                            keyboardType:
                                                const TextInputType
                                                    .numberWithOptions(
                                                    decimal: true,
                                                  ),
                                            decoration: InputDecoration(
                                              labelText:
                                                  '${s.text('amount_paid')} (${_selectedOffer!.currency})',
                                              counterText: '',
                                            ),
                                            validator: (value) {
                                              final parsed =
                                                  double.tryParse(
                                                    (value ?? '')
                                                        .replaceAll(',', '.'),
                                                  ) ??
                                                  0;
                                              return parsed <= 0
                                                  ? s.text('invalid_record')
                                                  : null;
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: width,
                                          child:
                                              DropdownButtonFormField<
                                                String
                                              >(
                                                initialValue: _method,
                                                decoration: InputDecoration(
                                                  labelText: s.text('method'),
                                                ),
                                                items: [
                                                  for (final m in [
                                                    'cash',
                                                    'moncash',
                                                    'natcash',
                                                    'bank',
                                                    'other',
                                                  ])
                                                    DropdownMenuItem(
                                                      value: m,
                                                      child: Text(
                                                        s.text('pay_$m'),
                                                      ),
                                                    ),
                                                ],
                                                onChanged:
                                                    _busy || _draft != null
                                                    ? null
                                                    : (value) => setState(
                                                        () => _method =
                                                            value!,
                                                      ),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                                const SizedBox(height: 32),
                                Text(
                                  s.text('gym_identity'),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 16),
                                Text(s.text('platform_online')),
                                if (_draft != null) ...[
                                  const SizedBox(height: 16),
                                  Text(s.text('provision_resume')),
                                  SelectableText(
                                    _draft!['request_id'] as String,
                                  ),
                                ],
                                const SizedBox(height: 24),
                                Wrap(
                                  spacing: 20,
                                  runSpacing: 20,
                                  children: _fields.entries.map((entry) {
                                    final key = entry.key;
                                    if (key == 'currency') {
                                      return SizedBox(
                                        width: width,
                                        child: DropdownButtonFormField<String>(
                                          initialValue: entry.value.text,
                                          decoration: InputDecoration(
                                            labelText: s.text(key),
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
                                          onChanged: _busy || _draft != null
                                              ? null
                                              : (value) =>
                                                    entry.value.text = value!,
                                        ),
                                      );
                                    }
                                    return SizedBox(
                                      width: width,
                                      child: TextFormField(
                                        controller: entry.value,
                                        onChanged: (_) => ref
                                            .read(appRuntimeProvider)
                                            .activity(),
                                        readOnly:
                                            _busy ||
                                            (_draft != null &&
                                                key != 'owner_password'),
                                        obscureText: key == 'owner_password',
                                        autocorrect: key != 'owner_password',
                                        enableSuggestions:
                                            key != 'owner_password',
                                        maxLength: key == 'owner_password'
                                            ? 128
                                            : key == 'address'
                                            ? 500
                                            : key.contains('email')
                                            ? 254
                                            : key == 'code'
                                            ? 4
                                            : key == 'phone'
                                            ? 32
                                            : key == 'timezone'
                                            ? 80
                                            : key == 'accent_color'
                                            ? 7
                                            : 120,
                                        keyboardType: key.contains('email')
                                            ? TextInputType.emailAddress
                                            : key == 'phone'
                                            ? TextInputType.phone
                                            : TextInputType.text,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(
                                          labelText: s.text(key),
                                          counterText: '',
                                        ),
                                        validator: (value) =>
                                            _validate(key, value, s),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                if (_error != null)
                                  MessagePanel(message: s.text(_error!)),
                                if (_busy) const LoadingPanel(rows: 1),
                                const SizedBox(height: 24),
                                FilledButton(
                                  onPressed: _busy ? null : _submit,
                                  child: Text(
                                    s.text(
                                      _draft == null
                                          ? 'create_gym'
                                          : 'resume_creation',
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
