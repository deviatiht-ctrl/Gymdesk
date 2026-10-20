import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../l10n/app_strings.dart';
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

  late final PortalRepository _portalRepo;

  String get _cleanGymCode => widget.gymCode.trim();
  String get _draftStorageKey => 'portal_draft_$_cleanGymCode';

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
    _loadGymData();
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
      );

      // Si soumèt avèk siksè, nou vide bouyon an pou pwochen moun
      try {
        await _storage.delete(key: _draftStorageKey);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submittedSuccess = true;
          _lastSubmittedRequestId = res['request_id'] as String? ?? _sessionCode;
        });
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

  @override
  void dispose() {
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
                      ? _buildSuccessView(s, gymName)
                      : _buildFormView(s, gymName, logoUrl),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView(AppStrings s, String gymName) {
    final selectedPlan = _plans.where((p) => p['id'] == _selectedPlanId).firstOrNull;
    final planName = selectedPlan != null ? selectedPlan['name'] as String? ?? '' : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Color(0xFFD1FAE5),
            shape: BoxShape.circle,
          ),
          child: const Icon(LucideIcons.circleCheck, color: Color(0xFF059669), size: 44),
        ),
        const SizedBox(height: 20),
        Text(
          _kind == 'renewal' ? 'Demande de renouvellement reçue !' : s.text('portal_success_title'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Text(
            'Réf. Dossier : #${_lastSubmittedRequestId ?? _sessionCode}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0369A1)),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Merci ${_firstNameController.text.trim()} ! Votre demande pour la formule "$planName" a bien été enregistrée pour $gymName.',
          style: TextStyle(fontSize: 15, color: Colors.grey.shade700, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDFA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF99F6E4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.info, color: Color(0xFF0F766E), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Prochaine étape :',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _kind == 'renewal'
                          ? "Présentez-vous à l'accueil du gym. Il vous suffira de poser votre doigt sur le lecteur d'empreinte pour vous identifier et régler votre abonnement."
                          : s.text('portal_success_message'),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF134E4A), height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: () {
            _clearDraft();
            setState(() {
              _submittedSuccess = false;
            });
          },
          icon: const Icon(LucideIcons.plusCircle, size: 16),
          label: const Text('Envoyer une autre demande'),
        ),
      ],
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
              setState(() => _kind = set.first);
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.info, color: Color(0xFF2563EB), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Renouvellement : Aucun frais d'inscription supplémentaire. Choisissez votre formule, puis présentez-vous à l'accueil pour poser votre doigt sur le lecteur et régler.",
                    style: TextStyle(fontSize: 13, color: Color(0xFF1E40AF)),
                  ),
                ),
              ],
            ),
          ),
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
