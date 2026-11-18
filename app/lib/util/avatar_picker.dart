import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;

/// Picks a photo and shrinks it so the base64 avatar fits inside one Noise
/// frame (the whole HELLO must stay below 65,519 bytes).
Future<String?> pickAvatarBase64() async {
  const typeGroup = XTypeGroup(
    label: 'Images',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
  );
  final file = await openFile(acceptedTypeGroups: const [typeGroup]);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return resizeAvatarBase64(bytes);
}

/// Decodes, crops to a square and encodes a 256px JPEG (about 8-20 KiB).
String? resizeAvatarBase64(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final square = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final resized = img.copyResize(square, width: 256, height: 256);
  final jpeg = img.encodeJpg(resized, quality: 82);
  return base64Encode(jpeg);
}
