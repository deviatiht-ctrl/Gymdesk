import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/securgym_background.dart';
import '../../../l10n/app_strings.dart';
import '../../gyms/data/gyms_repository.dart';

/// Assistant d'inscription self-service : la salle démarre avec un essai
/// de 7 jours contrôlé par le serveur (edge function create_gym_with_owner).
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});
  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  int _step = 0;
  bool _busy = false;
  String? _error;
  bool _done = false;

  final _gymName = TextEditingController();
  final _gymCode = TextEditingController();
  final _gymPhone = TextEditingController();
  final _gymAddress = TextEditingController();
  final _ownerName = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _ownerPhone = TextEditingController();
  final _ownerPassword = TextEditingController();
  String _currency = 'HTG';
  String _offerId = 'plan_basic';
  List<Map<String, dynamic>> _offers = const [];

  @override
  void initState() {
    super.initState();
    _loadOffers();
  }

  Future<void> _loadOffers() async {
    try {
      final offers = await GymsRepository(Supabase.instance.client).loadOffers();
      if (mounted) {
        setState(() {
          _offers = offers.map((o) => o.toJson()).toList();
          if (_offers.isNotEmpty) {
            final hot = offers.firstWhere((o) => o.isHot, orElse: () => offers.first);
            _offerId = hot.id;
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [
      _gymName,
      _gymCode,
      _gymPhone,
      _gymAddress,
      _ownerName,
      _ownerEmail,
      _ownerPhone,
      _ownerPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? get _offer =>
      _offers.where((o) => o['id'] == _offerId).firstOrNull;

  bool get _gymValid =>
      _gymName.text.trim().length >= 3 &&
      RegExp(r'^[A-Z0-9]{2,8}$').hasMatch(_gymCode.text.trim().toUpperCase()) &&
      _gymPhone.text.trim().length >= 7;

  bool get _ownerValid =>
      _ownerName.text.trim().length >= 3 &&
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_ownerEmail.text.trim()) &&
      _ownerPhone.text.trim().length >= 7 &&
      _ownerPassword.text.length >= 8;

  Future<void> _submit() async {
    if (_busy || !_gymValid || !_ownerValid || _offer == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'create_gym_with_owner',
        body: {
          'owner_name': _ownerName.text.trim(),
          'owner_email': _ownerEmail.text.trim(),
          'owner_phone': _ownerPhone.text.trim(),
          'owner_password': _ownerPassword.text,
          'offer_id': _offerId,
          'gym': {
            'name': _gymName.text.trim(),
            'code': _gymCode.text.trim().toUpperCase(),
            'currency': _currency,
            'timezone': 'America/Port-au-Prince',
            'phone': _gymPhone.text.trim(),
            'address': _gymAddress.text.trim(),
            'email': _ownerEmail.text.trim(),
          },
        },
      );
      final data = res.data;
      if (res.status >= 400 ||
          (data is Map && data['error'] != null)) {
        throw Exception(data is Map ? data['error'] : 'signup_failed');
      }
      setState(() => _done = true);
    } on FunctionException catch (e) {
      final details = e.details;
      setState(
        () => _error = details is Map
            ? details['error'] as String? ?? 'signup_failed'
            : 'signup_failed',
      );
    } catch (e) {
      setState(
        () => _error = e is Exception && e.toString().contains('Exception: ')
            ? e.toString().replaceFirst('Exception: ', '')
            : 'signup_failed',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    if (_done) return _success(s, theme);
    return Scaffold(
      backgroundColor: const Color(0xff121417),
      appBar: AppBar(
        backgroundColor: const Color(0xff1a1d24),
        elevation: 0,
        title: Image.asset(
          'assets/brand/logo_horizontal.png',
          height: 32,
          fit: BoxFit.contain,
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SecurGymBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xff1a1d24).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  _steps(theme),
                  const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      s.text(_error!),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                switch (_step) {
                  0 => _gymStep(s, theme),
                  1 => _ownerStep(s, theme),
                  2 => _planStep(s, theme),
                  _ => _reviewStep(s, theme),
                },
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (_step > 0)
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _step--),
                        child: Text(s.text('back')),
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : _step < 3
                          ? () => setState(() => _step++)
                          : _submit,
                      child: Text(
                        _step < 3
                            ? s.text('next')
                            : s.text('start_trial_7days'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  Widget _steps(ThemeData theme) => Row(
    children: List.generate(4, (i) {
      final active = i <= _step;
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          height: 4,
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }),
  );

  Widget _gymStep(AppStrings s, ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(s.text('signup_gym_step'), style: theme.textTheme.titleLarge),
      const SizedBox(height: 16),
      TextField(
        controller: _gymName,
        decoration: InputDecoration(labelText: s.text('gym_name')),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _gymCode,
        decoration: InputDecoration(
          labelText: s.text('gym_code'),
          helperText: s.text('gym_code_hint'),
        ),
        textCapitalization: TextCapitalization.characters,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _gymPhone,
        decoration: InputDecoration(labelText: s.text('gym_phone')),
        keyboardType: TextInputType.phone,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _gymAddress,
        decoration: InputDecoration(labelText: s.text('address')),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _currency,
        decoration: InputDecoration(labelText: s.text('currency')),
        items: ['HTG', 'USD']
            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
            .toList(),
        onChanged: (v) => setState(() => _currency = v ?? 'HTG'),
      ),
    ],
  );

  Widget _ownerStep(AppStrings s, ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(s.text('signup_owner_step'), style: theme.textTheme.titleLarge),
      const SizedBox(height: 16),
      TextField(
        controller: _ownerName,
        decoration: InputDecoration(labelText: s.text('full_name')),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _ownerEmail,
        decoration: InputDecoration(labelText: s.text('email')),
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _ownerPhone,
        decoration: InputDecoration(labelText: s.text('owner_phone')),
        keyboardType: TextInputType.phone,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _ownerPassword,
        decoration: InputDecoration(
          labelText: s.text('password'),
          helperText: s.text('password_min8'),
        ),
        obscureText: true,
        onChanged: (_) => setState(() {}),
      ),
    ],
  );

  String _billingLabel(String? period, AppStrings s) => switch (period) {
    'annual' => '/${s.text('per_year')}',
    'monthly' => '/${s.text('per_month')}',
    'one_time' || 'unique' => ' · ${s.text('billing_one_time')}',
    'lifetime' => ' · ${s.text('billing_lifetime')}',
    _ => '',
  };

  Widget _capabilityChip(String label, IconData icon, ThemeData theme) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: theme.colorScheme.primary),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _planStep(AppStrings s, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.text('signup_plan_step'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          s.text('select_plan_hint'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 16),
        for (final o in _offers) _offerCard(o, s, theme),
        const SizedBox(height: 12),
        ExpansionTile(
          title: Text(s.text('compare_offers')),
          children: _offers
              .map(
                (o) => ListTile(
                  title: Text(o['name'] as String? ?? ''),
                  trailing: Text(
                    '${o['price']} ${o['currency']}${_billingLabel(o['billing_period'] as String?, s)}',
                  ),
                  subtitle: Text(
                    ((o['config'] as Map?)?['max_members'] as num?)?.toInt() == 0
                        ? s.text('unlimited_members')
                        : s
                              .text('up_to_members')
                              .replaceAll(
                                '{n}',
                                '${(o['config'] as Map?)?['max_members'] ?? '-'}',
                              ),
                  ),
                  selected: o['id'] == _offerId,
                  onTap: () => setState(() {
                    _offerId = o['id'] as String;
                  }),
                ),
              )
              .toList(),
        ),
        ExpansionTile(
          title: Text(s.text('faq')),
          children: ['faq_trial', 'faq_badges', 'faq_offline']
              .map(
                (k) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Text(s.text(k)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _offerCard(Map<String, dynamic> o, AppStrings s, ThemeData theme) {
    final config = o['config'] as Map? ?? const {};
    final selected = o['id'] == _offerId;
    final maxMembers = (config['max_members'] as num?)?.toInt() ?? 0;
    final badgeQuota = (config['badge_quota'] as num?)?.toInt() ?? 0;
    final biometric = config['biometric_supported'] == true;
    final doorAccess = config['includes_door_access'] == true;
    final tabletIncluded = config['includes_tablet'] == true;
    final tabletOptional =
        ((config['tablet_optional_price'] as num?)?.toDouble() ?? 0) > 0;
    final installments = config['installments_allowed'] == true;
    final overage = (config['overage_member_fee'] as num?)?.toDouble() ?? 0;
    final isHot = config['is_hot'] == true;
    final features = [
      for (final f in (config['features'] as List? ?? const [])) '$f',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => setState(() {
          _offerId = o['id'] as String;
        }),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : Colors.white.withValues(alpha: 0.12),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected
                        ? LucideIcons.circleCheck
                        : LucideIcons.circle,
                    size: 22,
                    color: selected
                        ? theme.colorScheme.primary
                        : Colors.white54,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              o['name'] as String? ?? '',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (isHot)
                              Text(
                                s.text('hot_badge'),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: const Color(0xfff97316),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${o['price']} ${o['currency']}${_billingLabel(o['billing_period'] as String?, s)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if ((o['description'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 10),
                Text(
                  o['description'] as String,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _capabilityChip(
                    maxMembers == 0
                        ? s.text('unlimited_members')
                        : s
                              .text('up_to_members')
                              .replaceAll('{n}', '$maxMembers'),
                    LucideIcons.users,
                    theme,
                  ),
                  if (biometric)
                    _capabilityChip(
                      s.text('biometric_access'),
                      LucideIcons.fingerprint,
                      theme,
                    ),
                  if (doorAccess)
                    _capabilityChip(
                      s.text('door_access_included'),
                      LucideIcons.doorOpen,
                      theme,
                    ),
                  if (tabletIncluded)
                    _capabilityChip(
                      s.text('included_tablet_badge'),
                      LucideIcons.tablet,
                      theme,
                    )
                  else if (tabletOptional)
                    _capabilityChip(
                      s.text('tablet_option'),
                      LucideIcons.tablet,
                      theme,
                    ),
                  if (badgeQuota > 0)
                    _capabilityChip(
                      s
                          .text('badges_included_badge')
                          .replaceAll('{n}', '$badgeQuota'),
                      LucideIcons.badgeCheck,
                      theme,
                    )
                  else
                    _capabilityChip(
                      s.text('no_physical_badges'),
                      LucideIcons.badgeCheck,
                      theme,
                    ),
                  if (installments)
                    _capabilityChip(
                      s.text('installments_3'),
                      LucideIcons.creditCard,
                      theme,
                    ),
                  if (overage > 0)
                    _capabilityChip(
                      '${s.text('per_extra_member')} : +${overage.toStringAsFixed(2)} ${o['currency']}',
                      LucideIcons.userPlus,
                      theme,
                    ),
                ],
              ),
              if (features.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final f in features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: theme.textTheme.bodySmall),
                        Expanded(
                          child: Text(f, style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _reviewStep(AppStrings s, ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(s.text('signup_review_step'), style: theme.textTheme.titleLarge),
      const SizedBox(height: 16),
      _row(s.text('gym_name'), _gymName.text),
      _row(s.text('gym_code'), _gymCode.text.toUpperCase()),
      _row(s.text('email'), _ownerEmail.text),
      _row(s.text('plan'), _offer?['name'] as String? ?? _offerId),
      _row(s.text('trial'), '7 ${s.text('days')}'),
      const SizedBox(height: 12),
      Text(
        s.text('signup_legal'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    ],
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _success(AppStrings s, ThemeData theme) => Scaffold(
    backgroundColor: const Color(0xff121417),
    body: SecurGymBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xff1a1d24).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.circleCheck,
                  size: 72,
                  color: Color(0xffff6600),
                ),
                const SizedBox(height: 24),
                Text(
                  s.text('signup_done_title'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  s.text('signup_done_body'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xff9ca3af),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xffff6600),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => context.go('/login'),
                    child: Text(s.text('sign_in'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
