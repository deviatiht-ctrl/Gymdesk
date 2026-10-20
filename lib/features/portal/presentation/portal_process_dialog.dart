import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../core/biometrics/biometric_models.dart';
import '../../../core/biometrics/biometric_service.dart';
import '../../../core/sync/sync_models.dart';
import '../../../l10n/app_strings.dart';
import '../../members/domain/member.dart';
import '../../payments/data/receipt_pdf.dart';
import '../../plans/data/plans_repository.dart';
import '../../plans/domain/plan.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../domain/portal_request.dart';

class PortalProcessDialog extends ConsumerStatefulWidget {
  const PortalProcessDialog({
    super.key,
    required this.request,
    required this.onCompleted,
  });

  final PortalRequest request;
  final VoidCallback onCompleted;

  static Future<void> show(
    BuildContext context, {
    required PortalRequest request,
    required VoidCallback onCompleted,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PortalProcessDialog(
        request: request,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  ConsumerState<PortalProcessDialog> createState() => _PortalProcessDialogState();
}

class _PortalProcessDialogState extends ConsumerState<PortalProcessDialog> {
  late final BiometricService _biometricService;
  late final PlansRepository _plansRepo;

  StreamSubscription<BiometricEvent>? _bioEventSub;
  List<GymPlan> _plans = [];
  GymPlan? _selectedPlan;
  bool _loadingPlans = true;

  String? _fingerprintTemplate;
  bool _skipFingerprint = false;
  String _paymentMethod = 'cash';
  final _referenceController = TextEditingController();

  bool _isProcessing = false;
  String? _errorMessage;
  bool _isCompleted = false;

  String? _completedMemberNumber;
  String? _completedPaymentId;
  double _completedTotal = 0;
  DateTime? _completedEndDate;

  bool get _isRenewal => widget.request.kind == 'renewal';

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _biometricService = ref.read(biometricServiceProvider);
    _plansRepo = PlansRepository(runtime.database!, runtime.session!);

    // Kòmanse koute lektè anprent lan otomatikman san bezwen klike bouton
    _bioEventSub = _biometricService.events.listen(_onBiometricEvent);
    _biometricService.startCapture();

    _loadPlans();
  }

  @override
  void dispose() {
    _bioEventSub?.cancel();
    _biometricService.stopCapture();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    try {
      final list = await _plansRepo.watch().first;
      if (mounted) {
        setState(() {
          _plans = list.where((p) => p.active && p.deletedAt == null).toList();
          if (_plans.isNotEmpty) {
            GymPlan initial = _plans.first;
            if (widget.request.planId != null) {
              final found = _plans.where((p) => p.id == widget.request.planId).firstOrNull;
              if (found != null) initial = found;
            }
            _selectedPlan = initial;
          }
          _loadingPlans = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  void _onBiometricEvent(BiometricEvent event) {
    if (!mounted || _fingerprintTemplate != null || _skipFingerprint || _isProcessing) return;

    if (event.type == 'fingerprint_captured' && event.template != null && event.template!.isNotEmpty) {
      _processFingerprintSample(event.template!);
    } else if (event.type == 'low_quality') {
      if (mounted) {
        setState(() => _errorMessage = 'Qualité trop basse. Posez le doigt bien à plat sur le lecteur.');
      }
    }
  }

  Future<void> _processFingerprintSample(String sample) async {
    final runtime = ref.read(appRuntimeProvider);
    final db = runtime.database;

    // Verifikasyon doublon 1:N si se yon nouvo manm
    if (!_isRenewal && db != null) {
      try {
        final rows = await db.watchRecords(SyncEntity.members, limit: 50000).first;
        final enrolled = <Member>[];
        for (final r in rows) {
          try {
            final m = Member(Map<String, dynamic>.from(jsonDecode(r.payload) as Map));
            if (m.fingerprintTemplate?.isNotEmpty ?? false) enrolled.add(m);
          } catch (_) {}
        }
        final dup = await _biometricService.match1toN(candidateTemplate: sample, members: enrolled);
        if (dup != null && mounted) {
          setState(() {
            _errorMessage = 'Empreinte déjà enregistrée pour : ${dup.fullName} (${dup.memberNumber})';
          });
          return;
        }
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      _fingerprintTemplate = sample;
      _errorMessage = null;
    });

    // Notify Supabase immediately so the candidate's phone receives real-time green tick
    try {
      await runtime.client.from('portal_requests').update({
        'status': 'approved',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.request.id);
    } catch (_) {}
  }

  Future<void> _submitActivation() async {
    if (_selectedPlan == null) {
      setState(() => _errorMessage = 'Veuillez sélectionner une formule.');
      return;
    }

    if (_fingerprintTemplate == null && !_skipFingerprint) {
      setState(() => _errorMessage = 'Veuillez poser le doigt sur le lecteur USB ou cocher "Enregistrer sans empreinte".');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    final runtime = ref.read(appRuntimeProvider);
    final db = runtime.database;
    final session = runtime.session;
    if (db == null || session == null) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Base de données locale ou session non disponible.';
      });
      return;
    }

    final now = DateTime.now();
    final plan = _selectedPlan!;
    final regFee = _isRenewal ? 0.0 : plan.registrationFee;
    final planPrice = plan.price;
    final totalAmount = planPrice + regFee;
    final endDate = subscriptionEnd(now, plan.durationDays);
    final currency = (plan.currency.trim().toUpperCase() == 'USD') ? 'USD' : 'HTG';
    final paymentId = const Uuid().v4();

    try {
      if (_isRenewal) {
        // Traitement pour Renouvellement
        Member? member;
        final digits = widget.request.phone.replaceAll(RegExp(r'\D'), '');
        final rows = await db.watchRecords(SyncEntity.members, limit: 50000).first;
        for (final r in rows) {
          try {
            final m = Member(Map<String, dynamic>.from(jsonDecode(r.payload) as Map));
            if (widget.request.memberId != null && m.id == widget.request.memberId) {
              member = m;
              break;
            }
            final mDigits = (m.phone ?? m.whatsapp ?? '').replaceAll(RegExp(r'\D'), '');
            if (digits.isNotEmpty && mDigits.isNotEmpty && (mDigits.contains(digits) || digits.contains(mDigits))) {
              member = m;
              break;
            }
            if (m.fullName.toLowerCase() == widget.request.fullName.toLowerCase()) {
              member = m;
              break;
            }
          } catch (_) {}
        }

        if (member == null) {
          throw Exception('Membre introuvable pour ce renouvellement. Vérifiez le numéro de téléphone ou le compte.');
        }

        final subscriptionId = const Uuid().v4();
        final subRow = <String, dynamic>{
          'id': subscriptionId,
          'gym_id': session.gymId,
          'member_id': member.id,
          'plan_id': plan.id,
          'start_date': ymd(dateOnly(now)),
          'end_date': ymd(dateOnly(endDate)),
          'price': planPrice,
          'opening_credit': 0.0,
          'enrollment_kind': 'renewal',
          'status': 'active',
          'created_by': session.staffId,
          'validated_by': session.staffId,
          'validated_at': now.toUtc().toIso8601String(),
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
          'deleted_at': null,
        };

        final paymentRow = <String, dynamic>{
          'id': paymentId,
          'gym_id': session.gymId,
          'member_id': member.id,
          'subscription_id': subscriptionId,
          'amount': totalAmount,
          'currency': currency,
          'method': _paymentMethod,
          'reference': _referenceController.text.trim().isNotEmpty ? _referenceController.text.trim() : null,
          'received_amount': totalAmount,
          'credit_used': 0.0,
          'credit_amount': 0.0,
          'registration_fee': 0.0,
          'plan_fee': planPrice,
          'payment_reason': 'Renouvellement (${plan.name})',
          'paid_at': now.toUtc().toIso8601String(),
          'received_by': session.staffId,
          'notes': null,
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
          'deleted_at': null,
        };

        await db.save(SyncEntity.subscriptions, subRow, changedAt: now);
        await db.save(SyncEntity.payments, paymentRow, changedAt: now);

        if (_fingerprintTemplate != null) {
          await db.save(SyncEntity.members, {
            ...member.row,
            'fingerprint_registered': true,
            'fingerprint_template': _fingerprintTemplate,
            'fingerprint_enrolled_at': now.toUtc().toIso8601String(),
            'status': 'active',
          }, changedAt: now);
        }

        try {
          await runtime.client.from('portal_requests').update({
            'status': 'completed',
            'member_id': member.id,
            'updated_at': now.toUtc().toIso8601String(),
          }).eq('id', widget.request.id);
        } catch (_) {}

        await runtime.sync?.synchronize();

        if (mounted) {
          setState(() {
            _isProcessing = false;
            _isCompleted = true;
            _completedMemberNumber = member?.memberNumber;
            _completedPaymentId = paymentId;
            _completedTotal = totalAmount;
            _completedEndDate = endDate;
          });
          widget.onCompleted();
        }
      } else {
        // Traitement pour Nouvelle Inscription
        String fn = widget.request.firstName.trim();
        String ln = widget.request.lastName.trim();
        if (ln.length < 2) {
          final parts = fn.split(RegExp(r'\s+'));
          if (parts.length > 1) {
            fn = parts.first;
            ln = parts.sublist(1).join(' ');
          } else {
            ln = ln.isNotEmpty ? '$ln.' : 'Client';
          }
        }
        if (fn.length < 2) {
          final parts = ln.split(RegExp(r'\s+'));
          if (parts.length > 1) {
            fn = parts.first;
            ln = parts.sublist(1).join(' ');
          } else {
            fn = fn.isNotEmpty ? '$fn.' : 'Membre';
          }
        }

        final memberId = const Uuid().v4();
        final subscriptionId = const Uuid().v4();
        final memberNumber = await db.nextMemberNumber();
        final qrToken = const Uuid().v4();
        final rawEmail = (widget.request.email ?? '').trim();
        final validEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(rawEmail) ? rawEmail : null;
        final phone = normalizePhone(widget.request.phone);

        final isOneDayPass = plan.durationDays == 1 || plan.name.toLowerCase().contains('1 j') || plan.name.toLowerCase().contains('séance');
        final todayMidnight = DateTime(now.year, now.month, now.day, 23, 59, 59);
        final tempPin = isOneDayPass ? '${100000 + (memberId.hashCode.abs() % 900000)}' : null;

        final memberRow = <String, dynamic>{
          'id': memberId,
          'gym_id': session.gymId,
          'member_number': memberNumber,
          'qr_token': qrToken,
          'first_name': fn,
          'last_name': ln,
          'phone': phone.isNotEmpty ? phone : null,
          'whatsapp': phone.isNotEmpty ? phone : null,
          'email': validEmail,
          'enrollment_origin': 'new',
          'address': null,
          'nif': null,
          'cin': null,
          'emergency_contact_name': null,
          'emergency_contact_phone': null,
          'guardian_name': null,
          'photo_url': null,
          'notes': widget.request.notes?.trim().isNotEmpty == true ? widget.request.notes!.trim() : null,
          'fingerprint_template': _fingerprintTemplate,
          'fingerprint_registered': _fingerprintTemplate != null && _fingerprintTemplate!.isNotEmpty,
          'temporary_pin': tempPin,
          'pin_expires_at': isOneDayPass ? todayMidnight.toIso8601String() : null,
          'status': 'active',
          'is_test': false,
          'created_by': session.staffId,
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
          'deleted_at': null,
        };

        final subRow = <String, dynamic>{
          'id': subscriptionId,
          'gym_id': session.gymId,
          'member_id': memberId,
          'plan_id': plan.id,
          'start_date': ymd(dateOnly(now)),
          'end_date': ymd(dateOnly(endDate)),
          'price': totalAmount,
          'opening_credit': 0.0,
          'enrollment_kind': 'registration',
          'status': 'active',
          'created_by': session.staffId,
          'validated_by': session.staffId,
          'validated_at': now.toUtc().toIso8601String(),
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
          'deleted_at': null,
        };

        final reason = regFee > 0 ? 'Inscription + 1er mois' : 'Inscription (${plan.name})';

        final paymentRow = <String, dynamic>{
          'id': paymentId,
          'gym_id': session.gymId,
          'member_id': memberId,
          'subscription_id': subscriptionId,
          'amount': totalAmount,
          'currency': currency,
          'method': _paymentMethod,
          'reference': _referenceController.text.trim().isNotEmpty ? _referenceController.text.trim() : null,
          'received_amount': totalAmount,
          'credit_used': 0.0,
          'credit_amount': 0.0,
          'registration_fee': regFee,
          'plan_fee': planPrice,
          'payment_reason': reason,
          'paid_at': now.toUtc().toIso8601String(),
          'received_by': session.staffId,
          'notes': null,
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
          'deleted_at': null,
        };

        await db.activateMemberCard(
          member: memberRow,
          subscription: subRow,
          payment: paymentRow,
          changedAt: now,
        );

        try {
          await runtime.client.from('portal_requests').update({
            'status': 'completed',
            'member_id': memberId,
            'updated_at': now.toUtc().toIso8601String(),
          }).eq('id', widget.request.id);
        } catch (_) {
          try {
            await runtime.client.from('portal_requests').update({
              'status': 'completed',
              'updated_at': now.toUtc().toIso8601String(),
            }).eq('id', widget.request.id);
          } catch (_) {}
        }

        await runtime.sync?.synchronize();

        if (mounted) {
          setState(() {
            _isProcessing = false;
            _isCompleted = true;
            _completedMemberNumber = memberNumber;
            _completedPaymentId = paymentId;
            _completedTotal = totalAmount;
            _completedEndDate = endDate;
          });
          widget.onCompleted();
        }
      }
    } catch (e) {
      if (mounted) {
        String msg = '$e';
        if (e is MemberFailure) {
          switch (e.code) {
            case 'invalid_record':
              msg = 'Données invalides. Veuillez vérifier le nom et prénom.';
              break;
            case 'invalid_email':
              msg = 'Adresse email invalide.';
              break;
            case 'access_denied':
              msg = 'Accès refusé : permissions insuffisantes.';
              break;
            case 'local_storage':
              msg = 'Erreur d’enregistrement local dans la base SQLite.';
              break;
            default:
              msg = e.code;
          }
        }
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Erreur lors de l’enregistrement : $msg';
        });
      }
    }
  }

  Future<void> _printReceipt(AppStrings s) async {
    final runtime = ref.read(appRuntimeProvider);
    final gymName = runtime.session?.gym?['name']?.toString() ?? 'GymDesk';
    final currency = _selectedPlan?.currency.isNotEmpty == true ? _selectedPlan!.currency : 'HTG';
    final receiptNo = _completedPaymentId?.substring(0, 8) ?? 'REC-001';

    final data = ReceiptData(
      paymentId: receiptNo,
      memberName: widget.request.fullName,
      memberNumber: _completedMemberNumber ?? 'MEM-Actif',
      planName: _selectedPlan?.name ?? 'Abonnement',
      amount: _completedTotal,
      currency: currency,
      method: _paymentMethod,
      paidAt: DateTime.now(),
      gymName: gymName,
      accentColor: '#0F766E',
      periodStart: DateTime.now(),
      periodEnd: _completedEndDate,
      reference: receiptNo,
      memberPhone: widget.request.phone,
      memberEmail: widget.request.email,
    );

    final labels = {
      'receipt': s.text('receipt'),
      'receipt_paid': s.text('receipt_paid'),
      'receipt_plan': s.text('receipt_plan'),
      'receipt_period': s.text('receipt_period'),
      'receipt_amount': s.text('receipt_amount'),
      'receipt_received': s.text('receipt_received'),
      'receipt_credited': s.text('receipt_credited'),
      'receipt_paid_by_balance': s.text('receipt_paid_by_balance'),
      'receipt_change': s.text('receipt_change'),
      'receipt_paid_in': s.text('receipt_paid_in'),
      'received_by': s.text('received_by'),
      'receipt_balance': s.text('receipt_balance'),
      'receipt_reference': s.text('receipt_reference'),
      'receipt_signature': s.text('receipt_signature'),
      'receipt_thanks': s.text('receipt_thanks'),
      'member_number': s.text('member_number'),
      'payment_method': s.text('payment_method'),
      'date': s.text('date'),
      'method_cash': s.text('method_cash'),
      'method_moncash': s.text('method_moncash'),
      'method_natcash': s.text('method_natcash'),
      'method_bank': s.text('method_bank'),
    };

    try {
      final pdfBytes = await buildReceiptPdf(data, labels);
      await Printing.layoutPdf(
        name: 'recu_$receiptNo.pdf',
        onLayout: (format) async => pdfBytes,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    if (_isCompleted) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFD1FAE5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.circleCheck, color: Color(0xFF059669), size: 42),
              ),
              const SizedBox(height: 18),
              Text(
                _isRenewal ? 'Renouvellement Confirmé !' : 'Adhésion Activée avec Succès !',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF0F766E)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Le compte de ${widget.request.fullName} est opérationnel. Le reçu officiel a été transmis en direct sur son téléphone.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('N° Membre :', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                        Text(_completedMemberNumber ?? 'MEM-Actif', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Montant Total Réglé :', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                        Text('${_completedTotal.toStringAsFixed(0)} ${_selectedPlan?.currency ?? "HTG"}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _printReceipt(s),
                      icon: const Icon(LucideIcons.printer, size: 16),
                      label: const Text('Imprimer Reçu'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        widget.onCompleted();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Terminer', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final currency = _selectedPlan?.currency ?? 'HTG';
    final planPrice = _selectedPlan?.price ?? 0.0;
    final regFee = _isRenewal ? 0.0 : (_selectedPlan?.registrationFee ?? 0.0);
    final totalToPay = planPrice + regFee;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // En-tête du Modal
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _isRenewal ? const Color(0xFFEDE9FE) : const Color(0xFFCCFBF1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isRenewal ? LucideIcons.refreshCw : LucideIcons.userPlus,
                      color: _isRenewal ? const Color(0xFF6D28D9) : const Color(0xFF0F766E),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isRenewal ? 'Traiter le Renouvellement' : 'Finaliser l’Inscription en Direct',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        Text(
                          '${widget.request.fullName} · ${widget.request.phone}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.triangleAlert, color: Color(0xFFDC2626), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Section 1 : Formule d'abonnement
              const Text('1. Formule d’abonnement :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              if (_loadingPlans)
                const LinearProgressIndicator()
              else
                DropdownButtonFormField<GymPlan>(
                  value: _selectedPlan,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: _plans.map((p) {
                    final feeText = !_isRenewal && p.registrationFee > 0
                        ? ' (+${p.registrationFee.toStringAsFixed(0)} ${p.currency} frais)'
                        : '';
                    return DropdownMenuItem(
                      value: p,
                      child: Text('${p.name} — ${p.price.toStringAsFixed(0)} ${p.currency} / ${p.durationDays}j$feeText'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedPlan = val);
                  },
                ),
              const SizedBox(height: 18),

              // Section 2 : Empreinte digitale (Auto-Capture)
              const Text('2. Empreinte digitale (Lancement Automatique) :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _fingerprintTemplate != null
                      ? const Color(0xFFF0FDF4)
                      : (_skipFingerprint ? const Color(0xFFF8FAFC) : const Color(0xFFEFF6FF)),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _fingerprintTemplate != null
                        ? const Color(0xFF86EFAC)
                        : (_skipFingerprint ? const Color(0xFFE2E8F0) : const Color(0xFF93C5FD)),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    if (_fingerprintTemplate != null) ...[
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: Color(0xFFD1FAE5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.circleCheck, color: Color(0xFF059669), size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Empreinte capturée avec succès ✓',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF065F46)),
                                ),
                                Text(
                                  'Synchronisé en direct avec le téléphone du client.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _fingerprintTemplate = null),
                            child: const Text('Rescanner', style: TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ] else if (_skipFingerprint) ...[
                      Row(
                        children: [
                          Icon(LucideIcons.shieldOff, color: Colors.grey.shade500, size: 24),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Empreinte ignorée pour l’instant.',
                              style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDBEAFE),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.fingerprint, color: Color(0xFF2563EB), size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Poze dwèt la sou lektè a...',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E40AF)),
                                ),
                                Text(
                                  'Lektè a ap koute otomatikman — pa bezwen klike anyen.',
                                  style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _skipFingerprint,
                      title: const Text('Salle sans lecteur / Enregistrer l’empreinte plus tard', style: TextStyle(fontSize: 12)),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      onChanged: (val) => setState(() => _skipFingerprint = val ?? false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Section 3 : Paiement & Total
              const Text('3. Règlement & Mode de paiement :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    if (!_isRenewal && regFee > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Frais d’inscription :', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                          Text('${regFee.toStringAsFixed(0)} $currency', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Tarif formule (${_selectedPlan?.name ?? ""}) :', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                        Text('${planPrice.toStringAsFixed(0)} $currency', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(height: 18, thickness: 1),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL À ENCAISSER :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F766E))),
                        Text(
                          '${totalToPay.toStringAsFixed(0)} $currency',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F766E)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Sélecteur de méthode de paiement
                    DropdownButtonFormField<String>(
                      value: _paymentMethod,
                      decoration: InputDecoration(
                        labelText: 'Mode de paiement',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Espèces (Cash)')),
                        DropdownMenuItem(value: 'moncash', child: Text('MonCash')),
                        DropdownMenuItem(value: 'natcash', child: Text('Natcash')),
                        DropdownMenuItem(value: 'bank', child: Text('Carte / Virement')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _paymentMethod = val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // Bouton d'action principal
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isProcessing ? null : _submitActivation,
                  icon: _isProcessing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.checkCheck, size: 18),
                  label: Text(
                    _isProcessing
                        ? 'Activation en cours...'
                        : (_isRenewal ? 'Encaisser & Renouveler' : 'Valider & Activer le Compte'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
