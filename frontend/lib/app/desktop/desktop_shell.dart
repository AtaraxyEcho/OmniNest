import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/desktop/desktop_ambient.dart';
import 'package:omninest/app/desktop/desktop_appearance_sheet.dart';
import 'package:omninest/app/desktop/desktop_backdrop_layer.dart';
import 'package:omninest/app/desktop/desktop_backdrop_scope.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/app/desktop/desktop_command_palette.dart';
import 'package:omninest/app/desktop/desktop_dock.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_overlays.dart';
import 'package:omninest/app/desktop/desktop_player_bar.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_sidebar.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_boundary.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_frame.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_popovers.dart';
import 'package:omninest/app/desktop/desktop_title_bar.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_theme.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/features/video/video_dashboard.dart';

/// 壳层对当前路由的三种姿态。
enum DesktopShellMode {
  /// 常规工作区：标题栏 + 侧栏 + 内容 + 详情坞 + 播放条。
  chrome,

  /// 沉浸消费（播放/阅读/查看/编辑）：内容满铺，壳层让位。
  immersive,

  /// 未认证与公开分享页：自带构图，不套工作区。
  standalone,
}

/// 路由 → 壳层姿态。抽成纯函数以便直接断言，不用 pump 整个应用。
DesktopShellMode desktopShellModeForPath(String path) {
  if (path == '/login' ||
      path == '/setup' ||
      path == '/server-setup' ||
      path == '/boot' ||
      path.startsWith('/shared/') ||
      path.startsWith('/s/')) {
    return DesktopShellMode.standalone;
  }
  // 单张照片的查看器是满铺覆盖层（样例 `.viewer`），与相册详情那种
  // 多段路径的页面不同：只匹配 `/photos/<id>` 这一段。
  if (RegExp(r'^/photos/[^/]+$').hasMatch(path)) {
    return DesktopShellMode.immersive;
  }
  // 影视详情是满铺英雄区（样例 `.fd-hero` + `.film-page`），同样让出壳层。
  if (RegExp(r'^/video/[^/]+$').hasMatch(path)) {
    return DesktopShellMode.immersive;
  }
  if (RegExp(r'^/video/series/[^/]+$').hasMatch(path)) {
    return DesktopShellMode.immersive;
  }
  // 书本详情与参考稿一样铺满应用视口，阅读工作区壳层只在书架页保留。
  if (RegExp(r'^/reader/items/[^/]+$').hasMatch(path)) {
    return DesktopShellMode.immersive;
  }
  if (path == '/music/now-playing' ||
      path == '/photos/slideshow' ||
      path.endsWith('/play') ||
      path.endsWith('/edit') ||
      path.endsWith('/read') ||
      path.contains('/chapters/')) {
    return DesktopShellMode.immersive;
  }
  return DesktopShellMode.chrome;
}

/// 桌面统一壳的宿主。
///
/// 挂在 Router 之上（`MaterialApp.builder` 内），因此换模块只替换内容区，
/// 标题栏/侧栏/详情坞/播放条全程常驻——音乐跨模块不停、上下文不丢。
/// 移动形态不构造本组件，移动壳层与其测试完全不受影响。
class DesktopShellHost extends ConsumerStatefulWidget {
  const DesktopShellHost({
    required this.router,
    required this.child,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<DesktopShellHost> createState() => _DesktopShellHostState();
}

class _DesktopShellHostState extends ConsumerState<DesktopShellHost> {
  bool _appearanceOpen = false;

  /// 本帧是否已经排过一次路由后同步（delegate 与 routeInformationProvider
  /// 会在同一次 go 里先后通知）。
  bool _routeSyncScheduled = false;

  /// 当前 location 取 routerDelegate 的**匹配结果**。
  ///
  /// 守卫 redirect（未登录 → /login?redirect=…）之后，delegate 持有最终
  /// 匹配，而 routeInformationProvider 可能仍停在浏览器原始地址；取后者
  /// 会让登录页被套进工作区 chrome，出现「侧栏 + 登录卡」同屏。
  String get _path =>
      widget.router.routerDelegate.currentConfiguration.uri.toString();

  /// 姿态判定只看 path：带 `?redirect=…` 时全等比较会漏判。
  String get _routePath =>
      widget.router.routerDelegate.currentConfiguration.uri.path;

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onRouteChanged);
    widget.router.routeInformationProvider.addListener(_onRouteChanged);
    HardwareKeyboard.instance.addHandler(_handleKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(desktopAppearanceProvider.notifier).load();
      ref.read(desktopHistoryProvider.notifier).record(_path);
      // 样例是自绘无边框窗口：壳层常驻期间窗口不画原生标题栏，否则
      // 系统的最小化/最大化/关闭会和自绘的那三个按钮同屏出现两套。
      ref.read(windowChromeControllerProvider.notifier).setFrameless(true);
    });
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRouteChanged);
    widget.router.routeInformationProvider.removeListener(_onRouteChanged);
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  void _onRouteChanged() {
    if (!mounted || _routeSyncScheduled) {
      return;
    }
    // delegate 与 routeInformationProvider 会在同一次 go 里各通知一次；
    // `_routeSyncScheduled` 把同帧的两次合并成一次帧后记录 + setState。
    _routeSyncScheduled = true;
    // delegate 可能在路由子树构建过程中 notify；provider 写入与 setState
    // 一律延到帧后，避免「构建期修改 provider」断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 先解锁再判存活：dispose 后残留的锁会让下一次路由变化被静默吞掉。
      _routeSyncScheduled = false;
      if (!mounted) {
        return;
      }
      ref.read(desktopHistoryProvider.notifier).record(_path);
      setState(() {});
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _isTyping() {
    final focused = FocusManager.instance.primaryFocus;
    final widget = focused?.context?.widget;
    return widget is EditableText ||
        focused?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) {
      return false;
    }
    final shell = ref.read(desktopShellProvider.notifier);
    final keyboard = HardwareKeyboard.instance;
    final mod = keyboard.isControlPressed || keyboard.isMetaPressed;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      if (_appearanceOpen) {
        setState(() => _appearanceOpen = false);
        return true;
      }
      return shell.dismissTopLayer();
    }
    if (_isTyping()) {
      return false;
    }
    // 样例 `DesktopApp.tsx:57-76` 只有**一处** window keydown：导航、侧栏、
    // 坞这些全局键在任何页面都生效，只有 Space（播放/暂停）在播放器与阅读
    // 页要让位给页面自己的键位。这里的 `immersive` 只用来挡 Space，不再
    // 用来整段短路——否则详情页里 Alt 1-6 / Ctrl B / ? 全都会失效。
    final immersive =
        desktopShellModeForPath(_routePath) != DesktopShellMode.chrome;
    if (mod && key == LogicalKeyboardKey.keyB) {
      shell.toggleSidebar();
      return true;
    }
    if (mod && key == LogicalKeyboardKey.period) {
      shell.toggleDock();
      return true;
    }
    if (mod && key == LogicalKeyboardKey.comma) {
      widget.router.go(DesktopRoutes.settings);
      return true;
    }
    if (mod && key == LogicalKeyboardKey.arrowRight) {
      ref.read(musicPortalActionsProvider).nextTrack();
      return true;
    }
    if (mod && key == LogicalKeyboardKey.arrowLeft) {
      ref.read(musicPortalActionsProvider).previousTrack();
      return true;
    }
    if (keyboard.isAltPressed) {
      final digits = <LogicalKeyboardKey, int>{
        LogicalKeyboardKey.digit1: 0,
        LogicalKeyboardKey.digit2: 1,
        LogicalKeyboardKey.digit3: 2,
        LogicalKeyboardKey.digit4: 3,
        LogicalKeyboardKey.digit5: 4,
        LogicalKeyboardKey.digit6: 5,
      };
      final index = digits[key];
      if (index != null) {
        final items = desktopNavItems(AppLocalizations.of(context));
        widget.router.go(items[index].route);
        return true;
      }
      final history = ref.read(desktopHistoryProvider.notifier);
      if (key == LogicalKeyboardKey.arrowLeft) {
        final target = history.back();
        if (target != null) {
          widget.router.go(target);
          return true;
        }
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        final target = history.forward();
        if (target != null) {
          widget.router.go(target);
          return true;
        }
      }
      return false;
    }
    if (key == LogicalKeyboardKey.slash && keyboard.isShiftPressed) {
      shell.setShortcuts(true);
      return true;
    }
    if (key == LogicalKeyboardKey.space &&
        !immersive &&
        !ref.read(desktopShellProvider).commandPaletteOpen &&
        !_spaceTakenByFocus()) {
      ref.read(musicPortalActionsProvider).togglePlayback();
      return true;
    }
    return false;
  }

  /// 样例 `DesktopApp.tsx:73`：焦点在按钮 / 滑块 / 弹层里时，Space 归控件自己
  /// （按钮是「按一下」，滑块是步进，弹层里常是输入与开关）。
  bool _spaceTakenByFocus() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) {
      return false;
    }
    if (focused.widget is ButtonStyleButton) {
      return true;
    }
    return focused.findAncestorWidgetOfExactType<DesktopSlider>() != null ||
        focused.findAncestorWidgetOfExactType<DesktopModalResultScope>() !=
            null;
  }

  String? _ambientImage() {
    final path = _path;
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

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appearanceControllerProvider);
    // 根级 Theme 只依赖强调色。整份 watch 会让拖动「环境光」滑杆时每改一格
    // 都重新 resolve 一份 ThemeData，把全应用所有 `Theme.of` 依赖者拖进重建。
    final accent = ref.watch(
      desktopAppearanceProvider.select((appearance) => appearance.accent),
    );
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final theme = DesktopTheme.resolve(isDark: isDark, accent: accent);
    final mode = desktopShellModeForPath(_routePath);

    return Theme(
      data: theme,
      // 壳层挂在 Router 之上，拿不到路由页的 Material 与 Overlay：
      // 缺 DefaultTextStyle 时 Text 会继承 WidgetsApp 的兜底样式（黄色
      // 双下划线），缺 Overlay 时 Tooltip 直接建不起来。两者都在这里补齐。
      child: DefaultTextStyle(
        style: DesktopType.body(theme.extension<DesktopSkin>()!.text),
        child: DesktopRouterScope(
          router: widget.router,
          child: DesktopShellScope(
            hosted: mode == DesktopShellMode.chrome,
            // 壳层与沉浸页都是自绘表面，没有 Scaffold/Card：Material 控件
            // （TextField、Chip、Checkbox…）要求最近的 Material 祖先，缺了
            // 会抛 “No Material widget found.”。这里补一层透明 Material，
            // 并显式透传 DefaultTextStyle，避免 Material 自带 bodyMedium
            // 改掉未指定 style 的文字尺寸。
            child: Material(
              type: MaterialType.transparency,
              textStyle: DesktopType.body(theme.extension<DesktopSkin>()!.text),
              child: Overlay.wrap(
                child:
                    mode == DesktopShellMode.chrome
                        ? _Workspace(
                          path: _path,
                          ambientImage: _ambientImage(),
                          appearanceOpen: _appearanceOpen,
                          onAppearance:
                              () => setState(() => _appearanceOpen = true),
                          onCloseAppearance:
                              () => setState(() => _appearanceOpen = false),
                          child: widget.child,
                        )
                        : mode == DesktopShellMode.immersive
                        ? DesktopWindowChrome(
                          child: _DesktopImmersiveCanvas(
                            path: _path,
                            ambientImage: _ambientImage(),
                            child: widget.child,
                          ),
                        )
                        : DesktopWindowChrome(
                          child: ColoredBox(
                            color: theme.scaffoldBackgroundColor,
                            child: widget.child,
                          ),
                        ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Workspace extends ConsumerWidget {
  const _Workspace({
    required this.path,
    required this.ambientImage,
    required this.appearanceOpen,
    required this.onAppearance,
    required this.onCloseAppearance,
    required this.child,
  });

  final String path;
  final String? ambientImage;
  final bool appearanceOpen;
  final VoidCallback onAppearance;
  final VoidCallback onCloseAppearance;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final shell = ref.watch(desktopShellProvider);
    final offline = ref.watch(appOnlineStatusProvider).asData?.value == false;
    // 自定义壁纸在场时环境光整体让位（样例 `.bd-on .ambient { display:none }`）：
    // 两者叠在一起会把壁纸压成一层灰雾，暗纱也会重复叠加两次。
    // 只订阅这一位布尔：拖动暗化/模糊滑杆时 state 每帧都变，整份 watch 会把
    // 标题栏、侧栏、内容区、详情坞与播放条全部拖进每帧重建。
    final backdropConfigured = ref.watch(
      appBackdropControllerProvider.select(
        (async) => async.asData?.value.hasActiveBackdrop ?? false,
      ),
    );
    final backdropScope = ref.watch(desktopBackdropScopeProvider);
    final backdropActive =
        backdropConfigured &&
        desktopBackdropAppliesToRoute(backdropScope, path);

    // 工作区整体是一个 BackdropGroup：标题栏、卡片、吸顶表头等玻璃面板
    // 因此共享同一次 backdrop 取样，不再各自捕获一遍背后的场景。各面板
    // 仍用自己 σ / 色彩矩阵。弹层走 rootOverlay，不在本组内，取样不变。
    return BackdropGroup(
      child: DesktopWindowFrame(
        child: ColoredBox(
          color: skin.bg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!backdropActive) _AmbientLayer(imageUrl: ambientImage),
              DesktopBackdropLayer(path: path),
              Column(
                children: [
                  DesktopTitleBar(onAppearance: onAppearance),
                  if (offline)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      color: Color.lerp(skin.bg, skin.warm, 0.22),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            DesktopIcons.wifiOff,
                            size: 14,
                            color: skin.text,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              l10n.desktopOfflineBar,
                              style: DesktopType.caption(skin.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DesktopSidebar(path: path),
                        Expanded(child: _RouteEnter(path: path, child: child)),
                        const DesktopDock(),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: DesktopMetrics.playerBarBottom,
                child: const DesktopPlayerBar(),
              ),
              DesktopPanelLayer(onAppearance: onAppearance),
              const DesktopToasts(),
              const DesktopContextMenu(),
              if (shell.commandPaletteOpen) const DesktopCommandPalette(),
              if (shell.shortcutsOpen) const DesktopShortcutsSheet(),
              if (appearanceOpen)
                DesktopAppearanceSheet(onClose: onCloseAppearance),
            ],
          ),
        ),
      ),
    );
  }
}

/// 沉浸路由仍属于桌面窗口画布；壁纸层放在页面内容下方，范围切换与常规工作区一致。
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
class DesktopThemeScope extends ConsumerStatefulWidget {
  const DesktopThemeScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DesktopThemeScope> createState() => _DesktopThemeScopeState();
}

class _DesktopThemeScopeState extends ConsumerState<DesktopThemeScope> {
  @override
  void initState() {
    super.initState();
    // 未登录时壳层不构造，设备本地外观偏好由这里加载，
    // 否则登录页永远停在默认强调色，登出瞬间像换了个产品。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(desktopAppearanceProvider.notifier).load();
        // 启动页/登录页走的是本作用域而非工作区壳：无边框样式仍要在这里
        // 再声明一次，否则卡在 /boot 时窗口只靠启动期那一次下发，失败就
        // 留下系统描边。setFrameless 自带状态去重，与壳层重复调用无副作用。
        ref.read(windowChromeControllerProvider.notifier).setFrameless(true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final themeMode = ref.watch(appearanceControllerProvider);
    // 同壳层：登录/启动页的根级 Theme 也只跟强调色走。
    final accent = ref.watch(
      desktopAppearanceProvider.select((appearance) => appearance.accent),
    );
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final theme = DesktopTheme.resolve(isDark: isDark, accent: accent);
    return Theme(
      data: theme,
      child: DefaultTextStyle(
        style: DesktopType.body(theme.extension<DesktopSkin>()!.text),
        child: Material(
          type: MaterialType.transparency,
          child: ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: DesktopWindowChrome(child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// 桌面路由切换：同一入口按形态分派桌面新页与移动既有页。
///
/// 路由表保持不变（深链、分支声明、返回栈都不动），形态判定收敛在这里，
/// 窗口缩放时随 MediaQuery 重建，不需要重挂路由。
class DesktopFormSwitch extends StatelessWidget {
  const DesktopFormSwitch({
    required this.desktop,
    required this.mobile,
    super.key,
  });

  final Widget desktop;
  final Widget mobile;

  @override
  Widget build(BuildContext context) {
    final mobileForm = shouldUseResponsiveMobileShell(
      mobilePlatform: isMobilePlatform,
      width: MediaQuery.sizeOf(context).width,
    );
    return mobileForm ? mobile : desktop;
  }
}
