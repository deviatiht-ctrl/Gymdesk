import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../l10n/app_strings.dart';
import '../../payments/data/receipt_pdf.dart';
import '../data/portal_repository.dart';

class PortalJoinPage extends ConsumerStatefulWidget {
  const PortalJoinPage({super.key, required this.gymCode, this.initialKind});

  final String gymCode;
  final String? initialKind;

  @override
  ConsumerState<PortalJoinPage> createState() => _PortalJoinPageState();
}

class _PortalJoinPageState extends ConsumerState<PortalJoinPage> {
  static const _storage = FlutterSecureStorage();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loadingGym = true;
  String? _loadError;
  Map<String, dynamic>? _gym;
  List<Map<String, dynamic>> _plans = [];

  String _kind = 'new_membership'; // 'new_membership' or 'renewal'
  String? _selectedPlanId;
  String? _savedDraftPlanId;
  bool _isSubmitting = false;
  String? _formError;
  bool _submittedSuccess = false;
  String? _lastSubmittedRequestId;
  bool _hasRestoredDraft = false;
  late final String _sessionCode;
  Timer? _doorScanTimer;
  Timer? _liveTrackingTimer;
  Map<String, dynamic>? _liveRequestData;
  bool _isGeneratingPdf = false;
  Map<String, dynamic>? _identifiedMember;
  String? _memberId;
  final _searchPhoneController = TextEditingController();
  bool _searchingMember = false;
  String? _searchError;

  late final PortalRepository _portalRepo;

  String get _cleanGymCode => widget.gymCode.trim();
  String get _draftStorageKey => 'portal_draft_$_cleanGymCode';
  String get _activeReqStorageKey => 'portal_active_req_$_cleanGymCode';

  bool get _liveHasBiometric =>
      _liveRequestData?['has_biometric'] == true ||
      _liveRequestData?['status'] == 'approved' ||
      _liveRequestData?['status'] == 'completed';

  String get _liveStatus => _liveRequestData?['status'] as String? ?? 'pending';

  Map<String, dynamic>? get _liveReceipt =>
      _liveRequestData?['receipt'] as Map<String, dynamic>?;

  String? get _liveMemberNumber =>
      _liveRequestData?['member_number'] as String?;

  @override
  void initState() {
    super.initState();
    _sessionCode = 'SEC-${const Uuid().v4().substring(0, 8).toUpperCase()}';

    if (widget.initialKind == 'renewal') {
      _kind = 'renewal';
    } else if (widget.initialKind == 'new_membership') {
      _kind = 'new_membership';
    }

    final runtime = ref.read(appRuntimeProvider);
    _portalRepo = PortalRepository(runtime.client);

    // Auto-save listeners pou pa janm pèdi done si moun lan soti nan paj la
    _firstNameController.addListener(_onFieldChanged);
    _lastNameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _notesController.addListener(_onFieldChanged);

    _loadDraft();
    _loadActiveRequest();
    _loadGymData();
    if (_kind == 'renewal') {
      _startDoorScanPolling();
    }
  }

  void _onFieldChanged() {
    _saveDraft();
  }

  Future<void> _saveDraft() async {
    try {
      final draft = {
        'session_code': _sessionCode,
        'first_name': _firstNameController.text,
        'last_name': _lastNameController.text,
        'phone': _phoneController.text,
        'email': _emailController.text,
        'notes': _notesController.text,
        'kind': _kind,
        'plan_id': _selectedPlanId,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await _storage.write(key: _draftStorageKey, value: jsonEncode(draft));
    } catch (_) {}
  }

  Future<void> _loadDraft() async {
    try {
      final raw = await _storage.read(key: _draftStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            if (_firstNameController.text.isEmpty && data['first_name'] != null) {
              _firstNameController.text = data['first_name'] as String;
            }
            if (_lastNameController.text.isEmpty && data['last_name'] != null) {
              _lastNameController.text = data['last_name'] as String;
            }
            if (_phoneController.text.isEmpty && data['phone'] != null) {
              _phoneController.text = data['phone'] as String;
            }
            if (_emailController.text.isEmpty && data['email'] != null) {
              _emailController.text = data['email'] as String;
            }
            if (_notesController.text.isEmpty && data['notes'] != null) {
              _notesController.text = data['notes'] as String;
            }
            if (widget.initialKind == null && data['kind'] != null) {
              _kind = data['kind'] as String;
            }
            if (data['plan_id'] != null) {
              _savedDraftPlanId = data['plan_id'] as String;
              if (_plans.any((p) => p['id'] == _savedDraftPlanId)) {
                _selectedPlanId = _savedDraftPlanId;
              }
            }
            _hasRestoredDraft = _firstNameController.text.isNotEmpty ||
                _phoneController.text.isNotEmpty ||
                _notesController.text.isNotEmpty;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      await _storage.delete(key: _draftStorageKey);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _firstNameController.clear();
        _lastNameController.clear();
        _phoneController.clear();
        _emailController.clear();
        _notesController.clear();
        _hasRestoredDraft = false;
        _formError = null;
      });
    }
  }

  Future<void> _loadGymData() async {
    setState(() {
      _loadingGym = true;
      _loadError = null;
    });

    try {
      final res = await _portalRepo.getPublicGym(_cleanGymCode);
      final gymMap = res['gym'] as Map<String, dynamic>?;
      final rawPlans = res['plans'] as List<dynamic>? ?? [];

      if (gymMap == null) {
        setState(() {
          _loadingGym = false;
          _loadError = 'Gym introuvable ou inactif.';
        });
        return;
      }

      setState(() {
        _gym = gymMap;
        _plans = rawPlans.cast<Map<String, dynamic>>();
        if (_plans.isNotEmpty) {
          if (_savedDraftPlanId != null && _plans.any((p) => p['id'] == _savedDraftPlanId)) {
            _selectedPlanId = _savedDraftPlanId;
          } else {
            _selectedPlanId = _plans.first['id'] as String?;
          }
        }
        _loadingGym = false;
      });
    } catch (e) {
      setState(() {
        _loadingGym = false;
        _loadError = 'Erreur lors du chargement : $e';
      });
    }
  }

  Future<void> _submit(AppStrings s) async {
    final fn = _firstNameController.text.trim();
    final ln = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final notes = _notesController.text.trim();

    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (fn.length < 2 || ln.length < 2 || digits.length < 8) {
      setState(() => _formError = s.text('fill_required_fields'));
      return;
    }

    if (email.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _formError = s.text('invalid_email'));
      return;
    }

    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    try {
      final res = await _portalRepo.submitJoinRequest(
        gymCode: _cleanGymCode,
        planId: _selectedPlanId,
        firstName: fn,
        lastName: ln,
        phone: phone,
        email: email,
        kind: _kind,
        notes: notes,
        memberId: _memberId,
      );

      final reqId = res['request_id'] as String? ?? _sessionCode;
      try {
        await _storage.delete(key: _draftStorageKey);
        await _storage.write(key: _activeReqStorageKey, value: reqId);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submittedSuccess = true;
          _lastSubmittedRequestId = reqId;
        });
        _startLiveTracking(reqId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _formError = 'Erreur lors de l’envoi : $e';
        });
      }
    }
  }


  Future<void> _loadActiveRequest() async {
    try {
      final savedId = await _storage.read(key: _activeReqStorageKey);
      if (savedId != null && savedId.isNotEmpty) {
        final res = await _portalRepo.getRequestStatus(savedId);
        if (res['found'] == true && mounted) {
          final createdAt = DateTime.tryParse(res['created_at']?.toString() ?? '');
          // Si la demande date de moins de 24h, on reste sur le live tracker
          if (createdAt != null && DateTime.now().difference(createdAt).inHours < 24) {
            setState(() {
              _submittedSuccess = true;
              _lastSubmittedRequestId = savedId;
              _liveRequestData = res;
              _selectedPlanId = res['plan_id']?.toString() ?? _selectedPlanId;
              if (res['first_name'] != null) _firstNameController.text = res['first_name'];
              if (res['last_name'] != null) _lastNameController.text = res['last_name'];
              if (res['phone'] != null) _phoneController.text = res['phone'];
            });
            _startLiveTracking(savedId);
          }
        }
      }
    } catch (_) {}
  }

  void _startLiveTracking(String requestId) {
    _liveTrackingTimer?.cancel();
    _fetchLiveRequestStatus(requestId);
    _liveTrackingTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted) return;
      _fetchLiveRequestStatus(requestId);
    });
  }

  Future<void> _fetchLiveRequestStatus(String requestId) async {
    try {
      final res = await _portalRepo.getRequestStatus(requestId);
      if (res['found'] == true && mounted) {
        setState(() {
          _liveRequestData = res;
        });
      }
    } catch (_) {}
  }

  Future<void> _resetAndStartNew() async {
    _liveTrackingTimer?.cancel();
    try {
      await _storage.delete(key: _activeReqStorageKey);
      await _storage.delete(key: _draftStorageKey);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _submittedSuccess = false;
        _lastSubmittedRequestId = null;
        _liveRequestData = null;
        _identifiedMember = null;
        _memberId = null;
        _firstNameController.clear();
        _lastNameController.clear();
        _phoneController.clear();
        _emailController.clear();
        _notesController.clear();
      });
    }
  }

  Map<String, String> _getReceiptLabels(AppStrings s) {
    return {
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
  }

  Future<void> _downloadOrPrintReceipt(AppStrings s) async {
    if (_isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);

    try {
      final req = _liveRequestData ?? {};
      final receipt = _liveReceipt ?? {};
      final gymName = req['gym_name']?.toString() ?? _gym?['name']?.toString() ?? 'GymDesk';
      final currency = req['gym_currency']?.toString() ?? _gym?['currency']?.toString() ?? 'HTG';
      final planName = receipt['plan_name']?.toString() ?? req['plan_name']?.toString() ?? 'Abonnement';
      final amount = (receipt['amount'] as num?)?.toDouble() ?? (req['plan_price'] as num?)?.toDouble() ?? 0.0;
      final receiptNo = receipt['receipt_number']?.toString() ?? _lastSubmittedRequestId?.substring(0, 8) ?? 'REC-001';

      final data = ReceiptData(
        paymentId: receiptNo,
        memberName: '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
        memberNumber: _liveMemberNumber ?? 'MEM-Actif',
        planName: planName,
        amount: amount,
        currency: currency,
        method: receipt['payment_method']?.toString() ?? 'Comptoir',
        paidAt: DateTime.tryParse(receipt['payment_date']?.toString() ?? '') ?? DateTime.now(),
        gymName: gymName,
        accentColor: '#0F766E',
        periodStart: DateTime.tryParse(receipt['sub_start_date']?.toString() ?? ''),
        periodEnd: DateTime.tryParse(receipt['sub_end_date']?.toString() ?? ''),
        reference: receiptNo,
        memberPhone: _phoneController.text.trim(),
        memberEmail: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
      );

      final pdfBytes = await buildReceiptPdf(data, _getReceiptLabels(s));
      await Printing.layoutPdf(
        name: 'recu_$receiptNo.pdf',
        onLayout: (format) async => pdfBytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur génération reçu : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  void _shareReceiptWhatsApp() {
    final req = _liveRequestData ?? {};
    final receipt = _liveReceipt ?? {};
    final gymName = req['gym_name']?.toString() ?? _gym?['name']?.toString() ?? 'GymDesk';
    final currency = req['gym_currency']?.toString() ?? _gym?['currency']?.toString() ?? 'HTG';
    final planName = receipt['plan_name']?.toString() ?? req['plan_name']?.toString() ?? 'Abonnement';
    final amount = (receipt['amount'] as num?)?.toDouble() ?? (req['plan_price'] as num?)?.toDouble() ?? 0.0;
    final receiptNo = receipt['receipt_number']?.toString() ?? _lastSubmittedRequestId?.substring(0, 8) ?? 'REC-001';
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');

    final msg = StringBuffer()
      ..writeln('🏋️ *REÇU OFFICIEL D\'ADHÉSION - $gymName*')
      ..writeln('━━━━━━━━━━━━━━━━━━━━')
      ..writeln('👤 *Membre* : ${_firstNameController.text.trim()} ${_lastNameController.text.trim()}')
      ..writeln('🔢 *N° Membre* : ${_liveMemberNumber ?? "Activé"}')
      ..writeln('🧾 *Reçu N°* : #$receiptNo')
      ..writeln('📋 *Formule* : $planName')
      ..writeln('💰 *Montant Réglé* : ${amount.toStringAsFixed(0)} $currency')
      ..writeln('✅ *Statut* : PAYÉ & ACCÈS BIOMÉTRIQUE CONFIRMÉ')
      ..writeln('━━━━━━━━━━━━━━━━━━━━')
      ..writeln('Bienvenue chez $gymName ! Votre empreinte est enregistrée pour l\'accès aux portes.');

    final waUrl = 'https://wa.me/$phone?text=${Uri.encodeComponent(msg.toString())}';
    launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
  }

  void _startDoorScanPolling() {
    _doorScanTimer?.cancel();
    _doorScanTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _kind != 'renewal' || _identifiedMember != null) return;
      final scan = await _portalRepo.getLatestDoorScan(_cleanGymCode);
      if (scan['found'] == true && mounted) {
        _onMemberIdentified(scan);
      }
    });
  }

  void _onMemberIdentified(Map<String, dynamic> data) {
    setState(() {
      _identifiedMember = data;
      _memberId = data['member_id']?.toString();
      _firstNameController.text = data['first_name']?.toString() ?? _firstNameController.text;
      _lastNameController.text = data['last_name']?.toString() ?? _lastNameController.text;
      _phoneController.text = data['phone']?.toString() ?? _phoneController.text;
      if (data['email'] != null && (data['email'] as String).isNotEmpty) {
        _emailController.text = data['email'] as String;
      }
      _searchError = null;
    });
    _doorScanTimer?.cancel();
    _saveDraft();
  }

  Future<void> _searchMemberManual() async {
    final q = _searchPhoneController.text.trim();
    if (q.length < 4) {
      setState(() => _searchError = 'Entrez au moins 4 chiffres de votre téléphone.');
      return;
    }
    setState(() {
      _searchingMember = true;
      _searchError = null;
    });
    final res = await _portalRepo.lookupMember(gymCode: _cleanGymCode, query: q);
    if (mounted) {
      setState(() {
        _searchingMember = false;
        if (res['found'] == true) {
          _onMemberIdentified(res);
        } else {
          _searchError = 'Aucun membre trouvé avec ce numéro.';
        }
      });
    }
  }

  void _resetIdentifiedMember() {
    setState(() {
      _identifiedMember = null;
      _memberId = null;
      _searchPhoneController.clear();
      _searchError = null;
    });
    _startDoorScanPolling();
  }

  @override
  void dispose() {
    _doorScanTimer?.cancel();
    _liveTrackingTimer?.cancel();
    _searchPhoneController.dispose();
    _firstNameController.removeListener(_onFieldChanged);
    _lastNameController.removeListener(_onFieldChanged);
    _phoneController.removeListener(_onFieldChanged);
    _emailController.removeListener(_onFieldChanged);
    _notesController.removeListener(_onFieldChanged);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    if (_loadingGym) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null || _gym == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.alertTriangle, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                Text(
                  _loadError ?? 'Gym introuvable',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadGymData,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final gymName = _gym!['name'] as String? ?? 'Salle de Sport';
    final logoUrl = _gym!['logo_url'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Card(
                elevation: 4,
                shadowColor: Colors.black12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: _submittedSuccess
                      ? _buildLiveTrackingView(s, gymName, logoUrl)
                      : _buildFormView(s, gymName, logoUrl),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveTrackingView(AppStrings s, String gymName, String? logoUrl) {
    final req = _liveRequestData ?? {};
    final receipt = _liveReceipt;
    final selectedPlan = _plans.where((p) => p['id'] == _selectedPlanId).firstOrNull;
    final planName = receipt?['plan_name']?.toString() ?? req['plan_name']?.toString() ?? selectedPlan?['name']?.toString() ?? 'Formule d\'abonnement';
    final planPrice = (req['plan_price'] as num?)?.toDouble() ?? (selectedPlan?['price'] as num?)?.toDouble() ?? 0.0;
    final regFee = (req['registration_fee'] as num?)?.toDouble() ?? (selectedPlan?['registration_fee'] as num?)?.toDouble() ?? 0.0;
    final currency = req['gym_currency']?.toString() ?? _gym?['currency']?.toString() ?? 'HTG';
    final isDone = _liveStatus == 'completed';
    final hasBio = _liveHasBiometric;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // En-tête avec statut dynamique
        Center(
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFFD1FAE5)
                      : (hasBio ? const Color(0xFFCCFBF1) : const Color(0xFFEFF6FF)),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isDone ? const Color(0xFF059669) : const Color(0xFF0F766E)).withOpacity(0.18),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  isDone
                      ? LucideIcons.circleCheck
                      : (hasBio ? LucideIcons.fingerprint : LucideIcons.clock),
                  color: isDone
                      ? const Color(0xFF059669)
                      : (hasBio ? const Color(0xFF0F766E) : const Color(0xFF2563EB)),
                  size: 42,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isDone
                    ? 'Adhésion Activée ! Félicitations !'
                    : (hasBio
                        ? 'Empreinte Enregistrée ✓'
                        : (_kind == 'renewal' ? 'Demande de Renouvellement' : 'Demande d\'Inscription Reçue')),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                isDone
                    ? 'Votre compte est prêt et vos accès sont fonctionnels.'
                    : 'Suivi en direct de votre dossier auprès de la réception de $gymName.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Badge de suivi en direct
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      'Dossier #${_lastSubmittedRequestId ?? _sessionCode}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDone ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDone ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isDone ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isDone ? 'Compte Activé' : 'Synchronisé en direct',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isDone ? const Color(0xFF15803D) : const Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Timeline des 3 étapes en direct
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Étapes de finalisation :',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 14),

              // Étape 1 : Demande transmise
              _buildTimelineStep(
                stepNumber: '1',
                title: 'Demande transmise',
                subtitle: 'Formule : $planName (${planPrice.toStringAsFixed(0)} $currency)',
                isComplete: true,
                badgeText: 'Reçue ✓',
                badgeColor: const Color(0xFF16A34A),
                badgeBg: const Color(0xFFDCFCE7),
                icon: LucideIcons.circleCheck,
              ),

              const Padding(
                padding: EdgeInsets.only(left: 17),
                child: SizedBox(height: 14, child: VerticalDivider(thickness: 2, color: Color(0xFFCBD5E1))),
              ),

              // Étape 2 : Empreinte digitale
              _buildTimelineStep(
                stepNumber: '2',
                title: 'Prise d\'empreinte digitale à l\'accueil',
                subtitle: hasBio
                    ? 'Empreinte enregistrée avec succès sur le capteur USB du gym.'
                    : 'Veuillez vous présenter au comptoir pour scanner votre doigt.',
                isComplete: hasBio,
                isActive: !hasBio,
                badgeText: hasBio ? 'Enregistrée ✓' : 'En attente à l\'accueil...',
                badgeColor: hasBio ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                badgeBg: hasBio ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                icon: hasBio ? LucideIcons.circleCheck : LucideIcons.fingerprint,
              ),

              const Padding(
                padding: EdgeInsets.only(left: 17),
                child: SizedBox(height: 14, child: VerticalDivider(thickness: 2, color: Color(0xFFCBD5E1))),
              ),

              // Étape 3 : Validation & Paiement
              _buildTimelineStep(
                stepNumber: '3',
                title: 'Activation & Règlement',
                subtitle: isDone
                    ? 'Paiement enregistré et accès tourniquet activé !'
                    : 'L\'agent finalise votre encaissement à la réception.',
                isComplete: isDone,
                isActive: hasBio && !isDone,
                badgeText: isDone ? 'Confirmé ✓' : (hasBio ? 'En cours...' : 'En attente'),
                badgeColor: isDone ? const Color(0xFF16A34A) : const Color(0xFF0284C7),
                badgeBg: isDone ? const Color(0xFFDCFCE7) : const Color(0xFFE0F2FE),
                icon: isDone ? LucideIcons.badgeCheck : LucideIcons.wallet,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // Carte Reçu Numérique Officiel (si terminé ou données disponibles)
        if (isDone || receipt != null) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gymName.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F766E)),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'REÇU D\'ADHÉSION OFFICIEL',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B), letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: const Text(
                        'PAYÉ ✓',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF15803D)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(thickness: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 8),

                _buildReceiptRow('Membre', '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'),
                if (_liveMemberNumber != null)
                  _buildReceiptRow('N° Membre', _liveMemberNumber!),
                _buildReceiptRow('Téléphone', _phoneController.text.trim()),
                _buildReceiptRow('Reçu N°', '#${receipt?['receipt_number'] ?? _lastSubmittedRequestId?.substring(0, 8) ?? 'REC-001'}'),
                _buildReceiptRow('Date', receipt?['payment_date']?.toString().split('T').first ?? DateFormat('dd/MM/yyyy').format(DateTime.now())),
                if (receipt?['sub_start_date'] != null && receipt?['sub_end_date'] != null)
                  _buildReceiptRow('Période', 'Du ${receipt?['sub_start_date']} au ${receipt?['sub_end_date']}'),

                const SizedBox(height: 8),
                const Divider(thickness: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 8),

                if (regFee > 0)
                  _buildReceiptRow('Frais d\'inscription', '${regFee.toStringAsFixed(0)} $currency'),
                _buildReceiptRow('Abonnement ($planName)', '${planPrice.toStringAsFixed(0)} $currency'),

                const SizedBox(height: 8),
                const Divider(thickness: 1.5, color: Color(0xFF0F766E)),
                const SizedBox(height: 6),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL RÉGLÉ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F766E))),
                    Text(
                      '${((receipt?['amount'] as num?)?.toDouble() ?? (planPrice + regFee)).toStringAsFixed(0)} $currency',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF0F766E)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Boutons d'action pour le reçu
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isGeneratingPdf ? null : () => _downloadOrPrintReceipt(s),
                        icon: _isGeneratingPdf
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(LucideIcons.fileDown, size: 16),
                        label: Text(_isGeneratingPdf ? 'Génération...' : 'Télécharger Reçu'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _shareReceiptWhatsApp,
                        icon: const Icon(LucideIcons.messageCircle, size: 16),
                        label: const Text('Reçu WhatsApp'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Bouton pour refaire une nouvelle inscription
        Center(
          child: TextButton.icon(
            onPressed: _resetAndStartNew,
            icon: const Icon(LucideIcons.plusCircle, size: 16),
            label: const Text('Faire une nouvelle inscription'),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineStep({
    required String stepNumber,
    required String title,
    required String subtitle,
    required bool isComplete,
    bool isActive = false,
    required String badgeText,
    required Color badgeColor,
    required Color badgeBg,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isComplete
                ? const Color(0xFF10B981)
                : (isActive ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9)),
            shape: BoxShape.circle,
            border: Border.all(
              color: isComplete
                  ? const Color(0xFF10B981)
                  : (isActive ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1)),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Icon(
              icon,
              size: 18,
              color: isComplete
                  ? Colors.white
                  : (isActive ? const Color(0xFFD97706) : const Color(0xFF94A3B8)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isComplete
                            ? const Color(0xFF0F766E)
                            : (isActive ? const Color(0xFF1E293B) : const Color(0xFF64748B)),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: badgeColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
        ],
      ),
    );
  }

  Widget _buildFormView(AppStrings s, String gymName, String? logoUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // En-tête avec nom et logo
        Center(
          child: Column(
            children: [
              if (logoUrl != null && logoUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    logoUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(LucideIcons.dumbbell, size: 48, color: Color(0xFF0F766E)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                gymName,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                s.text('portal_join_subtitle'),
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              // Badge de session unique et privée
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.shieldCheck, size: 14, color: Color(0xFF0F766E)),
                    const SizedBox(width: 6),
                    Text(
                      'Session individuelle : #$_sessionCode',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Sélecteur Type de Demande (Inscription vs Renouvellement)
        Center(
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'new_membership',
                label: Text(s.text('request_kind_new')),
                icon: const Icon(LucideIcons.userPlus, size: 16),
              ),
              ButtonSegment(
                value: 'renewal',
                label: Text(s.text('request_kind_renewal')),
                icon: const Icon(LucideIcons.refreshCw, size: 16),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (set) {
              final newKind = set.first;
              setState(() {
                _kind = newKind;
                if (newKind == 'renewal') {
                  _startDoorScanPolling();
                } else {
                  _doorScanTimer?.cancel();
                }
              });
              _saveDraft();
            },
          ),
        ),
        const SizedBox(height: 16),

        // Bannière brouillon restauré si l'utilisateur avait commencé à écrire
        if (_hasRestoredDraft) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.save, color: Color(0xFF2563EB), size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Brouillon restauré : vos informations ont été conservées sur cet appareil.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF1E40AF)),
                  ),
                ),
                TextButton(
                  onPressed: _clearDraft,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Effacer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_kind == 'renewal') ...[
          if (_identifiedMember != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.circleCheck, color: Color(0xFF16A34A), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Compte identifié : ${_identifiedMember!['first_name']} ${_identifiedMember!['last_name']}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF14532D)),
                        ),
                      ),
                      TextButton(
                        onPressed: _resetIdentifiedMember,
                        child: const Text('Changer', style: TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Formule antérieure : ${_identifiedMember!['current_plan_name'] ?? 'Inconnue'} · Statut : ${_identifiedMember!['status'] == 'active' ? "Actif (${_identifiedMember!['days_left']} jours restants)" : "Expiré (${_identifiedMember!['expiration_date'] ?? ''})"}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF166534)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Aucun frais d’inscription pour le renouvellement.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF93C5FD)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.fingerprint, color: Color(0xFF2563EB), size: 30),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'En attente de votre empreinte...',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E40AF), fontSize: 14),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Posez votre doigt sur le lecteur d’empreinte devant la porte du gym pour charger vos informations.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchPhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Ou entrez votre téléphone...',
                            prefixIcon: Icon(LucideIcons.phone, size: 16),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          onSubmitted: (_) => _searchMemberManual(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onPressed: _searchingMember ? null : _searchMemberManual,
                        child: _searchingMember
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Rechercher'),
                      ),
                    ],
                  ),
                  if (_searchError != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_searchError!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],

        if (_formError != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.alertCircle, color: Color(0xFFDC2626), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formError!,
                    style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Choix de la formule
        if (_plans.isNotEmpty) ...[
          Text(
            s.text('enrollment_plan_select'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _plans.map((p) {
              final id = p['id'] as String;
              final name = p['name'] as String? ?? '';
              final price = (p['price'] as num?)?.toDouble() ?? 0.0;
              final regFee = (p['registration_fee'] as num?)?.toDouble() ?? 0.0;
              final currency = p['currency'] as String? ?? 'HTG';
              final days = p['duration_days'] as int? ?? 30;
              final isSelected = _selectedPlanId == id;

              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() => _selectedPlanId = id);
                  _saveDraft();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFF0FDFA) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF0F766E) : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected ? LucideIcons.circleCheck : LucideIcons.circle,
                            size: 16,
                            color: isSelected ? const Color(0xFF0F766E) : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isSelected ? const Color(0xFF0F766E) : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$days jours · ${price.toStringAsFixed(0)} $currency/mois',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? const Color(0xFF115E59) : Colors.grey.shade600,
                        ),
                      ),
                      if (_kind == 'new_membership' && regFee > 0)
                        Text(
                          '+ ${regFee.toStringAsFixed(0)} $currency inscription',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Coordonnées du prospect
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _firstNameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: '${s.text('first_name')} *',
                  prefixIcon: const Icon(LucideIcons.user, size: 18),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _lastNameController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: '${s.text('last_name')} *',
                  prefixIcon: const Icon(LucideIcons.user, size: 18),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: '${s.text('whatsapp_number')} *',
            prefixIcon: const Icon(LucideIcons.messageCircle, color: Color(0xFF25D366), size: 18),
            hintText: '+509 3000 0000',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: '${s.text('email')} (${s.text('optional')})',
            prefixIcon: const Icon(LucideIcons.mail, size: 18),
            hintText: 'nom@gmail.com',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Objectif / Message (optionnel)',
            prefixIcon: Icon(LucideIcons.messageSquare, size: 18),
            hintText: 'Ex: Remise en forme, musculation, cours collectifs...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(LucideIcons.shield, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(
              'Vos données saisies restent enregistrées sur votre appareil en cas d’interruption.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 20),

        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _isSubmitting ? null : () => _submit(s),
            icon: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(LucideIcons.send, size: 18),
            label: Text(
              _isSubmitting
                  ? 'Envoi en cours...'
                  : (_kind == 'renewal'
                      ? 'Envoyer ma demande de renouvellement'
                      : s.text('portal_submit_button')),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}
