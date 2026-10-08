import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../members/data/members_repository.dart';
import '../../members/domain/member.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/domain/gym_settings.dart';
import '../data/whatsapp_service.dart';
import '../data/badges_repository.dart';
import '../domain/badge.dart';
import '../domain/badge_background_themes.dart';
import 'badge_card.dart';

/// Paj Badj Fizik Manb lan avÃ¨k EditÃ¨ Drag & Drop, 10 Backgrounds, Zoom ak WhatsApp
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

  final GlobalKey _cardBoundaryKey = GlobalKey();
  final TransformationController _zoomController = TransformationController();

  bool _busy = false;
  bool _verso = false;
  bool _isEditingLayout = false;
  double _currentZoom = 1.0;

  String? _selectedThemeId;
  String _qrStyle = 'rounded';
  Map<String, dynamic> _positions = {};

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _members = MembersRepository(runtime.client, runtime.database!, runtime.session!);
    _badges = BadgesRepository(runtime.client, runtime.database!, runtime.session!);
    _settings = GymSettingsRepository(runtime.client, runtime.database!, runtime.session!);
  }

  @override
  void dispose() {
    _zoomController.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _zoomIn() {
    setState(() {
      _currentZoom = (_currentZoom + 0.25).clamp(0.8, 3.0);
      _zoomController.value =
          Matrix4.diagonal3Values(_currentZoom, _currentZoom, 1.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _currentZoom = (_currentZoom - 0.25).clamp(0.8, 3.0);
      _zoomController.value =
          Matrix4.diagonal3Values(_currentZoom, _currentZoom, 1.0);
    });
  }

  void _zoomReset() {
    setState(() {
      _currentZoom = 1.0;
      _zoomController.value = Matrix4.identity();
    });
  }

  Future<Uint8List?> _captureCardImage() async {
    try {
      final boundary = _cardBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 4.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _downloadHdBadge(BadgeItem badge, GymSettings gym) async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = AppStrings.of(context);
    try {
      final imgBytes = await _captureCardImage();
      if (imgBytes == null) {
        _toast(s.text('badge_export_failed'));
        return;
      }

      final doc = pw.Document();
      final pwImg = pw.MemoryImage(imgBytes);
      const cardW = 85.6 * PdfPageFormat.mm;
      const cardH = 54.0 * PdfPageFormat.mm;
      doc.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(cardW, cardH),
          margin: pw.EdgeInsets.zero,
          build: (ctx) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(pwImg, fit: pw.BoxFit.cover),
          ),
        ),
      );
      final pdfBytes = await doc.save();

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'gymdesk-${badge.formattedNumber}-HD.pdf',
      );
      _toast('${s.text('download_hd_badge')} OK !');
    } catch (_) {
      _toast(s.text('badge_export_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printDirectPdf(BadgeItem badge, GymSettings gym) async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = AppStrings.of(context);
    try {
      final imgBytes = await _captureCardImage();
      if (imgBytes == null) {
        _toast(s.text('badge_export_failed'));
        return;
      }

      final doc = pw.Document();
      final pwImg = pw.MemoryImage(imgBytes);
      const cardW = 85.6 * PdfPageFormat.mm;
      const cardH = 54.0 * PdfPageFormat.mm;
      doc.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(cardW, cardH),
          margin: pw.EdgeInsets.zero,
          build: (ctx) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(pwImg, fit: pw.BoxFit.cover),
          ),
        ),
      );
      final pdfBytes = await doc.save();
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } catch (_) {
      _toast(s.text('badge_export_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendViaWhatsApp(Member member, BadgeItem badge, GymSettings gym) async {
    final s = AppStrings.of(context);
    final ok = await WhatsAppService.sendBadgeActivation(
      context: context,
      member: member,
      badge: badge,
      gym: gym,
    );
    if (ok) {
      _toast(s.text('whatsapp_sent_success'));
    }
  }

  Future<void> _openCustomizerModal(GymSettings gym) async {
    final s = AppStrings.of(context);
    var tempTheme = _selectedThemeId ?? (gym.settings['badge_theme'] as String? ?? 'dark_carbon_gold');
    var tempQr = _qrStyle;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) => Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s.text('badge_customizer'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 1. Chwa 10 Backgrounds ModÃ¨n yo
                Text(
                  '${s.text('badge_background_theme')} (10 TÃ¨m ModÃ¨n) :',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 110,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: BadgeBackgroundTheme.themes.length,
                    itemBuilder: (context, index) {
                      final t = BadgeBackgroundTheme.themes[index];
                      final isSelected = t.id == tempTheme;
                      return GestureDetector(
                        onTap: () {
                          setModal(() => tempTheme = t.id);
                          setState(() => _selectedThemeId = t.id);
                        },
                        child: Container(
                          width: 140,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            gradient: t.gradient,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? Colors.yellowAccent : t.borderColor,
                              width: isSelected ? 3 : 1.2,
                            ),
                            boxShadow: isSelected
                                ? [BoxShadow(color: t.accentColor.withAlpha(120), blurRadius: 10)]
                                : null,
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: t.accentColor.withAlpha(50),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  t.category,
                                  style: TextStyle(color: t.accentColor, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text(
                                t.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (isSelected)
                                const Align(
                                  alignment: Alignment.bottomRight,
                                  child: Icon(Icons.check_circle, color: Colors.yellowAccent, size: 16),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // 2. Estil KÃ²d QR
                Text(
                  '${s.text('badge_qr_style')} :',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: Text(s.text('badge_qr_rounded')),
                      selected: tempQr == 'rounded',
                      onSelected: (val) {
                        if (val) {
                          setModal(() => tempQr = 'rounded');
                          setState(() => _qrStyle = 'rounded');
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(s.text('badge_qr_square')),
                      selected: tempQr == 'square',
                      onSelected: (val) {
                        if (val) {
                          setModal(() => tempQr = 'square');
                          setState(() => _qrStyle = 'square');
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(s.text('badge_qr_circle')),
                      selected: tempQr == 'circle',
                      onSelected: (val) {
                        if (val) {
                          setModal(() => tempQr = 'circle');
                          setState(() => _qrStyle = 'circle');
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // 3. MÃ²d Deplase Eleman (Drag & Drop)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.move, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Deplase Eleman sou Kat la (Drag & Drop)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              s.text('badge_drag_hint'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isEditingLayout,
                        onChanged: (v) {
                          setModal(() {});
                          setState(() => _isEditingLayout = v);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Bouton Reyajiste Pozisyon
                if (_positions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _positions = {});
                        Navigator.pop(context);
                        _toast(s.text('badge_reset_positions'));
                      },
                      icon: const Icon(LucideIcons.rotateCcw),
                      label: Text(s.text('badge_reset_positions')),
                    ),
                  ),

                // Bouton Enregistre kòm modèl defo pou tout sal la
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    icon: const Icon(LucideIcons.save, size: 18),
                    label: Text(s.text('save_default_badge')),
                    onPressed: () async {
                      try {
                        final updated = gym.copy(
                          settings: {
                            ...gym.settings,
                            'badge_theme': tempTheme,
                            'badge_qr_style': tempQr,
                            if (_positions.isNotEmpty) 'badge_positions': _positions,
                          },
                        );
                        final runtime = ref.read(appRuntimeProvider);
                        await _settings.save(
                          updated,
                          changedAt: runtime.sync?.clock.correctedNow ?? DateTime.now().toUtc(),
                        );
                        runtime.applyLocalGym(updated.row);
                        unawaited(runtime.sync?.synchronize());
                        if (context.mounted) Navigator.pop(context);
                        _toast(s.text('badge_design_saved'));
                      } catch (e, stack) {
                        debugPrint('Error saving default badge layout: $e\n$stack');
                        if (context.mounted) {
                          if (e is SettingsFailure) {
                            _toast(s.text(e.code));
                          } else {
                            _toast(s.text('error'));
                          }
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.text('close')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
          future: Future.wait([
            _badges.badgeForMember(member.id, badgeId: member.row['badge_id'] as String?),
            _settings.current(),
          ]),
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
                // Header avÃ¨k Tit ak Bouton Aksyon
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
                        Text('${member.fullName} Â· ${member.memberNumber}'),
                      ],
                    ),
                    if (badge != null)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // Bouton WhatsApp VÃ¨t
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xff25D366),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _busy ? null : () => _sendViaWhatsApp(member, badge, gym),
                            icon: const Icon(LucideIcons.messageSquare, size: 18),
                            label: Text(s.text('send_whatsapp')),
                          ),

                          // Bouton PÃ¨sonalize (10 Backgrounds, QR, Drag)
                          OutlinedButton.icon(
                            onPressed: () => _openCustomizerModal(gym),
                            icon: const Icon(LucideIcons.palette, size: 18),
                            label: Text(s.text('badge_customizer')),
                          ),

                          // Bouton Recto / Verso
                          OutlinedButton.icon(
                            onPressed: () => setState(() => _verso = !_verso),
                            icon: const Icon(LucideIcons.refreshCcw, size: 18),
                            label: Text(s.text(_verso ? 'badge_front' : 'badge_back')),
                          ),

                          // Bouton Telechaje Imaj HD
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _downloadHdBadge(badge, gym),
                            icon: const Icon(LucideIcons.fileDown, size: 18),
                            label: Text(s.text('download_hd_badge')),
                          ),

                          // Bouton Enprime
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _printDirectPdf(badge, gym),
                            icon: const Icon(LucideIcons.printer, size: 18),
                            label: Text(s.text('print_badge')),
                          ),
                        ],
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                if (badge == null)
                  MessagePanel(
                    message: s.text('member_no_badge'),
                    action: {'owner', 'supervisor'}.contains(ref.read(appRuntimeProvider).session?.role)
                        ? s.text('activate_card')
                        : null,
                    onAction: {'owner', 'supervisor'}.contains(ref.read(appRuntimeProvider).session?.role)
                        ? () => context.go('/badges')
                        : null,
                  )
                else ...[
                  // Ba KontwÃ²l Zoom (+, -, 100%) & MÃ²d Drag
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.zoomOut, size: 18),
                            tooltip: s.text('badge_zoom_out'),
                            onPressed: _zoomOut,
                          ),
                          Text(
                            '${(_currentZoom * 100).toInt()}%',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.zoomIn, size: 18),
                            tooltip: s.text('badge_zoom_in'),
                            onPressed: _zoomIn,
                          ),
                          const VerticalDivider(width: 16),
                          TextButton(
                            onPressed: _zoomReset,
                            child: Text(s.text('badge_zoom_reset')),
                          ),
                          if (_isEditingLayout) ...[
                            const VerticalDivider(width: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.withAlpha(40),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: const Row(
                                children: [
                                  Icon(LucideIcons.move, size: 14, color: Colors.orange),
                                  SizedBox(width: 4),
                                  Text(
                                    'MÃ²d Deplasman Aktif',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Kat la andedan InteractiveViewer pou Zoom ak RepaintBoundary pou Capture HD
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: InteractiveViewer(
                        transformationController: _zoomController,
                        minScale: 0.8,
                        maxScale: 3.5,
                        child: RepaintBoundary(
                          key: _cardBoundaryKey,
                          child: FutureBuilder<Uint8List?>(
                            future: _settings.logoBytes(gym.logoUrl),
                            builder: (context, logoSnap) => BadgeCard(
                              badge: badge,
                              gym: gym,
                              logo: logoSnap.data,
                              showBack: _verso,
                              themeId: _selectedThemeId,
                              qrStyle: _qrStyle,
                              customPositions: _positions,
                              memberName: member.fullName,
                              isEditing: _isEditingLayout,
                              onPositionChanged: (key, x, y) {
                                _positions[key] = {'x': x, 'y': y};
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // EnfÃ²masyon Sekirite ak Statut
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        children: [
                          Text(
                            '${s.text('badge_status_${badge.status}')} Â· ${badge.formattedNumber}',
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
