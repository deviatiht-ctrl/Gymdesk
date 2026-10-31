import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../data/gyms_repository.dart';
import '../domain/gym.dart';

/// Fiche complète d'une salle pour le super admin :
/// identité, contacts, statistiques, contrat/offre, propriétaire
/// et actions (édition, suspension, paiement, reset propriétaire, archivage).
class GymDetailPage extends ConsumerStatefulWidget {
  const GymDetailPage({super.key, required this.gymId});
  final String gymId;

  @override
  ConsumerState<GymDetailPage> createState() => _GymDetailPageState();
}

class _GymDetailPageState extends ConsumerState<GymDetailPage> {
  late final GymsRepository _repository;
  late Future<GymDetail> _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repository = GymsRepository(ref.read(appRuntimeProvider).client);
    _result = _repository.gymDetail(widget.gymId);
  }

  void _reload() =>
      setState(() => _result = _repository.gymDetail(widget.gymId));

  void _toast(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).text(key))));
  }

  String _billingLabel(String? period, AppStrings s) => switch (period) {
    'annual' => s.text('per_year'),
    'monthly' => s.text('per_month'),
    'one_time' || 'unique' => s.text('billing_one_time'),
    'lifetime' => s.text('billing_lifetime'),
    _ => '',
  };

  String _date(String? iso) =>
      iso != null && iso.length >= 10 ? iso.substring(0, 10) : '—';

  Future<void> _changeStatus(Gym gym, String action) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final confirmation = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${s.text(action)} · ${gym.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.text('${action}_confirmation')),
              if (action == 'archive') ...[
                const SizedBox(height: 16),
                Text(gym.code),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmation,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: s.text('confirm_code'),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.text('cancel')),
            ),
            FilledButton(
              onPressed: action == 'archive' && confirmation.text != gym.code
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(s.text(action)),
            ),
          ],
        ),
      ),
    );
    final typed = confirmation.text;
    confirmation.dispose();
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (action == 'reset_owner') {
        await _repository.resetOwnerPassword(gym);
      } else {
        await _repository.changeStatus(
          gym,
          action,
          confirmation: action == 'archive' ? typed : null,
        );
      }
      await HapticFeedback.lightImpact();
      _toast(action == 'reset_owner' ? 'reset_sent' : 'gym_updated');
      _reload();
    } on PlatformFailure catch (e) {
      _toast(e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(GymDetail detail) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final gym = detail.gym;
    final name = TextEditingController(text: gym.name);
    final code = TextEditingController(text: gym.code);
    final accent = TextEditingController(text: gym.accentColor);
    final timezone = TextEditingController(text: gym.timezone);
    final address = TextEditingController(text: gym.address ?? '');
    final phone = TextEditingController(text: gym.phone ?? '');
    final email = TextEditingController(text: gym.email ?? '');
    var currency = gym.currency;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${s.text('edit_gym')} · ${gym.name}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: s.text('name')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: code,
                    decoration: InputDecoration(
                      labelText: s.text('code'),
                      helperText: 'A–Z, 0–9 · 2–8',
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                      LengthLimitingTextInputFormatter(8),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: accent,
                    decoration: InputDecoration(
                      labelText: s.text('accent_color'),
                      helperText: s.text('accent_hint'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: timezone,
                    decoration: InputDecoration(
                      labelText: s.text('timezone'),
                      helperText: 'ex. America/Port-au-Prince',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: currency,
                    decoration: InputDecoration(
                      labelText: s.text('currency'),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'HTG', child: Text('HTG')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => currency = v ?? currency),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phone,
                    decoration: InputDecoration(labelText: s.text('phone')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: email,
                    decoration: InputDecoration(labelText: s.text('email')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: address,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: s.text('address')),
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
              child: Text(s.text('save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) {
      for (final c in [name, code, accent, timezone, address, phone, email]) {
        c.dispose();
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.updateGym(widget.gymId, {
        'name': name.text,
        'code': code.text,
        'accent_color': accent.text,
        'timezone': timezone.text,
        'currency': currency,
        'address': address.text,
        'phone': phone.text,
        'email': email.text,
      });
      await HapticFeedback.lightImpact();
      _toast('gym_updated');
      _reload();
    } on PlatformFailure catch (e) {
      _toast(e.code);
    } finally {
      for (final c in [name, code, accent, timezone, address, phone, email]) {
        c.dispose();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _registerPayment(GymDetail detail) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    List<PlatformOffer> offers;
    try {
      offers = await _repository.loadOffers();
    } catch (_) {
      offers = const [];
    }
    if (!mounted || offers.isEmpty) {
      _toast(offers.isEmpty ? 'no_offers' : 'network');
      return;
    }
    var offer = offers.firstWhere(
      (o) => o.id == detail.contract?['offer_id'],
      orElse: () => offers.first,
    );
    final amount = TextEditingController(
      text: offer.price.toStringAsFixed(0),
    );
    final reference = TextEditingController();
    final note = TextEditingController();
    var method = 'cash';
    var paid = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${s.text('register_payment')} · ${detail.gym.name}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<PlatformOffer>(
                    initialValue: offer,
                    decoration: InputDecoration(
                      labelText: s.text('select_offer'),
                    ),
                    items: [
                      for (final o in offers)
                        DropdownMenuItem(
                          value: o,
                          child: Text(
                            '${o.name} · ${o.price.toStringAsFixed(0)} ${o.currency}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() {
                      offer = v ?? offer;
                      amount.text = offer.price.toStringAsFixed(0);
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: s.text('amount_paid'),
                      suffixText: offer.currency,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: InputDecoration(labelText: s.text('method')),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(
                        value: 'transfer',
                        child: Text('Virement / Transfer'),
                      ),
                      DropdownMenuItem(value: 'card', child: Text('Carte')),
                      DropdownMenuItem(value: 'other', child: Text('Autre')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => method = v ?? method),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reference,
                    decoration: InputDecoration(
                      labelText: s.text('reference'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    decoration: InputDecoration(labelText: s.text('note')),
                  ),
                  SwitchListTile(
                    value: paid,
                    onChanged: (v) => setDialogState(() => paid = v),
                    title: Text(s.text('payment_received_now')),
                    subtitle: Text(s.text('payment_cash_hint')),
                    contentPadding: EdgeInsets.zero,
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
              child: Text(s.text('save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) {
      amount.dispose();
      reference.dispose();
      note.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.registerPayment(
        gymId: widget.gymId,
        offerId: offer.id,
        amount: double.tryParse(amount.text.replaceAll(',', '.')) ?? 0,
        currency: offer.currency,
        method: method,
        reference: reference.text.trim().isEmpty ? null : reference.text.trim(),
        note: note.text.trim().isEmpty ? null : note.text.trim(),
        paid: paid,
      );
      await HapticFeedback.lightImpact();
      _toast('payment_registered');
      _reload();
    } on PlatformFailure catch (e) {
      _toast(e.code);
    } finally {
      amount.dispose();
      reference.dispose();
      note.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: FutureBuilder<GymDetail>(
            future: _result,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: LoadingPanel(),
                );
              }
              if (snapshot.hasError) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: MessagePanel(
                    message: s.text(
                      snapshot.error is PlatformFailure
                          ? (snapshot.error as PlatformFailure).code
                          : 'error',
                    ),
                    action: s.text('retry'),
                    onAction: _reload,
                  ),
                );
              }
              final detail = snapshot.data!;
              final gym = detail.gym;
              final status = gym.archived ? 'archived' : gym.status;
              final color = status == 'active'
                  ? const Color(0xff37634d)
                  : const Color(0xff855f32);
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: s.text('back'),
                        onPressed: () =>
                            context.canPop() ? context.pop() : context.go('/gyms'),
                        icon: const Icon(LucideIcons.arrowLeft),
                      ),
                      _GymLogoBox(gymId: gym.id, logoUrl: detail.logoUrl),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                gym.name,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              Text(gym.code),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  s.text(status),
                                  style: TextStyle(color: color),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${gym.timezone} · ${gym.currency}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _edit(detail),
                        icon: const Icon(LucideIcons.penLine, size: 18),
                        label: Text(s.text('edit_gym')),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _changeStatus(
                                gym,
                                gym.status == 'active'
                                    ? 'suspend'
                                    : 'reactivate',
                              ),
                        icon: Icon(
                          gym.status == 'active'
                              ? LucideIcons.pause
                              : LucideIcons.play,
                          size: 18,
                        ),
                        label: Text(
                          s.text(
                            gym.status == 'active' ? 'suspend' : 'reactivate',
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _registerPayment(detail),
                        icon: const Icon(LucideIcons.banknote, size: 18),
                        label: Text(s.text('register_payment')),
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _changeStatus(gym, 'reset_owner'),
                        icon: const Icon(LucideIcons.keyRound, size: 18),
                        label: Text(s.text('reset_owner')),
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _changeStatus(gym, 'archive'),
                        icon: const Icon(LucideIcons.archive, size: 18),
                        label: Text(s.text('archive')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final two = constraints.maxWidth >= 900;
                      final width = two
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          SizedBox(width: width, child: _infoCard(detail, s)),
                          SizedBox(
                            width: width,
                            child: _statsCard(detail, s),
                          ),
                          SizedBox(
                            width: width,
                            child: _contractCard(detail, s),
                          ),
                          SizedBox(width: width, child: _ownerCard(detail, s)),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _card(String title, IconData icon, List<Widget> children) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Widget _row(String label, String? value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xff6b7280), fontSize: 13),
          ),
        ),
        Expanded(
          child: SelectableText(
            value == null || value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ),
  );

  Widget _infoCard(GymDetail d, AppStrings s) =>
      _card(s.text('general_info'), LucideIcons.building2, [
        _row(s.text('name'), d.gym.name),
        _row(s.text('code'), d.gym.code),
        _row(s.text('accent_color'), d.gym.accentColor),
        _row(s.text('timezone'), d.gym.timezone),
        _row(s.text('currency'), d.gym.currency),
        if (d.source?.isNotEmpty ?? false) _row('Source', d.source),
        _row(s.text('registered_on'), _date(d.createdAt)),
        if (d.trialEndsAt != null) _row(s.text('trial_ends'), _date(d.trialEndsAt)),
        _row(s.text('contact'), null),
        _row(s.text('address'), d.gym.address),
        _row(s.text('phone'), d.gym.phone),
        _row(s.text('email'), d.gym.email),
      ]);

  Widget _statsCard(GymDetail d, AppStrings s) {
    Widget stat(String label, String value, IconData icon) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Icon(icon, size: 18, color: const Color(0xff6b7280)),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xff6b7280)),
            ),
          ],
        ),
      ),
    );
    final money =
        '${d.paymentsTotal.toStringAsFixed(0)} ${d.gym.currency}';
    return _card(s.text('statistics'), LucideIcons.chartColumn, [
      Row(
        children: [
          stat(s.text('members'), '${d.stat('members')}', LucideIcons.users),
          stat(
            s.text('members_active'),
            '${d.stat('members_active')}',
            LucideIcons.userCheck,
          ),
          stat(s.text('staff'), '${d.stat('staff')}', LucideIcons.idCard),
        ],
      ),
      Row(
        children: [
          stat(
            s.text('subscriptions_active'),
            '${d.stat('subscriptions_active')}',
            LucideIcons.calendarCheck,
          ),
          stat(s.text('plans'), '${d.stat('plans')}', LucideIcons.tag),
          stat(
            s.text('entries_today'),
            '${d.stat('entries_today')}',
            LucideIcons.scanLine,
          ),
        ],
      ),
      Row(
        children: [
          stat(s.text('payments_collected'), money, LucideIcons.banknote),
          stat(
            s.text('payments_count'),
            '${d.stat('payments_count')}',
            LucideIcons.receipt,
          ),
          stat(
            s.text('badges_used'),
            '${d.stat('badges_used')}/${d.stat('badges')}',
            LucideIcons.badgeCheck,
          ),
        ],
      ),
      Row(
        children: [
          stat(
            s.text('portal_accounts'),
            '${d.stat('member_accounts')}',
            LucideIcons.smartphone,
          ),
          stat(
            s.text('portal_pending'),
            '${d.stat('portal_pending')}',
            LucideIcons.globe,
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    ]);
  }

  Widget _contractCard(GymDetail d, AppStrings s) {
    final c = d.contract;
    if (c == null) {
      return _card('${s.text('contract')} & ${s.text('offer')}', LucideIcons.fileText, [
        Text(s.text('no_contract')),
      ]);
    }
    final period = c['billing_period'] as String?;
    final expires = c['expires_at'] as String?;
    final snapshot = c['price_snapshot'];
    final paid = snapshot is Map ? snapshot['price'] : snapshot;
    final paidCurrency = (snapshot is Map ? snapshot['currency'] : null) ?? c['offer_currency'] ?? '';
    return _card('${s.text('contract')} & ${s.text('offer')}', LucideIcons.fileText, [
      _row(s.text('offer'), c['offer_name'] as String? ?? '—'),
      _row(
        s.text('offer_price'),
        '${(c['offer_price'] as num?)?.toStringAsFixed(0) ?? '—'} ${c['offer_currency'] ?? ''} ${_billingLabel(period, s)}'
            .trim(),
      ),
      _row(s.text('contract_status'), c['status'] as String? ?? '—'),
      _row('Début', _date(c['starts_at'] as String?)),
      _row(
        s.text('contract_expires'),
        expires == null ? s.text('never_expires') : _date(expires),
      ),
      _row(
        s.text('amount_paid'),
        '${paid is num ? paid.toStringAsFixed(0) : '—'} $paidCurrency',
      ),
    ]);
  }

  Widget _ownerCard(GymDetail d, AppStrings s) {
    final o = d.owner;
    if (o == null) {
      return _card(s.text('owner'), LucideIcons.userRound, [
        Text(s.text('owner_missing')),
      ]);
    }
    return _card(s.text('owner'), LucideIcons.userRound, [
      _row(s.text('owner_name'), o['full_name'] as String?),
      _row(s.text('email'), o['email'] as String?),
      _row(s.text('phone'), o['phone'] as String?),
      _row(s.text('last_sign_in'), _date(o['last_sign_in'] as String?)),
      _row(s.text('registered_on'), _date(o['created_at'] as String?)),
    ]);
  }
}

/// Logo de la salle via URL signée (gym-assets), sinon icône SecurGYM.
class _GymLogoBox extends ConsumerStatefulWidget {
  const _GymLogoBox({required this.gymId, this.logoUrl});
  final String gymId;
  final String? logoUrl;

  @override
  ConsumerState<_GymLogoBox> createState() => _GymLogoBoxState();
}

class _GymLogoBoxState extends ConsumerState<_GymLogoBox> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = widget.logoUrl;
    if (path == null || path.isEmpty) return;
    try {
      final url = await ref
          .read(appRuntimeProvider)
          .client
          .storage
          .from('gym-assets')
          .createSignedUrl(path, 3600);
      if (mounted) setState(() => _url = url);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 56,
        height: 56,
        color: const Color(0xfff3f4f6),
        child: url != null
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Padding(
    padding: const EdgeInsets.all(8),
    child: Image.asset('assets/brand/icon_securgym.png', fit: BoxFit.contain),
  );
}
