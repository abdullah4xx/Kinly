import 'package:flutter/material.dart';

import 'tokens.dart';

/// A raised or sunken neumorphic surface.
///
/// Raised surfaces use a dark shadow to the bottom-right and a light one to the
/// top-left. Sunken surfaces invert the shadows and add a soft inner gradient,
/// which is how the search field and message input look in the reference.
class Neu extends StatelessWidget {
  const Neu({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.radius = Tokens.radiusLarge,
    this.inset = false,
    this.accent = false,
    this.color,
    this.depth = 1,
    this.width,
    this.height,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final bool inset;
  final bool accent;
  final Color? color;
  final double depth;
  final double? width;
  final double? height;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    final surface = color ?? Tokens.surface;
    final base = accent ? accentColor : surface;

    final shadows = inset
        ? <BoxShadow>[
            BoxShadow(
              color: withOpacity(Tokens.shadowDark, 0.55),
              offset: const Offset(-4, -4),
              blurRadius: 10 * depth,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: withOpacity(Tokens.shadowLight, 0.35),
              offset: const Offset(5, 5),
              blurRadius: 12 * depth,
              spreadRadius: -3,
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: withOpacity(Tokens.shadowDark, accent ? 0.85 : 0.7),
              offset: Offset(6 * depth, 6 * depth),
              blurRadius: 14 * depth,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: withOpacity(Tokens.shadowLight, accent ? 0.55 : 0.5),
              offset: Offset(-5 * depth, -5 * depth),
              blurRadius: 12 * depth,
              spreadRadius: -3,
            ),
            if (accent)
              BoxShadow(
                color: withOpacity(accentColor, 0.28),
                blurRadius: 22,
                spreadRadius: 1,
              ),
          ];

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: base,
        border: border,
        boxShadow: shadows,
        gradient: inset
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: accent
                    ? [
                        withOpacity(Colors.black, 0.18),
                        base,
                        withOpacity(Colors.white, 0.08),
                      ]
                    : [
                        withOpacity(Tokens.shadowDark, 0.55),
                        withOpacity(surface, 0.92),
                        withOpacity(Tokens.shadowLight, 0.5),
                      ],
                stops: const [0, 0.55, 1],
              )
            : null,
      ),
      child: child,
    );
  }
}

/// Round neumorphic icon button with a press "sink" animation.
class NeuIconButton extends StatefulWidget {
  const NeuIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 52,
    this.iconSize = 22,
    this.accent = false,
    this.color,
    this.tooltip,
    this.inset = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool accent;
  final Color? color;
  final String? tooltip;
  final bool inset;

  @override
  State<NeuIconButton> createState() => _NeuIconButtonState();
}

class _NeuIconButtonState extends State<NeuIconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    final enabled = widget.onPressed != null;
    final iconColor = widget.accent
        ? readableOn(accentColor)
        : enabled
        ? Tokens.textPrimary
        : Tokens.textMuted;

    final button = GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              widget.onPressed?.call();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        child: Neu(
          width: widget.size,
          height: widget.size,
          radius: Tokens.radiusRound,
          inset: _down || widget.inset,
          accent: widget.accent,
          color: widget.color,
          child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
        ),
      ),
    );

    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

/// Primary action button (Enter, Save, ...).
class AccentButton extends StatefulWidget {
  const AccentButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool busy;

  @override
  State<AccentButton> createState() => _AccentButtonState();
}

class _AccentButtonState extends State<AccentButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final onAccent = readableOn(accent);
    final enabled = widget.onPressed != null && !widget.busy;
    final button = GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              widget.onPressed?.call();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 90),
        child: Neu(
          radius: Tokens.radiusLarge,
          accent: true,
          depth: _down ? 0.2 : 1,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          color: enabled ? null : withOpacity(accent, 0.45),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: onAccent,
                  ),
                )
              else if (widget.icon != null)
                Icon(widget.icon, size: 20, color: onAccent),
              if (widget.busy || widget.icon != null) const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return button;
  }
}

/// A small pill used for unread counts and statuses.
class AccentPill extends StatelessWidget {
  const AccentPill({
    super.key,
    required this.label,
    this.accent = true,
    this.compact = false,
  });

  final String label;
  final bool accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    final background = accent ? accentColor : Tokens.surfaceHigh;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Tokens.radiusRound),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent ? readableOn(accentColor) : Tokens.textSecondary,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Thin neumorphic switch used for visibility and settings toggles.
class NeuToggle extends StatelessWidget {
  const NeuToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 44,
    this.height = 26,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Neu(
        width: width,
        height: height,
        radius: Tokens.radiusRound,
        inset: !value,
        accent: value,
        depth: 0.5,
        padding: const EdgeInsets.all(4),
        child: AnimatedAlign(
          alignment: value
              ? (Directionality.of(context) == TextDirection.rtl
                    ? Alignment.centerLeft
                    : Alignment.centerRight)
              : (Directionality.of(context) == TextDirection.rtl
                    ? Alignment.centerRight
                    : Alignment.centerLeft),
          curve: Curves.easeOutCubic,
          duration: const Duration(milliseconds: 180),
          child: Container(
            width: height - 8,
            height: height - 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? readableOn(accent) : Tokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
