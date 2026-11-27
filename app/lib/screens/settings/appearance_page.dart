import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/node_controller.dart';
import '../../theme/neu.dart';
import '../../theme/tokens.dart';
import '../../widgets/settings_common.dart';
import '../../widgets/wallpaper.dart';

/// Accent color, custom color, motion and the default chat wallpaper.
class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key, required this.controller});

  final NodeController controller;

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  HSVColor? _custom;
  bool _customOpen = false;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final settings = widget.controller.settings;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final accent = settings.accent;
        return SettingsPageBody(
          title: strings.get('appearance'),
          children: [
            SettingsSectionTitle(text: strings.get('accentColor')),
            const SizedBox(height: 8),
            Text(
              strings.get('accentBody'),
              style: const TextStyle(
                color: Tokens.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final preset in Tokens.accentPresets)
                  _AccentSwatch(
                    color: preset.color,
                    selected: accent.toARGB32() == preset.color.toARGB32(),
                    onTap: () => settings.setAccent(preset.color),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _CustomColor(
              open: _customOpen,
              value: _custom ?? HSVColor.fromColor(accent),
              onToggle: () => setState(() => _customOpen = !_customOpen),
              onChanged: (value) {
                setState(() => _custom = value);
                if (!accentTooClose(value.toColor())) {
                  settings.setAccent(value.toColor());
                }
              },
            ),
            if (accentTooClose((_custom ?? HSVColor.fromColor(accent)).toColor()))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  strings.get('colorTooClose'),
                  style: const TextStyle(
                    color: Tokens.danger,
                    fontSize: 11.5,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            _AppearancePreview(accent: accent, strings: strings),
            const SizedBox(height: 26),
            SettingsSectionTitle(text: strings.get('wallpaper')),
            const SizedBox(height: 8),
            Text(
              strings.get('wallpaperBody'),
              style: const TextStyle(
                color: Tokens.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            WallpaperPicker(
              selected: settings.wallpaper,
              onSelected: settings.setWallpaper,
            ),
            const SizedBox(height: 26),
            SettingsSectionTitle(text: strings.get('settings')),
            const SizedBox(height: 10),
            Neu(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              child: SettingsToggleRow(
                icon: Icons.motion_photos_off_rounded,
                title: strings.get('reduceMotion'),
                subtitle: strings.get('reduceMotionBody'),
                value: settings.reduceMotion,
                onChanged: settings.setReduceMotion,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected ? Tokens.textPrimary : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: withOpacity(color, 0.35),
                blurRadius: selected ? 14 : 6,
                spreadRadius: selected ? 1 : 0,
              ),
            ],
          ),
          child: selected
              ? Icon(Icons.check_rounded, size: 20, color: readableOn(color))
              : null,
        ),
      ),
    );
  }
}

class _CustomColor extends StatelessWidget {
  const _CustomColor({
    required this.open,
    required this.value,
    required this.onToggle,
    required this.onChanged,
  });

  final bool open;
  final HSVColor value;
  final VoidCallback onToggle;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final color = value.toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: withOpacity(Colors.white, 0.2),
                    width: 1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                strings.get('customColor'),
                style: const TextStyle(
                  color: Tokens.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 18,
                color: Tokens.textMuted,
              ),
            ],
          ),
        ),
        if (open) ...[
          const SizedBox(height: 6),
          _ColorSlider(
            label: strings.get('hue'),
            value: value.hue,
            max: 360,
            color: color,
            onChanged: (hue) => onChanged(value.withHue(hue)),
          ),
          _ColorSlider(
            label: strings.get('saturation'),
            value: value.saturation,
            max: 1,
            color: color,
            onChanged: (saturation) =>
                onChanged(value.withSaturation(saturation)),
          ),
          _ColorSlider(
            label: strings.get('preview'),
            value: value.value,
            max: 1,
            color: color,
            onChanged: (brightness) => onChanged(value.withValue(brightness)),
          ),
        ],
      ],
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(color: Tokens.textMuted, fontSize: 11),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: color,
              inactiveTrackColor: withOpacity(Colors.white, 0.08),
              thumbColor: color,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(0, max),
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({required this.accent, required this.strings});

  final Color accent;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final onAccent = readableOn(accent);
    return Neu(
      inset: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.get('preview'),
            style: const TextStyle(color: Tokens.textMuted, fontSize: 10.5),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Tokens.surfaceHigh,
                borderRadius: BorderRadius.circular(Tokens.radiusMedium),
              ),
              child: Text(
                strings.get('noMessagesBody'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Tokens.textPrimary,
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(Tokens.radiusMedium),
              ),
              child: Text(
                strings.get('typing'),
                style: TextStyle(color: onAccent, fontSize: 11.5),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const AccentPill(label: '3'),
              const SizedBox(width: 10),
              Icon(Icons.mic_rounded, size: 18, color: accent),
              const SizedBox(width: 10),
              Icon(Icons.call_rounded, size: 18, color: accent),
              const Spacer(),
              Text(
                strings.get('online'),
                style: TextStyle(color: accent, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
