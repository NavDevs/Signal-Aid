import 'package:flutter/material.dart';

/// Staggered entrance: fades and slides the child up after [delay].
///
/// Wrap static screen sections (headers, cards, forms) to get the cascading
/// "rise in" effect. Elements that stay mounted keep their finished state, so
/// data refreshes do not replay the animation. Respects reduced-motion
/// settings by appearing instantly.
class StaggerIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;

  const StaggerIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offset = const Offset(0, 0.06),
  });

  /// Convenience for list items: cascade up to [maxDelayMs] across [index].
  factory StaggerIn.index({
    Key? key,
    required int index,
    required Widget child,
    int stepMs = 45,
    int maxDelayMs = 360,
  }) {
    final delayMs = (index * stepMs).clamp(0, maxDelayMs);
    return StaggerIn(
      key: key,
      delay: Duration(milliseconds: delayMs),
      child: child,
    );
  }

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _opacity = curved;
    _slide = Tween<Offset>(begin: widget.offset, end: Offset.zero).animate(curved);
    if (widget.delay == Duration.zero) {
      _controller.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.delay == Duration.zero) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _controller.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
