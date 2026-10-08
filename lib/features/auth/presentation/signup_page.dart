import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../l10n/app_strings.dart';

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
  String _offerId = 'per_member';
  double _offerIndex = 0;
  List<Map<String, dynamic>> _offers = const [];

  @override
  void initState() {
    super.initState();
    _loadOffers();
  }

  Future<void> _loadOffers() async {
    try {
      final rows = await Supabase.instance.client
          .from('platform_offers')
          .select()
          .eq('active', true)
          .order('price');
      if (mounted) {
        setState(() {
          _offers = List<Map<String, dynamic>>.from(rows);
          if (_offers.isNotEmpty) _offerId = _offers.first['id'] as String;
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
    if (_busy || !_gymValid || !_ownerValid) return;
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
      appBar: AppBar(
        title: Text(s.text('signup_title')),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(24),
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

  Widget _planStep(AppStrings s, ThemeData theme) {
    final count = _offers.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.text('signup_plan_step'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          s.text('signup_plan_hint'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 16),
        if (count > 1)
          Slider(
            value: _offerIndex.clamp(0, (count - 1).toDouble()),
            min: 0,
            max: (count - 1).toDouble(),
            divisions: count - 1,
            onChanged: (v) => setState(() {
              _offerIndex = v;
              _offerId = _offers[v.round()]['id'] as String;
            }),
          ),
        if (_offer != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _offer!['name'] as String? ?? '',
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        '${_offer!['price']} ${_offer!['currency']}/${_offer!['billing_period'] == 'annual' ? s.text('per_year') : s.text('per_month')}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_offer!['description'] as String? ?? ''),
                  const SizedBox(height: 8),
                  Text(
                    s.text('included_badges').replaceAll(
                      '{n}',
                      '${(_offer!['config'] as Map?)?['badge_quota'] ?? 10}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: Text(s.text('compare_offers')),
          children: _offers
              .map(
                (o) => ListTile(
                  title: Text(o['name'] as String? ?? ''),
                  trailing: Text('${o['price']} ${o['currency']}'),
                  subtitle: Text(
                    '${(o['config'] as Map?)?['badge_quota'] ?? '-'} ${s.text('badges').toLowerCase()}',
                  ),
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
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.circleCheck,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  s.text('signup_done_title'),
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  s.text('signup_done_body'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: Text(s.text('sign_in')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
