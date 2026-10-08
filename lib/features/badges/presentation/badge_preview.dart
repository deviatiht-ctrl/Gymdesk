import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../members/domain/member.dart';
import '../../settings/domain/gym_settings.dart';
import '../domain/badge_template.dart';

class BadgePreview extends StatelessWidget {
  const BadgePreview({
    super.key,
    required this.member,
    required this.gym,
    required this.template,
    required this.statusLabel,
    this.photo,
    this.logo,
  });
  final Member member;
  final GymSettings gym;
  final BadgeTemplate template;
  final String statusLabel;
  final Uint8List? photo;
  final Uint8List? logo;

  Color _accent() {
    final raw = template.accentColor.isEmpty
        ? gym.accentColor
        : template.accentColor;
    final value = int.tryParse(raw.replaceFirst('#', ''), radix: 16);
    return value == null ? const Color(0xff1f6f4a) : Color(0xff000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    final portrait = template.orientation == 'portrait';
    final content = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffd9e2dd)),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(width: 10, color: accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: portrait
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: _vertical(accent),
                    )
                  : Row(
                      children: [
                        if (template.showPhoto) _avatar(92),
                        if (template.showPhoto) const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: _text(accent),
                          ),
                        ),
                        if (template.showQr) ...[
                          const SizedBox(width: 16),
                          QrImageView(
                            data: member.qrPayload(gym.code),
                            version: QrVersions.auto,
                            size: 112,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
    return AspectRatio(
      aspectRatio: portrait ? 54 / 85.6 : 85.6 / 54,
      child: content,
    );
  }

  List<Widget> _vertical(Color accent) => [
    if (template.showPhoto) _avatar(108),
    if (template.showPhoto) const SizedBox(height: 14),
    ..._text(accent, centered: true),
    if (template.showQr) ...[
      const SizedBox(height: 12),
      Expanded(
        child: Center(
          child: QrImageView(
            data: member.qrPayload(gym.code),
            version: QrVersions.auto,
          ),
        ),
      ),
    ],
  ];

  List<Widget> _text(Color accent, {bool centered = false}) => [
    if (template.showGymName)
      Row(
        mainAxisSize: centered ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: centered
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          if (logo != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Image.memory(
                logo!,
                width: 22,
                height: 22,
                fit: BoxFit.contain,
              ),
            ),
          Flexible(
            child: Text(
              gym.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    const SizedBox(height: 8),
    Text(
      member.fullName,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: const TextStyle(
        fontSize: 23,
        fontWeight: FontWeight.w800,
        height: 1.05,
      ),
    ),
    const SizedBox(height: 5),
    Text(
      member.memberNumber,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xff52605a),
      ),
    ),
    if (template.showStatus)
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          statusLabel.toUpperCase(),
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: .7,
          ),
        ),
      ),
  ];

  Widget _avatar(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xffeef4f1),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    alignment: Alignment.center,
    child: photo == null
        ? Text(
            member.firstName.isEmpty
                ? '?'
                : member.firstName.substring(0, 1).toUpperCase(),
            style: TextStyle(
              fontSize: size * .36,
              fontWeight: FontWeight.w800,
              color: _accent(),
            ),
          )
        : Image.memory(photo!, width: size, height: size, fit: BoxFit.cover),
  );
}
