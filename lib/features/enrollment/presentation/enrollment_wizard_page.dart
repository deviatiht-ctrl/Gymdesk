import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../core/biometrics/biometric_service.dart';
import '../../../core/biometrics/biometric_models.dart';
import '../../../core/sync/sync_models.dart';
import '../../../l10n/app_strings.dart';
import '../../members/data/member_photo_codec.dart';
import '../../members/data/members_repository.dart';
import '../../members/domain/member.dart';
import '../../payments/data/receipt_pdf.dart';
import '../../payments/data/receipt_service.dart';
import '../../payments/domain/currency.dart';
import '../../payments/domain/payment.dart';
import '../../payments/presentation/collect_payment_dialog.dart';
import '../../payments/presentation/receipt_sheet.dart';
import '../../plans/data/plans_repository.dart';
import '../../plans/domain/plan.dart';
import '../../subscriptions/domain/gym_subscription.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../../../core/biometrics/access_agent_client.dart';
import '../../members/data/member_pin_service.dart';

class EnrollmentWizardPage extends ConsumerStatefulWidget {
  const EnrollmentWizardPage({
    super.key,
    this.initialFirstName,
    this.initialLastName,
    this.initialPhone,
    this.initialEmail,
    this.initialPlanId,
    this.portalRequestId,
  });

  final String? initialFirstName;
  final String? initialLastName;
  final String? initialPhone;
  final String? initialEmail;
  final String? initialPlanId;
  final String? portalRequestId;

  @override
  ConsumerState<EnrollmentWizardPage> createState() => _EnrollmentWizardPageState();
}

class _EnrollmentWizardPageState extends ConsumerState<EnrollmentWizardPage> {
  int _currentStep = 0;
  bool _quickMode = true;

  // Step 1: Idantite
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nifCinController = TextEditingController();
  final _addressController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _pinController = TextEditingController();
  String _sex = 'male';
  DateTime? _birthDate;
  Uint8List? _photoBytes;

  // Step 2: Abònman
  bool _isExistingMember = false;
  DateTime _startDate = dateOnly(DateTime.now());
  DateTime _endDate = subscriptionEnd(DateTime.now(), 30);
  GymPlan? _selectedPlan;
  List<GymPlan> _plans = [];
  bool _loadingPlans = true;

  // Frais d'inscription (Demande utilisateur & Phase 7)
  String _registrationFeeMode = 'separate'; // 'separate', 'included', 'waived'
  double _customRegistrationFee = 0.0;
  final _registrationFeeController = TextEditingController();

  double get _effectiveRegistrationFee {
    if (_isExistingMember) return 0.0;
    if (_registrationFeeMode == 'waived') return 0.0;
    if (_registrationFeeMode == 'included') return 0.0;
    return _customRegistrationFee > 0
        ? _customRegistrationFee
        : (_selectedPlan?.registrationFee ?? 0.0);
  }

  double _calculateTotalDue() {
    if (_selectedPlan == null) return 0.0;
    if (_isExistingMember) return _selectedPlan!.price;
    if (_registrationFeeMode == 'separate') {
      return _selectedPlan!.price + _effectiveRegistrationFee;
    }
    if (_registrationFeeMode == 'included') {
      return _selectedPlan!.registrationPrice;
    }
    return _selectedPlan!.price;
  }

  void _onSelectPlan(GymPlan plan) {
    setState(() {
      _selectedPlan = plan;
      _endDate = subscriptionEnd(_startDate, plan.durationDays);
      _customRegistrationFee = plan.registrationFee;
      _registrationFeeController.text = plan.registrationFee > 0
          ? plan.registrationFee.toStringAsFixed(0)
          : '';
      _paymentAmountController.text = _calculateTotalDue().toStringAsFixed(0);
    });
  }

  void _setRegistrationFeeMode(String mode) {
    setState(() {
      _registrationFeeMode = mode;
      _paymentAmountController.text = _calculateTotalDue().toStringAsFixed(0);
    });
  }

  String get _currency {
    final p = _selectedPlan?.currency;
    if (p != null && p.isNotEmpty) return p;
    final g = ref.read(appRuntimeProvider).session?.gym?['currency'] as String?;
    if (g != null && g.isNotEmpty) return g;
    return 'USD';
  }

  // Step 3: Peman
  String _paymentMethod = 'cash';
  String? _paidCurrency;
  double get _rate => gymExchangeRate(ref.read(appRuntimeProvider).session?.settings ?? const {});
  CashierMath get _cashier {
    final due = double.tryParse(_paymentAmountController.text.replaceAll(',', '.')) ?? 0;
    return CashierMath(currency: _currency, paidCurrency: _paidCurrency ?? _currency, rate: _rate, cashDue: due, tendered: double.tryParse(_paymentReceivedController.text.replaceAll(',', '.')));
  }

  final _paymentAmountController = TextEditingController();
  final _paymentReceivedController = TextEditingController();
  final _referenceController = TextEditingController();
  bool _paymentConfirmed = true;
  bool _keepChangeAsCredit = false;
  String _lastPaymentId = '';
  String _lastMemberNumber = '';
  double _lastAmount = 0;
  double _lastReceived = 0;
  double _lastCreditAdded = 0;
  double _lastRegFee = 0;
  double _lastPlanFee = 0;
  String? _lastPaymentReason;

  // Step 4: Anprent (2 Doigts + Konsantman)
  late final BiometricService _biometricService;
  late final MembersRepository _members;
  late final PlansRepository _plansRepo;

  int _selectedFingerIndex = 1; // 1 = Prensipal, 2 = Sekou
  String? _primaryTemplate;
  String? _backupTemplate;
  bool _consentGiven = false;
  bool _isCapturing = false;
  bool _skipFingerprintForNow = false;
  StreamSubscription<BiometricEvent>? _bioEventSub;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialFirstName != null) {
      _firstNameController.text = widget.initialFirstName!;
    }
    if (widget.initialLastName != null) {
      _lastNameController.text = widget.initialLastName!;
    }
    if (widget.initialPhone != null) {
      _phoneController.text = widget.initialPhone!;
      _whatsappController.text = widget.initialPhone!;
    }
    if (widget.initialEmail != null) {
      _emailController.text = widget.initialEmail!;
    }
    _biometricService = BiometricService();
    _bioEventSub = _biometricService.events.listen(_onAutoBiometricEvent);
    _biometricService.startCapture();
    final runtime = ref.read(appRuntimeProvider);
    _members = MembersRepository(runtime.client, runtime.database!, runtime.session!);
    _plansRepo = PlansRepository(runtime.database!, runtime.session!);
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final list = await _plansRepo.watch().first;
      if (mounted) {
        setState(() {
          _plans = list.where((p) => p.active && p.deletedAt == null).toList();
          if (_plans.isNotEmpty) {
            GymPlan initial = _plans.first;
            if (widget.initialPlanId != null) {
              final found = _plans.where((p) => p.id == widget.initialPlanId).firstOrNull;
              if (found != null) initial = found;
            }
            _onSelectPlan(initial);
          }
          _loadingPlans = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.camera, maxWidth: 800, maxHeight: 800);
      if (file != null) {
        final raw = await file.readAsBytes();
        final normalized = encodeMemberPhoto(raw);
        if (mounted) {
          setState(() => _photoBytes = normalized);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo error: $e')));
      }
    }
  }

  void _onAutoBiometricEvent(BiometricEvent event) {
    if (!mounted || _isCapturing || _isSaving || _skipFingerprintForNow) return;
    if (_selectedFingerIndex == 1 && _primaryTemplate != null) return;
    if (_selectedFingerIndex == 2 && _backupTemplate != null) return;

    if (event.type == 'fingerprint_captured' && event.template != null && event.template!.isNotEmpty) {
      _processAutoSample(event.template!);
    } else if (event.type == 'low_quality') {
      if (mounted) {
        setState(() => _errorMessage = 'Qualité trop basse. Posez le doigt bien à plat sur le lecteur.');
      }
    }
  }

  Future<void> _processAutoSample(String sample) async {
    final s = AppStrings.of(context);
    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });

    final runtime = ref.read(appRuntimeProvider);
    final db = runtime.database;
    if (db != null) {
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
        final dupName = '${dup.firstName} ${dup.lastName}';
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(LucideIcons.triangleAlert, color: Colors.orange, size: 36),
            title: Text(s.text('duplicate_fingerprint_alert')),
            content: Text('${s.text('duplicate_fingerprint_alert')}\n($dupName)'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('ok')))],
          ),
        );
        setState(() => _isCapturing = false);
        return;
      }
    }

    setState(() {
      if (_selectedFingerIndex == 1) {
        _primaryTemplate = sample;
      } else {
        _backupTemplate = sample;
      }
      _isCapturing = false;
    });

    if (widget.portalRequestId != null && _selectedFingerIndex == 1) {
      try {
        ref.read(appRuntimeProvider).client.from('portal_requests').update({
          'status': 'approved',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', widget.portalRequestId!);
      } catch (_) {}
    }
  }

  Future<void> _captureFingerprint(AppStrings s) async {
    if (!_consentGiven) {
      setState(() => _errorMessage = s.text('must_consent'));
      return;
    }
    setState(() {
      _errorMessage = null;
      _isCapturing = true;
    });

    try {
      final sample = await _biometricService.captureFingerprintSample(step: _selectedFingerIndex);

      // Verifikasyon 1:N kont doublon nan baz lokal (algorit SDK a)
      final runtime = ref.read(appRuntimeProvider);
      final db = runtime.database;
      if (db != null) {
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
          final dupName = '${dup.firstName} ${dup.lastName}';
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(LucideIcons.triangleAlert, color: Colors.orange, size: 36),
              title: Text(s.text('duplicate_fingerprint_alert')),
              content: Text('${s.text('duplicate_fingerprint_alert')}\n($dupName)'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('ok')))],
            ),
          );
          setState(() => _isCapturing = false);
          return;
        }
      }

      setState(() {
        if (_selectedFingerIndex == 1) {
          _primaryTemplate = sample;
        } else {
          _backupTemplate = sample;
        }
        _isCapturing = false;
      });

      if (widget.portalRequestId != null && _selectedFingerIndex == 1) {
        try {
          ref.read(appRuntimeProvider).client.from('portal_requests').update({
            'status': 'approved',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', widget.portalRequestId!);
        } catch (_) {}
      }
    } catch (e) {
      setState(() {
        _isCapturing = false;
        _errorMessage = '${s.text('finger_capture_error')} ($e)';
      });
    }
  }

  bool _validateStep1(AppStrings s) {
    setState(() => _errorMessage = null);
    final fn = _firstNameController.text.trim();
    final ln = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _whatsappController.text.trim().isNotEmpty ? _whatsappController.text.trim() : _phoneController.text.trim();

    // Enskripsyon rapid: non, siyati, telefòn. Imèl ak NIF/CIN opsyonèl.
    if (fn.length < 2 || ln.length < 2 || phone.replaceAll(RegExp(r'\D'), '').length < 8) {
      setState(() => _errorMessage = s.text('fill_required_fields'));
      return false;
    }
    if (email.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _errorMessage = s.text('invalid_email'));
      return false;
    }
    return true;
  }

  bool _validateStep2(AppStrings s) {
    setState(() => _errorMessage = null);
    if (_selectedPlan == null) {
      setState(() => _errorMessage = s.text('select_plan_required'));
      return false;
    }
    return true;
  }

  bool _validateStep3(AppStrings s) {
    setState(() => _errorMessage = null);
    final amt = double.tryParse(_paymentAmountController.text) ?? 0;
    if (amt <= 0 && !_isExistingMember) {
      setState(() => _errorMessage = s.text('select_payment_required'));
      return false;
    }
    if (!_paymentConfirmed) {
      setState(() => _errorMessage = s.text('select_payment_required'));
      return false;
    }
    if (!_cashier.enough) {
      setState(() => _errorMessage = s.text('amount_insufficient'));
      return false;
    }
    return true;
  }

  bool _validateQuickForm(AppStrings s) {
    setState(() => _errorMessage = null);
    final fn = _firstNameController.text.trim();
    final ln = _lastNameController.text.trim();
    final phone = _whatsappController.text.trim().isNotEmpty ? _whatsappController.text.trim() : _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (fn.length < 2 || ln.length < 2 || phone.replaceAll(RegExp(r'\D'), '').length < 8) {
      setState(() => _errorMessage = s.text('fill_required_fields'));
      return false;
    }
    if (email.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _errorMessage = s.text('invalid_email'));
      return false;
    }
    if (_selectedPlan == null) {
      setState(() => _errorMessage = s.text('select_plan_required'));
      return false;
    }
    final amt = double.tryParse(_paymentAmountController.text) ?? 0;
    if (amt <= 0 && !_isExistingMember) {
      setState(() => _errorMessage = s.text('select_payment_required'));
      return false;
    }
    if (!_paymentConfirmed) {
      setState(() => _errorMessage = s.text('select_payment_required'));
      return false;
    }
    if (!_cashier.enough) {
      setState(() => _errorMessage = s.text('amount_insufficient'));
      return false;
    }
    if (_primaryTemplate == null && _pinController.text.trim().isEmpty) {
      _skipFingerprintForNow = true;
    }
    return true;
  }

  Future<void> _submitEnrollment(AppStrings s) async {
    final runtime = ref.read(appRuntimeProvider);

    final hasPin = _pinController.text.trim().isNotEmpty;
    final isFr = s.locale.languageCode == 'fr';
    if (_primaryTemplate == null && !_skipFingerprintForNow && !hasPin) {
      if (_quickMode) {
        _skipFingerprintForNow = true;
      } else {
        setState(
          () => _errorMessage = isFr
              ? 'Veuillez enregistrer une empreinte, saisir un code PIN, ou cocher "Salle sans empreinte".'
              : 'Tanpri anrejistre yon anprent, mete yon kòd PIN, oswa koche "Sal san anprent".',
        );
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final plan = _selectedPlan!;
      final startOnly = dateOnly(_startDate);
      final endDate = dateOnly(_endDate.isBefore(startOnly) ? subscriptionEnd(startOnly, plan.durationDays) : _endDate);
      final amt = double.tryParse(_paymentAmountController.text) ?? plan.price;
      final cashier = _cashier;
      final received = cashier.receivedInBase;
      final creditAdded = _keepChangeAsCredit && received > amt ? received - amt : 0.0;
      final paymentId = const Uuid().v4();

      final draft = MemberRegistration(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        sex: _sex,
        birthDate: _birthDate,
        phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : _whatsappController.text.trim(),
        whatsapp: _whatsappController.text.trim(),
        email: _emailController.text.trim(),
        address: _addressController.text.trim(),
        nif: _nifCinController.text.trim().length == 10 ? _nifCinController.text.trim() : '',
        cin: _nifCinController.text.trim().length != 10 ? _nifCinController.text.trim() : '',
        emergencyName: _emergencyNameController.text.trim(),
        emergencyPhone: _emergencyPhoneController.text.trim(),
        guardianName: '',
        notes: _isExistingMember ? 'Repris ancien système' : '',
        photo: _photoBytes,
      );

      final effectiveFee = _effectiveRegistrationFee;
      final planFee = (amt - effectiveFee).clamp(0.0, double.infinity).toDouble();
      final reason = effectiveFee > 0
          ? 'Inscription + 1er mois'
          : (_registrationFeeMode == 'included'
              ? 'Inscription (1er mois inclus)'
              : 'Inscription');

      final result = await _members.register(
        draft,
        subscription: SubscriptionCommand(
          planId: plan.id,
          startDate: _startDate,
          endDate: endDate,
          price: _isExistingMember ? plan.price : (planFee > 0 ? planFee : plan.registrationPrice),
          status: 'active',
        ),
        payment: PaymentCommand(
          id: paymentId,
          memberId: '',
          subscriptionId: '',
          amount: amt,
          currency: plan.currency.isNotEmpty ? plan.currency : _currency,
          method: _paymentMethod,
          reference: _referenceController.text.trim(),
          receivedAmount: received,
          keepChangeAsCredit: _keepChangeAsCredit,
          paidCurrency: cashier.paidCurrency,
          exchangeRate: _rate > 0 ? _rate : null,
          tenderedAmount: cashier.given,
          registrationFee: effectiveFee,
          planFee: planFee,
          paymentReason: reason,
          notes: _paymentConfirmed
              ? '$reason · Frais: ${effectiveFee.toStringAsFixed(0)} $_currency, Plan: ${planFee.toStringAsFixed(0)} $_currency'
              : '',
        ),
        changedAt: now,
      );

      if (widget.portalRequestId != null) {
        try {
          await runtime.client.from('portal_requests').update({
            'status': 'completed',
            'member_id': result.memberId,
            'updated_at': now.toUtc().toIso8601String(),
          }).eq('id', widget.portalRequestId!);
        } catch (_) {}
      }
      _lastPaymentId = paymentId;
      _lastAmount = amt;
      _lastReceived = received;
      _lastCreditAdded = creditAdded;
      _lastMemberNumber = result.memberNumber;
      _lastRegFee = effectiveFee;
      _lastPlanFee = planFee;
      _lastPaymentReason = reason;

      if (_primaryTemplate != null && runtime.database != null) {
        await runtime.database!.save(SyncEntity.members, {
          'id': result.memberId,
          'gym_id': runtime.session!.gymId,
          'fingerprint_registered': true,
          'fingerprint_template': _primaryTemplate,
          'fingerprint_backup_template': _backupTemplate,
          'fingerprint_enrolled_at': now.toUtc().toIso8601String(),
        }, changedAt: now);
      }

      if (hasPin && runtime.database != null && runtime.session?.gymId != null) {
        final pinService = MemberPinService(runtime.database!);
        final pinData = await pinService.createPinData(result.memberId, runtime.session!.gymId!, _pinController.text.trim());
        await pinService.savePinData(pinData);
      }

      unawaited(runtime.sync?.synchronize());

      final fullName = '${draft.firstName} ${draft.lastName}'.trim();

      // Synchronisation immédiate du membre sur le terminal IP mural Suprema (BioEntry W2)
      if (_primaryTemplate != null) {
        final agentClient = AccessAgentClient();
        final tmpls = [_primaryTemplate!];
        if (_backupTemplate != null) tmpls.add(_backupTemplate!);
        unawaited(agentClient.syncTerminalMember(userId: result.memberId, name: fullName, startDate: _startDate, endDate: endDate, templates: tmpls).catchError((_) => false));
      }

      final email = draft.email.trim();

      // Resi peman an voye OTOMATIK pa email (silansye si offline).
      final gym = runtime.session?.gym ?? const <String, dynamic>{};
      final gymId = runtime.session?.gymId;
      if (gymId != null && _lastPaymentId.isNotEmpty) {
        unawaited(ReceiptService(runtime.client, gymId).autoEnqueue(_receiptData(fullName, plan.name, endDate, gym), gym['logo_url'] as String?));
      }

      if (mounted) {
        _showSuccessDialog(s, result.memberId, fullName, plan.name, endDate, email);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = '${s.text('error')}: $e';
        });
      }
    }
  }

  /// Resi PDF peman enskripsyon an (download / print / email / WhatsApp).
  Future<void> _openReceipt(String fullName, String planName, String memberId, DateTime endDate) async {
    final runtime = ref.read(appRuntimeProvider);
    final gym = runtime.session?.gym ?? const <String, dynamic>{};
    if (!mounted) return;
    await showReceiptSheet(context, ref, _receiptData(fullName, planName, endDate, gym));
  }

  ReceiptData _receiptData(String fullName, String planName, DateTime endDate, Map<String, dynamic> gym) => ReceiptData(
    paymentId: _lastPaymentId,
    memberName: fullName,
    memberNumber: _lastMemberNumber,
    planName: planName,
    amount: _lastAmount,
    currency: _currency,
    method: _paymentMethod,
    paidAt: DateTime.now().toUtc(),
    gymName: gym['name'] as String? ?? 'GymDesk',
    accentColor: gym['accent_color'] as String? ?? '#0F766E',
    periodStart: _startDate,
    periodEnd: endDate,
    receivedAmount: _lastReceived,
    creditAdded: _lastCreditAdded,
    creditBalance: _lastCreditAdded,
    memberEmail: _emailController.text.trim(),
    memberPhone: _whatsappController.text.trim().isNotEmpty ? _whatsappController.text.trim() : _phoneController.text.trim(),
    gymAddress: gym['address'] as String?,
    gymPhone: gym['phone'] as String?,
    gymEmail: gym['email'] as String?,
    reference: _referenceController.text.trim(),
    registrationFee: _lastRegFee,
    planFee: _lastPlanFee,
    paymentReason: _lastPaymentReason,
  );

  void _showSuccessDialog(AppStrings s, String memberId, String fullName, String planName, DateTime endDate, String email) {
    final gymName = ref.read(appRuntimeProvider).session?.name ?? 'GymDesk';
    final wa = _whatsappController.text.trim();
    final isFr = s.locale.languageCode == 'fr';
    final isEn = s.locale.languageCode == 'en';
    final startStr = ymd(_startDate);
    final endStr = ymd(endDate);

    final waMessageText = isFr
        ? 'Bonjour $fullName ! Bienvenue chez $gymName.\n'
              'Votre inscription est confirmée pour la formule : $planName.\n'
              'Période : du $startStr au $endStr.\n'
              '⚠️ RAPPEL IMPORTANT : Votre abonnement débutera officiellement le $startStr. Merci de vous présenter à la salle à cette date exacte, car c\'est à ce moment précis que votre abonnement commencera à être décompté.\n'
              'Votre empreinte sera prête pour l\'accès.\n'
              'Merci pour votre confiance !'
        : isEn
        ? 'Hello $fullName! Welcome to $gymName.\n'
              'Your membership is confirmed for: $planName.\n'
              'Period: from $startStr to $endStr.\n'
              '⚠️ IMPORTANT REMINDER: Your membership officially begins on $startStr. Please make sure to come to the gym on this exact date, as your access begins counting down from that day.\n'
              'Your fingerprint access will be ready.\n'
              'Thank you for choosing us!'
        : 'Bonjou $fullName! Byenvini nan $gymName.\n'
              'Enskripsyon ou konfime sou fòmil : $planName.\n'
              'Peryòd : soti $startStr rive $endStr.\n'
              '⚠️ RAPÈL ENPÒTAN : Abònman w lan ap kòmanse ofisyèlman nan dat $startStr la. Tanpri prezante nan sal la egzakteman jou sa a, paske se jou sa a menm abònman w lan ap kòmanse konte.\n'
              'Anprent ou ap pare pou ouvri baryè a.\n'
              'Mèsi pou konfyans ou!';

    final waUrl = 'https://wa.me/${wa.replaceAll('+', '').replaceAll(' ', '')}?text=${Uri.encodeComponent(waMessageText)}';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(LucideIcons.circleCheck, color: Color(0xFF059669), size: 28),
            const SizedBox(width: 10),
            Text(s.text('enrollment_confirmed')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$fullName : ${s.text('member_enrolled_success')}'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF99F6E4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.calendarClock, size: 16, color: Color(0xFF0F766E)),
                      const SizedBox(width: 6),
                      Text(
                        '${s.text('subscription_period')}: $startStr → $endStr',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E), fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isFr ? 'Rappel : Le membre doit se présenter le $startStr (date de début de son accès).' : 'Rapèl : Manm nan dwe vini jou $startStr la (se lè sa a abònman an kòmanse).',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF134E4A)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (email.contains('@'))
              Text(
                '${s.text('email_after_sync')} ($email)',
                style: const TextStyle(color: Color(0xFF047857), fontSize: 13, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
              onPressed: () => launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication),
              icon: const Icon(LucideIcons.messageCircle, size: 18),
              label: Text(s.text('send_whatsapp_btn')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openReceipt(fullName, planName, memberId, endDate);
              },
              icon: const Icon(LucideIcons.receipt, size: 18),
              label: Text(s.text('view_receipt')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/members/$memberId');
            },
            child: Text(s.text('go_to_member_profile')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/members');
            },
            child: Text(s.text('finish_btn')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _whatsappController.dispose();
    _phoneController.dispose();
    _nifCinController.dispose();
    _addressController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _paymentAmountController.dispose();
    _paymentReceivedController.dispose();
    _referenceController.dispose();
    _registrationFeeController.dispose();
    _pinController.dispose();
    _bioEventSub?.cancel();
    _biometricService.stopCapture();
    _biometricService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_quickMode ? s.text('enrollment_mode_quick') : s.text('enroll_wizard_title')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  icon: const Icon(LucideIcons.zap, size: 16),
                  label: Text(s.text('enrollment_mode_quick')),
                ),
                ButtonSegment(
                  value: false,
                  icon: const Icon(LucideIcons.listOrdered, size: 16),
                  label: Text(s.text('enrollment_mode_wizard')),
                ),
              ],
              selected: {_quickMode},
              onSelectionChanged: (set) => setState(() => _quickMode = set.first),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loadingPlans
            ? const Center(child: CircularProgressIndicator())
            : _quickMode
                ? _buildQuickForm(s)
                : Stepper(
                currentStep: _currentStep,
                type: StepperType.horizontal,
                onStepTapped: (step) {
                  if (step < _currentStep) setState(() => _currentStep = step);
                },
                controlsBuilder: (context, details) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Row(
                      children: [
                        if (_currentStep < 3)
                          ElevatedButton.icon(
                            onPressed: () {
                              if (_currentStep == 0 && _validateStep1(s)) {
                                setState(() => _currentStep = 1);
                              } else if (_currentStep == 1 && _validateStep2(s)) {
                                setState(() => _currentStep = 2);
                              } else if (_currentStep == 2 && _validateStep3(s)) {
                                setState(() => _currentStep = 3);
                              }
                            },
                            icon: const Icon(LucideIcons.arrowRight, size: 16),
                            label: Text(s.text('continue_btn')),
                          )
                        else
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                            onPressed: _isSaving ? null : () => _submitEnrollment(s),
                            icon: _isSaving
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(LucideIcons.checkCheck, size: 18),
                            label: Text(_isSaving ? s.text('saving') : s.text('submit_enrollment')),
                          ),
                        const SizedBox(width: 12),
                        if (_currentStep > 0) OutlinedButton(onPressed: () => setState(() => _currentStep--), child: Text(s.text('back_btn'))),
                      ],
                    ),
                  );
                },
                steps: [
                  Step(title: Text(s.text('step_identity')), isActive: _currentStep >= 0, state: _currentStep > 0 ? StepState.complete : StepState.indexed, content: _buildStep1(s)),
                  Step(title: Text(s.text('step_plan')), isActive: _currentStep >= 1, state: _currentStep > 1 ? StepState.complete : StepState.indexed, content: _buildStep2(s)),
                  Step(title: Text(s.text('step_payment')), isActive: _currentStep >= 2, state: _currentStep > 2 ? StepState.complete : StepState.indexed, content: _buildStep3(s)),
                  Step(title: Text(s.text('step_biometrics')), isActive: _currentStep >= 3, state: _primaryTemplate != null ? StepState.complete : StepState.indexed, content: _buildStep4(s)),
                ],
              ),
      ),
    );
  }

  Widget _buildQuickForm(AppStrings s) {
    final cashier = _cashier;
    final isFr = s.locale.languageCode == 'fr';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) _buildErrorBanner(),

              // SECTION 1: IDENTITE PRINCIPALE
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.user, color: Color(0xFF0F766E), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            s.text('step_identity'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _whatsappController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: '${s.text('whatsapp_number')} *',
                                prefixIcon: const Icon(LucideIcons.messageCircle, color: Color(0xFF25D366), size: 18),
                                border: const OutlineInputBorder(),
                                hintText: '+509 3000 0000',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: '${s.text('email')} (${s.text('optional')})',
                                prefixIcon: const Icon(LucideIcons.mail, size: 18),
                                border: const OutlineInputBorder(),
                                hintText: 'nom@gmail.com',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // SECTION 2: FORMULE & ABONNEMENT
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.calendarDays, color: Color(0xFF0F766E), size: 20),
                              const SizedBox(width: 8),
                              Text(
                                s.text('enrollment_plan_select'),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(LucideIcons.calendar, size: 15),
                                label: Text('${isFr ? 'Début' : 'Kòmansman'}: ${ymd(_startDate)}'),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _startDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _startDate = dateOnly(picked);
                                      _endDate = subscriptionEnd(_startDate, _selectedPlan?.durationDays ?? 30);
                                    });
                                  }
                                },
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(LucideIcons.calendarCheck, size: 15),
                                label: Text('${isFr ? 'Fin' : 'Fen'}: ${ymd(_endDate)}'),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
                                    firstDate: _startDate,
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) {
                                    setState(() => _endDate = dateOnly(picked));
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Existing member toggle
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.text('existing_member_no_fee'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        value: _isExistingMember,
                        onChanged: (val) {
                          setState(() {
                            _isExistingMember = val ?? false;
                            _paymentAmountController.text = _calculateTotalDue().toStringAsFixed(0);
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      // Plans tiles
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: _plans.map((plan) {
                          final isSelected = _selectedPlan?.id == plan.id;
                          final price = _isExistingMember ? plan.price : plan.registrationPrice;
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _onSelectPlan(plan),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFF0FDFA) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF0F766E) : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSelected ? LucideIcons.circleCheck : LucideIcons.circle,
                                    size: 18,
                                    color: isSelected ? const Color(0xFF0F766E) : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        plan.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? const Color(0xFF0F766E) : Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        '${plan.durationDays} ${s.text('days')} · ${price.toStringAsFixed(0)} ${plan.currency}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isSelected ? const Color(0xFF115E59) : Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _buildRegistrationFeeSection(s),
              const SizedBox(height: 16),

              // SECTION 3: PAIEMENT & CAISSE
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.banknote, color: Color(0xFF0F766E), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            s.text('enrollment_cashier_section'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              value: _paymentMethod,
                              decoration: InputDecoration(labelText: s.text('payment_method'), border: const OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'cash', child: Text('Espèces / Cash')),
                                DropdownMenuItem(value: 'moncash', child: Text('MonCash')),
                                DropdownMenuItem(value: 'natcash', child: Text('NatCash')),
                                DropdownMenuItem(value: 'bank', child: Text('Virement')),
                                DropdownMenuItem(value: 'card', child: Text('Carte')),
                                DropdownMenuItem(value: 'other', child: Text('Autre')),
                              ],
                              onChanged: (val) => setState(() => _paymentMethod = val ?? 'cash'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _paymentAmountController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: '${s.text('amount_due')} ($_currency) *',
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _paymentReceivedController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: '${s.text('amount_received')} (${cashier.paidCurrency})',
                                border: const OutlineInputBorder(),
                                hintText: cashier.dueInPaid.toStringAsFixed(2),
                                errorText: cashier.enough ? null : s.text('amount_insufficient'),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      if (_rate > 0) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(s.text('paid_in_currency')),
                            SegmentedButton<String>(
                              segments: [for (final c in supportedCurrencies) ButtonSegment(value: c, label: Text(c))],
                              selected: {cashier.paidCurrency},
                              onSelectionChanged: (v) => setState(() {
                                _paidCurrency = v.first;
                                _paymentReceivedController.clear();
                              }),
                            ),
                            Text(
                              '${s.text('amount_due')}: ${money(cashier.dueInPaid, cashier.paidCurrency)}'
                              '  ·  1 USD = ${_rate.toStringAsFixed(2)} HTG',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                      if (cashier.changeInPaid > 0.004) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${s.text('change_due')}: ${money(cashier.changeInPaid, cashier.paidCurrency)}',
                                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF047857), fontSize: 15),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: _keepChangeAsCredit,
                                    onChanged: (v) => setState(() => _keepChangeAsCredit = v == true),
                                  ),
                                  Text(s.text('keep_change_as_credit'), style: const TextStyle(fontSize: 13)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.text('payment_collected_confirmed'), style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          isFr ? 'Le montant a bien été encaissé et vérifié' : 'Kòb la fin konte epi verifye nan kès la',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                        value: _paymentConfirmed,
                        onChanged: (v) => setState(() => _paymentConfirmed = v ?? true),
                        activeColor: const Color(0xFF059669),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // SECTION 4: OPTIONS AVANCEES (Replié par défaut)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  backgroundColor: Colors.white,
                  collapsedBackgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  leading: const Icon(LucideIcons.listPlus, color: Color(0xFF0F766E)),
                  title: Text(
                    s.text('enrollment_optional_section'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    s.text('enrollment_fingerprint_quick_hint'),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          const SizedBox(height: 12),
                          // Photo + Sexe + NIF
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: _pickPhoto,
                                child: Container(
                                  width: 90,
                                  height: 105,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: _photoBytes != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.memory(_photoBytes!, fit: BoxFit.cover),
                                        )
                                      : Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(LucideIcons.camera, size: 28, color: Colors.grey),
                                            const SizedBox(height: 4),
                                            Text(s.text('take_photo'), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: _sex,
                                            decoration: InputDecoration(labelText: s.text('sex'), border: const OutlineInputBorder()),
                                            items: [
                                              DropdownMenuItem(value: 'male', child: Text(s.text('male'))),
                                              DropdownMenuItem(value: 'female', child: Text(s.text('female'))),
                                            ],
                                            onChanged: (val) => setState(() => _sex = val ?? 'male'),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: TextField(
                                            controller: _nifCinController,
                                            decoration: InputDecoration(
                                              labelText: s.text('nif_cin'),
                                              prefixIcon: const Icon(LucideIcons.idCard, size: 18),
                                              border: const OutlineInputBorder(),
                                              hintText: '000-000-000-0',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _addressController,
                                      decoration: InputDecoration(
                                        labelText: s.text('address'),
                                        prefixIcon: const Icon(LucideIcons.mapPin, size: 18),
                                        border: const OutlineInputBorder(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Contact d'urgence
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _emergencyNameController,
                                  decoration: InputDecoration(
                                    labelText: isFr ? 'Contact d\'urgence (nom)' : 'Moun pou kontakte an ijans',
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _emergencyPhoneController,
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    labelText: isFr ? 'Téléphone d\'urgence' : 'Telefòn ijans',
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // PIN & Empreinte
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _pinController,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  decoration: InputDecoration(
                                    labelText: isFr ? 'Code PIN d\'accès (4 à 6 chiffres)' : 'Kòd PIN pou antre',
                                    prefixIcon: const Icon(LucideIcons.lock, size: 18),
                                    border: const OutlineInputBorder(),
                                    counterText: '',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    side: BorderSide(
                                      color: _primaryTemplate != null ? const Color(0xFF059669) : const Color(0xFF0F766E),
                                    ),
                                  ),
                                  onPressed: _isCapturing
                                      ? null
                                      : () async {
                                          _consentGiven = true;
                                          await _captureFingerprint(s);
                                        },
                                  icon: _isCapturing
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                      : Icon(
                                          _primaryTemplate != null ? LucideIcons.circleCheck : LucideIcons.fingerprint,
                                          color: _primaryTemplate != null ? const Color(0xFF059669) : const Color(0xFF0F766E),
                                        ),
                                  label: Text(
                                    _primaryTemplate != null
                                        ? (isFr ? 'Empreinte enregistrée' : 'Anprent anrejistre')
                                        : (_isCapturing ? s.text('finger_capturing') : (isFr ? 'Scanner empreinte (USB)' : 'Skane anprent (USB)')),
                                    style: TextStyle(
                                      color: _primaryTemplate != null ? const Color(0xFF059669) : const Color(0xFF0F766E),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // BOUTON ACTION PRINCIPAL
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isSaving
                      ? null
                      : () {
                          if (_validateQuickForm(s)) {
                            _submitEnrollment(s);
                          }
                        },
                  icon: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.checkCheck, size: 22),
                  label: Text(
                    _isSaving ? s.text('saving') : s.text('enroll_and_collect'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegistrationFeeSection(AppStrings s) {
    if (_isExistingMember) return const SizedBox.shrink();

    final isFr = s.locale.languageCode == 'fr';
    final regFee = _effectiveRegistrationFee;
    final planPrice = _selectedPlan?.price ?? 0.0;
    final total = _calculateTotalDue();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.tag, color: Color(0xFF0F766E), size: 20),
                const SizedBox(width: 8),
                Text(
                  s.text('registration_fee'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'separate',
                  label: Text(s.text('reg_fee_separate')),
                  icon: const Icon(LucideIcons.plusCircle, size: 16),
                ),
                ButtonSegment(
                  value: 'included',
                  label: Text(s.text('reg_fee_included')),
                  icon: const Icon(LucideIcons.checkCircle, size: 16),
                ),
                ButtonSegment(
                  value: 'waived',
                  label: Text(s.text('reg_fee_waived')),
                  icon: const Icon(LucideIcons.gift, size: 16),
                ),
              ],
              selected: {_registrationFeeMode},
              onSelectionChanged: (set) => _setRegistrationFeeMode(set.first),
            ),
            if (_registrationFeeMode == 'separate') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _registrationFeeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '${s.text('registration_fee_amount')} ($_currency)',
                        prefixIcon: const Icon(LucideIcons.dollarSign, size: 18),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setState(() {
                          _customRegistrationFee = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
                          _paymentAmountController.text = _calculateTotalDue().toStringAsFixed(0);
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF99F6E4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _registrationFeeMode == 'separate'
                            ? '${isFr ? 'Frais' : 'Frè'}: ${regFee.toStringAsFixed(0)} $_currency + ${isFr ? '1er mois' : '1ye mwa'}: ${planPrice.toStringAsFixed(0)} $_currency'
                            : _registrationFeeMode == 'included'
                                ? (isFr ? 'Frais d’adhésion inclus dans le 1er mois' : 'Frè enskripsyon ladan l nan 1ye mwa a')
                                : (isFr ? 'Frais d’inscription offerts (0 $_currency)' : 'Frè enskripsyon gratis (0 $_currency)'),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF134E4A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.text('amount_due')}: ${total.toStringAsFixed(0)} $_currency',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F766E)),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${total.toStringAsFixed(0)} $_currency',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) _buildErrorBanner(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                width: 110,
                height: 130,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _photoBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_photoBytes!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.camera, size: 32, color: Colors.grey),
                          const SizedBox(height: 6),
                          Text(s.text('take_photo'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  TextField(
                    controller: _firstNameController,
                    decoration: InputDecoration(labelText: '${s.text('first_name')} *', border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lastNameController,
                    decoration: InputDecoration(labelText: '${s.text('last_name')} *', border: const OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _whatsappController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: s.text('whatsapp_number'),
                  prefixIcon: const Icon(LucideIcons.messageCircle, color: Color(0xFF25D366)),
                  border: const OutlineInputBorder(),
                  hintText: '+509 3000 0000',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: '${s.text('email')} (${s.text('optional')})',
                  prefixIcon: const Icon(LucideIcons.mail),
                  border: const OutlineInputBorder(),
                  hintText: 'member@gmail.com',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.listPlus),
            title: Text('${s.text('more_info')} (${s.text('optional')})'),
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nifCinController,
                      decoration: InputDecoration(labelText: s.text('nif_cin'), prefixIcon: const Icon(LucideIcons.idCard), border: const OutlineInputBorder(), hintText: '000-000-000-0'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _sex,
                      decoration: InputDecoration(labelText: s.text('sex'), border: const OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: 'male', child: Text(s.text('male'))),
                        DropdownMenuItem(value: 'female', child: Text(s.text('female'))),
                      ],
                      onChanged: (val) => setState(() => _sex = val ?? 'male'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _addressController,
                decoration: InputDecoration(labelText: s.text('address'), prefixIcon: const Icon(LucideIcons.mapPin), border: const OutlineInputBorder()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep2(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) _buildErrorBanner(),
        Card(
          elevation: 0,
          color: const Color(0xFFF0FDFA),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF99F6E4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.calendarDays, color: Color(0xFF0F766E), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      s.text('start_date_exact'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F766E)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(s.text('start_date_hint'), style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                ListTile(
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  leading: const Icon(LucideIcons.calendar, color: Color(0xFF0F766E)),
                  title: Text('${ymd(_startDate)} → ${ymd(_endDate)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text(
                    '${s.text('subscription_period')} (${dateOnly(_endDate).difference(dateOnly(_startDate)).inDays} ${s.text('days')})',
                    style: const TextStyle(color: Color(0xFF0F766E), fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0F766E),
                          side: const BorderSide(color: Color(0xFF0F766E)),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _startDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() {
                              _startDate = dateOnly(picked);
                              _endDate = subscriptionEnd(_startDate, _selectedPlan?.durationDays ?? 30);
                            });
                          }
                        },
                        icon: const Icon(LucideIcons.calendar, size: 16),
                        label: Text(s.text('start_date')),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0F766E),
                          side: const BorderSide(color: Color(0xFF0F766E)),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
                            firstDate: _startDate,
                            lastDate: DateTime.now().add(const Duration(days: 730)),
                          );
                          if (picked != null) {
                            setState(() => _endDate = dateOnly(picked));
                          }
                        },
                        icon: const Icon(LucideIcons.calendarCheck, size: 16),
                        label: Text(s.text('end_date')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: _isExistingMember ? const Color(0xFFEFF6FF) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _isExistingMember ? Colors.blue : Colors.grey.shade300),
          ),
          child: SwitchListTile(
            title: Text(s.text('existing_member_no_fee'), style: const TextStyle(fontWeight: FontWeight.bold)),
            value: _isExistingMember,
            onChanged: (val) {
              setState(() {
                _isExistingMember = val;
                _paymentAmountController.text = _calculateTotalDue().toStringAsFixed(0);
              });
            },
          ),
        ),
        const SizedBox(height: 16),
        Text(s.text('plans'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        ..._plans.map((plan) {
          final isSelected = _selectedPlan?.id == plan.id;
          final effectivePrice = _isExistingMember ? plan.price : plan.registrationPrice;
          return Card(
            elevation: isSelected ? 3 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: isSelected ? const Color(0xFF0F766E) : Colors.transparent, width: 2),
            ),
            child: ListTile(
              onTap: () => _onSelectPlan(plan),
              leading: Icon(isSelected ? LucideIcons.checkCircle2 : LucideIcons.circle, color: isSelected ? const Color(0xFF0F766E) : Colors.grey),
              title: Text(plan.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                plan.enrollmentPrice != null && !_isExistingMember
                    ? '${plan.durationDays} ${s.text('days')} · (Renouvèlman: ${plan.price.toStringAsFixed(0)} ${plan.currency})'
                    : '${plan.durationDays} ${s.text('days')}',
              ),
              trailing: Text(
                '${effectivePrice.toStringAsFixed(0)} ${plan.currency}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        _buildRegistrationFeeSection(s),
      ],
    );
  }

  Widget _buildStep3(AppStrings s) {
    final isFr = s.locale.languageCode == 'fr';
    final totalDue = _calculateTotalDue();
    final regFee = _effectiveRegistrationFee;
    final planPrice = _selectedPlan?.price ?? 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) _buildErrorBanner(),
        Card(
          color: const Color(0xFFF8FAFC),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.text('plans')}: ${_selectedPlan?.name ?? ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (!_isExistingMember && regFee > 0)
                  Text(
                    '${isFr ? 'Frais inscription' : 'Frè enskripsyon'}: ${regFee.toStringAsFixed(0)} $_currency + ${isFr ? 'Abonnement' : 'Abònman'}: ${planPrice.toStringAsFixed(0)} $_currency = ${totalDue.toStringAsFixed(0)} $_currency',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F766E), fontSize: 13),
                  )
                else
                  Text(
                    '${s.text('amount_due')}: ${totalDue.toStringAsFixed(0)} $_currency',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F766E), fontSize: 13),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(LucideIcons.calendarClock, size: 16, color: Color(0xFF0F766E)),
                    const SizedBox(width: 6),
                    Text(
                      '${s.text('subscription_period')}: ${ymd(_startDate)} → ${ymd(_endDate)}',
                      style: const TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: InputDecoration(labelText: s.text('payment_method'), border: const OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Espèces / Cash')),
                  DropdownMenuItem(value: 'moncash', child: Text('MonCash')),
                  DropdownMenuItem(value: 'natcash', child: Text('NatCash')),
                  DropdownMenuItem(value: 'bank', child: Text('Virement Bancaire')),
                  DropdownMenuItem(value: 'card', child: Text('Carte de Crédit / Débit')),
                  DropdownMenuItem(value: 'other', child: Text('Autre')),
                ],
                onChanged: (val) => setState(() => _paymentMethod = val ?? 'cash'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _paymentAmountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: '${s.text('amount_paid')} ($_currency) *', border: const OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _paymentReceivedController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '${s.text('amount_received')} (${_cashier.paidCurrency})',
                  border: const OutlineInputBorder(),
                  hintText: _cashier.dueInPaid.toStringAsFixed(2),
                  errorText: _cashier.enough ? null : s.text('amount_insufficient'),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        if (_rate > 0) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(s.text('paid_in_currency')),
              SegmentedButton<String>(
                segments: [for (final c in supportedCurrencies) ButtonSegment(value: c, label: Text(c))],
                selected: {_cashier.paidCurrency},
                onSelectionChanged: (v) => setState(() {
                  _paidCurrency = v.first;
                  _paymentReceivedController.clear();
                }),
              ),
              Text(
                '${s.text('amount_due')}: ${money(_cashier.dueInPaid, _cashier.paidCurrency)}'
                '  ·  1 USD = ${_rate.toStringAsFixed(2)} HTG',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
        Builder(
          builder: (context) {
            final cashier = _cashier;
            if (cashier.changeInPaid <= 0.004) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  '${s.text('change_due')}: ${money(cashier.changeInPaid, cashier.paidCurrency)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F766E)),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.text('keep_change_as_credit')),
                  subtitle: Text('+${money(cashier.receivedInBase - cashier.cashDue, _currency)}'),
                  value: _keepChangeAsCredit,
                  onChanged: (v) => setState(() => _keepChangeAsCredit = v == true),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _referenceController,
          decoration: InputDecoration(labelText: s.text('reference_receipt'), prefixIcon: const Icon(LucideIcons.hash), border: const OutlineInputBorder(), hintText: 'Ex: MC-89234712'),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _paymentConfirmed ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _paymentConfirmed ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_paymentConfirmed ? LucideIcons.circleCheck : LucideIcons.shieldAlert, color: _paymentConfirmed ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                  const SizedBox(width: 10),
                  Text(
                    _paymentConfirmed ? s.text('confirm') : s.text('pending_renewals_title'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _paymentConfirmed ? const Color(0xFF065F46) : const Color(0xFF991B1B)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _paymentConfirmed ? const Color(0xFF059669) : const Color(0xFFDC2626), foregroundColor: Colors.white),
                onPressed: () => setState(() => _paymentConfirmed = !_paymentConfirmed),
                icon: Icon(_paymentConfirmed ? LucideIcons.check : LucideIcons.checkCheck),
                label: Text(_paymentConfirmed ? s.text('confirm') : s.text('select_payment_required')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep4(AppStrings s) {
    final isFr = s.locale.languageCode == 'fr';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) _buildErrorBanner(),

        // Section Code PIN d'accès (Optionnel)
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.keyRound, color: Color(0xFF0F766E), size: 22),
                    const SizedBox(width: 10),
                    Text(isFr ? 'Code PIN d\'Accès (Optionnel)' : 'Kòd PIN pou Antre (Opsyonèl)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isFr
                      ? 'Recommandé si la salle dispose d\'un clavier à code ou si le lecteur d\'empreintes n\'est pas utilisé.'
                      : 'Rekòmande si sal la gen yon klavye nan pòt la oswa si yo pa itilize lektè anprent.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: isFr ? 'Code PIN (4 à 6 chiffres)' : 'Kòd PIN (4 a 6 chif)',
                    hintText: 'Ex: 1234',
                    prefixIcon: const Icon(LucideIcons.lock),
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Option : Salle sans lecteur d'empreinte / Enregistrer plus tard
        Card(
          color: _skipFingerprintForNow ? const Color(0xFFEFF6FF) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _skipFingerprintForNow ? Colors.blue : Colors.grey.shade300),
          ),
          child: CheckboxListTile(
            title: Text(isFr ? 'Salle sans empreinte / Enregistrer plus tard' : 'Sal san anprent / Anrejistre pita', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              isFr ? 'Cochez si cette salle utilise le code PIN uniquement ou n\'a pas de lecteur Suprema.' : 'Koche sa si sal sa a itilize kòd PIN sèlman oswa pa gen lektè Suprema.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            value: _skipFingerprintForNow,
            onChanged: (val) => setState(() => _skipFingerprintForNow = val ?? false),
          ),
        ),
        const SizedBox(height: 16),

        if (!_skipFingerprintForNow) ...[
          Card(
            color: const Color(0xFFF0FDF4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(LucideIcons.fingerprint, color: Color(0xFF047857), size: 36),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      s.text('biometrics_settings_hint'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Consentement obligatoire
          CheckboxListTile(
            value: _consentGiven,
            onChanged: (val) => setState(() => _consentGiven = val ?? false),
            title: Text(s.text('consent_checkbox'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 16),
          // Choix du doigt (Principal ou Secours)
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 1, label: Text(s.text('primary_finger')), icon: const Icon(LucideIcons.fingerprint)),
              ButtonSegment(value: 2, label: Text(s.text('backup_finger')), icon: const Icon(LucideIcons.shieldCheck)),
            ],
            selected: {_selectedFingerIndex},
            onSelectionChanged: (set) => setState(() => _selectedFingerIndex = set.first),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: (_selectedFingerIndex == 1 ? _primaryTemplate != null : _backupTemplate != null)
                        ? const Color(0xFF059669)
                        : const Color(0xFF0F766E),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F766E).withOpacity(0.3),
                        blurRadius: 16,
                        spreadRadius: 4,
                      )
                    ],
                  ),
                  child: Center(
                    child: _isCapturing
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Icon(
                            (_selectedFingerIndex == 1 ? _primaryTemplate != null : _backupTemplate != null)
                                ? LucideIcons.checkCheck
                                : LucideIcons.fingerprint,
                            size: 56,
                            color: Colors.white,
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  (_selectedFingerIndex == 1 ? _primaryTemplate != null : _backupTemplate != null)
                      ? s.text('finger_captured_success')
                      : 'Poze dwèt la sou lektè a (Kapti otomatik)...',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  (_selectedFingerIndex == 1 ? _primaryTemplate != null : _backupTemplate != null)
                      ? 'Empreinte enregistrée et configurée.'
                      : 'Lektè a ap koute otomatikman — pa bezwen klike anyen.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                if ((_selectedFingerIndex == 1 ? _primaryTemplate != null : _backupTemplate != null)) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                    onPressed: () {
                      setState(() {
                        if (_selectedFingerIndex == 1) {
                          _primaryTemplate = null;
                        } else {
                          _backupTemplate = null;
                        }
                      });
                    },
                    icon: const Icon(LucideIcons.refreshCw, size: 14),
                    label: const Text('Rekaptire / Chanje dwèt'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEF4444)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.triangleAlert, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFF991B1B))),
          ),
        ],
      ),
    );
  }
}
