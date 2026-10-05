import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Shared frosted surface ported from JumperCut's proven Flutter glass layer.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.blur = 26,
    this.radius = AppColors.radius,
    this.borderRadius,
    this.padding,
    this.scrim = .30,
    this.frost = .12,
    this.border = true,
    this.shadow = false,
  });

  final Widget child;
  final double blur;
  final double radius;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final double scrim;
  final double frost;
  final bool border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final corners = borderRadius ?? BorderRadius.circular(radius);
    final palette = AppColors.of(context);
    final fill = palette.card.withValues(alpha: (scrim + .48).clamp(0, .96));
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: corners,
        border: border ? Border.all(color: palette.sep) : null,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    final glass = ClipRRect(
      borderRadius: corners,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
      ),
    );
    if (!shadow) return glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.light ? .12 : .32),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: glass,
    );
  }
}
