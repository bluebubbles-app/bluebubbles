import 'dart:ui';

import 'package:flutter/cupertino.dart';

import '../theme/messages_theme.dart';

/// A restrained iOS 26-style glass surface. The blur is clipped to the exact
/// control bounds so scrolling content outside the control is not repainted.
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.borderRadius,
    required this.child,
    this.blurSigma = 18,
    this.transparency = 1,
    this.padding = EdgeInsets.zero,
    this.boxShadows,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final double blurSigma;
  final double transparency;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow>? boxShadows;

  @override
  Widget build(BuildContext context) {
    final isDark = MessagesPalette.isDark(context);
    final strength = transparency.clamp(0.0, 1.0);
    final tint = isDark
        ? CupertinoColors.black.withValues(
            alpha: lerpDouble(.94, .42, strength)!,
          )
        : CupertinoColors.white.withValues(
            alpha: lerpDouble(.96, .58, strength)!,
          );
    final highlight = isDark
        ? CupertinoColors.white.withValues(alpha: .18)
        : CupertinoColors.white.withValues(alpha: .82);

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: boxShadows ??
              [
                BoxShadow(
                  color: CupertinoColors.black.withValues(alpha: .11),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 5),
                ),
              ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: blurSigma,
              sigmaY: blurSigma,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tint,
                borderRadius: borderRadius,
                border: Border.all(color: highlight, width: .75),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    highlight.withValues(alpha: .48),
                    tint,
                    tint.withValues(alpha: .72),
                  ],
                  stops: const [0, .42, 1],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
