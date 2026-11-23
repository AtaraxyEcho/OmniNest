part of 'router.dart';

/// 音乐沉浸播放页专属上滑淡入（500ms）与下滑淡出（320ms）。
GoRoute _desktopNowPlayingRoute(
  String path,
  Widget Function(GoRouterState state) builder, {
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    path: path,
    parentNavigatorKey: parentNavigatorKey,
    pageBuilder: (context, state) {
      final child = routeSurface(path, builder(state));
      if (!_isDesktopRouteContext(context)) {
        return NoTransitionPage<void>(key: state.pageKey, child: child);
      }
      return CustomTransitionPage<void>(
        key: state.pageKey,
        transitionDuration: DesktopMotion.nowPlayingIn,
        reverseTransitionDuration: DesktopMotion.nowPlayingOut,
        child: DesktopImmersiveOverlay(
          path: state.uri.toString(),
          child: child,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
            return child;
          }
          final curved = CurvedAnimation(
            parent: animation,
            curve: DesktopMotion.ease,
            reverseCurve: DesktopMotion.exitCurve,
          );
          return FadeTransition(
            opacity: curved,
            alwaysIncludeSemantics: true,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          );
        },
      );
    },
  );
}

Page<void> _immersiveTransitionPage(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  required Duration duration,
  String? photoTransitionId,
}) {
  final isDesktop = _isDesktopRouteContext(context);
  final wrapped =
      isDesktop
          ? DesktopImmersiveOverlay(path: state.uri.toString(), child: child)
          : child;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    child: wrapped,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        return child;
      }
      if (isDesktop && photoTransitionId != null) {
        return DesktopPhotoViewerTransition(
          initialPhotoId: photoTransitionId,
          animation: animation,
          child: child,
        );
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: DesktopMotion.ease,
        reverseCurve: DesktopMotion.exitCurve,
      );
      return FadeTransition(
        opacity: curved,
        alwaysIncludeSemantics: true,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 全局查看器（Video / Reader / Comic / PhotoViewer）的柔和缩放淡入淡出路由。
GoRoute _desktopViewerRoute(
  String path,
  Widget Function(GoRouterState state) builder, {
  required Duration duration,
  GlobalKey<NavigatorState>? parentNavigatorKey,
  String Function(GoRouterState state)? photoTransitionIdBuilder,
}) {
  return GoRoute(
    path: path,
    parentNavigatorKey: parentNavigatorKey,
    pageBuilder:
        (context, state) => _immersiveTransitionPage(
          context,
          state,
          routeSurface(path, builder(state)),
          duration: duration,
          photoTransitionId: photoTransitionIdBuilder?.call(state),
        ),
  );
}
