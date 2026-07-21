import 'dart:async';

import 'package:flutter/material.dart';

/// Shared iOS-like motion curves. `spring` overshoots slightly then settles;
/// `springSoft` is a gentler settle with no visible bounce.
class AppCurves {
  AppCurves._();
  static const spring = Cubic(0.34, 1.42, 0.5, 1.0);
  static const springSoft = Cubic(0.22, 1.0, 0.36, 1.0);
}

/// Whether the OS asks for reduced motion (Windows "Show animations" off, or
/// the equivalent accessibility switch on other platforms).
///
/// Reduced motion does not mean *no* feedback — it means no spatial travel and
/// no overshoot. Callers keep opacity changes and drop slides/scales.
bool prefersReducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = .94,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;
  bool get _active => widget.enabled && widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    // Under reduced motion the press still gives feedback, but without the
    // scale travel and without the spring's overshoot.
    final reduced = prefersReducedMotion(context);
    return MouseRegion(
      cursor: _active ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _active ? widget.onTap : null,
        onTapDown: _active ? (_) => setState(() => _down = true) : null,
        onTapUp: _active ? (_) => setState(() => _down = false) : null,
        onTapCancel: _active ? () => setState(() => _down = false) : null,
        child: AnimatedScale(
          scale: _down && !reduced ? widget.pressedScale : 1,
          duration: reduced
              ? Duration.zero
              : Duration(milliseconds: _down ? 90 : 260),
          curve: _down ? Curves.easeOut : AppCurves.spring,
          child: AnimatedOpacity(
            opacity: _down && reduced ? .72 : 1,
            duration: const Duration(milliseconds: 90),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class FadeInUp extends StatefulWidget {
  const FadeInUp({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 10,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;

  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp>
    with SingleTickerProviderStateMixin {
  Timer? _delayTimer;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: AppCurves.springSoft,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, _controller.forward);
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion keeps the fade (it aids comprehension) but drops the
    // upward travel, which is the vestibular part.
    final reduced = prefersReducedMotion(context);
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final faded = Opacity(opacity: _animation.value, child: child);
        if (reduced) return faded;
        return Transform.translate(
          offset: Offset(0, widget.offset * (1 - _animation.value)),
          child: faded,
        );
      },
      child: widget.child,
    );
  }
}
