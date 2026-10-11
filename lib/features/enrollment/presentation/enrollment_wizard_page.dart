import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/biometrics/biometric_service.dart';
import '../../../core/sync/sync_models.dart';
import '../../../l10n/app_strings.dart';
import '../../members/data/member_photo_codec.dart';
import '../../members/data/members_repository.dart';
import '../../members/domain/member.dart';
import '../../payments/domain/payment.dart';
import '../../plans/data/plans_repository.dart';
import '../../plans/domain/plan.dart';
import '../../subscriptions/domain/gym_subscription.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../../../core/biometrics/access_agent_client.dart';
import '../../members/data/member_pin_service.dart';

class EnrollmentWizardPage extends ConsumerStatefulWidget {
  const EnrollmentWizardPage({super.key});

  @override
  ConsumerState<EnrollmentWizardPage> createState() => _EnrollmentWizardPageState();
}

class _EnrollmentWizardPageState extends ConsumerState<EnrollmentWizardPage> {
  int _currentStep = 0;

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
  DateTime _startDate = DateTime.now();
  GymPlan? _selectedPlan;
  List<GymPlan> _plans = [];
  bool _loadingPlans = true;

  // Step 3: Peman
  String _paymentMethod = 'cash';
  final _paymentAmountController = TextEditingController();
  final _referenceController = TextEditingController();
  bool _paymentConfirmed = false;

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

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _biometricService = BiometricService();
    final runtime = ref.read(appRuntimeProvider);
    _members = MembersRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
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
            _selectedPlan = _plans.first;
            _paymentAmountController.text = _selectedPlan!.price.toStringAsFixed(0);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo error: $e')),
        );
      }
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
        final dup = await _biometricService.match1toN(
          candidateTemplate: sample,
          members: enrolled,
        );
        if (dup != null && mounted) {
          final dupName = '${dup.firstName} ${dup.lastName}';
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(LucideIcons.triangleAlert, color: Colors.orange, size: 36),
              title: Text(s.text('duplicate_fingerprint_alert')),
              content: Text('${s.text('duplicate_fingerprint_alert')}\n($dupName)'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('ok'))),
              ],
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
    final wa = _whatsappController.text.trim();
    final nifCin = _nifCinController.text.trim();

    if (fn.length < 2 || ln.length < 2 || wa.isEmpty || email.isEmpty || !email.contains('@') || nifCin.length < 5) {
      setState(() => _errorMessage = s.text('fill_required_fields'));
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
    return true;
  }

  Future<void> _submitEnrollment(AppStrings s) async {
    final runtime = ref.read(appRuntimeProvider);

    final hasPin = _pinController.text.trim().isNotEmpty;
    final isFr = s.locale.languageCode == 'fr';
    if (_primaryTemplate == null && !_skipFingerprintForNow && !hasPin) {
      setState(() => _errorMessage = isFr
          ? 'Veuillez enregistrer une empreinte, saisir un code PIN, ou cocher "Salle sans empreinte".'
          : 'Tanpri anrejistre yon anprent, mete yon kòd PIN, oswa koche "Sal san anprent".');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final plan = _selectedPlan!;
      final endDate = subscriptionEnd(_startDate, plan.durationDays);
      final amt = double.tryParse(_paymentAmountController.text) ?? plan.price;

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

      final result = await _members.register(
        draft,
        subscription: SubscriptionCommand(
          planId: plan.id,
          startDate: _startDate,
          endDate: endDate,
          price: plan.price,
          status: 'active',
        ),
        payment: PaymentCommand(
          memberId: '',
          subscriptionId: '',
          amount: amt,
          currency: 'HTG',
          method: _paymentMethod,
          reference: _referenceController.text.trim(),
          notes: _paymentConfirmed ? 'Paiement confirmé en caisse' : '',
        ),
        changedAt: now,
      );

      if (_primaryTemplate != null && runtime.database != null) {
        await runtime.database!.save(
          SyncEntity.members,
          {
            'id': result.memberId,
            'gym_id': runtime.session!.gymId,
            'fingerprint_registered': true,
            'fingerprint_template': _primaryTemplate,
            'fingerprint_backup_template': _backupTemplate,
            'fingerprint_enrolled_at': now.toUtc().toIso8601String(),
          },
          changedAt: now,
        );
      }

      if (hasPin && runtime.database != null && runtime.session?.gymId != null) {
        final pinService = MemberPinService(runtime.database!);
        final pinData = await pinService.createPinData(
          result.memberId,
          runtime.session!.gymId!,
          _pinController.text.trim(),
        );
        await pinService.savePinData(pinData);
      }

      unawaited(runtime.sync?.synchronize());

      final fullName = '${draft.firstName} ${draft.lastName}'.trim();

      // Synchronisation immédiate du membre sur le terminal IP mural Suprema (BioEntry W2)
      if (_primaryTemplate != null) {
        final agentClient = AccessAgentClient();
        final tmpls = [_primaryTemplate!];
        if (_backupTemplate != null) tmpls.add(_backupTemplate!);
        unawaited(agentClient.syncTerminalMember(
          userId: result.memberId,
          name: fullName,
          startDate: _startDate,
          endDate: endDate,
          templates: tmpls,
        ).catchError((_) => false));
      }

      final email = draft.email.trim();

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

  void _showSuccessDialog(AppStrings s, String memberId, String fullName, String planName, DateTime endDate, String email) {
    final gymName = ref.read(appRuntimeProvider).session?.name ?? 'GymDesk';
    final wa = _whatsappController.text.trim();
    final isFr = s.locale.languageCode == 'fr';
    final isEn = s.locale.languageCode == 'en';

    final waMessageText = isFr
        ? 'Bonjour $fullName ! Bienvenue chez $gymName.\nVotre inscription est confirmée pour la formule : $planName.\nValable jusqu\'au : ${ymd(endDate)}.\nVotre empreinte est activée pour l\'accès.\nMerci pour votre confiance !'
        : isEn
            ? 'Hello $fullName! Welcome to $gymName.\nYour membership is confirmed for: $planName.\nValid until: ${ymd(endDate)}.\nYour fingerprint access is now active.\nThank you for choosing us!'
            : 'Bonjou $fullName! Byenvini nan $gymName.\nEnskripsyon ou konfime sou plan: $planName.\nAbonman ou valid jiska: ${ymd(endDate)}.\nOu ka pase dwèt ou sou lektè a pou antre nenpòt lè.\nMèsi pou konfyans ou!';

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
            if (email.contains('@'))
              Text(
                '${s.text('email_after_sync')} ($email)',
                style: const TextStyle(color: Color(0xFF047857), fontSize: 13, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
              ),
              onPressed: () => launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication),
              icon: const Icon(LucideIcons.messageCircle, size: 18),
              label: Text(s.text('send_whatsapp_btn')),
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
    _referenceController.dispose();
    _pinController.dispose();
    _biometricService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('enroll_wizard_title')),
      ),
      body: SafeArea(
        child: _loadingPlans
            ? const Center(child: CircularProgressIndicator())
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
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            onPressed: _isSaving ? null : () => _submitEnrollment(s),
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(LucideIcons.checkCheck, size: 18),
                            label: Text(_isSaving ? s.text('saving') : s.text('submit_enrollment')),
                          ),
                        const SizedBox(width: 12),
                        if (_currentStep > 0)
                          OutlinedButton(
                            onPressed: () => setState(() => _currentStep--),
                            child: Text(s.text('back_btn')),
                          ),
                      ],
                    ),
                  );
                },
                steps: [
                  Step(
                    title: Text(s.text('step_identity')),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                    content: _buildStep1(s),
                  ),
                  Step(
                    title: Text(s.text('step_plan')),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                    content: _buildStep2(s),
                  ),
                  Step(
                    title: Text(s.text('step_payment')),
                    isActive: _currentStep >= 2,
                    state: _currentStep > 2 ? StepState.complete : StepState.indexed,
                    content: _buildStep3(s),
                  ),
                  Step(
                    title: Text(s.text('step_biometrics')),
                    isActive: _currentStep >= 3,
                    state: _primaryTemplate != null ? StepState.complete : StepState.indexed,
                    content: _buildStep4(s),
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
                  labelText: '${s.text('email')} *',
                  prefixIcon: const Icon(LucideIcons.mail),
                  border: const OutlineInputBorder(),
                  hintText: 'member@gmail.com',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nifCinController,
                decoration: InputDecoration(
                  labelText: s.text('nif_cin'),
                  prefixIcon: const Icon(LucideIcons.idCard),
                  border: const OutlineInputBorder(),
                  hintText: '000-000-000-0',
                ),
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
          decoration: InputDecoration(
            labelText: s.text('address'),
            prefixIcon: const Icon(LucideIcons.mapPin),
            border: const OutlineInputBorder(),
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
                if (!val) _startDate = DateTime.now();
              });
            },
          ),
        ),
        const SizedBox(height: 16),
        if (_isExistingMember) ...[
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
            leading: const Icon(LucideIcons.calendar),
            title: Text(s.text('start_date')),
            subtitle: Text(ymd(_startDate)),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _startDate = picked);
            },
          ),
          const SizedBox(height: 16),
        ],
        Text(s.text('plans'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        ..._plans.map((plan) {
          final isSelected = _selectedPlan?.id == plan.id;
          return Card(
            elevation: isSelected ? 3 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: isSelected ? const Color(0xFF0F766E) : Colors.transparent, width: 2),
            ),
            child: ListTile(
              onTap: () {
                setState(() {
                  _selectedPlan = plan;
                  _paymentAmountController.text = plan.price.toStringAsFixed(0);
                });
              },
              leading: Icon(
                isSelected ? LucideIcons.checkCircle2 : LucideIcons.circle,
                color: isSelected ? const Color(0xFF0F766E) : Colors.grey,
              ),
              title: Text(plan.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${plan.durationDays} ${s.text('days')}'),
              trailing: Text(
                '${plan.price.toStringAsFixed(0)} HTG',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep3(AppStrings s) {
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
                Text(
                  '${s.text('plans')}: ${_selectedPlan?.name ?? ''} (${_selectedPlan?.price.toStringAsFixed(0) ?? '0'} HTG)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${ymd(_startDate)} - ${ymd(subscriptionEnd(_startDate, _selectedPlan?.durationDays ?? 30))}',
                  style: const TextStyle(color: Colors.grey),
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
                decoration: InputDecoration(
                  labelText: '${s.text('amount_paid')} (HTG) *',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _referenceController,
          decoration: InputDecoration(
            labelText: s.text('reference_receipt'),
            prefixIcon: const Icon(LucideIcons.hash),
            border: const OutlineInputBorder(),
            hintText: 'Ex: MC-89234712',
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _paymentConfirmed ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _paymentConfirmed ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _paymentConfirmed ? LucideIcons.circleCheck : LucideIcons.shieldAlert,
                    color: _paymentConfirmed ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _paymentConfirmed ? s.text('confirm') : s.text('pending_renewals_title'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _paymentConfirmed ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _paymentConfirmed ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                ),
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
                    Text(
                      isFr ? 'Code PIN d\'Accès (Optionnel)' : 'Kòd PIN pou Antre (Opsyonèl)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
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
            title: Text(
              isFr ? 'Salle sans empreinte / Enregistrer plus tard' : 'Sal san anprent / Anrejistre pita',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              isFr
                  ? 'Cochez si cette salle utilise le code PIN uniquement ou n\'a pas de lecteur Suprema.'
                  : 'Koche sa si sal sa a itilize kòd PIN sèlman oswa pa gen lektè Suprema.',
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
                GestureDetector(
                  onTap: _isCapturing ? null : () => _captureFingerprint(s),
                  child: Container(
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
                        ),
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
                ),
                const SizedBox(height: 16),
                Text(
                  (_selectedFingerIndex == 1 ? _primaryTemplate != null : _backupTemplate != null)
                      ? s.text('finger_captured_success')
                      : s.text('capture_finger_btn'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
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
