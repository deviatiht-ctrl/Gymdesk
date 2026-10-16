import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/runtime.dart';

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
  });

  final AppRuntime runtime;
  final Widget child;

  @override
  State<AccessPopupOverlay> createState() => AccessPopupOverlayState();

  static AccessPopupOverlayState? of(BuildContext context) =>
      context.findAncestorStateOfType<AccessPopupOverlayState>();
}

class AccessPopupOverlayState extends State<AccessPopupOverlay> {
  AccessEventNotification? _currentEvent;
  Timer? _dismissTimer;
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
  }

  @override
  void didUpdateWidget(AccessPopupOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.runtime.session?.gymId != oldWidget.runtime.session?.gymId) {
      _setupRealtimeListener();
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
    final eventType = row['event_type']?.toString() ?? 'unknown';
    final isGranted = eventType == 'granted';
    final snapshot = Map<String, dynamic>.from(row['member_snapshot'] as Map? ?? {});

    final memberName = snapshot['name']?.toString() ?? row['reason']?.toString() ?? 'Manm';
    final memberId = row['member_id']?.toString() ?? snapshot['member_id']?.toString();
    final planName = snapshot['plan_name']?.toString();
    final endDate = snapshot['end_date']?.toString();
    final daysLeft = (snapshot['days_left'] as num?)?.toInt();

    final lang = Localizations.localeOf(context).languageCode;
    final isFr = lang == 'fr';
    final isEn = lang == 'en';

    String title;
    String message;

    if (isGranted) {
      title = isFr ? 'Accès Autorisé' : isEn ? 'Access Granted' : 'Aksè Otorize';
      message = daysLeft != null
          ? (daysLeft <= 5
              ? (isFr
                  ? 'Porte déverrouillée. Attention : expiration dans $daysLeft jour(s) !'
                  : isEn
                      ? 'Door unlocked. Warning: expires in $daysLeft day(s)!'
                      : 'Pòt louvri. Atansyon: abònman fini nan $daysLeft jou!')
              : (isFr
                  ? 'Porte déverrouillée. Abonnement valide ($daysLeft jours restants).'
                  : isEn
                      ? 'Door unlocked. Active subscription ($daysLeft days left).'
                      : 'Pòt louvri. Abònman valab (rete $daysLeft jou).'))
          : (isFr ? 'Porte déverrouillée avec succès.' : isEn ? 'Door unlocked successfully.' : 'Pòt la louvri avèk siksè.');
    } else if (eventType == 'denied_expired') {
      title = isFr ? 'Accès Refusé — Abonnement Expiré' : isEn ? 'Access Denied — Subscription Expired' : 'Aksè Refize — Abònman Fini';
      message = isFr ? 'L’abonnement de ce membre est expiré. Porte verrouillée.' : isEn ? 'This member\'s subscription has expired. Door locked.' : 'Abònman manm sa a ekspire. Pòt la rete fèmen.';
    } else if (eventType == 'denied_no_subscription') {
      title = isFr ? 'Accès Refusé — Pas d’Abonnement' : isEn ? 'Access Denied — No Subscription' : 'Aksè Refize — Pa Gen Abònman';
      message = isFr ? 'Aucun abonnement actif pour ce membre aujourd’hui.' : isEn ? 'No active subscription for this member today.' : 'Manm lan pa gen okenn abònman aktif pou jodi a.';
    } else if (eventType == 'door_forced' || eventType == 'door_manual_open') {
      title = isFr ? 'Alerte Sécurité — Porte Ouverte Manuellement' : isEn ? 'Security Alert — Door Opened Manually' : 'Alèt Sekirite — Pòt Louvri Manyèlman';
      message = row['reason']?.toString() ?? (isFr ? 'Porte ouverte sans empreinte validée.' : 'Pòt la louvri san anprent valide.');
    } else {
      title = isFr ? 'Accès Refusé' : isEn ? 'Access Denied' : 'Aksè Refize';
      message = row['reason']?.toString() ?? (isFr ? 'Vérification biométrique échouée.' : 'Verifikasyon pa reyisi.');
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
