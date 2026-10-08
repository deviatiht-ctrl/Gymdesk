import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../gyms/data/gyms_repository.dart';
import '../../gyms/domain/gym.dart';

/// Katalòg ofisyèl plan yo pou Super Admin ak Kliyan :
/// - Pèmèt Super Admin modifye tout bagay (pri, avantaj, tablèt enkli, badges gratis, plan popilè/hot).
/// - Pèmèt ajoute nouvo plan oswa dezaktive ansyen plan.
/// - Afichaj modèn ak badge "PI POPILÈ 🔥", "Tablèt Enkli 📱", elatriye.
class OffersPage extends ConsumerStatefulWidget {
  const OffersPage({super.key});
  @override
  ConsumerState<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends ConsumerState<OffersPage> {
  late Future<List<PlatformOffer>> _offers;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() {
    _offers = GymsRepository(ref.read(appRuntimeProvider).client).loadOffers();
  });

  Future<void> _seedOfficialPlans() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = GymsRepository(ref.read(appRuntimeProvider).client);
      await repo.seedDefaultAnnualPlans();
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('4 Plan Anyèl yo anrejistre nan baz la avèk siksè !'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erè : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEditDialog([PlatformOffer? existing]) async {
    final s = AppStrings.of(context);
    final repo = GymsRepository(ref.read(appRuntimeProvider).client);

    final isNew = existing == null;
    final idController = TextEditingController(text: existing?.id ?? '');
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    final priceController = TextEditingController(
      text: existing != null
          ? (existing.price % 1 == 0 ? existing.price.toStringAsFixed(0) : existing.price.toStringAsFixed(2))
          : '350',
    );
    final currencyController = TextEditingController(text: existing?.currency ?? 'USD');
    final badgeQuotaController = TextEditingController(
      text: existing != null ? '${existing.badgeQuota}' : '0',
    );
    final maxMembersController = TextEditingController(
      text: existing != null ? '${existing.maxMembers}' : '50',
    );
    final overageMemberFeeController = TextEditingController(
      text: existing != null ? '${existing.overageMemberFee}' : '2.0',
    );
    final tabletCountController = TextEditingController(
      text: existing != null ? '${existing.tabletCount}' : '0',
    );
    final tabletOptionalPriceController = TextEditingController(
      text: existing != null ? '${existing.tabletOptionalPrice}' : '180.0',
    );
    final featuresController = TextEditingController(
      text: existing != null && existing.features.isNotEmpty
          ? existing.features.join('\n')
          : 'Jiska 50 manb aktif\nDepasman : +2.00 USD / manb extra\nBadj QR fizik sou kòmand\nOpsyon Tablèt Android : +180 USD',
    );

    String billingPeriod = existing?.billingPeriod ?? 'annual';
    bool isHot = existing?.isHot ?? false;
    bool includesTablet = existing?.includesTablet ?? (billingPeriod == 'annual');

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isNew ? LucideIcons.plusCircle : LucideIcons.edit3,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(isNew ? s.text('add_offer') : s.text('edit_offer')),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isNew) ...[
                      TextField(
                        controller: idController,
                        decoration: const InputDecoration(
                          labelText: 'ID Inik (pa egzanp: pro_annual, starter)',
                          prefixIcon: Icon(LucideIcons.key),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: s.text('offer_name'),
                        prefixIcon: const Icon(LucideIcons.tag),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Deskripsyon kout',
                        prefixIcon: Icon(LucideIcons.alignLeft),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: priceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: s.text('offer_price'),
                              prefixIcon: const Icon(LucideIcons.dollarSign),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: currencyController.text,
                            decoration: InputDecoration(labelText: s.text('offer_currency')),
                            items: const [
                              DropdownMenuItem(value: 'USD', child: Text('USD')),
                              DropdownMenuItem(value: 'HTG', child: Text('HTG')),
                            ],
                            onChanged: (v) {
                              if (v != null) currencyController.text = v;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: billingPeriod,
                      decoration: InputDecoration(labelText: s.text('offer_billing_period')),
                      items: [
                        DropdownMenuItem(value: 'annual', child: Text(s.text('annual'))),
                        DropdownMenuItem(value: 'monthly', child: Text(s.text('monthly'))),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            billingPeriod = val;
                            if (val == 'annual') includesTablet = true;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: maxMembersController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Max Manb (0 = Ilimite)',
                              prefixIcon: Icon(LucideIcons.users),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: overageMemberFeeController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Frè Depasman / manb',
                              prefixIcon: Icon(LucideIcons.userPlus),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: tabletCountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Tablèt Gratis',
                              prefixIcon: Icon(LucideIcons.tablet),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: tabletOptionalPriceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Pri Opsyon Tablèt',
                              prefixIcon: Icon(LucideIcons.dollarSign),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: badgeQuotaController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '${s.text('badge_quota_count')} (Gratis)',
                        prefixIcon: const Icon(LucideIcons.idCard),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Switches pou opsyon kle
                    SwitchListTile(
                      title: Text(s.text('includes_tablet')),
                      subtitle: const Text('Founi yon tablèt Android pou scan badges nan gym nan'),
                      value: includesTablet,
                      onChanged: (val) => setDialogState(() => includesTablet = val),
                    ),
                    SwitchListTile(
                      title: Text(s.text('is_hot_plan')),
                      subtitle: const Text('Mete yon bèl etikèt "PI POPILÈ 🔥" ak koulè anfaz'),
                      value: isHot,
                      onChanged: (val) => setDialogState(() => isHot = val),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: featuresController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: s.text('plan_features'),
                        hintText: s.text('plan_features_hint'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.text('cancel')),
              ),
              FilledButton.icon(
                icon: const Icon(LucideIcons.check, size: 16),
                label: Text(s.text('save')),
                onPressed: () async {
                  final id = isNew ? idController.text.trim() : existing.id;
                  final name = nameController.text.trim();
                  final price = double.tryParse(priceController.text.replaceAll(',', '.')) ?? 0;
                  final quota = int.tryParse(badgeQuotaController.text) ?? 0;
                  final maxMembers = int.tryParse(maxMembersController.text) ?? 50;
                  final overageFee = double.tryParse(overageMemberFeeController.text.replaceAll(',', '.')) ?? 0.0;
                  final tabletCount = int.tryParse(tabletCountController.text) ?? (includesTablet ? 1 : 0);
                  final tabletOptionalPrice = double.tryParse(tabletOptionalPriceController.text.replaceAll(',', '.')) ?? 0.0;
                  if (id.isEmpty || name.isEmpty) return;

                  final rawFeatures = featuresController.text
                      .split('\n')
                      .map((l) => l.trim())
                      .where((l) => l.isNotEmpty)
                      .toList();

                  final Map<String, dynamic> config = Map<String, dynamic>.from(existing?.config ?? {});
                  config['badge_quota'] = quota;
                  config['max_members'] = maxMembers;
                  config['overage_member_fee'] = overageFee;
                  config['tablet_count'] = tabletCount;
                  config['tablet_optional_price'] = tabletOptionalPrice;
                  config['includes_tablet'] = includesTablet || tabletCount > 0;
                  config['is_hot'] = isHot;
                  config['features'] = rawFeatures;

                  final offerToSave = PlatformOffer(
                    id: id,
                    name: name,
                    description: descController.text.trim(),
                    billingPeriod: billingPeriod,
                    price: price,
                    currency: currencyController.text,
                    config: config,
                  );

                  try {
                    await repo.saveOffer(offerToSave);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Erè nan anrejistreman: $e')),
                      );
                    }
                  }
                },
              ),
            ],
          );
        },
      ),
    );

    if (updated == true) {
      _reload();
    }
  }

  Future<void> _confirmDelete(PlatformOffer offer) async {
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('delete_offer')),
        content: Text('Èske ou sèten ou vle efase/dezaktive plan "${offer.name}" la?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.text('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final repo = GymsRepository(ref.read(appRuntimeProvider).client);
      await repo.deleteOffer(offer.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final runtime = ref.watch(appRuntimeProvider);
    final isSuperAdmin = runtime.session?.isPlatformAdmin == true;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.text('offers_catalog'),
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSuperAdmin
                        ? 'Ou gen kontwòl total : ou ka ajoute, modifye pri, avantaj, tablèt, ak badges pou chak plan.'
                        : s.text('offers_catalog_hint'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: s.text('retry'),
                  onPressed: _reload,
                  icon: const Icon(LucideIcons.refreshCw, size: 18),
                ),
                if (isSuperAdmin) ...[
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.sparkles, size: 18),
                    label: const Text('Inisyalize 4 Plan Anyèl yo'),
                    onPressed: _busy ? null : _seedOfficialPlans,
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text(s.text('add_offer')),
                    onPressed: _busy ? null : () => _openEditDialog(),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        FutureBuilder<List<PlatformOffer>>(
          future: _offers,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingPanel();
            }
            if (snapshot.hasError) {
              return MessagePanel(
                message: s.text(
                  snapshot.error is PlatformFailure
                      ? (snapshot.error as PlatformFailure).code
                      : 'error',
                ),
                action: s.text('retry'),
                onAction: _reload,
              );
            }
            final offers = snapshot.data!;
            if (offers.isEmpty) {
              return MessagePanel(message: s.text('no_offers'));
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 960;
                final width = wide
                    ? (constraints.maxWidth - 32) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final offer in offers)
                      SizedBox(
                        width: width,
                        child: _OfferCard(
                          offer,
                          isSuperAdmin: isSuperAdmin,
                          onEdit: () => _openEditDialog(offer),
                          onDelete: () => _confirmDelete(offer),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard(
    this.offer, {
    required this.isSuperAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  final PlatformOffer offer;
  final bool isSuperAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isHot = offer.isHot;

    return Card(
      elevation: isHot ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isHot ? colors.primary : colors.outlineVariant.withAlpha(120),
          width: isHot ? 2.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isHot) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        s.text('hot_badge'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        offer.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(s.text(offer.isAnnual ? 'annual' : 'monthly')),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: offer.isAnnual
                          ? colors.primaryContainer.withAlpha(150)
                          : colors.surfaceContainerHighest,
                    ),
                  ],
                ),
                if (offer.description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 6),
                  Text(
                    offer.description!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${offer.price % 1 == 0 ? offer.price.toStringAsFixed(0) : offer.price.toStringAsFixed(2)} ${offer.currency}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '/${s.text(offer.isAnnual ? 'per_year' : 'per_month')}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.outline,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // Karakteristik & Avantaj founi
                _FeatureRow(
                  icon: LucideIcons.users,
                  text: offer.maxMembers == 0
                      ? 'Manb Ilimite (San limit) 🚀'
                      : 'Jiska ${offer.maxMembers} manb aktif',
                  highlight: offer.maxMembers == 0,
                ),
                const SizedBox(height: 8),
                if (offer.overageMemberFee > 0) ...[
                  _FeatureRow(
                    icon: LucideIcons.userPlus,
                    text: 'Depasman : +${offer.overageMemberFee.toStringAsFixed(2)} USD / manb extra',
                  ),
                  const SizedBox(height: 8),
                ],
                _FeatureRow(
                  icon: LucideIcons.idCard,
                  text: offer.badgeQuota > 0
                      ? '${offer.badgeQuota} Badj QR GRATIS enkli 🪪'
                      : 'Badj QR fizik sou kòmand (frais impression)',
                  highlight: offer.badgeQuota > 0,
                ),
                const SizedBox(height: 8),
                if (offer.tabletCount > 0) ...[
                  _FeatureRow(
                    icon: LucideIcons.tablet,
                    text: '${offer.tabletCount} Tablèt Android GRATIS enkli 📱',
                    highlight: true,
                  ),
                  const SizedBox(height: 8),
                ] else if (offer.tabletOptionalPrice > 0) ...[
                  _FeatureRow(
                    icon: LucideIcons.tablet,
                    text: 'Opsyon Tablèt Android : +${offer.tabletOptionalPrice.toStringAsFixed(0)} USD',
                  ),
                  const SizedBox(height: 8),
                ],
                for (final feat in offer.features) ...[
                  _FeatureRow(
                    icon: LucideIcons.checkCircle2,
                    text: feat,
                  ),
                  const SizedBox(height: 8),
                ],

                if (offer.minMonthly > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${s.text('min_monthly')} : ${offer.minMonthly.toStringAsFixed(0)} ${offer.currency}',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
                    ),
                  ),

                // Bouton pou Super Admin modifye dirèkteman
                if (isSuperAdmin) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(LucideIcons.edit2, size: 16),
                          label: Text(s.text('edit_offer')),
                          onPressed: onEdit,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: s.text('delete_offer'),
                        icon: Icon(LucideIcons.trash2, size: 16, color: colors.error),
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.text,
    this.highlight = false,
  });

  final IconData icon;
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: highlight ? colors.primary : Colors.green.shade600,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              color: highlight ? colors.primary : theme.textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ],
    );
  }
}
