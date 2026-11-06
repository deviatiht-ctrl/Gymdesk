import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../members/data/member_photo_codec.dart';
import '../data/member_portal_repository.dart';
import 'member_ui.dart';

const _jobColors = <String, Color>{
  'coach': Color(0xFF0F766E),
  'reception': Color(0xFF2563EB),
  'cleaning': Color(0xFF7C3AED),
  'security': Color(0xFFB91C1C),
  'manager': Color(0xFFB45309),
  'maintenance': Color(0xFF475569),
  'other': Color(0xFF64748B),
};

const _jobIcons = <String, IconData>{
  'coach': LucideIcons.dumbbell,
  'reception': LucideIcons.conciergeBell,
  'cleaning': LucideIcons.sparkles,
  'security': LucideIcons.shieldCheck,
  'manager': LucideIcons.briefcase,
  'maintenance': LucideIcons.wrench,
  'other': LucideIcons.user,
};

const _surfaceColor = Color(0xFF0F172A);
const _cardColor = Color(0xFF1E293B);
const _borderColor = Color(0xFF334155);

/// Tableau de bord de l'employé dans l'espace membre / portail SecurGYM.
/// Permet à l'employé de voir son profil complet, son matricule, son statut d'accès
/// et de changer ou ajouter sa photo de profil directement depuis son smartphone.
class EmployeeDashboardView extends StatefulWidget {
  const EmployeeDashboardView({
    super.key,
    required this.data,
    required this.onRefresh,
    required this.onSignOut,
    required this.onChangeGym,
  });

  final Map<String, dynamic> data;
  final Future<void> Function() onRefresh;
  final VoidCallback onSignOut;
  final VoidCallback onChangeGym;

  @override
  State<EmployeeDashboardView> createState() => _EmployeeDashboardViewState();
}

class _EmployeeDashboardViewState extends State<EmployeeDashboardView> {
  final _repo = MemberPortalRepository();
  final _picker = ImagePicker();
  String? _photoUrl;
  String? _photoPath;
  bool _uploading = false;
  String? _error;

  Map<String, dynamic> get _gym =>
      Map<String, dynamic>.from(widget.data['gym'] as Map? ?? const {});
  Map<String, dynamic> get _employee =>
      Map<String, dynamic>.from(widget.data['employee'] as Map? ?? const {});

  String get _gymId => _gym['id']?.toString() ?? '';
  String get _employeeId => _employee['id']?.toString() ?? '';
  Color get _accent => gymAccent(_gym['accent_color'] as String?);

  String get _firstName => _employee['first_name']?.toString() ?? '';
  String get _lastName => _employee['last_name']?.toString() ?? '';
  String get _fullName => '$_firstName $_lastName'.trim();
  String get _jobType => _employee['job_type']?.toString() ?? 'other';
  String get _jobTitle => _employee['job_title']?.toString() ?? _jobType;
  String get _employeeNumber =>
      _employee['employee_number']?.toString() ??
      (_employeeId.length >= 6 ? 'EMP-${_employeeId.replaceAll('-', '').substring(0, 6).toUpperCase()}' : 'EMP-$_employeeId');
  bool get _active => _employee['active'] != false;
  bool get _hasFingerprint => _employee['fingerprint_registered'] == true;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(EmployeeDashboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final path = _employee['photo_url'] as String?;
    if (path == _photoPath && _photoUrl != null) return;
    _photoPath = path;
    if (path == null || path.isEmpty) {
      if (mounted) setState(() => _photoUrl = null);
      return;
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      if (mounted) setState(() => _photoUrl = path);
      return;
    }
    final url = await _repo.photoUrl(path);
    if (mounted) setState(() => _photoUrl = url);
  }

  Future<void> _pickAndUploadPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: memberSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera, color: Colors.white),
              title: const Text('Prendre une photo (Selfie)', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image, color: Colors.white),
              title: const Text('Choisir dans la galerie', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final file = await _picker.pickImage(source: source, maxWidth: 1200, maxHeight: 1200);
      if (file == null) {
        setState(() => _uploading = false);
        return;
      }
      final raw = await file.readAsBytes();
      final encoded = encodeMemberPhoto(raw);

      final objectPath = '$_gymId/$_employeeId/${const Uuid().v4()}.jpg';
      await _repo.uploadPhoto(objectPath, encoded);

      final patch = {'photo_url': objectPath};
      final res = await _repo.updateProfile(_gymId, patch);

      if (res == 'ok') {
        _photoPath = objectPath;
        final url = await _repo.photoUrl(objectPath);
        if (mounted) {
          setState(() {
            _photoUrl = url;
            _uploading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo mise à jour avec succès !'),
              backgroundColor: Color(0xFF0F766E),
            ),
          );
        }
        await widget.onRefresh();
      } else {
        if (mounted) {
          setState(() {
            _uploading = false;
            _error = 'Impossible d’enregistrer la photo.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = 'Erreur lors du téléchargement de la photo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _jobColors[_jobType] ?? _jobColors['other']!;
    final icon = _jobIcons[_jobType] ?? LucideIcons.user;

    return Scaffold(
      backgroundColor: _surfaceColor,
      appBar: AppBar(
        backgroundColor: _surfaceColor,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent.withOpacity(0.4)),
              ),
              child: Text(
                _gym['name']?.toString() ?? 'Gym',
                style: TextStyle(color: _accent, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Espace Personnel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Déconnexion',
            icon: const Icon(LucideIcons.logOut, size: 20),
            onPressed: widget.onSignOut,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                ErrorBox(_error!),
                const SizedBox(height: 16),
              ],

              // Employee ID Card / Badge
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1E293B),
                      color.withOpacity(0.35),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: color.withOpacity(0.5), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Avatar with Photo & Camera Button
                    Stack(
                      children: [
                        GestureDetector(
                          onTap: _uploading ? null : _pickAndUploadPhoto,
                          child: Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withOpacity(0.2),
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                              image: _photoUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(_photoUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _uploading
                                ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                                : (_photoUrl == null
                                    ? Center(child: Icon(icon, size: 50, color: Colors.white))
                                    : null),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _uploading ? null : _pickAndUploadPhoto,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F766E),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.camera, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _uploading ? null : _pickAndUploadPhoto,
                      icon: const Icon(LucideIcons.imagePlus, size: 16),
                      label: Text(
                        _photoUrl != null ? 'Changer ma photo' : 'Ajouter ma photo de profil',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    // Matricule badge with Copy
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _employeeNumber));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Matricule $_employeeNumber copié !'), duration: const Duration(seconds: 1)),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.idCard, size: 14, color: Colors.white70),
                            const SizedBox(width: 8),
                            Text(
                              _employeeNumber,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                            ),
                            const SizedBox(width: 6),
                            const Icon(LucideIcons.copy, size: 12, color: Colors.white70),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Position Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.7)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            _jobTitle.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Access & Security Status Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(LucideIcons.shieldCheck, size: 18, color: Color(0xFF10B981)),
                        SizedBox(width: 8),
                        Text(
                          'Contrôle d’accès & Sécurité',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _StatusRow(
                      icon: _active ? LucideIcons.doorOpen : LucideIcons.ban,
                      color: _active ? const Color(0xFF10B981) : Colors.redAccent,
                      title: 'Statut Porte',
                      value: _active ? 'Accès Actif · Autorisé' : 'Accès Suspendu',
                    ),
                    const Divider(color: _borderColor, height: 24),
                    _StatusRow(
                      icon: LucideIcons.fingerprint,
                      color: _hasFingerprint ? const Color(0xFF10B981) : Colors.amber,
                      title: 'Empreinte biométrique',
                      value: _hasFingerprint
                          ? 'Enregistrée sur le terminal'
                          : 'Non enregistrée (Passez à la réception)',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Contact Info Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(LucideIcons.contact, size: 18, color: Color(0xFF38BDF8)),
                        SizedBox(width: 8),
                        Text(
                          'Coordonnées',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _StatusRow(
                      icon: LucideIcons.phone,
                      color: const Color(0xFF38BDF8),
                      title: 'Téléphone',
                      value: _employee['phone']?.toString().isNotEmpty == true
                          ? _employee['phone'].toString()
                          : 'Non renseigné',
                    ),
                    if (_employee['email']?.toString().isNotEmpty == true) ...[
                      const Divider(color: _borderColor, height: 24),
                      _StatusRow(
                        icon: LucideIcons.mail,
                        color: const Color(0xFF38BDF8),
                        title: 'Email',
                        value: _employee['email'].toString(),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Friendly Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF0F766E).withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.sparkles, color: Color(0xFF2DD4BF), size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Bonne prise de poste et bon travail au sein de l’équipe de votre salle de sport !',
                        style: TextStyle(color: Color(0xFF99F6E4), fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Sign Out Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: _borderColor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: widget.onSignOut,
                icon: const Icon(LucideIcons.logOut, size: 18),
                label: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: memberMuted, fontSize: 12)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
