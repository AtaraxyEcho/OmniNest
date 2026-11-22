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
    final isFullscreen = ref.watch(
      windowChromeControllerProvider.select((state) => state.isFullscreen),
    );
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    return BackdropGroup(
      // 所有沉浸路由统一包裹 DesktopWindowFrame（恢复四边+四角边缘缩放），
      // 在 child 上方（DesktopToasts 下方）放置 14px 顶边兜底拖拽条：
      // 避让窗口控制键、全屏态关闭、仅绑 onPanStart 不绑 onDoubleTap 防拖慢单击。
      child: DesktopWindowFrame(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: skin.bg),
            if (backdropActive)
              DesktopBackdropLayer(path: path)
            else
              _AmbientLayer(path: path),
            child,
            if (isDesktopPlatform && !isFullscreen)
              Positioned(
                top: 0,
                left: isMacOS ? 80 : 0,
                right: isMacOS ? 0 : 148,
                height: 14,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart:
                      (_) =>
                          ref
                              .read(windowChromeControllerProvider.notifier)
                              .startDragging(),
                  child: const SizedBox.expand(),
                ),
              ),
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

  /// 按模块前缀内存缓存最近一次有效 `ambientUrl`，避免切页时 provider
  /// 短暂空值导致回退黑底再切回封面、二次触发 1.6s 环境光闪烁。
  static final Map<String, String> _lastAmbientByModule = <String, String>{};

  static String? _modulePrefix(String path) {
    if (path.startsWith('/music')) return '/music';
    if (path.startsWith('/video')) return '/video';
    if (path.startsWith('/reader')) return '/reader';
    if (path.startsWith('/photos')) return '/photos';
    return null;
  }

  String? _resolveAmbientImage(WidgetRef ref) {
    final prefix = _modulePrefix(path);
    String? resolved;
    if (prefix == '/music') {
      resolved = ref.watch(
        musicPortalSnapshotProvider.select((snapshot) {
          final music = snapshot.asData?.value;
          return music?.activeTrack?.coverUrl ?? music?.featuredAlbum?.coverUrl;
        }),
      );
    } else if (prefix == '/video') {
      resolved = ref.watch(
        movieDashboardProvider.select((dashboard) {
          for (final item
              in dashboard.asData?.value.recentlyAdded ??
                  const <MovieVideoItem>[]) {
            final image = item.backdropImageUrl ?? item.posterImageUrl;
            if (image != null && image.isNotEmpty) {
              return image;
            }
          }
          return null;
        }),
      );
    } else if (prefix == '/reader') {
      resolved = ref.watch(
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
    } else if (prefix == '/photos') {
      resolved = ref.watch(
        photoDashboardProvider.select((dashboard) {
          for (final item
              in dashboard.asData?.value.recentPhotos ?? const <PhotoItem>[]) {
            final cover = item.coverUrl;
            if (cover != null && cover.isNotEmpty) {
              return cover;
            }
          }
          return null;
        }),
      );
    } else {
      // 随包资产而不是网络 URL：`DesktopAmbient` 按前缀识别并走 `Image.asset`。
      return bundledDefaultWallpaperAssetPath;
    }

    if (resolved != null && resolved.isNotEmpty) {
      _lastAmbientByModule[prefix!] = resolved;
      return resolved;
    }
    return _lastAmbientByModule[prefix];
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
    final prefix = _modulePrefix(path);
    final showArt =
        prefix == '/video' ||
        prefix == '/photos' ||
        prefix == '/music' ||
        prefix == '/reader';
    return ExcludeSemantics(
      child: DesktopAmbient(
        imageUrl: imageUrl,
        intensity: intensity,
        reduceMotion: reduceMotion,
        showArt: showArt,
      ),
    );
  }
}

/// 页面入场（样例 `.route`）：纯 GPU 合成层 `FadeTransition(alwaysIncludeSemantics: true)` +
/// `SlideTransition` + `ScaleTransition`（180ms，`DesktopMotion.ease`），拓扑恒定不插拔节点。
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
  static const Duration _transitionDuration = Duration(milliseconds: 180);

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
