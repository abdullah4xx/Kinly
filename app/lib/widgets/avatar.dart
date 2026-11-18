import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Round avatar with a soft neumorphic ring, optional photo and online dot.
class KinlyAvatar extends StatelessWidget {
  const KinlyAvatar({
    super.key,
    required this.name,
    this.avatarBase64,
    this.size = 52,
    this.online = false,
    this.showDot = true,
    this.muted = false,
  });

  final String name;
  final String? avatarBase64;
  final double size;
  final bool online;
  final bool showDot;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final initials = _initials(name);
    final image = _decode(avatarBase64);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Tokens.surface,
              boxShadow: [
                BoxShadow(
                  color: withOpacity(Tokens.shadowDark, 0.65),
                  offset: const Offset(3, 3),
                  blurRadius: 8,
                ),
                BoxShadow(
                  color: withOpacity(Tokens.shadowLight, 0.45),
                  offset: const Offset(-2, -2),
                  blurRadius: 6,
                ),
              ],
            ),
            padding: const EdgeInsets.all(2.5),
            child: ClipOval(
              child: image != null
                  ? Image.memory(
                      image,
                      fit: BoxFit.cover,
                      width: size,
                      height: size,
                      gaplessPlayback: true,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            withOpacity(accent, muted ? 0.25 : 0.55),
                            withOpacity(accent, muted ? 0.1 : 0.25),
                          ],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: muted
                              ? Tokens.textSecondary
                              : Tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: size * 0.32,
                        ),
                      ),
                    ),
            ),
          ),
          if (showDot)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: size * 0.24,
                height: size * 0.24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? Tokens.success : Tokens.textMuted,
                  border: Border.all(color: Tokens.background, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Uint8List? _decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final raw = value.contains(',') ? value.split(',').last : value;
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  static String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return parts
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
  }
}
