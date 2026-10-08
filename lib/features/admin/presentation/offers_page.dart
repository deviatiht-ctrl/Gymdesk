import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../gyms/data/gyms_repository.dart';
import '../../gyms/domain/gym.dart';

/// Catalogue des offres plateforme (super admin) : montre au client
/// les plans disponibles avec prix, période et quota de badges.
class OffersPage extends ConsumerStatefulWidget {
  const OffersPage({super.key});
  @override
  ConsumerState<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends ConsumerState<OffersPage> {
  late Future<List<PlatformOffer>> _offers;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() {
    _offers = GymsRepository(ref.read(appRuntimeProvider).client).loadOffers();
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
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
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(s.text('offers_catalog_hint')),
                ],
              ),
            ),
            IconButton(
              tooltip: s.text('retry'),
              onPressed: _reload,
              icon: const Icon(LucideIcons.refreshCw),
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
                final wide = constraints.maxWidth >= 900;
                final width = wide
                    ? (constraints.maxWidth - 32) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final offer in offers)
                      SizedBox(width: width, child: _OfferCard(offer)),
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
  const _OfferCard(this.offer);
  final PlatformOffer offer;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    offer.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (offer.isAnnual)
                  Chip(
                    label: Text(s.text('annual')),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (offer.description?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(
                offer.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.outline,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${offer.price % 1 == 0 ? offer.price.toStringAsFixed(0) : offer.price.toStringAsFixed(2)} ${offer.currency}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    ' ${s.text(offer.isAnnual ? 'per_year' : 'per_month')}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(LucideIcons.idCard, size: 14),
                  label: Text(
                    '${s.text('badge_quota')} : ${offer.badgeQuota}',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                if (offer.minMonthly > 0)
                  Chip(
                    avatar: const Icon(LucideIcons.banknote, size: 14),
                    label: Text(
                      '${s.text('min_monthly')} : ${offer.minMonthly.toStringAsFixed(0)} ${offer.currency}',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                if (offer.setupFee > 0)
                  Chip(
                    avatar: const Icon(LucideIcons.wrench, size: 14),
                    label: Text(
                      '${s.text('setup_fee')} : ${offer.setupFee.toStringAsFixed(0)} ${offer.currency}',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (offer.tiers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                s.text('tiers'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              for (final tier in offer.tiers)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s
                              .text('up_to_members')
                              .replaceAll('{n}', '${tier['max_members']}'),
                        ),
                      ),
                      Text(
                        '${tier['price']} ${offer.currency} ${s.text('per_month')}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
}
