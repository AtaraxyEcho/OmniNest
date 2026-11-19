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
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: skin.bg),
          if (backdropActive)
            DesktopBackdropLayer(path: path)
          else
            _AmbientLayer(imageUrl: ambientImage),
          child,
        ],
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

/// 页面入场（样例 `.route`）：淡入 + 上移 12px + 4px 模糊收束，600ms。
///
/// 只在路由切换时重播，窗口缩放/主题切换不重播——样例里这条动画挂在
/// `key={a.route}` 的容器上，语义相同。
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

  /// 路由正在切换：入场动画期间顶栏扫一条 2px 进度条（样例 `.route-load`）。
  bool _loading = false;

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
      setState(() => _loading = loading);
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
      _controller.value = 1;
      return;
    }
    // 这里不能 setState：`forward()` 会同步派发状态回调，而 didUpdateWidget
    // 处在构建期。直接改字段，靠本次重建把进度条画出来。
    _loading = true;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onEnterStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: _controller,
      curve: DesktopMotion.ease,
    );
    // 崩溃边界与进度条挂在动画**外面**：放进 builder 里会让
    // `DesktopErrorBoundary.build` 在入场的 36 帧里每帧去接管并还原全局
    // `ErrorWidget.builder`、每帧再注册一次帧后回调，2px 扫描条也顺带被
    // 4σ 糊掉。
    return DesktopRouteContainer(
      path: widget.path,
      loading: _loading,
      child: AnimatedBuilder(
        animation: animation,
        // 入场 600ms 内整页 display list 不再每帧重录（σ 随进度变，模糊本身
        // 省不掉；但只需作用在缓存的画面上）。
        child: RepaintBoundary(child: widget.child),
        builder: (context, child) {
          final t = animation.value.clamp(0.0, 1.0);
          final content = Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 12),
              child: child,
            ),
          );
          final blur = (1 - t) * 4;
          // 只保留肉眼可辨的一段模糊。ease(0.22,0.8,0.24,1) 下 4px 在
          // 220ms 就跌到 0.5px 以下，按 0.05 收尾等于再白跑 380ms（约 23 帧）
          // 的亚像素全屏高斯——每帧两张离屏纹理，肉眼收益为零。
          if (blur < 0.5) {
            return content;
          }
          return ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              tileMode: TileMode.decal,
            ),
            child: content,
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
