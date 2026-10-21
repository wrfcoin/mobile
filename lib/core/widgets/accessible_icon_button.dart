import 'package:flutter/material.dart';

/// A wrapper around [IconButton] that enforces a minimum 48×48 tap target,
/// satisfying WCAG 2.5.5 (Target Size — Level AAA).
///
/// Use this in place of bare [IconButton] wherever the button does not already
/// carry sufficient padding from its parent (e.g. app-bar action rows,
/// standalone icon-only controls).
class AccessibleIconButton extends StatelessWidget {
  const AccessibleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.semanticsLabel,
    this.color,
    this.iconSize,
  });

  final Widget icon;
  final VoidCallback? onPressed;

  /// Shown in long-press tooltip and used as the default Semantics label.
  final String tooltip;

  /// Overrides the Semantics label when [tooltip] is not descriptive enough
  /// for screen-reader users (e.g. when the tooltip is abbreviated).
  final String? semanticsLabel;

  final Color? color;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel ?? tooltip,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: IconButton(
          tooltip: tooltip,
          icon: icon,
          onPressed: onPressed,
          color: color,
          iconSize: iconSize,
        ),
      ),
    );
  }
}
