import 'package:flutter/material.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/widgets/animated_switcher_semantics.dart';
import 'package:omninest/features/video/application/movie_controller.dart';

/// 影片资料库分区的方向感切换动画。
class MovieSectionTransition extends StatefulWidget {
  const MovieSectionTransition({
    required this.section,
    required this.child,
    this.slideDistance = 0.018,
    super.key,
  });

  final MovieSection section;
  final Widget child;
  final double slideDistance;

  @override
  State<MovieSectionTransition> createState() => _MovieSectionTransitionState();
}

class _MovieSectionTransitionState extends State<MovieSectionTransition> {
  int _direction = 1;

  @override
  void didUpdateWidget(covariant MovieSectionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _direction = widget.section.index >= oldWidget.section.index ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentKey = ValueKey<MovieSection>(widget.section);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: MotionToken.resolve(context, MotionToken.pageSwitch),
        reverseDuration: MotionToken.resolve(context, MotionToken.fast),
        switchInCurve: MotionToken.pageCurve,
        switchOutCurve: MotionToken.curveIn,
        layoutBuilder: (currentChild, previousChildren) {
          return excludeExitingSemanticsStack(
            currentChild,
            previousChildren,
            alignment: Alignment.topLeft,
          );
        },
        transitionBuilder: (child, animation) {
          final isIncoming = child.key == currentKey;
          final offset =
              widget.slideDistance * _direction * (isIncoming ? 1 : -0.65);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(offset, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(key: currentKey, child: widget.child),
      ),
    );
  }
}
