part of 'desktop_shell.dart';

/// 桌面端根 `Navigator` 沉浸式全窗路由覆盖壳层。
///
/// 用于 `parentNavigatorKey: rootNavigatorKey` 的沉浸路由页面：补齐无边框窗口
/// 顶部拖拽条、`DesktopToasts()` 与 `DesktopShellScope(hosted: false)`；
/// 无桌面壳宿主（移动端或未登录过渡态）时直接透传 `child`。
class DesktopImmersiveOverlay extends ConsumerWidget {
  const DesktopImmersiveOverlay({
    required this.path,
    required this.child,
    super.key,
  });

  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasDesktopHost =
        context.dependOnInheritedWidgetOfExactType<DesktopRouterScope>() !=
            null &&
        Theme.of(context).extension<DesktopSkin>() != null;
    if (!hasDesktopHost) {
      return child;
    }
    final routePath = Uri.tryParse(path)?.path ?? path.split('?').first;
    final backdropConfigured = ref.watch(
      appBackdropControllerProvider.select(
        (async) => async.asData?.value.hasActiveBackdrop ?? false,
      ),
    );
    final backdropScope = ref.watch(desktopBackdropScopeProvider);
    final backdropActive =
        backdropConfigured &&
        desktopBackdropAppliesToRoute(backdropScope, routePath);
    return DesktopShellScope(
      hosted: false,
      backdropActive: backdropActive,
      child: _DesktopImmersiveCanvas(path: path, child: child),
    );
  }
}

/// 沉浸路由前景覆盖层（与常规工作区共享底层 `_AmbientLayer` 与 `DesktopBackdropLayer`，
/// 避免进出沉浸页时销毁重建环境光双缓冲）。
class _DesktopImmersiveCanvas extends ConsumerWidget {
  const _DesktopImmersiveCanvas({required this.path, required this.child});

  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFullscreen = ref.watch(
      windowChromeControllerProvider.select((state) => state.isFullscreen),
    );
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    return Stack(
      fit: StackFit.expand,
      children: [
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
    );
  }
}

/// 桌面环境光解析结果。
@immutable
class _ResolvedAmbientSpec {
  const _ResolvedAmbientSpec({
    required this.imageUrl,
    required this.showArt,
    required this.artPreset,
    this.fallbackTone,
    this.useMusicAuth = false,
    this.isPhotoSource = false,
  });

  final String? imageUrl;
  final bool showArt;
  final EditorialArtPreset artPreset;
  final Color? fallbackTone;
  final bool useMusicAuth;
  final bool isPhotoSource;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ResolvedAmbientSpec &&
        other.imageUrl == imageUrl &&
        other.showArt == showArt &&
        other.artPreset == artPreset &&
        other.fallbackTone == fallbackTone &&
        other.useMusicAuth == useMusicAuth &&
        other.isPhotoSource == isPhotoSource;
  }

  @override
  int get hashCode => Object.hash(
    imageUrl,
    showArt,
    artPreset,
    fallbackTone,
    useMusicAuth,
    isPhotoSource,
  );
}

/// 环境光层：独立订阅当前路由的环境封面、「强度」与「减动效」，
/// 接入 `desktopAmbientHintProvider` 统一解析五大模块封面与 `EditorialArtPreset`，
/// 并用 `ExcludeSemantics` 屏蔽装饰层，避免污染 Windows AXTree 或拖累壳层整树重建。
class _AmbientLayer extends ConsumerStatefulWidget {
  const _AmbientLayer({required this.path, super.key});

  final String path;

  @override
  ConsumerState<_AmbientLayer> createState() => _AmbientLayerState();
}

class _AmbientLayerState extends ConsumerState<_AmbientLayer> {
  static const Duration _homeAntiFlickerWindow = Duration(milliseconds: 180);

  /// 按模块前缀内存缓存最近一次有效 `ambientUrl`，避免切页时 provider
  /// 短暂空值导致回退黑底再切回封面。
  static final Map<String, String> _lastAmbientByModule = <String, String>{};

  _ResolvedAmbientSpec? _homeLockedSpec;
  _ResolvedAmbientSpec? _pendingHomeSpec;
  Timer? _homeLockTimer;

  static String? _modulePrefix(String path) {
    final routePath = Uri.tryParse(path)?.path ?? path.split('?').first;
    if (routePath.startsWith('/music')) return '/music';
    if (routePath.startsWith('/video')) return '/video';
    if (routePath.startsWith('/reader')) return '/reader';
    if (routePath.startsWith('/photos')) return '/photos';
    return null;
  }

  static bool _isMediaAmbientRoute(String path) {
    final routePath = Uri.tryParse(path)?.path ?? path.split('?').first;
    return routePath == '/' ||
        routePath == '/portal' ||
        routePath.startsWith('/video') ||
        routePath.startsWith('/photos') ||
        routePath.startsWith('/music') ||
        routePath.startsWith('/reader');
  }

  @override
  void dispose() {
    _homeLockTimer?.cancel();
    super.dispose();
  }

  String? _watchMusicCover(WidgetRef ref) {
    return ref.watch(
      musicPortalSnapshotProvider.select((snapshot) {
        final music = snapshot.asData?.value;
        return music?.activeTrack?.coverUrl ?? music?.featuredAlbum?.coverUrl;
      }),
    );
  }

  String? _watchMoviesDashboardCover(WidgetRef ref) {
    return ref.watch(
      movieDashboardProvider.select((dashboard) {
        final items =
            dashboard.asData?.value.recentlyAdded ?? const <MovieVideoItem>[];
        // 优先遍历所有具备横屏剧照（backdropImageUrl）的作品，再回退竖版海报。
        for (final item in items) {
          final backdrop = item.backdropImageUrl;
          if (backdrop != null && backdrop.isNotEmpty) {
            return backdrop;
          }
        }
        for (final item in items) {
          final poster = item.posterImageUrl;
          if (poster != null && poster.isNotEmpty) {
            return poster;
          }
        }
        return null;
      }),
    );
  }

  ({String? coverUrl, Color? fallbackTone}) _watchReaderDashboardCover(
    WidgetRef ref,
  ) {
    return ref.watch(
      readerDashboardProvider.select((dashboard) {
        final value = dashboard.asData?.value;
        if (value == null) {
          return (coverUrl: null, fallbackTone: null);
        }
        final candidates = <ReaderItem>[
          ...value.continueReading,
          ...value.recentItems,
        ];
        for (final item in candidates) {
          final cover = item.coverUrl;
          if (cover != null && cover.isNotEmpty) {
            return (
              coverUrl: cover,
              fallbackTone: DesktopPalette.bookToneFor(item.id).tone,
            );
          }
        }
        if (candidates.isNotEmpty) {
          return (
            coverUrl: null,
            fallbackTone: DesktopPalette.bookToneFor(candidates.first.id).tone,
          );
        }
        return (coverUrl: null, fallbackTone: null);
      }),
    );
  }

  static String? _freshPhotoImageUrl(PhotoItem item) {
    final cover = item.coverUrl?.trim();
    if (cover != null && cover.isNotEmpty) {
      return cover;
    }
    final source = item.sourceUrl?.trim();
    if (source != null && source.isNotEmpty) {
      return source;
    }
    return null;
  }

  /// Photos 背景解析链：
  /// 1) 若存在 `photosLastViewedId`，按 id 从 `photoListProvider` 与
  ///    `photoDashboardProvider.recentPhotos` 查找鲜活的 `coverUrl ?? sourceUrl`；
  /// 2) 否则取 `photoListProvider` 最新日期第 1 张非视频图片；
  /// 3) 否则取 `photoDashboardProvider.recentPhotos` 第 1 张有效图片；
  /// 4) 若列表中暂未命中且存在内存态 `photosLastViewedUrl`，作最后兼容兜底。
  String? _watchPhotosAmbientCover(WidgetRef ref, DesktopAmbientHints hints) {
    final targetId = hints.photosLastViewedId;
    final listMatch = ref.watch(
      photoListProvider.select((pageAsync) {
        final items = pageAsync.asData?.value.items ?? const <PhotoItem>[];
        String? byId;
        String? firstImage;
        for (final item in items) {
          final url = _freshPhotoImageUrl(item);
          if (url == null) continue;
          if (targetId != null && item.id == targetId) {
            byId = url;
            break;
          }
          if (firstImage == null && !item.isVideo) {
            firstImage = url;
          }
        }
        return (byId: byId, firstImage: firstImage);
      }),
    );
    if (listMatch.byId != null) {
      return listMatch.byId;
    }

    final dashboardMatch = ref.watch(
      photoDashboardProvider.select((dashboardAsync) {
        final items =
            dashboardAsync.asData?.value.recentPhotos ?? const <PhotoItem>[];
        String? byId;
        String? firstImage;
        String? firstAny;
        for (final item in items) {
          final url = _freshPhotoImageUrl(item);
          if (url == null) continue;
          if (targetId != null && item.id == targetId) {
            byId = url;
            break;
          }
          firstAny ??= url;
          if (firstImage == null && !item.isVideo) {
            firstImage = url;
          }
        }
        return (byId: byId, firstImage: firstImage ?? firstAny);
      }),
    );
    if (dashboardMatch.byId != null) {
      return dashboardMatch.byId;
    }
    if (listMatch.firstImage != null) {
      return listMatch.firstImage;
    }
    if (dashboardMatch.firstImage != null) {
      return dashboardMatch.firstImage;
    }
    final fallbackUrl = hints.photosLastViewedUrl;
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      return fallbackUrl;
    }
    return null;
  }

  _ResolvedAmbientSpec _resolveRawSpec(WidgetRef ref) {
    final prefix = _modulePrefix(widget.path);
    final hints = ref.watch(desktopAmbientHintProvider);

    if (prefix == '/music') {
      final resolved = _watchMusicCover(ref);
      final effective = _rememberOrFallback('/music', resolved);
      return _ResolvedAmbientSpec(
        imageUrl: effective,
        showArt: effective != null && effective.isNotEmpty,
        artPreset: EditorialArtPreset.square,
        useMusicAuth: true,
      );
    }

    if (prefix == '/video') {
      final hintUrl = hints.moviesActiveUrl;
      final dashboardUrl = _watchMoviesDashboardCover(ref);
      final resolved =
          (hintUrl != null && hintUrl.isNotEmpty) ? hintUrl : dashboardUrl;
      final effective = _rememberOrFallback('/video', resolved);
      return _ResolvedAmbientSpec(
        imageUrl: effective,
        showArt: effective != null && effective.isNotEmpty,
        artPreset: EditorialArtPreset.landscape,
      );
    }

    if (prefix == '/photos') {
      final resolved = _watchPhotosAmbientCover(ref, hints);
      final effective = _rememberOrFallback('/photos', resolved);
      return _ResolvedAmbientSpec(
        imageUrl: effective,
        showArt: effective != null && effective.isNotEmpty,
        artPreset: EditorialArtPreset.landscape,
        isPhotoSource: true,
      );
    }

    if (prefix == '/reader') {
      final dashboard = _watchReaderDashboardCover(ref);
      final hintUrl = hints.readerLastOpenedUrl;
      final resolvedUrl =
          (hintUrl != null && hintUrl.isNotEmpty)
              ? hintUrl
              : dashboard.coverUrl;
      final effectiveUrl = _rememberOrFallback('/reader', resolvedUrl);
      final fallbackTone = hints.readerFallbackTone ?? dashboard.fallbackTone;
      return _ResolvedAmbientSpec(
        imageUrl: effectiveUrl,
        showArt: effectiveUrl != null && effectiveUrl.isNotEmpty,
        artPreset: EditorialArtPreset.portraitBook,
        fallbackTone: fallbackTone,
      );
    }

    // Home 及其他通用路由：优先级链（Music 播放封面 -> Movies 轮播/最近 ->
    // Photos 上次查看/最新 -> Reader 上次打开/继续阅读 -> 随包默认壁纸）。
    final musicCover = _watchMusicCover(ref);
    if (musicCover != null && musicCover.isNotEmpty) {
      return _ResolvedAmbientSpec(
        imageUrl: musicCover,
        showArt: true,
        artPreset: EditorialArtPreset.ambientSubtle,
        useMusicAuth: true,
      );
    }
    final movieCover =
        (hints.moviesActiveUrl != null && hints.moviesActiveUrl!.isNotEmpty)
            ? hints.moviesActiveUrl
            : _watchMoviesDashboardCover(ref);
    if (movieCover != null && movieCover.isNotEmpty) {
      return _ResolvedAmbientSpec(
        imageUrl: movieCover,
        showArt: true,
        artPreset: EditorialArtPreset.ambientSubtle,
      );
    }
    final photoCover = _watchPhotosAmbientCover(ref, hints);
    if (photoCover != null && photoCover.isNotEmpty) {
      return _ResolvedAmbientSpec(
        imageUrl: photoCover,
        showArt: true,
        artPreset: EditorialArtPreset.ambientSubtle,
        isPhotoSource: true,
      );
    }
    final readerDashboard = _watchReaderDashboardCover(ref);
    final readerCover =
        (hints.readerLastOpenedUrl != null &&
                hints.readerLastOpenedUrl!.isNotEmpty)
            ? hints.readerLastOpenedUrl
            : readerDashboard.coverUrl;
    if (readerCover != null && readerCover.isNotEmpty) {
      return _ResolvedAmbientSpec(
        imageUrl: readerCover,
        showArt: true,
        artPreset: EditorialArtPreset.ambientSubtle,
        fallbackTone: hints.readerFallbackTone ?? readerDashboard.fallbackTone,
      );
    }
    return const _ResolvedAmbientSpec(
      imageUrl: bundledDefaultWallpaperAssetPath,
      showArt: true,
      artPreset: EditorialArtPreset.ambientSubtle,
    );
  }

  static String? _rememberOrFallback(String prefix, String? resolved) {
    if (resolved != null && resolved.isNotEmpty) {
      _lastAmbientByModule[prefix] = resolved;
      return resolved;
    }
    return _lastAmbientByModule[prefix];
  }

  /// Home 180ms 防闪烁锁：冷启动期间多个模块异步先后就绪时，
  /// 将 180ms 内的快速候选跳变合并为一次平滑提交。
  _ResolvedAmbientSpec _applyHomeAntiFlicker(_ResolvedAmbientSpec raw) {
    final current = _homeLockedSpec;
    if (current == null) {
      _homeLockedSpec = raw;
      return raw;
    }
    if (current == raw) {
      _pendingHomeSpec = null;
      _homeLockTimer?.cancel();
      _homeLockTimer = null;
      return current;
    }
    _pendingHomeSpec = raw;
    _homeLockTimer ??= Timer(_homeAntiFlickerWindow, () {
      _homeLockTimer = null;
      if (!mounted) return;
      final pending = _pendingHomeSpec;
      if (pending != null && pending != _homeLockedSpec) {
        setState(() {
          _homeLockedSpec = pending;
          _pendingHomeSpec = null;
        });
      }
    });
    return current;
  }

  @override
  Widget build(BuildContext context) {
    final dynamicBg = ref.watch(
      desktopAppearanceProvider.select((appearance) => appearance.dynamicBg),
    );
    if (!dynamicBg || !_isMediaAmbientRoute(widget.path)) {
      return const ExcludeSemantics(child: DesktopAmbientPlain());
    }
    final intensity = ref.watch(
      desktopAppearanceProvider.select((appearance) => appearance.ambient),
    );
    final reduceMotion = ref.watch(
      desktopAppearanceProvider.select((appearance) => appearance.reduceMotion),
    );
    final prefix = _modulePrefix(widget.path);
    final isHome = prefix == null;
    final isReaderRoute = prefix == '/reader';
    final rawSpec = _resolveRawSpec(ref);
    final spec = isHome ? _applyHomeAntiFlicker(rawSpec) : rawSpec;
    final imageUrl = spec.imageUrl;
    ImageProvider<Object>? imageProvider;
    if (spec.useMusicAuth &&
        imageUrl != null &&
        imageUrl.isNotEmpty &&
        !imageUrl.startsWith('assets/')) {
      final cacheManager = ref.watch(musicCoverCacheManagerProvider(imageUrl));
      imageProvider = CachedNetworkImageProvider(
        imageUrl,
        cacheManager: cacheManager,
        imageRenderMethodForWeb: musicCoverRenderMethodForWeb(cacheManager),
      );
    }

    VoidCallback? onImageError;
    if (spec.isPhotoSource) {
      onImageError = () {
        if (!mounted) return;
        _lastAmbientByModule.remove('/photos');
        ref.read(desktopAmbientHintProvider.notifier).clearPhotoHint();
        setState(() {});
      };
    }

    return ExcludeSemantics(
      child: DesktopAmbient(
        imageUrl: imageUrl,
        intensity: intensity,
        reduceMotion: reduceMotion,
        showArt: spec.showArt,
        artPreset: spec.artPreset,
        fallbackTone: spec.fallbackTone,
        isReaderRoute: isReaderRoute,
        imageProvider: imageProvider,
        onImageError: onImageError,
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
  const _RouteEnter({
    required this.path,
    required this.child,
    this.suppressEnter = false,
  });

  final String path;
  final Widget child;
  final bool suppressEnter;

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
    if (widget.suppressEnter ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
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
