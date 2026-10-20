import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/runtime.dart';
import '../../features/subscriptions/domain/subscription_rules.dart';
import '../../l10n/app_strings.dart';
import 'access_monitor.dart';
import 'terminal_access_service.dart';

class AccessEventNotification {
  const AccessEventNotification({
    required this.id,
    required this.eventType,
    required this.title,
    required this.message,
    this.memberName,
    this.memberId,
    this.planName,
    this.endDate,
    this.daysLeft,
    this.photoUrl,
    required this.isGranted,
    required this.occurredAt,
  });

  final String id;
  final String eventType;
  final String title;
  final String message;
  final String? memberName;
  final String? memberId;
  final String? planName;
  final String? endDate;
  final int? daysLeft;
  final String? photoUrl;
  final bool isGranted;
  final DateTime occurredAt;
}

class AccessPopupOverlay extends StatefulWidget {
  const AccessPopupOverlay({
    super.key,
    required this.runtime,
    required this.child,
    this.location = '',
  });

  final AppRuntime runtime;
  final Widget child;
  final String location;

  @override
  State<AccessPopupOverlay> createState() => AccessPopupOverlayState();

  static AccessPopupOverlayState? of(BuildContext context) =>
      context.findAncestorStateOfType<AccessPopupOverlayState>();
}

class AccessPopupOverlayState extends State<AccessPopupOverlay> {
  AccessEventNotification? _currentEvent;
  Timer? _dismissTimer;
  RealtimeChannel? _subscription;
  StreamSubscription<AccessDecision>? _local;

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
    _local = AccessMonitor.instance.decisions.listen(
      (d) => _handleNewEvent(TerminalAccessService.eventRowFor(d)),
    );
    unawaited(AccessMonitor.instance.start(widget.runtime));
  }

  @override
  void didUpdateWidget(AccessPopupOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.runtime.session?.gymId != oldWidget.runtime.session?.gymId) {
      _setupRealtimeListener();
      unawaited(AccessMonitor.instance.start(widget.runtime));
    }
  }

  void _setupRealtimeListener() {
    _subscription?.unsubscribe();
    final gymId = widget.runtime.session?.gymId;
    if (gymId == null) return;

    try {
      final client = Supabase.instance.client;
      _subscription = client
          .channel('public:access_events:$gymId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'access_events',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'gym_id',
              value: gymId,
            ),
            callback: (payload) {
              final row = payload.newRecord;
              // PC sa a deja montre evènman tèminal li te trete a (popup lokal).
              if (AccessMonitor.instance.active && row['source'] == 'terminal') return;
              _handleNewEvent(row);
            },
          )
          .subscribe();
    } catch (_) {}
  }

  void triggerEventManually(AccessEventNotification event) {
    if (!mounted) return;
    setState(() {
      _currentEvent = event;
    });
    _dismissTimer?.cancel();
    if (event.isGranted) {
      _dismissTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _currentEvent = null);
      });
    }
  }

  void _handleNewEvent(Map<String, dynamic> row) {
    if (!mounted || widget.location == '/door_access') return;
    final eventType = row['event_type']?.toString() ?? 'unknown';
    final isGranted = eventType == 'granted';
    final snapshot = Map<String, dynamic>.from(row['member_snapshot'] as Map? ?? {});

    final s = AppStrings.of(context);
    final isEmployee = snapshot['is_employee'] == true;
    final memberName = snapshot['name']?.toString() ?? s.text('member');
    final memberId = isEmployee ? null : row['member_id']?.toString() ?? snapshot['member_id']?.toString();
    final planName = snapshot['plan_name']?.toString();
    final endRaw = DateTime.tryParse(snapshot['end_date']?.toString() ?? '');
    final endDate = endRaw == null ? null : ymd(endRaw);
    final daysLeft = (snapshot['days_left'] as num?)?.toInt();

    final String title;
    final String message;
    if (isGranted) {
      title = isEmployee ? '${s.text('scan_granted')} · ${s.text('employee_access')}' : s.text('scan_granted');
      message = isEmployee
          ? s.text('employee_welcome')
          : daysLeft == null
          ? s.text('door_pulse_sent')
          : daysLeft <= 0
          ? s.text('expires_today')
          : s.text('days_left_n').replaceAll('{n}', '$daysLeft');
    } else if (eventType == 'door_forced' || eventType == 'door_manual_open') {
      title = s.text('door_forced_title');
      message = row['reason']?.toString() ?? '';
    } else {
      title = s.text('scan_access_denied');
      message = s.text(switch (eventType) {
        'denied_expired' => 'validity_expired',
        'denied_no_subscription' => 'validity_no_subscription',
        'denied_pending' => 'validity_pending_payment',
        'denied_suspended' => 'validity_suspended',
        _ => 'fingerprint_not_recognized',
      });
    }
    final notif = AccessEventNotification(
      id: row['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      eventType: eventType,
      title: title,
      message: message,
      memberName: memberName,
      memberId: memberId,
      planName: planName,
      endDate: endDate,
      daysLeft: daysLeft,
      photoUrl: snapshot['photo_url']?.toString(),
      isGranted: isGranted,
      occurredAt: DateTime.now(),
    );

    triggerEventManually(notif);
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    if (mounted) {
      setState(() => _currentEvent = null);
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _subscription?.unsubscribe();
    _local?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = _currentEvent;

    return Stack(
      children: [
        widget.child,
        if (event != null)
          Positioned(
            top: 24,
            left: 20,
            right: 20,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(16),
                  color: event.isGranted ? const Color(0xFF064E3B) : const Color(0xFF7F1D1D),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: event.isGranted ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: event.isGranted
                              ? const Color(0xFF047857)
                              : const Color(0xFF991B1B),
                          child: Icon(
                            event.isGranted ? LucideIcons.checkCheck : LucideIcons.shieldAlert,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      event.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: _dismiss,
                                    child: const Icon(LucideIcons.x, color: Colors.white70, size: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              if (event.memberName != null) ...[
                                Text(
                                  event.memberName!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                event.message,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                              if (event.planName != null || event.endDate != null) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (event.planName != null)
                                      Chip(
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        label: Text(
                                          event.planName!,
                                          style: const TextStyle(fontSize: 11, color: Colors.white),
                                        ),
                                        backgroundColor: Colors.white24,
                                      ),
                                    if (event.endDate != null)
                                      Chip(
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        label: Text(
                                          '${Localizations.localeOf(context).languageCode == 'fr' ? 'Fin' : Localizations.localeOf(context).languageCode == 'en' ? 'End' : 'Fini'}: ${event.endDate}',
                                          style: const TextStyle(fontSize: 11, color: Colors.white),
                                        ),
                                        backgroundColor: Colors.white24,
                                      ),
                                  ],
                                ),
                              ],
                              if (!event.isGranted && event.memberId != null) ...[
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF7F1D1D),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                  onPressed: () {
                                    _dismiss();
                                    context.push('/members/${event.memberId}');
                                  },
                                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                                  label: Text(
                                    Localizations.localeOf(context).languageCode == 'fr'
                                        ? 'Renouveler Maintenant'
                                        : Localizations.localeOf(context).languageCode == 'en'
                                            ? 'Renew Now'
                                            : 'Renouvle Kounye a',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
