import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Modèl pou yon tèm background badj modèn ak liksye
class BadgeBackgroundTheme {
  const BadgeBackgroundTheme({
    required this.id,
    required this.name,
    required this.category,
    required this.gradient,
    required this.accentColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.borderColor,
    required this.qrFgColor,
    required this.qrBgColor,
    required this.pillBgColor,
    required this.pillBorderColor,
    this.badgePattern = BadgePattern.carbonMesh,
  });

  final String id;
  final String name;
  final String category;
  final LinearGradient gradient;
  final Color accentColor;
  final Color textPrimary;
  final Color textSecondary;
  final Color borderColor;
  final Color qrFgColor;
  final Color qrBgColor;
  final Color pillBgColor;
  final Color pillBorderColor;
  final BadgePattern badgePattern;

  static const List<BadgeBackgroundTheme> themes = [
    // 1. Kabòn Lò VIP
    BadgeBackgroundTheme(
      id: 'dark_carbon_gold',
      name: 'Kabòn Nwa & Lò (VIP)',
      category: 'Liks & VIP',
      gradient: LinearGradient(
        colors: [Color(0xff111317), Color(0xff1c2026), Color(0xff121418)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accentColor: Color(0xffE5A93C),
      textPrimary: Color(0xffFFFFFF),
      textSecondary: Color(0xffC8CDD0),
      borderColor: Color(0xffE5A93C),
      qrFgColor: Color(0xff121418),
      qrBgColor: Color(0xffFFFFFF),
      pillBgColor: Color(0x33E5A93C),
      pillBorderColor: Color(0xffE5A93C),
      badgePattern: BadgePattern.carbonMesh,
    ),

    // 2. Kibè Nèon Ble
    BadgeBackgroundTheme(
      id: 'cyber_neon_cyan',
      name: 'Kibè Nèon Ble',
      category: 'High-Tech',
      gradient: LinearGradient(
        colors: [Color(0xff060C1B), Color(0xff0A1931), Color(0xff050F26)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accentColor: Color(0xff00F5D4),
      textPrimary: Color(0xffFFFFFF),
      textSecondary: Color(0xff94A3B8),
      borderColor: Color(0xff00F5D4),
      qrFgColor: Color(0xff060C1B),
      qrBgColor: Color(0xffFFFFFF),
      pillBgColor: Color(0x2E00F5D4),
      pillBorderColor: Color(0xff00F5D4),
      badgePattern: BadgePattern.cyberCircuit,
    ),

    // 3. Wouj Obsidiyèn Espò
    BadgeBackgroundTheme(
      id: 'crimson_obsidian',
      name: 'Wouj Obsidiyèn Espò',
      category: 'Puisans & Spò',
      gradient: LinearGradient(
        colors: [Color(0xff150A0C), Color(0xff2A1015), Color(0xff14090B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accentColor: Color(0xffFF2A54),
      textPrimary: Color(0xffFFFFFF),
      textSecondary: Color(0xffFCA5A5),
      borderColor: Color(0xffFF2A54),
      qrFgColor: Color(0xff150A0C),
      qrBgColor: Color(0xffFFFFFF),
      pillBgColor: Color(0x33FF2A54),
      pillBorderColor: Color(0xffFF2A54),
      badgePattern: BadgePattern.sportSpeedLines,
    ),

    // 4. Emrod Mant Liks
    BadgeBackgroundTheme(
      id: 'emerald_prestige',
      name: 'Emrod & Mant Liks',
      category: 'Liks & Byennèt',
      gradient: LinearGradient(
        colors: [Color(0xff051F16), Color(0xff0B3B2B), Color(0xff041811)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accentColor: Color(0xff00E676),
      textPrimary: Color(0xffFFFFFF),
      textSecondary: Color(0xffA7F3D0),
      borderColor: Color(0xff00E676),
      qrFgColor: Color(0xff051F16),
      qrBgColor: Color(0xffFFFFFF),
      pillBgColor: Color(0x3300E676),
      pillBorderColor: Color(0xff00E676),
      badgePattern: BadgePattern.waveCurves,
    ),

    // 5. Vyolèt Ametis Wayal
    BadgeBackgroundTheme(
      id: 'royal_amethyst',
      name: 'Vyolèt Ametis Wayal',
      category: 'Liks & VIP',
      gradient: LinearGradient(
        colors: [Color(0xff140924), Color(0xff291045), Color(0xff120720)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accentColor: Color(0xffC084FC),
      textPrimary: Color(0xffFFFFFF),
      textSecondary: Color(0xffE9D5FF),
      borderColor: Color(0xffC084FC),
      qrFgColor: Color(0xff140924),
      qrBgColor: Color(0xffFFFFFF),
      pillBgColor: Color(0x33C084FC),
      pillBorderColor: Color(0xffC084FC),
      badgePattern: BadgePattern.geometricPolygons,
    ),

    // 6. Solèy Kouche Amber
    BadgeBackgroundTheme(
      id: 'sunset_forge',
      name: 'Solèy Kouche Amber',
      category: 'Enèji & Chalè',
      gradient: LinearGradient(
        colors: [Color(0xff1C140F), Color(0xff331C11), Color(0xff1A110D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accentColor: Color(0xffFF7A00),
      textPrimary: Color(0xffFFFFFF),
      textSecondary: Color(0xffFED7AA),
      borderColor: Color(0xffFF7A00),
      qrFgColor: Color(0xff1C140F),
      qrBgColor: Color(0xffFFFFFF),
      pillBgColor: Color(0x33FF7A00),
      pillBorderColor: Color(0xffFF7A00),
      badgePattern: BadgePattern.honeycombGrid,
    ),

    // 7. Ajan Glase Platinum
    BadgeBackgroundTheme(
      id: 'arctic_silver',
      name: 'Ajan Glase Platinum',
      category: 'Minimalist & Klè',
      gradient: LinearGradient(
        colors: [Color(0xffF1F5F9), Color(0xffE2E8F0), Color(0xffCBD5E1)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accentColor: Color(0xff0F172A),
      textPrimary: Color(0xff0F172A),
      textSecondary: Color(0xff475569),
      borderColor: Color(0xff94A3B8),
      qrFgColor: Color(0xff0F172A),
      qrBgColor: Color(0xffFFFFFF),
      pillBgColor: Color(0x220F172A),
      pillBorderColor: Color(0xff0F172A),
      badgePattern: BadgePattern.brushedMetal,
    ),

    // 8. Mat Jeometrik Cobalt
    BadgeBackgroundTheme(
      id: 'geometric_midnight',
      name: 'Mat Jeometrik Cobalt',
      category: 'Modèn & Presizyon',
      gradient: LinearGradient(
        colors: [Color(0xff0B0F17), Color(0xff141B2B), Color(0xff090D14)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accentColor: Color(0xff3B82F6),
      textPrimary: Color(0xffFFFFFF),
      textSecondary: Color(0xff93C5FD),
      borderColor: Color(0xff3B82F6),
      qrFgColor: Color(0xff0B0F17),
      qrBgColor: Color(0xffFFFFFF),
      pillBgColor: Color(0x333B82F6),
      pillBorderColor: Color(0xff3B82F6),
      badgePattern: BadgePattern.geometricPolygons,
    ),

    // 9. Monokwòm Minimalist Liks
    BadgeBackgroundTheme(
      id: 'monochrome_lux',
      name: 'Monokwòm Minimalist Liks',
      category: 'Klasik & Elegant',
      gradient: LinearGradient(
        colors: [Color(0xff050505), Color(0xff121212), Color(0xff080808)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accentColor: Color(0xffFFFFFF),
      textPrimary: Color(0xffFFFFFF),
      textSecondary: Color(0xff9CA3AF),
      borderColor: Color(0xff4B5563),
      qrFgColor: Color(0xff000000),
      qrBgColor: Color(0xffFFFFFF),
      pillBgColor: Color(0x22FFFFFF),
      pillBorderColor: Color(0xff9CA3AF),
      badgePattern: BadgePattern.carbonMesh,
    ),

    // 10. Oseyan Pwofon Tiwkwaz
    BadgeBackgroundTheme(
      id: 'ocean_depth',
      name: 'Oseyan Pwofon Tiwkwaz',
      category: 'Enèji Dlo',
      gradient: LinearGradient(
        colors: [Color(0xff02131F), Color(0xff04273F), Color(0xff02111C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accentColor: Color(0xff06B6D4),
      textPrimary: Color(0xffFFFFFF),
      textSecondary: Color(0xffA5F3FC),
      borderColor: Color(0xff06B6D4),
      qrFgColor: Color(0xff02131F),
      qrBgColor: Color(0xffFFFFFF),
      pillBgColor: Color(0x3306B6D4),
      pillBorderColor: Color(0xff06B6D4),
      badgePattern: BadgePattern.waveCurves,
    ),
  ];

  static BadgeBackgroundTheme find(String? id) {
    if (id == null || id.isEmpty) return themes.first;
    return themes.firstWhere(
      (t) => t.id == id,
      orElse: () => themes.first,
    );
  }
}

enum BadgePattern {
  carbonMesh,
  cyberCircuit,
  sportSpeedLines,
  waveCurves,
  geometricPolygons,
  honeycombGrid,
  brushedMetal,
}

/// CustomPainter ki desine motif pwofesyonèl yo anba badj la
class BadgeBackgroundPainter extends CustomPainter {
  const BadgeBackgroundPainter({
    required this.theme,
    this.opacity = 0.22,
  });

  final BadgeBackgroundTheme theme;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final accentPaint = Paint()
      ..color = theme.accentColor.withAlpha((opacity * 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final fillPaint = Paint()
      ..color = theme.accentColor.withAlpha((opacity * 100).round())
      ..style = PaintingStyle.fill;

    switch (theme.badgePattern) {
      case BadgePattern.carbonMesh:
        _paintCarbonMesh(canvas, w, h, accentPaint);
        break;
      case BadgePattern.cyberCircuit:
        _paintCyberCircuit(canvas, w, h, accentPaint, fillPaint);
        break;
      case BadgePattern.sportSpeedLines:
        _paintSpeedLines(canvas, w, h, accentPaint, fillPaint);
        break;
      case BadgePattern.waveCurves:
        _paintWaves(canvas, w, h, accentPaint, fillPaint);
        break;
      case BadgePattern.geometricPolygons:
        _paintPolygons(canvas, w, h, accentPaint, fillPaint);
        break;
      case BadgePattern.honeycombGrid:
        _paintHoneycomb(canvas, w, h, accentPaint);
        break;
      case BadgePattern.brushedMetal:
        _paintBrushedMetal(canvas, w, h, accentPaint);
        break;
    }

    // Ti efè limyè / Glow sou kwen dwat anwo
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          theme.accentColor.withAlpha((opacity * 140).round()),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(w * 0.85, h * 0.15), radius: w * 0.45));
    canvas.drawCircle(Offset(w * 0.85, h * 0.15), w * 0.45, glowPaint);
  }

  void _paintCarbonMesh(Canvas canvas, double w, double h, Paint stroke) {
    const step = 16.0;
    for (double x = -h; x < w + h; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + h, h), stroke);
      canvas.drawLine(Offset(x + h, 0), Offset(x, h), stroke);
    }
    final path = Path()
      ..moveTo(w * 0.55, h)
      ..lineTo(w, h)
      ..lineTo(w, h * 0.65)
      ..close();
    final p = Paint()
      ..color = theme.accentColor.withAlpha((opacity * 80).round())
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, p);
  }

  void _paintCyberCircuit(Canvas canvas, double w, double h, Paint stroke, Paint fill) {
    final p = Path()
      ..moveTo(0, h * 0.3)
      ..lineTo(w * 0.25, h * 0.3)
      ..lineTo(w * 0.35, h * 0.5)
      ..lineTo(w * 0.85, h * 0.5)
      ..lineTo(w, h * 0.25);
    canvas.drawPath(p, stroke);

    final p2 = Path()
      ..moveTo(w * 0.1, h)
      ..lineTo(w * 0.3, h * 0.7)
      ..lineTo(w * 0.7, h * 0.7)
      ..lineTo(w * 0.9, h);
    canvas.drawPath(p2, stroke);

    canvas.drawCircle(Offset(w * 0.35, h * 0.5), 3, fill);
    canvas.drawCircle(Offset(w * 0.85, h * 0.5), 3, fill);
    canvas.drawCircle(Offset(w * 0.3, h * 0.7), 3, fill);
  }

  void _paintSpeedLines(Canvas canvas, double w, double h, Paint stroke, Paint fill) {
    final p = Path()
      ..moveTo(w * 0.6, 0)
      ..lineTo(w * 0.8, 0)
      ..lineTo(w * 0.4, h)
      ..lineTo(w * 0.2, h)
      ..close();
    canvas.drawPath(p, fill);

    for (int i = 0; i < 5; i++) {
      final offset = i * 14.0;
      canvas.drawLine(
        Offset(w * 0.75 + offset, 0),
        Offset(w * 0.35 + offset, h),
        stroke,
      );
    }
  }

  void _paintWaves(Canvas canvas, double w, double h, Paint stroke, Paint fill) {
    final path = Path()
      ..moveTo(0, h * 0.6)
      ..quadraticBezierTo(w * 0.35, h * 0.35, w * 0.65, h * 0.65)
      ..quadraticBezierTo(w * 0.85, h * 0.85, w, h * 0.5)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path, fill);

    final line = Path()
      ..moveTo(0, h * 0.6)
      ..quadraticBezierTo(w * 0.35, h * 0.35, w * 0.65, h * 0.65)
      ..quadraticBezierTo(w * 0.85, h * 0.85, w, h * 0.5);
    canvas.drawPath(line, stroke);
  }

  void _paintPolygons(Canvas canvas, double w, double h, Paint stroke, Paint fill) {
    final p1 = Path()
      ..moveTo(w * 0.7, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.5)
      ..lineTo(w * 0.8, h * 0.3)
      ..close();
    canvas.drawPath(p1, fill);

    final p2 = Path()
      ..moveTo(w * 0.5, h)
      ..lineTo(w, h)
      ..lineTo(w * 0.8, h * 0.6)
      ..close();
    canvas.drawPath(p2, fill);

    canvas.drawLine(Offset(w * 0.7, 0), Offset(w * 0.8, h * 0.3), stroke);
    canvas.drawLine(Offset(w * 0.8, h * 0.3), Offset(w, h * 0.5), stroke);
    canvas.drawLine(Offset(w * 0.5, h), Offset(w * 0.8, h * 0.6), stroke);
  }

  void _paintHoneycomb(Canvas canvas, double w, double h, Paint stroke) {
    const r = 18.0;
    const dx = r * 1.5;
    final dy = r * math.sqrt(3);

    for (double x = w * 0.4; x < w + r; x += dx) {
      for (double y = 0; y < h + r; y += dy) {
        final cx = x;
        final cy = y + ((x / dx).round() % 2 == 1 ? dy / 2 : 0);
        final hex = Path();
        for (int i = 0; i < 6; i++) {
          final angle = i * math.pi / 3;
          final px = cx + r * 0.7 * math.cos(angle);
          final py = cy + r * 0.7 * math.sin(angle);
          if (i == 0) {
            hex.moveTo(px, py);
          } else {
            hex.lineTo(px, py);
          }
        }
        hex.close();
        canvas.drawPath(hex, stroke);
      }
    }
  }

  void _paintBrushedMetal(Canvas canvas, double w, double h, Paint stroke) {
    for (double y = 0; y < h; y += 6) {
      canvas.drawLine(Offset(0, y), Offset(w, y), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant BadgeBackgroundPainter oldDelegate) =>
      oldDelegate.theme.id != theme.id || oldDelegate.opacity != opacity;
}
