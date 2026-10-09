import 'fingerprint_enrollment_dialog.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../core/widgets/scanner_camera_view.dart';
import '../../../l10n/app_strings.dart';
import '../../badges/data/badges_repository.dart';
import '../../badges/domain/badge.dart';
import '../../plans/data/plans_repository.dart';
import '../../plans/domain/plan.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../data/member_photo_codec.dart';
import '../data/member_pin_service.dart';
import '../domain/member.dart';
import '../domain/enrollment_terms.dart';
import '../domain/member_pin.dart';

class CardActivationPage extends ConsumerStatefulWidget {
  const CardActivationPage({super.key, this.preselectedBadgeId});
  final String? preselectedBadgeId;

  @override
  ConsumerState<CardActivationPage> createState() => _CardActivationPageState();
}

class _CardActivationPageState extends ConsumerState<CardActivationPage> {
  int _step = 0;
  bool _busy = false;

  // Étape 1 : Badge (Opsyonèl)
  bool _skipBadge = false;
  String? _enrolledFingerprint;
  String? _generatedTempPin;
  DateTime? _tempPinExpiresAt;
  BadgeItem? _selectedBadge;
  final _usbScanController = TextEditingController();
  final _usbFocusNode = FocusNode();
  String? _badgeError;

  // Étape 2 : Membre
  final _memberFormKey = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final k in [
      'first_name',
      'last_name',
      'phone',
      'whatsapp',
      'email',
      'address',
      'nif',
      'cin',
      'emergency_name',
      'emergency_phone',
      'guardian_name',
      'notes',
    ])
      k: TextEditingController(),
  };
  String? _sex;
  DateTime? _birthDate;
  Uint8List? _photoBytes;
  final _picker = ImagePicker();

  // Étape 3 : Plan & Paiement
  late final PlansRepository _plansRepo;
  GymPlan? _selectedPlan;
  DateTime _startDate = DateTime.now();
  DateTime? _paidThrough;
  bool _existingMember = false;
  final _subscriptionFormKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  String _paymentMethod = 'cash';

  // Étape 4 : PIN du membre
  String _pinFirst = '';
  String _pinConfirm = '';
  String _pinMemorized = '';
  int _pinStage =
      0; // 0: saisie, 1: confirmation, 2: compte à rebours 5s, 3: test mémorisation
  int _countdown = 5;
  Timer? _countdownTimer;
  String? _pinError;

  // Succès
  String? _createdMemberNumber;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _plansRepo = PlansRepository(runtime.database!, runtime.session!);
    _startDate = gymDate(
      runtime.sync?.clock.correctedNow ?? DateTime.now().toUtc(),
      runtime.session!.timezone,
    );
    _loadPreselected();
  }

  Future<void> _loadPreselected() async {
    if (widget.preselectedBadgeId != null) {
      final db = ref.read(appRuntimeProvider).database!;
      final record = await db.record(
        SyncEntity.badges,
        widget.preselectedBadgeId!,
      );
      if (record != null) {
        final badge = BadgeItem(
          jsonDecode(record.payload) as Map<String, dynamic>,
        );
        if (badge.isAvailable) {
          setState(() {
            _selectedBadge = badge;
            _step = 1;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _usbScanController.dispose();
    _usbFocusNode.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    _amountController.dispose();
    _referenceController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim() ?? '';
      if (raw.isNotEmpty) {
        _processBadgeRaw(raw);
        break;
      }
    }
  }

  Future<void> _processBadgeRaw(String raw) async {
    final runtime = ref.read(appRuntimeProvider);
    final db = runtime.database!;
    final gymCode = runtime.session?.gym?['code'] ?? '';

    String? token;
    final parts = raw.split('|');
    if (parts.length >= 4 && (parts[0] == 'GD2' || parts[0] == 'GD1')) {
      if (parts[1] != gymCode) {
        setState(() => _badgeError = 'badge_other_gym');
        return;
      }
      token = parts[3];
    } else {
      token = raw;
    }

    final record = await db.badgeByToken(token);
    if (record == null) {
      setState(() => _badgeError = 'badge_unknown');
      return;
    }

    final badge = BadgeItem(jsonDecode(record.payload) as Map<String, dynamic>);
    if (badge.isBound) {
      setState(() => _badgeError = 'badge_already_bound');
      return;
    }
    if (badge.isBlocked) {
      setState(() => _badgeError = 'badge_blocked');
      return;
    }

    setState(() {
      _selectedBadge = badge;
      _badgeError = null;
      _step = 1;
    });
  }

  Future<void> _pickPhoto() async {
    final s = AppStrings.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: Text(s.text('take_instant_photo')),
              subtitle: Text(s.text('photo_instant_hint')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: Text(s.text('choose_from_gallery')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_photoBytes != null)
              ListTile(
                leading: Icon(
                  LucideIcons.trash2,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  s.text('delete'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  setState(() => _photoBytes = null);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (file == null) return;
      final bytes = encodeMemberPhoto(await file.readAsBytes());
      if (mounted) setState(() => _photoBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('invalid_photo'))),
      );
    }
  }

  void _startMemorizationCountdown() {
    setState(() {
      _pinStage = 2;
      _countdown = 5;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        setState(() {
          _pinStage = 3;
          _pinMemorized = '';
        });
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _completeActivation() async {
    if (_busy) return;
    try {
      await _persistActivation();
    } catch (error) {
      if (mounted) {
        final code = error is MemberFailure
            ? error.code
            : error is SyncRejected
            ? error.code
            : 'local_storage';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).text(code))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persistActivation() async {
    if (_busy || (!_skipBadge && _selectedBadge == null) || _selectedPlan == null) return;
    setState(() => _busy = true);

    try {
      final runtime = ref.read(appRuntimeProvider);
      final db = runtime.database!;
      final session = runtime.session!;
      final now = runtime.sync?.clock.correctedNow ?? DateTime.now().toUtc();
      const uuid = Uuid();

      final memberId = uuid.v4();
      final subscriptionId = uuid.v4();
      final paymentId = uuid.v4();
      final historyId = uuid.v4();

      final String memberNumber = _skipBadge || _selectedBadge == null
          ? await db.nextMemberNumber()
          : _selectedBadge!.formattedNumber;
      final String qrToken = _skipBadge || _selectedBadge == null
          ? uuid.v4()
          : _selectedBadge!.qrToken;
      final String? badgeId = _skipBadge ? null : _selectedBadge?.id;

      final pinService = MemberPinService(db);
      final pinData = await pinService.createPinData(
        memberId,
        session.gymId!,
        _pinFirst,
      );

      final isOneDayPass = _selectedPlan!.durationDays == 1 || _selectedPlan!.name.toLowerCase().contains('1 j') || _selectedPlan!.name.toLowerCase().contains('séance');
      final todayMidnight = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final tempPin = isOneDayPass ? (_pinFirst.isNotEmpty ? _pinFirst : '${100000 + (memberId.hashCode.abs() % 900000)}') : null;

      final terms = EnrollmentTerms.create(
        plan: _selectedPlan!,
        existing: _existingMember,
        canManage: session.canManageGym,
        start: _startDate,
        end: _paidThrough,
        paid: _existingMember
            ? 0
            : double.tryParse(_amountController.text.replaceAll(',', '.')) ??
                  double.nan,
      );
      final paidAmount = terms.paymentAmount;
      final endDate = terms.end;

      final firstName = _fields['first_name']!.text.trim();
      final lastName = _fields['last_name']!.text.trim();

      // 1. Membre
      final memberRow = <String, dynamic>{
        'id': memberId,
        'gym_id': session.gymId,
        'badge_id': badgeId,
        'member_number': memberNumber,
        'qr_token': qrToken,
        'first_name': firstName,
        'last_name': lastName,
        'sex': _sex,
        'birth_date': _birthDate == null ? null : ymd(dateOnly(_birthDate!)),
        'phone': normalizePhone(_fields['phone']!.text),
        'whatsapp': normalizePhone(_fields['whatsapp']!.text),
        'email': _fields['email']!.text.trim().toLowerCase(),
        'enrollment_origin': _existingMember ? 'existing' : 'new',
        'address': _fields['address']!.text.trim(),
        'nif': normalizeNif(_fields['nif']!.text),
        'cin': _fields['cin']!.text.trim(),
        'emergency_contact_name': _fields['emergency_name']!.text.trim(),
        'emergency_contact_phone': normalizePhone(
          _fields['emergency_phone']!.text,
        ),
        'guardian_name': _fields['guardian_name']!.text.trim(),
        'photo_url': null,
        'notes': _fields['notes']!.text.trim(),
        'fingerprint_template': _enrolledFingerprint,
        'fingerprint_registered': _enrolledFingerprint != null && _enrolledFingerprint!.isNotEmpty,
        'temporary_pin': tempPin,
        'pin_expires_at': isOneDayPass ? todayMidnight.toIso8601String() : null,
        'status': 'active',
        'is_test': false,
        'created_by': session.staffId,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      // 2. Abonnement
      final subRow = <String, dynamic>{
        'id': subscriptionId,
        'gym_id': session.gymId,
        'member_id': memberId,
        'plan_id': _selectedPlan!.id,
        'start_date': ymd(_startDate),
        'end_date': ymd(endDate),
        'price': terms.price,
        'opening_credit': terms.openingCredit,
        'enrollment_kind': terms.kind,
        'status': terms.status,
        'created_by': session.staffId,
        'validated_by': session.staffId,
        'validated_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      // 3. Paiement
      Map<String, dynamic>? paymentRow;
      if (paidAmount > 0) {
        paymentRow = <String, dynamic>{
          'id': paymentId,
          'gym_id': session.gymId,
          'member_id': memberId,
          'subscription_id': subscriptionId,
          'amount': paidAmount,
          'currency': _selectedPlan!.currency,
          'method': _paymentMethod,
          'reference': _referenceController.text.trim(),
          'paid_at': now.toIso8601String(),
          'received_by': session.staffId,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        };
      }

      // 4. Badge (opsyonèl si skip)
      Map<String, dynamic>? badgeRow;
      Map<String, dynamic>? historyRow;
      if (!_skipBadge && _selectedBadge != null) {
        badgeRow = <String, dynamic>{
          ..._selectedBadge!.row,
          'status': 'bound',
          'member_id': memberId,
          'bound_at': now.toIso8601String(),
          'bound_by': session.staffId,
          'updated_at': now.toIso8601String(),
        };

        historyRow = <String, dynamic>{
          'id': historyId,
          'gym_id': session.gymId,
          'badge_id': _selectedBadge!.id,
          'member_id': memberId,
          'event': 'bound',
          'actor_id': session.staffId,
          'reason': 'Activation de carte',
          'created_at': now.toIso8601String(),
        };
      }

      // 5. PIN
      final pinRow = pinData.toJson();

      // Enregistrement atomique immédiat en base locale
      await db.activateMemberCard(
        member: memberRow,
        subscription: subRow,
        payment: paymentRow,
        badge: badgeRow,
        pin: pinRow,
        history: historyRow,
        photoBytes: _photoBytes,
        changedAt: now,
      );

      if (mounted) {
        setState(() {
          _busy = false;
          _createdMemberNumber = memberNumber;
          _generatedTempPin = tempPin;
          _tempPinExpiresAt = isOneDayPass ? todayMidnight : null;
          _step = 4;
        });

        // Pouse imedyatman sou Tèminal Pòt FSTW F30
        try {
          final fstw = ref.read(fstwAccessControlServiceProvider);
          if (_enrolledFingerprint != null && _enrolledFingerprint!.isNotEmpty) {
            unawaited(fstw.sendUserFingerprint(memberId, _enrolledFingerprint!, '$firstName $lastName'));
          }
          if (tempPin != null) {
            unawaited(fstw.setTemporaryPin(memberId, tempPin, todayMidnight));
          }
        } catch (doorErr) {
          debugPrint('FSTW door dispatch error (queued): $doorErr');
        }
      }

      unawaited(
        runtime.sync?.synchronize().catchError((e) {
          debugPrint('Sync after activation (will retry automatically): $e');
        }),
      );
    } catch (e, st) {
      debugPrint('Error activating card: $e\n$st');
      if (mounted) {
        setState(() => _busy = false);
        final s = AppStrings.of(context);
        final code = e is MemberFailure
            ? e.code
            : e is SyncRejected
            ? e.code
            : 'local_storage';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.text(code)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _printWelcomeSlip() async {
    final session = ref.read(appRuntimeProvider).session;
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(12),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              session?.name.toUpperCase() ?? 'GYMDESK',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'FICHE DE BIENVENUE',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.Divider(),
            pw.SizedBox(height: 4),
            pw.Text(
              '${_fields['first_name']!.text} ${_fields['last_name']!.text}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Numéro : $_createdMemberNumber',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('Formule : ${_selectedPlan?.name ?? ""}'),
            pw.Divider(),
            pw.Text(
              'CONSIGNES DE SÉCURITÉ :',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '• Votre code PIN est strictement personnel.\n• Ne le communiquez à personne.\n• En cas d\'oubli, présentez-vous à la réception avec une pièce d\'identité.',
              style: const pw.TextStyle(fontSize: 7),
              textAlign: pw.TextAlign.center,
            ),
            pw.Divider(),
            pw.Text(
              'Merci pour votre confiance !',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  Future<void> _shareOnWhatsApp() async {
    final rawPhone = _fields['whatsapp']!.text.trim().isNotEmpty
        ? _fields['whatsapp']!.text.trim()
        : _fields['phone']!.text.trim();
    final phone = normalizePhone(rawPhone);
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context).text('no_whatsapp_number')),
          ),
        );
      }
      return;
    }
    final cleanDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final gymName = ref.read(appRuntimeProvider).session?.name ?? 'GymDesk';
    final firstName = _fields['first_name']!.text.trim();
    final lastName = _fields['last_name']!.text.trim();
    final badgeNum =
        _createdMemberNumber ?? _selectedBadge?.formattedNumber ?? '';
    final planName = _selectedPlan?.name ?? '';
    final message = '''*Byenvini nan $gymName !* 🏋️‍♂️

Bonjou $firstName $lastName,
Kat manm ou an aktive avèk siksè !

📋 *Enfòmasyon sou abònman ou :*
• Nimewo manm : $badgeNum
• Fòmil : $planName
• Estati : Aktif

🔐 *Sekirite :*
Kòd PIN ou an se sekrè pèsonèl ou. Pa pataje l ak pèsonn pou aksè nan sal la.

Mèsi pou konfyans ou, bòn antrènman !''';

    final uri = Uri.parse(
      'https://wa.me/$cleanDigits?text=${Uri.encodeComponent(message)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enposib ouvri WhatsApp.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    if (_step == 4) {
      return Scaffold(
        appBar: AppBar(title: Text(s.text('card_activated_title'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.circleCheck,
                    color: Colors.green,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.text('card_activated_success'),
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${s.text('member_badge')}: $_createdMemberNumber',
                    style: theme.textTheme.titleMedium,
                  ),
                  if (_generatedTempPin != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade800),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.keyRound, color: Colors.amber.shade900, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'KÒD PIN TANPORÈ POU PÒT LA (1 JOU)',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            _generatedTempPin!,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Kòd sa a valab jiska minwi aswè a pou louvri tèminal FSTW F30 la.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.brown.shade800),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(s.text('email_after_sync'), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(LucideIcons.printer),
                        label: Text(s.text('print_welcome_slip')),
                        onPressed: _printWelcomeSlip,
                      ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(LucideIcons.messageCircle),
                        label: Text(s.text('share_whatsapp')),
                        onPressed: _shareOnWhatsApp,
                      ),
                      OutlinedButton(
                        onPressed: () => context.go('/members'),
                        child: Text(s.text('done')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('activate_card')),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.go('/members'),
        ),
      ),
      body: SafeArea(
        child: Stepper(
          currentStep: _step,
          type: StepperType.horizontal,
          elevation: 0,
          controlsBuilder: (context, details) => const SizedBox.shrink(),
          steps: [
            Step(
              title: Text(s.text('step_badge')),
              isActive: _step >= 0,
              content: _buildStepBadge(s, theme),
            ),
            Step(
              title: Text(s.text('step_member')),
              isActive: _step >= 1,
              content: _buildStepMember(s, theme),
            ),
            Step(
              title: Text(s.text('step_subscription')),
              isActive: _step >= 2,
              content: _buildStepSubscription(s, theme),
            ),
            Step(
              title: Text(s.text('step_pin')),
              isActive: _step >= 3,
              content: _buildStepPin(s, theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBadge(AppStrings s, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                    s.text('scan_blank_card_prompt'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.text('scan_blank_card_hint'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.secondaryContainer,
              ),
              icon: const Icon(LucideIcons.fingerprint, size: 16),
              label: const Text('Kontinye San Badj (Byometri/PIN) ➔'),
              onPressed: () {
                setState(() {
                  _skipBadge = true;
                  _selectedBadge = null;
                  _step = 1;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_badgeError != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withAlpha(24),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.error),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.triangleAlert,
                  color: theme.colorScheme.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.text(_badgeError!),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final scanInput = Column(
              children: [
                TextField(
                  controller: _usbScanController,
                  focusNode: _usbFocusNode,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: s.text('scan_or_type_qr'),
                    prefixIcon: const Icon(LucideIcons.barcode),
                    suffixIcon: IconButton(
                      icon: const Icon(LucideIcons.arrowRight),
                      onPressed: () =>
                          _processBadgeRaw(_usbScanController.text),
                    ),
                  ),
                  onSubmitted: _processBadgeRaw,
                ),
                const SizedBox(height: 16),
                FutureBuilder<List<BadgeItem>>(
                  future: BadgesRepository(
                    ref.read(appRuntimeProvider).client,
                    ref.read(appRuntimeProvider).database!,
                    ref.read(appRuntimeProvider).session!,
                  ).getAvailableBadges(),
                  builder: (context, snap) {
                    final available = snap.data ?? [];
                    if (available.isEmpty) {
                      return MessagePanel(
                        message: s.text('no_available_badges'),
                      );
                    }
                    return DropdownButtonFormField<BadgeItem>(
                      decoration: InputDecoration(
                        labelText: s.text('select_available_badge'),
                      ),
                      items: available
                          .map(
                            (b) => DropdownMenuItem(
                              value: b,
                              child: Text(
                                '${b.formattedNumber} (${b.qrToken.substring(0, 8)}...)',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (badge) {
                        if (badge != null) {
                          setState(() {
                            _selectedBadge = badge;
                            _badgeError = null;
                            _step = 1;
                          });
                        }
                      },
                    );
                  },
                ),
              ],
            );

            final cameraWidget = AspectRatio(
              aspectRatio: 4 / 3,
              child: ScannerCameraView(
                borderRadius: 12,
                onDetect: _onDetect,
              ),
            );

            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: scanInput),
                      const SizedBox(width: 24),
                      Expanded(flex: 4, child: cameraWidget),
                    ],
                  )
                : Column(
                    children: [
                      scanInput,
                      const SizedBox(height: 16),
                      cameraWidget,
                    ],
                  );
          },
        ),
      ],
    );
  }

  Widget _buildStepMember(AppStrings s, ThemeData theme) {
    return Form(
      key: _memberFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${s.text('badge')}: ${_selectedBadge?.formattedNumber}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              TextButton.icon(
                icon: const Icon(LucideIcons.arrowLeft, size: 16),
                label: Text(s.text('change_badge')),
                onPressed: () => setState(() => _step = 0),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;

              final photoCard = Column(
                children: [
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: _photoBytes != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                _photoBytes!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(LucideIcons.camera, size: 36),
                                const SizedBox(height: 6),
                                Text(
                                  s.text('take_instant_photo'),
                                  style: theme.textTheme.labelSmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(LucideIcons.camera, size: 14),
                    label: Text(
                      s.text(
                        _photoBytes != null ? 'retake_photo' : 'take_photo',
                      ),
                    ),
                  ),
                ],
              );

              final fieldsList = [
                TextFormField(
                  controller: _fields['first_name'],
                  decoration: InputDecoration(labelText: s.text('first_name')),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? s.text('required')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fields['last_name'],
                  decoration: InputDecoration(labelText: s.text('last_name')),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? s.text('required')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fields['phone'],
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: s.text('phone')),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? s.text('required')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fields['email'],
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 254,
                  decoration: InputDecoration(
                    labelText: s.text('email'),
                    helperText: s.text('member_email_hint'),
                    helperMaxLines: 3,
                  ),
                  validator: (v) =>
                      RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch((v ?? '').trim())
                      ? null
                      : s.text('invalid_email'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fields['nif'],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: s.text('nif')),
                ),
              ];

              if (isMobile) {
                return Column(
                  children: [
                    Center(child: photoCard),
                    const SizedBox(height: 16),
                    ...fieldsList,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  photoCard,
                  const SizedBox(width: 24),
                  Expanded(child: Column(children: fieldsList)),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _step = 0),
                child: Text(s.text('previous')),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  if (_memberFormKey.currentState!.validate()) {
                    setState(() => _step = 2);
                  }
                },
                child: Text(s.text('next')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickPaidPeriod() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _paidThrough == null
          ? null
          : DateTimeRange(start: _startDate, end: _paidThrough!),
    );
    if (range != null && mounted) {
      setState(() {
        _startDate = range.start;
        _paidThrough = range.end;
      });
    }
  }

  Widget _buildStepSubscription(AppStrings s, ThemeData theme) {
    return Form(
      key: _subscriptionFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.text('choose_subscription_plan'),
            style: theme.textTheme.titleMedium,
          ),
          if (ref.read(appRuntimeProvider).session!.canManageGym)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.text('existing_member_import')),
              subtitle: Text(s.text('existing_member_import_hint')),
              value: _existingMember,
              onChanged: (value) => setState(() {
                _existingMember = value;
                _startDate = gymDate(
                  DateTime.now().toUtc(),
                  ref.read(appRuntimeProvider).session!.timezone,
                );
                _paidThrough = null;
                _amountController.text = value
                    ? '0'
                    : _selectedPlan?.registrationPrice.toStringAsFixed(2) ?? '';
              }),
            ),
          if (_existingMember) ...[
            OutlinedButton.icon(
              onPressed: _pickPaidPeriod,
              icon: const Icon(LucideIcons.calendar),
              label: Text(
                _paidThrough == null
                    ? s.text('choose_paid_period')
                    : '${ymd(_startDate)} → ${ymd(_paidThrough!)}',
              ),
            ),
            const SizedBox(height: 8),
            Text(s.text('import_no_cash')),
          ],
          const SizedBox(height: 16),
          StreamBuilder<List<GymPlan>>(
            stream: _plansRepo.watch(),
            builder: (context, snap) {
              final plans = (snap.data ?? [])
                  .where((p) => p.active && p.deletedAt == null)
                  .toList();
              if (plans.isEmpty) return const LoadingPanel();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: plans.map((p) {
                      final selected = _selectedPlan?.id == p.id;
                      return ChoiceChip(
                        selected: selected,
                        label: Text(
                          '${p.name} (${_existingMember ? p.price : p.registrationPrice} ${p.currency})',
                        ),
                        onSelected: (_) => setState(() {
                          _selectedPlan = p;
                          _amountController.text = _existingMember
                              ? '0'
                              : p.registrationPrice.toStringAsFixed(2);
                        }),
                      );
                    }).toList(),
                  ),
                  if (_selectedPlan != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '${s.text(_existingMember ? 'renewal_price' : 'enrollment_price')}: ${(_existingMember ? _selectedPlan!.price : _selectedPlan!.registrationPrice).toStringAsFixed(2)} ${_selectedPlan!.currency}\n${s.text('renewal_price')}: ${_selectedPlan!.price.toStringAsFixed(2)} ${_selectedPlan!.currency}',
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (!_existingMember)
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 220,
                          child: TextFormField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: s.text('paid_amount'),
                            ),
                            validator: (v) {
                              final amount = double.tryParse(
                                (v ?? '').replaceAll(',', '.'),
                              );
                              return amount == null ||
                                      !amount.isFinite ||
                                      amount < 0 ||
                                      amount >
                                          (_selectedPlan?.registrationPrice ??
                                              0)
                                  ? s.text('invalid_record')
                                  : null;
                            },
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            initialValue: _paymentMethod,
                            decoration: InputDecoration(
                              labelText: s.text('payment_method'),
                            ),
                            items:
                                ['cash', 'moncash', 'natcash', 'bank', 'other']
                                    .map(
                                      (m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(s.text('method_$m')),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) =>
                                setState(() => _paymentMethod = v ?? 'cash'),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextFormField(
                            controller: _referenceController,
                            decoration: InputDecoration(
                              labelText: s.text('payment_reference'),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _step = 1),
                child: Text(s.text('previous')),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed:
                    _selectedPlan == null ||
                        (_existingMember && _paidThrough == null)
                    ? null
                    : () {
                        if (!_subscriptionFormKey.currentState!.validate()) {
                          return;
                        }
                        setState(() {
                          _step = 3;
                          _pinStage = 0;
                          _pinFirst = '';
                          _pinConfirm = '';
                          _pinMemorized = '';
                        });
                      },
                child: Text(s.text('next_to_pin')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepPin(AppStrings s, ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.shieldCheck,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.text('member_pin_privacy_notice'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Enwolman Anprent DigitalPersona 4500 USB
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _enrolledFingerprint != null
                    ? Colors.green.withAlpha(24)
                    : theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _enrolledFingerprint != null
                      ? Colors.green
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.fingerprint,
                    size: 22,
                    color: _enrolledFingerprint != null ? Colors.green : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _enrolledFingerprint != null
                          ? '✅ Anprent Enwole avèk Siksè !'
                          : 'Lektè Anprent DigitalPersona 4500 (Akèy)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _enrolledFingerprint != null ? Colors.green.shade800 : null,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: Icon(
                      _enrolledFingerprint != null ? LucideIcons.refreshCw : LucideIcons.scanLine,
                      size: 14,
                    ),
                    label: Text(_enrolledFingerprint != null ? 'Refè' : 'Enwole Anprent'),
                    onPressed: () async {
                      final memberSim = Member({
                        'id': 'draft-enrollee',
                        'first_name': _fields['first_name']!.text.trim(),
                        'last_name': _fields['last_name']!.text.trim(),
                      });
                      await FingerprintEnrollmentDialog.show(
                        context,
                        member: memberSim,
                        onSaved: () {
                          setState(() {
                            _enrolledFingerprint = 'DP4500_TEMPLATE_' + DateTime.now().millisecondsSinceEpoch.toString();
                          });
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_pinError != null) ...[
              Text(
                s.text(_pinError!),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            if (_pinStage == 0) ...[
              Text(
                s.text('enter_new_pin_prompt'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                s.text('pin_requirements_hint'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              _buildPinDots(_pinFirst),
              const SizedBox(height: 20),
              _buildKeypad(
                (d) {
                  if (_pinFirst.length < 6) {
                    setState(() {
                      _pinFirst += d;
                      _pinError = null;
                    });
                  }
                },
                () {
                  if (_pinFirst.isNotEmpty) {
                    setState(
                      () => _pinFirst = _pinFirst.substring(
                        0,
                        _pinFirst.length - 1,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _pinFirst.length >= 4
                    ? () {
                        final err = validateMemberPinFormat(
                          _pinFirst,
                          birthDate: _birthDate,
                        );
                        if (err != null) {
                          setState(() => _pinError = err);
                        } else {
                          setState(() {
                            _pinStage = 1;
                            _pinConfirm = '';
                            _pinError = null;
                          });
                        }
                      }
                    : null,
                child: Text(s.text('continue')),
              ),
            ] else if (_pinStage == 1) ...[
              Text(
                s.text('confirm_pin_prompt'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              _buildPinDots(_pinConfirm),
              const SizedBox(height: 20),
              _buildKeypad(
                (d) {
                  if (_pinConfirm.length < 6) {
                    setState(() {
                      _pinConfirm += d;
                      _pinError = null;
                    });
                  }
                },
                () {
                  if (_pinConfirm.isNotEmpty) {
                    setState(
                      () => _pinConfirm = _pinConfirm.substring(
                        0,
                        _pinConfirm.length - 1,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _pinConfirm.length == _pinFirst.length
                    ? () {
                        if (_pinConfirm != _pinFirst) {
                          setState(() => _pinError = 'pin_mismatch');
                        } else {
                          _startMemorizationCountdown();
                        }
                      }
                    : null,
                child: Text(s.text('confirm')),
              ),
            ] else if (_pinStage == 2) ...[
              const Icon(LucideIcons.brain, size: 48),
              const SizedBox(height: 16),
              Text(
                s.text('memorize_pin_prompt'),
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                s.text('memorize_countdown_hint'),
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                '$_countdown',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ] else if (_pinStage == 3) ...[
              Text(
                s.text('reenter_pin_test_prompt'),
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                s.text('reenter_pin_test_hint'),
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _buildPinDots(_pinMemorized),
              const SizedBox(height: 20),
              _buildKeypad(
                (d) {
                  if (_pinMemorized.length < 6) {
                    setState(() {
                      _pinMemorized += d;
                      _pinError = null;
                    });
                  }
                },
                () {
                  if (_pinMemorized.isNotEmpty) {
                    setState(
                      () => _pinMemorized = _pinMemorized.substring(
                        0,
                        _pinMemorized.length - 1,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || _pinMemorized.length != _pinFirst.length
                    ? null
                    : () {
                        if (_pinMemorized != _pinFirst) {
                          setState(
                            () => _pinError = 'memorization_failed_try_again',
                          );
                        } else {
                          _completeActivation();
                        }
                      },
                child: _busy
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(s.text('finalize_activation')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPinDots(String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final filled = index < text.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildKeypad(void Function(String) onDigit, VoidCallback onDelete) {
    return Column(
      children: [
        for (var row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row
                .map((digit) => _keyButton(digit, () => onDigit(digit)))
                .toList(),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 80, height: 60),
            _keyButton('0', () => onDigit('0')),
            SizedBox(
              width: 80,
              height: 60,
              child: IconButton(
                icon: const Icon(LucideIcons.delete),
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _keyButton(String text, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.all(4),
      width: 72,
      height: 54,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.zero,
        ),
        onPressed: onTap,
        child: Text(
          text,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
