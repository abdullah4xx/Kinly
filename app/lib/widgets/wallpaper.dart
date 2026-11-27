import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import 'settings_common.dart';

/// Built-in chat patterns. Every pattern is drawn with the current accent, so
/// changing the accent recolours the wallpaper too. `none` draws nothing.
const List<String> builtInWallpapers = [
  'none',
  'dunes',
  'grid',
  'waves',
  'dots',
  'rays',
  'terrain',
  'mesh',
  'aurora',
];

bool isCustomWallpaper(String id) => id.startsWith('file:');

/// Draws the wallpaper behind a chat. Custom photos are dimmed with a scrim so
/// message text keeps its contrast.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({
    super.key,
    required this.id,
    required this.child,
    this.scrim = 0.32,
  });

  final String id;
  final Widget child;
  final double scrim;

  @override
  Widget build(BuildContext context) {
    if (id == 'none' || id.isEmpty) return child;
    final accent = Theme.of(context).colorScheme.primary;
    Widget layer;
    if (isCustomWallpaper(id)) {
      final file = File(id.substring(5));
      if (!file.existsSync()) return child;
      layer = Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } else {
      layer = CustomPaint(painter: WallpaperPainter(id, accent));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: layer),
        ColoredBox(color: withOpacity(Colors.black, scrim)),
        child,
      ],
    );
  }
}

class WallpaperPainter extends CustomPainter {
  WallpaperPainter(this.id, this.accent);

  final String id;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = withOpacity(accent, 0.13);
    final fill = Paint()..color = withOpacity(accent, 0.07);
    switch (id) {
      case 'dunes':
        for (var row = 0; row < 7; row++) {
          final path = Path();
          final base = size.height * (row + 1) / 8;
          path.moveTo(0, base);
          for (var x = 0.0; x <= size.width; x += 8) {
            path.lineTo(
              x,
              base + math.sin((x / size.width * 2.4 + row) * math.pi) * 26,
            );
          }
          canvas.drawPath(path, paint);
        }
      case 'grid':
        const step = 34.0;
        for (var x = 0.0; x <= size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (var y = 0.0; y <= size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case 'waves':
        final center = Offset(size.width / 2, size.height / 2);
        for (var radius = 30.0; radius < size.longestSide; radius += 34) {
          canvas.drawCircle(center, radius, paint);
        }
      case 'dots':
        const step = 26.0;
        for (var y = step / 2; y < size.height; y += step) {
          for (var x = step / 2; x < size.width; x += step) {
            canvas.drawCircle(Offset(x, y), 1.6, fill);
          }
        }
      case 'rays':
        final center = Offset(size.width / 2, size.height * 0.42);
        for (var index = 0; index < 28; index++) {
          final angle = index * math.pi * 2 / 28;
          canvas.drawLine(
            center,
            center +
                Offset(math.cos(angle), math.sin(angle)) * size.longestSide,
            paint,
          );
        }
      case 'terrain':
        for (var row = 0; row < 9; row++) {
          final path = Path();
          final base = size.height * row / 8;
          path.moveTo(-20, base);
          for (var x = -20.0; x <= size.width + 20; x += 6) {
            final wave = math.sin(x / 46 + row) * 14 + math.cos(x / 23) * 6;
            path.lineTo(x, base + wave);
          }
          canvas.drawPath(path, paint);
        }
      case 'mesh':
        for (var offset = -size.height; offset < size.width; offset += 30) {
          canvas.drawLine(
            Offset(offset, size.height),
            Offset(offset + size.height, 0),
            paint,
          );
        }
        for (var offset = 0.0; offset < size.width + size.height; offset += 30) {
          canvas.drawLine(Offset(offset, 0), Offset(offset - size.height, size.height), paint);
        }
      case 'aurora':
        for (var index = 0; index < 5; index++) {
          final center = Offset(
            size.width * (0.18 + index * 0.19),
            size.height * (0.22 + (index.isEven ? 0.1 : 0.45)),
          );
          canvas.drawCircle(
            center,
            size.shortestSide * (0.3 + index * 0.03),
            Paint()
              ..shader = RadialGradient(
                colors: [
                  withOpacity(accent, 0.12),
                  withOpacity(accent, 0),
                ],
              ).createShader(
                Rect.fromCircle(
                  center: center,
                  radius: size.shortestSide * 0.4,
                ),
              ),
          );
        }
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(WallpaperPainter oldDelegate) =>
      oldDelegate.id != id || oldDelegate.accent != accent;
}

/// Lets the user pick a built-in pattern, a gallery photo, or the default.
class WallpaperPicker extends StatelessWidget {
  const WallpaperPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final id in builtInWallpapers)
              _Swatch(
                id: id,
                label: id == 'none'
                    ? strings.get('wallpaperNone')
                    : id,
                selected: selected == id,
                accent: accent,
                onTap: () => onSelected(id),
              ),
            if (isCustomWallpaper(selected))
              _Swatch(
                id: selected,
                label: strings.get('wallpaperCustom'),
                selected: true,
                accent: accent,
                onTap: () => onSelected(selected),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsLinkRow(
          icon: Icons.photo_library_outlined,
          title: strings.get('wallpaperCustom'),
          subtitle: strings.get('wallpaperBody'),
          onTap: () async {
            final picked = await pickWallpaperImage();
            if (picked != null) onSelected('file:$picked');
          },
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.id,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String id;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final custom = isCustomWallpaper(id);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: Tokens.surfaceHigh,
            borderRadius: BorderRadius.circular(Tokens.radiusMedium),
            border: Border.all(
              color: selected ? accent : withOpacity(Colors.white, 0.05),
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (id == 'none')
                const Icon(
                  Icons.block_rounded,
                  color: Tokens.textMuted,
                  size: 20,
                )
              else if (custom)
                Image.file(
                  File(id.substring(5)),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Tokens.textMuted,
                    size: 18,
                  ),
                )
              else
                CustomPaint(painter: WallpaperPainter(id, accent)),
              if (selected)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks a gallery photo and copies it into the app's private directory.
Future<String?> pickWallpaperImage() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  try {
    final directory = await getApplicationSupportDirectory();
    final folder = Directory('${directory.path}/wallpapers');
    await folder.create(recursive: true);
    final extension = picked.path.split('.').last;
    final target =
        '${folder.path}/wallpaper-${DateTime.now().millisecondsSinceEpoch}.$extension';
    await File(picked.path).copy(target);
    return target;
  } catch (_) {
    return null;
  }
}
