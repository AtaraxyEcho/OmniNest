part of 'desktop_shell.dart';

class _DesktopImmersiveCanvas extends ConsumerWidget {
  const _DesktopImmersiveCanvas({
    required this.path,
    required this.ambientImage,
    required this.child,
  });

  final String path;
  final String? ambientImage;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final backdropConfigured = ref.watch(
      appBackdropControllerProvider.select(
        (async) => async.asData?.value.hasActiveBackdrop ?? false,
      ),
    );
    final backdropScope = ref.watch(desktopBackdropScopeProvider);
    final backdropActive =
        backdropConfigured &&
        desktopBackdropAppliesToRoute(backdropScope, path);
    return BackdropGroup(
      // 所有沉浸路由统一包裹 DesktopWindowFrame（恢复四边+四角边缘缩放），
      // 并在 child 底层贴顶铺设 64px 兜底拖拽区，确保阅读器/播放器自动隐藏顶栏时仍可拖动窗口与双击最大化。
      child: DesktopWindowFrame(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: skin.bg),
            if (backdropActive)
              DesktopBackdropLayer(path: path)
            else
              _AmbientLayer(imageUrl: ambientImage),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 64,
              child: DesktopWindowDragRegion(child: SizedBox.expand()),
            ),
            child,
            const DesktopToasts(),
          ],
        ),
      ),
    );
  }
}

/// 环境光层：只订阅「强度」与「减动效」两位。
///
/// 外观抽屉与设置页的强度滑杆每拖一格都会写一次外观偏好；若在 `_Workspace`
/// 里 watch 整份外观，整条壳层（标题栏、侧栏、内容区、播放条）会跟着每帧
/// 重建，而真正要变的只有这一层的整层 opacity。
class _AmbientLayer extends ConsumerWidget {
  const _AmbientLayer({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intensity = ref.watch(
      desktopAppearanceProvider.select((appearance) => appearance.ambient),
    );
    final reduceMotion = ref.watch(
      desktopAppearanceProvider.select((appearance) => appearance.reduceMotion),
    );
    return DesktopAmbient(
      imageUrl: imageUrl,
      intensity: intensity,
      reduceMotion: reduceMotion,
    );
  }
}

bool _isShellBranchPath(String rawPath) {
  final path = Uri.tryParse(rawPath)?.path ?? rawPath.split('?').first;
  return path == '/portal' ||
      path == '/library' ||
      path == '/files' ||
      path == '/reader' ||
      path == '/reader/bookshelf' ||
      path == '/reader/stats' ||
      path == '/reader/admin';
}

/// 页面入场（样例 `.route`）：opacity + 12px translateY + 0.992 scale，
/// 彻底移除每帧全屏 `ImageFilter.blur` 与 build 期重复构造 `CurvedAnimation`。
///
/// 一级壳层分支间切换由 `MobileAppShell` 桌面分支同步承载，避免双层叠动画；
/// 本层负责顶部 2px 路由进度条及非分支主路由的丝滑入场。
class _RouteEnter extends StatefulWidget {
  const _RouteEnter({required this.path, required this.child});

  final String path;
  final Widget child;

  @override
  State<_RouteEnter> createState() => _RouteEnterState();
}

class _RouteEnterState extends State<_RouteEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesktopMotion.route,
    value: 1,
  );
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: DesktopMotion.ease,
  );

  /// 路由正在切换：入场动画期间顶栏扫一条 2px 进度条（样例 `.route-load`）。
  bool _loading = false;

  /// 一级分支间切换由内层 `_DesktopBranchTransition` 承载内容过渡，本层仅播进度条。
  bool _animateContent = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onEnterStatus);
  }

  void _onEnterStatus(AnimationStatus status) {
    // 状态回调发生在 ticker 里，不在构建期，可以安全 setState。
    if (!mounted) {
      return;
    }
    final loading = status == AnimationStatus.forward;
    if (loading != _loading) {
      setState(() {
        _loading = loading;
        if (!loading) {
          _animateContent = false;
        }
      });
    }
  }

  @override
  void didUpdateWidget(_RouteEnter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path == widget.path) {
      return;
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _loading = false;
      _animateContent = false;
      _controller.value = 1;
      return;
    }
    final bothBranches =
        _isShellBranchPath(oldWidget.path) && _isShellBranchPath(widget.path);
    // 这里不能 setState：`forward()` 会同步派发状态回调，而 didUpdateWidget
    // 处在构建期。直接改字段，靠本次重建把进度条画出来。
    _loading = true;
    _animateContent = !bothBranches;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onEnterStatus);
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 崩溃边界与进度条挂在动画**外面**：放进 builder 里会让
    // `DesktopErrorBoundary.build` 在入场的每一帧去接管并还原全局
    // `ErrorWidget.builder`。
    return DesktopRouteContainer(
      path: widget.path,
      loading: _loading,
      child: AnimatedBuilder(
        animation: _curved,
        child: RepaintBoundary(child: widget.child),
        builder: (context, child) {
          if (!_animateContent) {
            return child!;
          }
          final t = _curved.value.clamp(0.0, 1.0);
          final scale = 0.992 + 0.008 * t;
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 12),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 只上桌面设计语言、不上工作区 chrome 的作用域。
///
/// 登录 / 首启 / 公开分享页自带构图，但必须与已登录界面同一套色板与
/// 字体，否则登出瞬间会看到两种产品。未认证时壳层不构造，由它接管材质。
