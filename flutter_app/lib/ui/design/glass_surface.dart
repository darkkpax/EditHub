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
    final fill = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(
          Colors.white.withValues(alpha: frost),
          AppColors.card.withValues(alpha: scrim),
        ),
        Color.alphaBlend(
          Colors.white.withValues(alpha: frost * .4),
          AppColors.bg.withValues(alpha: scrim * .82),
        ),
      ],
    );
    final content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: fill,
        borderRadius: corners,
        border: border
            ? Border.all(color: Colors.white.withValues(alpha: .16))
            : null,
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
            color: Colors.black.withValues(alpha: .45),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: glass,
    );
  }
}
