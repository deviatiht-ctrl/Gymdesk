import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../data/member_portal_repository.dart';
import 'member_ui.dart';

/// « Modifier mon profil » : le membre corrige lui-même sa fiche (photo,
/// téléphone, date de naissance, urgence…) — envoyé à member_portal_update_profile
/// qui n'accepte que des champs en liste blanche.
Future<bool> showMemberProfileSheet(
  BuildContext context, {
  required Map<String, dynamic> data,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _MemberProfileSheet(data: data),
    ),
  );
  return result == true;
}

class _MemberProfileSheet extends StatefulWidget {
  const _MemberProfileSheet({required this.data});
  final Map<String, dynamic> data;

  @override
  State<_MemberProfileSheet> createState() => _MemberProfileSheetState();
}

class _MemberProfileSheetState extends State<_MemberProfileSheet> {
  final _repo = MemberPortalRepository();
  late final Map<String, dynamic> _member =
      Map<String, dynamic>.from(widget.data['member'] as Map? ?? const {});
  String get _gymId => (Map<String, dynamic>.from(widget.data['gym'] as Map? ?? const {}))['id']?.toString() ?? '';

  late final _firstName = TextEditingController(text: _member['first_name']?.toString() ?? '');
  late final _lastName = TextEditingController(text: _member['last_name']?.toString() ?? '');
  late final _phone = TextEditingController(text: _member['phone']?.toString() ?? '');
  late final _whatsapp = TextEditingController(text: _member['whatsapp']?.toString() ?? '');
  late final _email = TextEditingController(text: _member['email']?.toString() ?? '');
  late final _address = TextEditingController(text: _member['address']?.toString() ?? '');
  late final _emergencyName = TextEditingController(text: _member['emergency_contact_name']?.toString() ?? '');
  late final _emergencyPhone = TextEditingController(text: _member['emergency_contact_phone']?.toString() ?? '');
  late final _guardian = TextEditingController(text: _member['guardian_name']?.toString() ?? '');
  late String? _sex = _member['sex']?.toString();
  late DateTime? _birth = DateTime.tryParse(_member['birth_date']?.toString() ?? '');
  Uint8List? _photoBytes;
  String? _photoUrl;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _phone, _whatsapp, _email, _address, _emergencyName, _emergencyPhone, _guardian]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPhoto() async {
    final url = await _repo.photoUrl(_member['photo_url'] as String?);
    if (mounted) setState(() => _photoUrl = url);
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        setState(() => _error = 'Photo trop lourde (5 Mo maximum).');
        return;
      }
      setState(() => _photoBytes = bytes);
    } catch (_) {
      setState(() => _error = 'Impossible de lire cette photo.');
    }
  }

  Future<void> _save() async {
    if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      setState(() => _error = 'Nom et prénom sont requis.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final patch = <String, dynamic>{
        'first_name': _firstName.text,
        'last_name': _lastName.text,
        'phone': _phone.text,
        'whatsapp': _whatsapp.text,
        'email': _email.text,
        'address': _address.text,
        'emergency_contact_name': _emergencyName.text,
        'emergency_contact_phone': _emergencyPhone.text,
        'guardian_name': _guardian.text,
        'sex': _sex,
        'birth_date': _birth == null
            ? ''
            : '${_birth!.year.toString().padLeft(4, '0')}-${_birth!.month.toString().padLeft(2, '0')}-${_birth!.day.toString().padLeft(2, '0')}',
      };
      final photo = _photoBytes;
      if (photo != null) {
        final path = '$_gymId/${_member['id']}/${const Uuid().v4()}.jpg';
        await _repo.uploadPhoto(path, photo);
        patch['photo_url'] = path;
      }
      final status = await _repo.updateProfile(_gymId, patch);
      if (!mounted) return;
      if (status == 'ok') {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = status == 'invalid'
            ? 'Une information est invalide. Vérifiez les champs.'
            : memberAuthError(status));
      }
    } catch (_) {
      if (mounted) setState(() => _error = memberAuthError('network'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = gymAccent((Map<String, dynamic>.from(widget.data['gym'] as Map? ?? const {}))['accent_color'] as String?);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .86,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Row(children: [
              Icon(LucideIcons.userRoundPen, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('Mon profil', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: memberInk))),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), children: [
              Center(
                child: Stack(children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: accent.withAlpha(28),
                    backgroundImage: _photoBytes != null
                        ? MemoryImage(_photoBytes!)
                        : (_photoUrl == null ? null : NetworkImage(_photoUrl!)),
                    child: _photoBytes == null && _photoUrl == null
                        ? Icon(LucideIcons.user, color: accent, size: 38)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Material(
                      color: accent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _busy ? null : _pickPhoto,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(LucideIcons.camera, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text('Touchez pour changer la photo', style: TextStyle(color: memberMuted, fontSize: 12)),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _field(_firstName, 'Prénom *', LucideIcons.user)),
                const SizedBox(width: 10),
                Expanded(child: _field(_lastName, 'Nom *', null)),
              ]),
              _field(_phone, 'Téléphone', LucideIcons.phone, type: TextInputType.phone),
              _field(_whatsapp, 'WhatsApp', LucideIcons.messageCircle, type: TextInputType.phone),
              _field(_email, 'Email sur la fiche (pas l’email de connexion)', LucideIcons.mail, type: TextInputType.emailAddress),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _birth ?? DateTime(2000),
                                firstDate: DateTime(1920),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) setState(() => _birth = picked);
                            },
                      icon: const Icon(LucideIcons.cake, size: 16),
                      label: Text(_birth == null ? 'Date de naissance' : fmtDate(_birth)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _sex,
                      decoration: const InputDecoration(labelText: 'Sexe', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'male', child: Text('Homme')),
                        DropdownMenuItem(value: 'female', child: Text('Femme')),
                        DropdownMenuItem(value: 'other', child: Text('Autre')),
                      ],
                      onChanged: _busy ? null : (v) => setState(() => _sex = v),
                    ),
                  ),
                ]),
              ),
              _field(_address, 'Adresse', LucideIcons.mapPin),
              _field(_emergencyName, 'Contact d’urgence (nom)', LucideIcons.siren),
              _field(_emergencyPhone, 'Contact d’urgence (téléphone)', LucideIcons.phoneCall, type: TextInputType.phone),
              _field(_guardian, 'Responsable (si mineur)', LucideIcons.shield),
              if (_error != null) ...[const SizedBox(height: 4), ErrorBox(_error!)],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(50)),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData? icon, {TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: type,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            prefixIcon: icon == null ? null : Icon(icon, size: 18),
          ),
        ),
      );
}
