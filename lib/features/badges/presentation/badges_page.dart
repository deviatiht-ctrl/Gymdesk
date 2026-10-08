import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../settings/data/settings_repository.dart';
import '../data/badge_pdf.dart';
import '../data/badges_repository.dart';
import '../domain/badge.dart';
import 'badge_card.dart';

class BadgesPage extends ConsumerStatefulWidget {
  const BadgesPage({super.key});

  @override
  ConsumerState<BadgesPage> createState() => _BadgesPageState();
}

class _BadgesPageState extends ConsumerState<BadgesPage> {
  late final BadgesRepository _repository;
  late final GymSettingsRepository _settings;
  final _search = TextEditingController();
  String _filter = 'all';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = BadgesRepository(runtime.client, runtime.database!, runtime.session!);
    _settings = GymSettingsRepository(runtime.client, runtime.database!, runtime.session!);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toast(String code) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text(code))),
      );
    }
  }

  Future<void> _generateBatchDialog(BadgeQuotaInfo quota) async {
    final s = AppStrings.of(context);
    if (!quota.canGenerate) {
      _toast('badge_quota_reached');
      return;
    }

    int quantity = quota.quotaRemaining.clamp(1, 50);
    final countController = TextEditingController(text: quantity.toString());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(s.text('generate_badge_batch')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${s.text('quota_remaining')}: ${quota.quotaRemaining} ${s.text('badges').toLowerCase()}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: countController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: s.text('badge_quantity'),
                  helperText: '${s.text('max')}: ${quota.quotaRemaining}',
                ),
                onChanged: (v) {
                  final parsed = int.tryParse(v) ?? 1;
                  quantity = parsed.clamp(1, quota.quotaRemaining);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.text('generate')),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _busy = true);
      try {
        await _repository.generateBatch(quantity);
        await ref.read(appRuntimeProvider).sync?.synchronize();
        _toast('badge_batch_generated');
      } catch (_) {
        _toast('badge_batch_failed');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  /// Dialogue de sélection de la quantité pour l'impression ou l'export
  Future<void> _showPrintQuantityDialog(List<BadgeItem> badges, {required bool isShare}) async {
    final s = AppStrings.of(context);
    if (_busy || badges.isEmpty) return;

    final availableBadges = badges.where((b) => b.isAvailable).toList();
    int selectedCount = availableBadges.isNotEmpty ? availableBadges.length : badges.length;
    String mode = availableBadges.isNotEmpty ? 'available' : 'all';

    final confirmed = await showDialog<List<BadgeItem>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final countController = TextEditingController(text: selectedCount.toString());
          return AlertDialog(
            title: Text(s.text('select_print_quantity')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<String>(
                    title: Text('${s.text('print_all_available')} (${availableBadges.length})'),
                    value: 'available',
                    groupValue: mode,
                    onChanged: availableBadges.isEmpty ? null : (v) {
                      setModalState(() {
                        mode = v!;
                        selectedCount = availableBadges.length;
                      });
                    },
                  ),
                  RadioListTile<String>(
                    title: Text('${s.text('print_all_badges')} (${badges.length})'),
                    value: 'all',
                    groupValue: mode,
                    onChanged: (v) {
                      setModalState(() {
                        mode = v!;
                        selectedCount = badges.length;
                      });
                    },
                  ),
                  RadioListTile<String>(
                    title: Text(s.text('custom_quantity')),
                    value: 'custom',
                    groupValue: mode,
                    onChanged: (v) {
                      setModalState(() {
                        mode = v!;
                        selectedCount = selectedCount.clamp(1, badges.length);
                      });
                    },
                  ),
                  if (mode == 'custom') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: countController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.text('badge_quantity'),
                        helperText: '1 - ${badges.length}',
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val) ?? 1;
                        selectedCount = parsed.clamp(1, badges.length);
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(s.text('cancel')),
              ),
              FilledButton(
                onPressed: () {
                  List<BadgeItem> target;
                  if (mode == 'available') {
                    target = availableBadges;
                  } else if (mode == 'all') {
                    target = badges;
                  } else {
                    target = (availableBadges.isNotEmpty ? availableBadges : badges).take(selectedCount).toList();
                  }
                  Navigator.pop(context, target);
                },
                child: Text(isShare ? s.text('export_planche_a4') : s.text('print_batch')),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != null && confirmed.isNotEmpty && mounted) {
      setState(() => _busy = true);
      try {
        final gym = await _settings.current();
        final logoBytes = await _settings.logoBytes(gym.logoUrl);
        final pdfBytes = await buildV2BatchPlanchePdf(badges: confirmed, gym: gym, logo: logoBytes);

        if (isShare) {
          await Printing.sharePdf(
            bytes: pdfBytes,
            filename: 'gymdesk-badges-${confirmed.length}-cartes.pdf',
          );
        } else {
          await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
        }
      } catch (_) {
        _toast('badge_export_failed');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  /// Modal de prévisualisation et personnalisation globale du badge
  Future<void> _showBadgeDesignModal(BadgeItem sampleBadge) async {
    final s = AppStrings.of(context);
    final gym = await _settings.current();
    final logoBytes = await _settings.logoBytes(gym.logoUrl);

    if (!mounted) return;

    var isBack = false;
    var currentAccent = gym.accentColor;
    final footerController = TextEditingController(
      text: (gym.settings['doc_footer'] as String?) ?? 'Merci de votre visite — ${gym.name}',
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final customGym = gym.copy(
            accentColor: currentAccent,
            settings: {
              ...gym.settings,
              'doc_footer': footerController.text.trim(),
            },
          );

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        s.text('badge_design_preview'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Sélecteur Recto / Verso
                  Center(
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: false, label: Text(s.text('badge_recto')), icon: const Icon(LucideIcons.idCard)),
                        ButtonSegment(value: true, label: Text(s.text('badge_verso')), icon: const Icon(LucideIcons.fileText)),
                      ],
                      selected: {isBack},
                      onSelectionChanged: (set) => setModalState(() => isBack = set.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Carte en direct
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: BadgeCard(
                        badge: sampleBadge,
                        gym: customGym,
                        logo: logoBytes,
                        showBack: isBack,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Palette de couleurs d'accent
                  Text(s.text('badge_accent'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: [
                      '#1F6F4A', // Vert GymDesk
                      '#0D5C75', // Bleu Océan
                      '#B84018', // Rouge Brique
                      '#2B2D42', // Noir Ardoise
                      '#5A3E85', // Violet Sport
                    ].map((colorHex) {
                      final selected = currentAccent.toUpperCase() == colorHex.toUpperCase();
                      final colorVal = int.parse(colorHex.replaceFirst('#', ''), radix: 16);
                      return GestureDetector(
                        onTap: () => setModalState(() => currentAccent = colorHex),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Color(0xff000000 | colorVal),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: selected
                                ? [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 6)]
                                : null,
                          ),
                          child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Texte au verso
                  TextField(
                    controller: footerController,
                    decoration: InputDecoration(
                      labelText: s.text('badge_footer_text'),
                      helperText: s.text('badge_footer_text_hint'),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 24),
                  // Bouton Enregistrer
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(LucideIcons.save),
                      label: Text(s.text('save')),
                      onPressed: () async {
                        try {
                          final updated = gym.copy(
                            accentColor: currentAccent,
                            settings: {
                              ...gym.settings,
                              'doc_footer': footerController.text.trim(),
                            },
                          );
                          final runtime = ref.read(appRuntimeProvider);
                          await _settings.save(
                            updated,
                            changedAt: runtime.sync?.clock.correctedNow ?? DateTime.now().toUtc(),
                          );
                          await runtime.sync?.synchronize();
                          if (context.mounted) Navigator.pop(context);
                          _toast('saved');
                        } catch (_) {
                          _toast('error');
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(String status, ColorScheme colors) => switch (status) {
    'unassigned' => colors.primary,
    'bound' => Colors.blueGrey,
    'blocked' => colors.error,
    _ => colors.outline,
  };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return StreamBuilder<BadgeQuotaInfo>(
      stream: _repository.watchQuota(),
      builder: (context, quotaSnap) {
        final quota = quotaSnap.data ?? const BadgeQuotaInfo(
          totalGenerated: 0,
          totalBound: 0,
          totalAvailable: 0,
          totalBlocked: 0,
          quotaLimit: 100,
        );

        return StreamBuilder<List<BadgeItem>>(
          stream: _repository.watchBadges(filter: _filter, query: _search.text),
          builder: (context, badgesSnap) {
            final badges = badgesSnap.data ?? [];
            final sampleBadge = badges.isNotEmpty
                ? badges.first
                : BadgeItem({
                    'id': 'preview-01',
                    'badge_number': 1,
                    'qr_token': 'demo-token-preview',
                    'status': 'unassigned',
                  });

            return LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 640;

                return Column(
                  children: [
                    // Entête avec boutons d'actions
                    Padding(
                      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, isMobile ? 16 : 24, isMobile ? 16 : 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.text('badges'), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                                    Text(
                                      '${s.text('quota_used')}: ${quota.totalGenerated} / ${quota.quotaLimit} · ${quota.quotaRemaining} ${s.text('remaining').toLowerCase()}',
                                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.outline),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton.filledTonal(
                                icon: const Icon(LucideIcons.palette),
                                tooltip: s.text('badge_design_preview'),
                                onPressed: () => _showBadgeDesignModal(sampleBadge),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Boutons d'export et génération
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _busy || badges.isEmpty ? null : () => _showPrintQuantityDialog(badges, isShare: true),
                                icon: const Icon(LucideIcons.fileDown, size: 16),
                                label: Text(s.text('export_planche_a4')),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy || badges.isEmpty ? null : () => _showPrintQuantityDialog(badges, isShare: false),
                                icon: const Icon(LucideIcons.printer, size: 16),
                                label: Text(s.text('print_batch')),
                              ),
                              FilledButton.icon(
                                onPressed: _busy ? null : () => _generateBatchDialog(quota),
                                icon: const Icon(LucideIcons.plus, size: 16),
                                label: Text(s.text('generate_batch')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Compteurs de statistiques (Responsive 2x2 sur Mobile)
                    if (isMobile)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: _metricCard(s.text('total_badges'), quota.totalGenerated.toString(), LucideIcons.qrCode, colors.primary)),
                                const SizedBox(width: 8),
                                Expanded(child: _metricCard(s.text('available_badges'), quota.totalAvailable.toString(), LucideIcons.sparkles, colors.primary)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _metricCard(s.text('assigned_badges'), quota.totalBound.toString(), LucideIcons.userCheck, Colors.blueGrey)),
                                const SizedBox(width: 8),
                                Expanded(child: _metricCard(s.text('blocked_badges'), quota.totalBlocked.toString(), LucideIcons.shieldAlert, colors.error)),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(child: _metricCard(s.text('total_badges'), quota.totalGenerated.toString(), LucideIcons.qrCode, colors.primary)),
                            const SizedBox(width: 12),
                            Expanded(child: _metricCard(s.text('assigned_badges'), quota.totalBound.toString(), LucideIcons.userCheck, Colors.blueGrey)),
                            const SizedBox(width: 12),
                            Expanded(child: _metricCard(s.text('available_badges'), quota.totalAvailable.toString(), LucideIcons.sparkles, colors.primary)),
                            const SizedBox(width: 12),
                            Expanded(child: _metricCard(s.text('blocked_badges'), quota.totalBlocked.toString(), LucideIcons.shieldAlert, colors.error)),
                          ],
                        ),
                      ),

                    // Recherche et Filtres
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 6),
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(LucideIcons.search),
                          labelText: s.text('search_badges'),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(LucideIcons.x),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() {});
                                  },
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),

                    // Filtres horizontaux sans texte erroné
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final f in ['all', 'unassigned', 'bound', 'blocked']) ...[
                                ChoiceChip(
                                  label: Text(s.text('badge_filter_$f')),
                                  selected: _filter == f,
                                  onSelected: (_) => setState(() => _filter = f),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Grille des badges (1 colonne sur mobile pour éviter les chevauchements)
                    Expanded(
                      child: badgesSnap.hasError
                          ? MessagePanel(message: s.text('local_storage'))
                          : !badgesSnap.hasData
                              ? const LoadingPanel()
                              : badges.isEmpty
                                  ? MessagePanel(
                                      message: s.text('badges_empty'),
                                      action: s.text('generate_batch'),
                                      onAction: () => _generateBatchDialog(quota),
                                    )
                                  : GridView.builder(
                                      padding: EdgeInsets.all(isMobile ? 16 : 24),
                                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: isMobile ? 600 : 320,
                                        mainAxisExtent: isMobile ? 128 : 136,
                                        crossAxisSpacing: 14,
                                        mainAxisSpacing: 14,
                                      ),
                                      itemCount: badges.length,
                                      itemBuilder: (context, index) {
                                        final badge = badges[index];
                                        final statusColor = _statusColor(badge.status, colors);
                                        return Card(
                                          child: Padding(
                                            padding: const EdgeInsets.all(14),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(
                                                      badge.formattedNumber,
                                                      style: theme.textTheme.titleMedium?.copyWith(
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: statusColor.withAlpha(24),
                                                        borderRadius: BorderRadius.circular(999),
                                                        border: Border.all(color: statusColor),
                                                      ),
                                                      child: Text(
                                                        s.text('badge_status_${badge.status}'),
                                                        style: theme.textTheme.labelSmall?.copyWith(
                                                          color: statusColor,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Text(
                                                  badge.isBound
                                                      ? s.text('assigned_to_member')
                                                      : badge.isAvailable
                                                          ? s.text('ready_for_activation')
                                                          : s.text('badge_blocked_notice'),
                                                  style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
                                                ),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.end,
                                                  children: [
                                                    if (badge.isBound)
                                                      TextButton.icon(
                                                        icon: const Icon(LucideIcons.user, size: 14),
                                                        onPressed: () => context.go('/members/${badge.memberId}'),
                                                        label: Text(s.text('view_member')),
                                                      ),
                                                    if (badge.isAvailable)
                                                      FilledButton.tonalIcon(
                                                        icon: const Icon(LucideIcons.sparkles, size: 14),
                                                        onPressed: () => context.go('/activate?badge=${badge.id}'),
                                                        label: Text(s.text('activate_card')),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
