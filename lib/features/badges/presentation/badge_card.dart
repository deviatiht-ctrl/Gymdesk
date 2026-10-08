import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../settings/domain/gym_settings.dart';
import '../domain/badge.dart';
import '../domain/badge_background_themes.dart';

/// Kat Badj Modèn GymDesk (CR80 Paysage / Portrait)
/// Sipòte 10 background modèn, pèsonalizasyon QR, ak pozisyonman lib (Drag & Drop)
class BadgeCard extends StatefulWidget {
  const BadgeCard({
    super.key,
    required this.badge,
    required this.gym,
    this.logo,
    this.showBack = false,
    this.themeId,
    this.qrStyle = 'rounded',
    this.qrFgColor,
    this.qrBgColor,
    this.customPositions = const {},
    this.memberName,
    this.memberPhoto,
    this.isEditing = false,
    this.onPositionChanged,
  });

  final BadgeItem badge;
  final GymSettings gym;
  final Uint8List? logo;
  final bool showBack;
  final String? themeId;
  final String qrStyle; // 'square', 'rounded', 'circle'
  final Color? qrFgColor;
  final Color? qrBgColor;
  final Map<String, dynamic> customPositions;
  final String? memberName;
  final Uint8List? memberPhoto;
  final bool isEditing;
  final void Function(String elementKey, double x, double y)? onPositionChanged;

  @override
  State<BadgeCard> createState() => _BadgeCardState();
}

class _BadgeCardState extends State<BadgeCard> {
  String? _activeDraggedKey;
  late Map<String, Offset> _positions;

  @override
  void initState() {
    super.initState();
    _initPositions();
  }

  @override
  void didUpdateWidget(covariant BadgeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customPositions != widget.customPositions) {
      _initPositions();
    }
  }

  void _initPositions() {
    final gymPositions = widget.gym.settings['badge_positions'] is Map
        ? widget.gym.settings['badge_positions'] as Map
        : const {};
    final combined = {...gymPositions, ...widget.customPositions};
    _positions = {
      'brand': _parseOffset(combined['brand'], const Offset(0.06, 0.08)),
      'number': _parseOffset(combined['number'], const Offset(0.06, 0.44)),
      'qr': _parseOffset(combined['qr'], const Offset(0.66, 0.14)),
      'footer': _parseOffset(combined['footer'], const Offset(0.06, 0.82)),
      'status': _parseOffset(combined['status'], const Offset(0.66, 0.82)),
    };
  }

  Offset _parseOffset(dynamic data, Offset fallback) {
    if (data is Map) {
      final x = (data['x'] as num?)?.toDouble() ?? fallback.dx;
      final y = (data['y'] as num?)?.toDouble() ?? fallback.dy;
      return Offset(x.clamp(0.0, 0.85), y.clamp(0.0, 0.85));
    }
    return fallback;
  }

  BadgeBackgroundTheme get _theme => BadgeBackgroundTheme.find(
    widget.themeId ?? (widget.gym.settings['badge_theme'] as String? ?? 'dark_carbon_gold'),
  );

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return AspectRatio(
      aspectRatio: 85.6 / 54, // Format CR80 Kat Plastik Estanda
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(90),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // 1. Kouch Gradyan Fond
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(gradient: theme.gradient),
              ),
            ),

            // 2. Kouch Motif Vektoryèl Canvas
            Positioned.fill(
              child: CustomPaint(
                painter: BadgeBackgroundPainter(theme: theme, opacity: 0.28),
              ),
            ),

            // 3. Kontni Kat la (Recto oswa Verso)
            Positioned.fill(
              child: widget.showBack ? _buildVerso(theme) : _buildRecto(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecto(BadgeBackgroundTheme theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardW = constraints.maxWidth;
        final cardH = constraints.maxHeight;

        return Stack(
          children: [
            // Logo & Non Gym
            _wrapElement(
              key: 'brand',
              cardW: cardW,
              cardH: cardH,
              child: _buildBrand(theme),
            ),

            // Nimewo Manb & Badj
            _wrapElement(
              key: 'number',
              cardW: cardW,
              cardH: cardH,
              child: _buildNumber(theme),
            ),

            // Kòd QR Pèsonalize
            _wrapElement(
              key: 'qr',
              cardW: cardW,
              cardH: cardH,
              child: _buildQr(theme, cardH),
            ),

            // Kontak & Telefòn
            _wrapElement(
              key: 'footer',
              cardW: cardW,
              cardH: cardH,
              child: _buildFooter(theme),
            ),

            // Statut Pill (VIP / Aktif)
            _wrapElement(
              key: 'status',
              cardW: cardW,
              cardH: cardH,
              child: _buildStatusPill(theme),
            ),
          ],
        );
      },
    );
  }

  Widget _wrapElement({
    required String key,
    required double cardW,
    required double cardH,
    required Widget child,
  }) {
    final pos = _positions[key] ?? Offset.zero;
    final left = pos.dx * cardW;
    final top = pos.dy * cardH;
    final isSelected = _activeDraggedKey == key;

    if (!widget.isEditing) {
      return Positioned(left: left, top: top, child: child);
    }

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanStart: (_) {
          setState(() => _activeDraggedKey = key);
        },
        onPanUpdate: (details) {
          setState(() {
            final cur = _positions[key] ?? Offset.zero;
            final newX = (cur.dx + details.delta.dx / cardW).clamp(0.0, 0.82);
            final newY = (cur.dy + details.delta.dy / cardH).clamp(0.0, 0.82);
            _positions[key] = Offset(newX, newY);
            widget.onPositionChanged?.call(key, newX, newY);
          });
        },
        onPanEnd: (_) {
          setState(() => _activeDraggedKey = null);
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? Colors.yellowAccent : Colors.white.withAlpha(120),
              width: isSelected ? 2.0 : 1.0,
            ),
            borderRadius: BorderRadius.circular(6),
            color: isSelected ? Colors.yellowAccent.withAlpha(30) : Colors.transparent,
          ),
          padding: const EdgeInsets.all(2),
          child: child,
        ),
      ),
    );
  }

  Widget _buildBrand(BadgeBackgroundTheme theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.logo != null)
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.accentColor, width: 1.2),
            ),
            child: ClipOval(
              child: Image.memory(
                widget.logo!,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.gym.name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                'GYMDESK ACCESS SYSTEM',
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 7.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNumber(BadgeBackgroundTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 3,
          decoration: BoxDecoration(
            color: theme.accentColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 5),
        if (widget.memberName != null && widget.memberName!.isNotEmpty) ...[
          Text(
            widget.memberName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
        ],
        Text(
          widget.badge.formattedNumber,
          style: TextStyle(
            color: theme.accentColor,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'CARTE D\'ACCÈS OFFICIELLE',
          style: TextStyle(
            color: theme.textSecondary,
            fontSize: 7.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildQr(BadgeBackgroundTheme theme, double cardH) {
    final qrSize = (cardH * 0.52).clamp(70.0, 115.0);
    final fg = widget.qrFgColor ?? theme.qrFgColor;
    final bg = widget.qrBgColor ?? theme.qrBgColor;
    final effectiveQr = widget.qrStyle.isNotEmpty
        ? widget.qrStyle
        : ((widget.gym.settings['badge_qr_style'] as String?) ?? 'rounded');
    final isRound = effectiveQr == 'rounded' || effectiveQr == 'circle';
    final isCircle = effectiveQr == 'circle';

    return Container(
      width: qrSize,
      height: qrSize,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: bg,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(8),
        border: Border.all(color: theme.accentColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: theme.accentColor.withAlpha(60),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: ClipRRect(
          borderRadius: isCircle ? BorderRadius.circular(qrSize) : BorderRadius.circular(4),
          child: QrImageView(
            data: widget.badge.qrPayload(widget.gym.code),
            version: QrVersions.auto,
            errorCorrectionLevel: QrErrorCorrectLevel.Q,
            backgroundColor: bg,
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: isRound ? QrDataModuleShape.circle : QrDataModuleShape.square,
              color: fg,
            ),
            eyeStyle: QrEyeStyle(
              eyeShape: isRound ? QrEyeShape.circle : QrEyeShape.square,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BadgeBackgroundTheme theme) {
    return Text(
      widget.gym.phone.isNotEmpty ? widget.gym.phone : 'GYMDESK SECURITY',
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        color: theme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildStatusPill(BadgeBackgroundTheme theme) {
    final status = widget.badge.status == 'bound' ? 'AKTIF' : widget.badge.status.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.pillBgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.pillBorderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.accentColor,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              color: theme.accentColor,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerso(BadgeBackgroundTheme theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.pillBgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.accentColor, width: 1),
            ),
            child: Text(
              'CARTE PERSONNELLE — CODE PIN EXIGÉ À L\'ENTRÉE',
              style: TextStyle(
                color: theme.accentColor,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Text(
            '• Présentez cette carte au scanner puis validez avec votre code PIN.\n'
            '• Cette carte est strictement personnelle et incessible.\n'
            '• En cas de perte ou d\'oubli, présentez-vous à la réception.',
            style: TextStyle(
              fontSize: 9.5,
              color: theme.textSecondary,
              height: 1.4,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.gym.address.isNotEmpty ? widget.gym.address : 'Sal GymDesk',
                style: TextStyle(fontSize: 9, color: theme.textSecondary),
              ),
              Text(
                widget.gym.phone.isNotEmpty ? 'Tél : ${widget.gym.phone}' : 'GYMDESK',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: theme.accentColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
