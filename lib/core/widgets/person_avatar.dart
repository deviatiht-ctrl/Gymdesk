import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/local_database.dart';
import '../storage/person_photo_cache.dart';

/// Avatar circulaire uniforme avec chargement local, Storage privé Supabase et cache mémoire.
class PersonAvatar extends StatefulWidget {
  const PersonAvatar({
    super.key,
    required this.size,
    this.personId,
    this.photoUrl,
    this.name,
    this.db,
    this.client,
    this.initialBytes,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 0,
    this.shadows,
    this.fallbackIcon,
    this.fallbackColor,
    this.iconSize,
    this.initialsStyle,
    this.preferIconFallback = false,
  });

  final double size;
  final String? personId;
  final String? photoUrl;
  final String? name;
  final LocalDatabase? db;
  final SupabaseClient? client;
  final Uint8List? initialBytes;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? shadows;
  final IconData? fallbackIcon;
  final Color? fallbackColor;
  final double? iconSize;
  final TextStyle? initialsStyle;
  final bool preferIconFallback;

  @override
  State<PersonAvatar> createState() => _PersonAvatarState();
}

class _PersonAvatarState extends State<PersonAvatar> {
  Uint8List? _bytes;
  Object? _lastLookupKey;

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes ??
        PersonPhotoCache.peek(personId: widget.personId, photoUrl: widget.photoUrl);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PersonAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialBytes != oldWidget.initialBytes) {
      if (widget.initialBytes != null && widget.initialBytes!.isNotEmpty) {
        _bytes = widget.initialBytes;
      } else if (widget.personId != oldWidget.personId || widget.photoUrl != oldWidget.photoUrl) {
        _bytes = PersonPhotoCache.peek(personId: widget.personId, photoUrl: widget.photoUrl);
      }
    }
    if (widget.personId != oldWidget.personId ||
        widget.photoUrl != oldWidget.photoUrl ||
        (widget.initialBytes == null && oldWidget.initialBytes != null)) {
      _bytes = widget.initialBytes ??
          PersonPhotoCache.peek(personId: widget.personId, photoUrl: widget.photoUrl);
      unawaited(_load(force: true));
    }
  }

  Future<void> _load({bool force = false}) async {
    final key = '${widget.personId ?? ''}|${widget.photoUrl ?? ''}';
    if (!force && _lastLookupKey == key && _bytes != null) return;
    _lastLookupKey = key;

    final bytes = widget.initialBytes ??
        await PersonPhotoCache.resolve(
          personId: widget.personId,
          photoUrl: widget.photoUrl,
          db: widget.db,
          client: widget.client,
        );
    if (!mounted) return;
    final currentKey = '${widget.personId ?? ''}|${widget.photoUrl ?? ''}';
    if (currentKey != key) return;
    if (bytes != null && bytes.isNotEmpty) {
      setState(() => _bytes = bytes);
    }
  }

  String _initials() {
    final n = widget.name?.trim() ?? '';
    if (n.isEmpty) return '';
    return n
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.initialBytes ?? _bytes;
    final bg = widget.backgroundColor ?? Theme.of(context).colorScheme.primaryContainer;
    final fg = widget.fallbackColor ?? Theme.of(context).colorScheme.onPrimaryContainer;
    final initials = _initials();

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        boxShadow: widget.shadows,
      ),
      foregroundDecoration: widget.borderWidth > 0 && widget.borderColor != null
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: widget.borderColor!, width: widget.borderWidth),
            )
          : null,
      child: ClipOval(
        child: bytes != null && bytes.isNotEmpty
            ? Image.memory(
                bytes,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _fallback(initials, fg),
              )
            : _fallback(initials, fg),
      ),
    );
  }

  Widget _fallback(String initials, Color fg) {
    if (!widget.preferIconFallback && initials.isNotEmpty) {
      return Center(
        child: Text(
          initials,
          style: widget.initialsStyle ??
              TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: (widget.size * 0.36).clamp(12.0, 64.0),
              ),
        ),
      );
    }
    return Center(
      child: Icon(
        widget.fallbackIcon ?? LucideIcons.user,
        color: fg,
        size: widget.iconSize ?? (widget.size * 0.48).clamp(16.0, 84.0),
      ),
    );
  }
}
