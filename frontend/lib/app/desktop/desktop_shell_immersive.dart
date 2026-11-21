part of 'desktop_shell.dart';

class _DesktopImmersiveCanvas extends ConsumerWidget {
  const _DesktopImmersiveCanvas({required this.path, required this.child});

  final String path;
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
              _AmbientLayer(path: path),
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

/// 环境光层：独立订阅当前路由的环境封面、「强度」与「减动效」，并用
/// `ExcludeSemantics` 屏蔽装饰层，避免污染 Windows AXTree 或拖累壳层整树重建。
class _AmbientLayer extends ConsumerWidget {
  const _AmbientLayer({required this.path});

  final String path;

  String? _resolveAmbientImage(WidgetRef ref) {
    if (path.startsWith('/music')) {
      return ref.watch(
        musicPortalSnapshotProvider.select((snapshot) {
          final music = snapshot.asData?.value;
          return music?.activeTrack?.coverUrl ?? music?.featuredAlbum?.coverUrl;
        }),
      );
    }
    if (path.startsWith('/video')) {
      return ref.watch(
        movieDashboardProvider.select((dashboard) {
          for (final item
              in dashboard.asData?.value.recentlyAdded ??
                  const <MovieVideoItem>[]) {
            final image = item.backdropImageUrl ?? item.posterImageUrl;
            if (image != null) {
              return image;
            }
          }
          return null;
        }),
      );
    }
    if (path.startsWith('/reader')) {
      return ref.watch(
        readerDashboardProvider.select((dashboard) {
          for (final item
              in dashboard.asData?.value.continueReading ??
                  const <ReaderItem>[]) {
            final cover = item.coverUrl;
            if (cover != null && cover.isNotEmpty) {
              return cover;
            }
          }
          return null;
        }),
      );
    }
    if (path.startsWith('/photos')) {
      return ref.watch(
        photoDashboardProvider.select((dashboard) {
          for (final item
              in dashboard.asData?.value.recentPhotos ?? const <PhotoItem>[]) {
            if (item.coverUrl != null) {
              return item.coverUrl;
            }
          }
          return null;
        }),
      );
    }
    // 随包资产而不是网络 URL：`DesktopAmbient` 按前缀识别并走 `Image.asset`。
    return bundledDefaultWallpaperAssetPath;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intensity = ref.watch(
      desktopAppearanceProvider.select((appearance) => appearance.ambient),
    );
    final reduceMotion = ref.watch(
      desktopAppearanceProvider.select((appearance) => appearance.reduceMotion),
    );
    final imageUrl = _resolveAmbientImage(ref);
    return ExcludeSemantics(
      child: DesktopAmbient(
        imageUrl: imageUrl,
        intensity: intensity,
        reduceMotion: reduceMotion,
      ),
    );
  }
}

/// 页面入场（样例 `.route`）：纯 GPU 合成层 `FadeTransition(alwaysIncludeSemantics: true)` +
/// `SlideTransition` + `ScaleTransition`（300ms，`DesktopMotion.ease`），拓扑恒定不插拔节点。
///
/// 桌面工作区（`DesktopShellMode.chrome`）内的一级分支与常规/二级路由统一由本层
/// 单一承载过渡，不再与内层分支动画或路由动画叠跑，也不再强行展示伪进度条。
class _RouteEnter extends StatefulWidget {
  const _RouteEnter({required this.path, required this.child});

  final String path;
  final Widget child;

  @override
  State<_RouteEnter> createState() => _RouteEnterState();
}

class _RouteEnterState extends State<_RouteEnter>
    with SingleTickerProviderStateMixin {
  static const Duration _transitionDuration = Duration(milliseconds: 300);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _transitionDuration,
    value: 1,
  );
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: DesktopMotion.ease,
  );
  late final Animation<Offset> _slideAnimation = Tween<Offset>(
    begin: const Offset(0, 0.015),
    end: Offset.zero,
  ).animate(_curved);
  late final Animation<double> _scaleAnimation = Tween<double>(
    begin: 0.992,
    end: 1.0,
  ).animate(_curved);

  @override
  void didUpdateWidget(_RouteEnter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path == widget.path) {
      return;
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 崩溃边界挂在动画外面；过渡全程保持 FadeTransition -> SlideTransition ->
    // ScaleTransition -> RepaintBoundary 拓扑恒定，避免动态插拔节点导致
    // Windows AXTree 语义链断裂。
    return DesktopRouteContainer(
      path: widget.path,
      child: FadeTransition(
        opacity: _curved,
        alwaysIncludeSemantics: true,
        child: SlideTransition(
          position: _slideAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            alignment: Alignment.topCenter,
            child: RepaintBoundary(child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// 只上桌面设计语言、不上工作区 chrome 的作用域。
///
/// 登录 / 首启 / 公开分享页自带构图，但必须与已登录界面同一套色板与
/// 字体，否则登出瞬间会看到两种产品。未认证时壳层不构造，由它接管材质。
