import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/member.dart';

Uint8List encodeMemberPhoto(Uint8List source, {bool portrait = false}) {
  final decoded = img.decodeImage(source);
  if (decoded == null) throw const MemberFailure('invalid_photo');
  final targetRatio = portrait ? 3 / 4 : 1.0;
  var cropWidth = decoded.width;
  var cropHeight = decoded.height;
  if (decoded.width / decoded.height > targetRatio) {
    cropWidth = (decoded.height * targetRatio).round();
  } else {
    cropHeight = (decoded.width / targetRatio).round();
  }
  final x = ((decoded.width - cropWidth) / 2).round();
  final y = ((decoded.height - cropHeight) / 2).round();
  var image = img.copyCrop(
    decoded,
    x: x,
    y: y,
    width: cropWidth,
    height: cropHeight,
  );
  if (image.width > 800 || image.height > 800) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 800 : null,
      height: image.height > image.width ? 800 : null,
    );
  }
  final encoded = img.encodeJpg(image, quality: 80);
  if (encoded.length > 5 * 1024 * 1024) {
    throw const MemberFailure('invalid_photo');
  }
  return Uint8List.fromList(encoded);
}
