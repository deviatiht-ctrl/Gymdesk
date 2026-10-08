import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../members/data/members_repository.dart';
import '../../members/domain/member.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/domain/gym_settings.dart';
import '../data/badge_pdf.dart';
import '../data/badges_repository.dart';
import '../domain/badge.dart';
import 'badge_card.dart';

/// Badge physique du membre (carte anonyme V2).
/// La carte n'affiche ni nom ni photo : seulement le numéro,
/// le QR et l'identité de la salle.
class MemberBadgePage extends ConsumerStatefulWidget {
  const MemberBadgePage({super.key, required this.memberId});
  final String memberId;
  @override
  ConsumerState<MemberBadgePage> createState() => _MemberBadgePageState();
}

class _MemberBadgePageState extends ConsumerState<MemberBadgePage> {
  late final MembersRepository _members;
  late final BadgesRepository _badges;
  late final GymSettingsRepository _settings;
  bool _busy = false;
  bool _verso = false;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _members = MembersRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
    _badges = BadgesRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
    _settings = GymSettingsRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
  }

  Future<BadgeItem?> _badgeFor(Member member) => _badges.badgeForMember(
    member.id,
    badgeId: member.row['badge_id'] as String?,
  );

  void _error(String code) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).text(code))));

  Future<void> _print(BadgeItem badge, GymSettings gym) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final logo = await _settings.logoBytes(gym.logoUrl);
      final bytes = await buildV2BadgeCardsPdf(
        badges: [badge],
        gym: gym,
        logo: logo,
        withBleed: true,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      await _audit(badge);
    } catch (_) {
      _error('badge_export_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(BadgeItem badge, GymSettings gym) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final logo = await _settings.logoBytes(gym.logoUrl);
      final bytes = await buildV2BadgeCardsPdf(
        badges: [badge],
        gym: gym,
        logo: logo,
        withBleed: true,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'gymdesk-${badge.formattedNumber}.pdf',
      );
      await _audit(badge);
    } catch (_) {
      _error('badge_export_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _audit(BadgeItem badge) async {
    try {
      await ref
          .read(appRuntimeProvider)
          .client
          .rpc(
            'audit',
            params: {
              'p_action': 'export',
              'p_entity': 'badges',
              'p_entity_id': badge.id,
              'p_details': {'document': 'member_badge'},
            },
          );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    return StreamBuilder<Member?>(
      stream: _members.watchMember(widget.memberId),
      builder: (context, memberSnapshot) {
        if (memberSnapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: MessagePanel(message: s.text('local_storage')),
          );
        }
        if (!memberSnapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: LoadingPanel(),
          );
        }
        final member = memberSnapshot.data;
        if (member == null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: MessagePanel(message: s.text('member_missing')),
          );
        }
        return FutureBuilder<List<Object?>>(
          future: Future.wait([_badgeFor(member), _settings.current()]),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: LoadingPanel(),
              );
            }
            final badge = snap.data![0] as BadgeItem?;
            final gym = snap.data![1] as GymSettings;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.text('member_badge'),
                          style: theme.textTheme.headlineMedium,
                        ),
                        Text('${member.fullName} · ${member.memberNumber}'),
                      ],
                    ),
                    if (badge != null)
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _verso = !_verso),
                            icon: const Icon(LucideIcons.refreshCcw),
                            label: Text(
                              s.text(_verso ? 'badge_front' : 'badge_back'),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _export(badge, gym),
                            icon: const Icon(LucideIcons.fileDown),
                            label: Text(s.text('export_pdf')),
                          ),
                          FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _print(badge, gym),
                            icon: const Icon(LucideIcons.printer),
                            label: Text(s.text('print_badge')),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                if (badge == null)
                  MessagePanel(
                    message: s.text('member_no_badge'),
                    action:
                        {
                          'owner',
                          'supervisor',
                        }.contains(ref.read(appRuntimeProvider).session?.role)
                        ? s.text('activate_card')
                        : null,
                    onAction:
                        {
                          'owner',
                          'supervisor',
                        }.contains(ref.read(appRuntimeProvider).session?.role)
                        ? () => context.go('/badges')
                        : null,
                  )
                else ...[
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: FutureBuilder<Uint8List?>(
                        future: _settings.logoBytes(gym.logoUrl),
                        builder: (context, logoSnap) => BadgeCard(
                          badge: badge,
                          gym: gym,
                          logo: logoSnap.data,
                          showBack: _verso,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        children: [
                          Text(
                            '${s.text('badge_status_${badge.status}')} · ${badge.formattedNumber}',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s.text('badge_security_hint'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
