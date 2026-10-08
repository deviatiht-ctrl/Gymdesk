import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../payments/domain/payment.dart';
import '../../plans/data/plans_repository.dart';
import '../../plans/domain/plan.dart';
import '../../subscriptions/domain/gym_subscription.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../data/member_photo_codec.dart';
import '../data/members_repository.dart';
import '../domain/member.dart';

class MemberFormPage extends ConsumerStatefulWidget {
  const MemberFormPage({super.key, this.memberId});
  final String? memberId;

  @override
  ConsumerState<MemberFormPage> createState() => _MemberFormPageState();
}

class _MemberFormPageState extends ConsumerState<MemberFormPage> {
  final _form = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final MembersRepository _members;
  late final PlansRepository _plans;
  final _fields = <String, TextEditingController>{};
  Member? _existing;
  Uint8List? _photo;
  String? _sex;
  DateTime? _birthDate;
  DateTime _startDate = DateTime.now();
  GymPlan? _plan;
  String _method = 'cash';
  bool _withSubscription = true;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _members = MembersRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
    _plans = PlansRepository(runtime.database!, runtime.session!);
    for (final key in [
      'first_name',
      'last_name',
      'phone',
      'whatsapp',
      'email',
      'address',
      'nif',
      'cin',
      'emergency_name',
      'emergency_phone',
      'guardian_name',
      'notes',
      'paid_amount',
    ]) {
      _fields[key] = TextEditingController();
    }
    _load();
  }

  Future<void> _load() async {
    if (widget.memberId == null) {
      _loaded = true;
      return;
    }
    _existing = await _members.watchMember(widget.memberId!).first;
    final member = _existing;
    if (member == null || !mounted) return;
    _fields['first_name']!.text = member.firstName;
    _fields['last_name']!.text = member.lastName;
    _fields['phone']!.text = member.phone ?? '';
    _fields['whatsapp']!.text = member.whatsapp ?? '';
    _fields['email']!.text = member.email ?? '';
    _fields['address']!.text = member.address ?? '';
    _fields['nif']!.text = member.nif ?? '';
    _fields['cin']!.text = member.cin ?? '';
    _fields['emergency_name']!.text = member.emergencyName ?? '';
    _fields['emergency_phone']!.text = member.emergencyPhone ?? '';
    _fields['guardian_name']!.text = member.guardianName ?? '';
    _fields['notes']!.text = member.notes ?? '';
    _sex = member.sex;
    _birthDate = member.birthDate;
    _photo = await _members.localPhoto(member.id);
    _withSubscription = false;
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  MemberRegistration _draft() => MemberRegistration(
    firstName: _fields['first_name']!.text,
    lastName: _fields['last_name']!.text,
    sex: _sex,
    birthDate: _birthDate,
    phone: _fields['phone']!.text,
    whatsapp: _fields['whatsapp']!.text,
    email: _fields['email']!.text,
    address: _fields['address']!.text,
    nif: _fields['nif']!.text,
    cin: _fields['cin']!.text,
    emergencyName: _fields['emergency_name']!.text,
    emergencyPhone: _fields['emergency_phone']!.text,
    guardianName: _fields['guardian_name']!.text,
    notes: _fields['notes']!.text,
    photo: _photo,
  );

  Future<void> _pickPhoto() async {
    final s = AppStrings.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: Text(s.text('take_instant_photo')),
              subtitle: Text(s.text('photo_instant_hint')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: Text(s.text('choose_from_gallery')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_photo != null)
              ListTile(
                leading: Icon(
                  LucideIcons.trash2,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  s.text('delete'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  setState(() => _photo = null);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (file == null) return;
      final bytes = encodeMemberPhoto(await file.readAsBytes());
      if (mounted) setState(() => _photo = bytes);
    } on MemberFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text(e.code))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text('invalid_photo'))));
      }
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
    );
    if (date != null && mounted) setState(() => _birthDate = date);
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (date != null && mounted) setState(() => _startDate = date);
  }

  Future<bool> _confirmDuplicates() async {
    final s = AppStrings.of(context);
    final duplicates = await _members.duplicates(_draft());
    if (duplicates.isEmpty || !mounted) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.text('duplicate_warning')),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.text('duplicate_warning_hint')),
                const SizedBox(height: 16),
                for (final duplicate in duplicates.take(8))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(duplicate.member.fullName),
                    subtitle: Text(
                      '${duplicate.member.memberNumber} · ${s.text('duplicate_${duplicate.reason}')}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('continue_anyway')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final s = AppStrings.of(context);
    final runtime = ref.read(appRuntimeProvider);
    final changedAt =
        runtime.sync?.clock.correctedNow ?? DateTime.now().toUtc();
    setState(() => _busy = true);
    try {
      if (_existing == null && !await _confirmDuplicates()) return;
      final draft = _draft();
      if (_existing != null) {
        await _members.updateProfile(_existing!, draft, changedAt: changedAt);
        await runtime.sync?.synchronize();
        if (mounted) context.go('/members/${_existing!.id}');
        return;
      }
      SubscriptionCommand? subscription;
      PaymentCommand? payment;
      if (_withSubscription) {
        final plan = _plan;
        if (plan == null) throw const MemberFailure('invalid_record');
        final amount =
            double.tryParse(
              _fields['paid_amount']!.text.replaceAll(',', '.'),
            ) ??
            0;
        if (!amount.isFinite || amount < 0 || amount > plan.registrationPrice) {
          throw const MemberFailure('invalid_record');
        }
        final start = dateOnly(_startDate);
        subscription = SubscriptionCommand(
          planId: plan.id,
          startDate: start,
          endDate: subscriptionEnd(start, plan.durationDays),
          price: plan.registrationPrice,
          status: amount >= plan.registrationPrice ? 'active' : 'pending',
        );
        if (amount > 0) {
          payment = PaymentCommand(
            memberId: '',
            amount: amount,
            currency: plan.currency,
            method: _method,
          );
        }
      }
      final result = await _members.register(
        draft,
        subscription: subscription,
        payment: payment,
        changedAt: changedAt,
      );
      await runtime.sync?.synchronize();
      await HapticFeedback.lightImpact();
      if (mounted) context.go('/members/${result.memberId}');
    } on MemberFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text(e.code))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(AppStrings s, String key) =>
      InputDecoration(labelText: s.text(key));
  Widget _space() => const SizedBox(height: 14);

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final editing = widget.memberId != null;
    if (editing && !_loaded) {
      return const Padding(padding: EdgeInsets.all(24), child: LoadingPanel());
    }
    if (editing && _existing == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: MessagePanel(message: s.text('member_missing')),
      );
    }
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.text(editing ? 'edit_member' : 'new_member'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      InkWell(
                        onTap: _busy ? null : _pickPhoto,
                        child: CircleAvatar(
                          radius: 48,
                          backgroundImage: _photo == null
                              ? null
                              : MemoryImage(_photo!),
                          child: _photo == null
                              ? const Icon(LucideIcons.camera, size: 32)
                              : null,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _pickPhoto,
                            icon: const Icon(LucideIcons.imagePlus),
                            label: Text(s.text('choose_photo')),
                          ),
                          Text(
                            s.text('photo_hint'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: 300,
                        child: TextFormField(
                          controller: _fields['first_name'],
                          decoration: _decoration(s, 'first_name'),
                          validator: (v) => (v?.trim().length ?? 0) < 2
                              ? s.text('required')
                              : null,
                        ),
                      ),
                      SizedBox(
                        width: 300,
                        child: TextFormField(
                          controller: _fields['last_name'],
                          decoration: _decoration(s, 'last_name'),
                          validator: (v) => (v?.trim().length ?? 0) < 2
                              ? s.text('required')
                              : null,
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String?>(
                          initialValue: _sex,
                          decoration: _decoration(s, 'sex'),
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text(s.text('unknown')),
                            ),
                            DropdownMenuItem(
                              value: 'male',
                              child: Text(s.text('male')),
                            ),
                            DropdownMenuItem(
                              value: 'female',
                              child: Text(s.text('female')),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text(s.text('other_sex')),
                            ),
                          ],
                          onChanged: (v) => setState(() => _sex = v),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _pickBirthDate,
                          icon: const Icon(LucideIcons.calendar),
                          label: Text(
                            _birthDate == null
                                ? s.text('birth_date')
                                : DateFormat.yMMMd(
                                    Localizations.localeOf(context).toString(),
                                  ).format(_birthDate!),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: TextFormField(
                          controller: _fields['phone'],
                          keyboardType: TextInputType.phone,
                          decoration: _decoration(s, 'phone'),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: TextFormField(
                          controller: _fields['whatsapp'],
                          keyboardType: TextInputType.phone,
                          decoration: _decoration(s, 'whatsapp'),
                        ),
                      ),
                      SizedBox(
                        width: 300,
                        child: TextFormField(
                          controller: _fields['email'],
                          keyboardType: TextInputType.emailAddress,
                          decoration: _decoration(s, 'email'),
                          maxLength: 254,
                          validator: (v) =>
                              (_existing != null && (v ?? '').isEmpty) ||
                                  RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch((v ?? '').trim())
                              ? null
                              : s.text('invalid_email'),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextFormField(
                          controller: _fields['nif'],
                          keyboardType: TextInputType.number,
                          decoration: _decoration(s, 'nif'),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextFormField(
                          controller: _fields['cin'],
                          decoration: _decoration(s, 'cin'),
                        ),
                      ),
                      SizedBox(
                        width: 610,
                        child: TextFormField(
                          controller: _fields['address'],
                          maxLength: 500,
                          decoration: _decoration(
                            s,
                            'address',
                          ).copyWith(counterText: ''),
                        ),
                      ),
                    ],
                  ),
                  _space(),
                  Wrap(
                    spacing: 16,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: 290,
                        child: TextFormField(
                          controller: _fields['emergency_name'],
                          decoration: _decoration(s, 'emergency_name'),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: TextFormField(
                          controller: _fields['emergency_phone'],
                          keyboardType: TextInputType.phone,
                          decoration: _decoration(s, 'emergency_phone'),
                        ),
                      ),
                      SizedBox(
                        width: 290,
                        child: TextFormField(
                          controller: _fields['guardian_name'],
                          decoration: _decoration(s, 'guardian_name'),
                        ),
                      ),
                      SizedBox(
                        width: 610,
                        child: TextFormField(
                          controller: _fields['notes'],
                          maxLength: 1000,
                          maxLines: 3,
                          decoration: _decoration(
                            s,
                            'notes',
                          ).copyWith(counterText: ''),
                        ),
                      ),
                    ],
                  ),
                  if (!editing) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.text('create_subscription')),
                      subtitle: Text(s.text('subscription_optional_hint')),
                      value: _withSubscription,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _withSubscription = v),
                    ),
                    if (_withSubscription)
                      StreamBuilder<List<GymPlan>>(
                        stream: _plans.watch(),
                        builder: (context, snapshot) {
                          final plans = (snapshot.data ?? [])
                              .where((p) => p.active && p.deletedAt == null)
                              .toList();
                          return Card(
                            margin: const EdgeInsets.only(top: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Wrap(
                                spacing: 16,
                                runSpacing: 14,
                                children: [
                                  SizedBox(
                                    width: 280,
                                    child: DropdownButtonFormField<GymPlan?>(
                                      initialValue: _plan,
                                      decoration: _decoration(s, 'plan'),
                                      items: plans
                                          .map(
                                            (plan) => DropdownMenuItem(
                                              value: plan,
                                              child: Text(
                                                '${plan.name} · ${plan.registrationPrice.toStringAsFixed(2)} ${plan.currency}',
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: _busy
                                          ? null
                                          : (plan) => setState(() {
                                              _plan = plan;
                                              _fields['paid_amount']!.text =
                                                  plan == null
                                                  ? ''
                                                  : plan.registrationPrice
                                                        .toStringAsFixed(2);
                                            }),
                                      validator: (_) =>
                                          _withSubscription && _plan == null
                                          ? s.text('required')
                                          : null,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 220,
                                    child: OutlinedButton.icon(
                                      onPressed: _busy ? null : _pickStartDate,
                                      icon: const Icon(LucideIcons.calendar),
                                      label: Text(
                                        '${s.text('start_date')}: ${DateFormat.yMd(Localizations.localeOf(context).toString()).format(_startDate)}',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 220,
                                    child: TextFormField(
                                      controller: _fields['paid_amount'],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: _decoration(s, 'paid_amount'),
                                      validator: (v) =>
                                          !_withSubscription ||
                                              (double.tryParse(
                                                        (v ?? '0').replaceAll(
                                                          ',',
                                                          '.',
                                                        ),
                                                      ) ??
                                                      -1) >=
                                                  0
                                          ? null
                                          : s.text('invalid_record'),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 220,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _method,
                                      decoration: _decoration(
                                        s,
                                        'payment_method',
                                      ),
                                      items:
                                          [
                                                'cash',
                                                'moncash',
                                                'natcash',
                                                'bank',
                                                'other',
                                              ]
                                              .map(
                                                (method) => DropdownMenuItem(
                                                  value: method,
                                                  child: Text(
                                                    s.text('method_$method'),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: _busy
                                          ? null
                                          : (v) => setState(
                                              () => _method = v ?? 'cash',
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => context.go(
                                editing
                                    ? '/members/${_existing!.id}'
                                    : '/members',
                              ),
                        child: Text(s.text('cancel')),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(LucideIcons.check),
                        label: Text(s.text('save')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
