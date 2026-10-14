import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_strings.dart';
import '../data/members_repository.dart';

/// Chif kle + graf sou manm yo (kalkile lokalman, mache offline).
class MembersStats {
  MembersStats.from(List<MemberListEntry> entries, DateTime now) {
    total = entries.length;
    final today = DateTime.utc(now.year, now.month, now.day);
    for (final e in entries) {
      final v = e.validity;
      if (v.valid) {
        active++;
        if ((v.daysLeft ?? 99) <= 7) expiring++;
      } else {
        switch (v.reason) {
          case 'expired':
            expired++;
          case 'pending_payment':
            pending++;
          case 'no_subscription':
            noSubscription++;
          default:
            suspended++;
        }
      }
      if (!e.member.fingerprintRegistered) noFingerprint++;
      final created = DateTime.tryParse(e.member.row['created_at'] as String? ?? '')?.toLocal();
      if (created != null) {
        final monthsAgo = (now.year - created.year) * 12 + now.month - created.month;
        if (monthsAgo >= 0 && monthsAgo < 6) newPerMonth[5 - monthsAgo]++;
        if (monthsAgo == 0) newThisMonth++;
      }
      final end = v.endDate;
      if (end != null) {
        final inDays = DateTime.utc(end.year, end.month, end.day).difference(today).inDays;
        if (inDays >= 0 && inDays < 14) expirationsNext14[inDays]++;
      }
    }
  }

  int total = 0;
  int active = 0;
  int expiring = 0;
  int expired = 0;
  int pending = 0;
  int noSubscription = 0;
  int suspended = 0;
  int noFingerprint = 0;
  int newThisMonth = 0;
  final List<int> newPerMonth = List.filled(6, 0);
  final List<int> expirationsNext14 = List.filled(14, 0);

  double get activeRate => total == 0 ? 0 : active / total;
}

class MembersStatsPanel extends StatelessWidget {
  const MembersStatsPanel({super.key, required this.entries});
  final List<MemberListEntry> entries;

  static const _green = Color(0xFF10B981);
  static const _amber = Color(0xFFF59E0B);
  static const _red = Color(0xFFEF4444);
  static const _blue = Color(0xFF3B82F6);
  static const _violet = Color(0xFF8B5CF6);
  static const _slate = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final now = DateTime.now();
    final st = MembersStats.from(entries, now);
    final nf = NumberFormat.decimalPattern();
    final kpis = <(IconData, String, String, Color, String?)>[
      (LucideIcons.users, s.text('stats_total'), nf.format(st.total), const Color(0xFF0F766E), null),
      (LucideIcons.userCheck, s.text('stats_active'), nf.format(st.active), _green,
          '${(st.activeRate * 100).round()}% ${s.text('active_rate')}'),
      (LucideIcons.hourglass, s.text('stats_expiring'), nf.format(st.expiring), _amber, null),
      (LucideIcons.userX, s.text('stats_expired'), nf.format(st.expired), _red, null),
      (LucideIcons.clock, s.text('stats_pending'), nf.format(st.pending), _violet, null),
      (LucideIcons.fingerprintPattern, s.text('stats_no_fingerprint'), nf.format(st.noFingerprint), _slate, null),
      (LucideIcons.trendingUp, s.text('stats_new_month'), nf.format(st.newThisMonth), _blue, null),
    ];
    final locale = Localizations.localeOf(context).languageCode;
    final monthFmt = DateFormat.MMM(locale == 'ht' ? 'fr' : locale);
    final monthLabels = [
      for (var i = 5; i >= 0; i--) monthFmt.format(DateTime(now.year, now.month - i, 1)),
    ];

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final cardWidth = wide ? (c.maxWidth - 6 * 12) / 7 : 170.0;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kpis.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final k = kpis[i];
              return _KpiCard(width: math.max(150, cardWidth), icon: k.$1, label: k.$2, value: k.$3, color: k.$4, foot: k.$5);
            },
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 230,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            _ChartCard(
              width: wide ? (c.maxWidth - 24) * .30 : 300,
              title: s.text('chart_status'),
              child: _Donut(
                segments: [
                  (s.text('stats_active'), st.active - st.expiring, _green),
                  (s.text('stats_expiring'), st.expiring, _amber),
                  (s.text('stats_expired'), st.expired, _red),
                  (s.text('stats_pending'), st.pending, _violet),
                  (s.text('stats_no_subscription'), st.noSubscription + st.suspended, _slate),
                ],
                center: '${(st.activeRate * 100).round()}%',
                centerLabel: s.text('active_rate'),
              ),
            ),
            const SizedBox(width: 12),
            _ChartCard(
              width: wide ? (c.maxWidth - 24) * .35 : 330,
              title: s.text('chart_new_members'),
              child: _Bars(values: st.newPerMonth, labels: monthLabels, color: _blue),
            ),
            const SizedBox(width: 12),
            _ChartCard(
              width: wide ? (c.maxWidth - 24) * .35 : 330,
              title: s.text('chart_expirations'),
              child: _Bars(
                values: st.expirationsNext14,
                labels: [for (var i = 0; i < 14; i++) i % 2 == 0 ? DateFormat.d().format(now.add(Duration(days: i))) : ''],
                color: _amber,
                highlightFirst: 3,
                highlightColor: _red,
              ),
            ),
          ]),
        ),
      ]);
    });
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.width, required this.icon, required this.label, required this.value, required this.color, this.foot});
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? foot;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withAlpha(dark ? 60 : 32), color.withAlpha(dark ? 20 : 8)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ]),
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color, height: 1)),
        if (foot != null)
          Text(foot!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: color))
        else
          const SizedBox(height: 13),
      ]),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.width, required this.title, required this.child});
  final double width;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Expanded(child: child),
        ]),
      );
}

class _Donut extends StatelessWidget {
  const _Donut({required this.segments, required this.center, required this.centerLabel});
  final List<(String, int, Color)> segments;
  final String center;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    final visible = segments.where((e) => e.$2 > 0).toList();
    return Row(children: [
      AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _DonutPainter(visible, Theme.of(context).colorScheme.outlineVariant),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Text(centerLabel, style: const TextStyle(fontSize: 10)),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final seg in segments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: seg.$3, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(seg.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                Text('${seg.$2}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments, this.track);
  final List<(String, int, Color)> segments;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final stroke = side * .16;
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: side - stroke, height: side - stroke);
    final total = segments.fold<int>(0, (a, e) => a + e.$2);
    if (total == 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = stroke);
      return;
    }
    var start = -math.pi / 2;
    const gap = 0.03;
    for (final seg in segments) {
      final sweep = math.pi * 2 * seg.$2 / total;
      canvas.drawArc(
        rect,
        start + (segments.length > 1 ? gap / 2 : 0),
        math.max(0.001, sweep - (segments.length > 1 ? gap : 0)),
        false,
        Paint()
          ..color = seg.$3
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels, required this.color, this.highlightFirst = 0, this.highlightColor});
  final List<int> values;
  final List<String> labels;
  final Color color;
  final int highlightFirst;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final maxV = math.max(1, values.fold<int>(0, math.max));
    return LayoutBuilder(builder: (context, c) {
      final barArea = c.maxHeight - 34;
      return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: values.length > 8 ? 2 : 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(values[i] == 0 ? '' : '${values[i]}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: values[i] / maxV),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => Container(
                    height: math.max(3, barArea * .82 * t),
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          (i < highlightFirst ? (highlightColor ?? color) : color).withAlpha(140),
                          i < highlightFirst ? (highlightColor ?? color) : color,
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 14,
                  child: Text(labels[i], maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 10)),
                ),
              ]),
            ),
          ),
      ]);
    });
  }
}
