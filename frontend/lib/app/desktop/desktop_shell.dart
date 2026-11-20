import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/desktop/desktop_ambient.dart';
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
import 'package:omninest/features/reader/reader_dashboard.dart';
import 'package:omninest/features/video/video_dashboard.dart';

part 'desktop_shell_immersive.dart';

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
  // 影视详情是内容区里的 `.page.film-page`：样例 `Movies.tsx:15` 把
  // `FilmDetail` 直接渲染在 `.main` 里，标题栏与侧栏始终在场。海报英雄区
  // 只是页面内的圆角卡，不再是满铺沉浸画布。
  // 剧集详情仍保留独立沉浸画布（`.video`），两者不共用路由姿态。
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

/// 取当前真正压在栈顶的路由位置。
///
/// `StatefulShellRoute.indexedStack` 下，`currentConfiguration.uri` 只代表
/// 当前 branch（如 `/portal`）；`push('/photos/p-1')` 之后真正的新页面是
/// `matches.last` 的 `ImperativeRouteMatch`。只读 uri 会让壳层一直以为还在
/// `/portal`，于是查看器被当成普通内容页，侧栏/顶栏/播放条继续盖在上面。
String desktopActiveRouteLocation(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  final matches = configuration.matches;
  if (matches.isNotEmpty) {
    return matches.last.matchedLocation;
  }
  return configuration.uri.toString();
}

String desktopActiveRoutePath(GoRouter router) =>
    Uri.parse(desktopActiveRouteLocation(router)).path;

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
  /// 本帧是否已经排过一次路由后同步（delegate 与 routeInformationProvider
  /// 会在同一次 go 里先后通知）。
  bool _routeSyncScheduled = false;

  /// 音乐中心状态变化后，同一帧只排一次播放会话同步。
  ///
  /// 桌面没有移动端的 MiniPlayerSlot / MusicCenterPage 常驻监听，播放条与
  /// 沉浸播放页都只改中心状态；不在这里补一次同步，按钮会翻图标但音频
  /// 引擎始终停在初始状态，表现为「播放器没接上」。
  bool _playbackSyncScheduled = false;

  /// 当前 location 取 routerDelegate 的**匹配结果**。
  ///
  /// 守卫 redirect（未登录 → /login?redirect=…）之后，delegate 持有最终
  /// 匹配，而 routeInformationProvider 可能仍停在浏览器原始地址；取后者
  /// 会让登录页被套进工作区 chrome，出现「侧栏 + 登录卡」同屏。
  String get _path => desktopActiveRouteLocation(widget.router);

  /// 姿态判定只看 path：带 `?redirect=…` 时全等比较会漏判。
  String get _routePath => desktopActiveRoutePath(widget.router);

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
      // 冷启动时把已恢复的播放计划交给音频会话；后续状态变化由 build 里的监听接管。
      _schedulePlaybackSync();
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

  void _schedulePlaybackSync() {
    if (_playbackSyncScheduled) {
      return;
    }
    _playbackSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playbackSyncScheduled = false;
      if (!mounted) {
        return;
      }
      ref.read(musicPortalActionsProvider).syncPlayback().ignore();
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

  /// 环境光封面按路由取（样例 `Shell.tsx` 的 `covers` 映射）。
  ///
  /// 只有媒体路由借「当前内容」当封面；home / files / settings / admin 在
  /// 样例里统一取同一张 `img.environment`，这里落成随包的默认场景。
  /// 此前这些页面都退到「最近一张照片」，关掉背景库后环境光仍会画出用户
  /// 自己的照片，看起来像壁纸没关——那不是壁纸层，但肉眼分不出来。
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
  Widget build(BuildContext context) {
    // 桌面播放条与沉浸播放页只改音乐中心状态；真正开流由播放会话完成。
    // 这里只盯播放相关的三个字段，避免听歌时长写回时把音频层一起抖动。
    ref.listen(
      musicCenterControllerProvider.select((async) {
        final state = async.asData?.value;
        return (
          state?.currentItem?.playableKey,
          state?.playbackPlan?.url,
          state?.isPlaying,
        );
      }),
      (_, _) => _schedulePlaybackSync(),
    );
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
    final backdropConfigured = ref.watch(
      appBackdropControllerProvider.select(
        (async) => async.asData?.value.hasActiveBackdrop ?? false,
      ),
    );
    final backdropScope = ref.watch(desktopBackdropScopeProvider);
    final backdropActive =
        backdropConfigured &&
        desktopBackdropAppliesToRoute(backdropScope, _routePath);

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
            backdropActive: backdropActive,
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
                          child: widget.child,
                        )
                        : mode == DesktopShellMode.immersive
                        ? _DesktopImmersiveCanvas(
                          path: _path,
                          ambientImage: _ambientImage(),
                          child: widget.child,
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
    required this.child,
  });

  final String path;
  final String? ambientImage;
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
    final routePath = Uri.tryParse(path)?.path ?? path.split('?').first;

    // 工作区整体是一个 BackdropGroup：标题栏、卡片、吸顶表头等玻璃面板
    // 因此共享同一次 backdrop 取样，不再各自捕获一遍背后的场景。各面板
    // 仍用自己 σ / 色彩矩阵。弹层走 rootOverlay，不在本组内，取样不变。
    return BackdropGroup(
      child: DesktopWindowFrame(
        child: ColoredBox(
          // Home 的样例壁纸态让窗口底面完全透出背景库；其它页面继续保留
          // 壳层基色，避免关闭壁纸后露出平台窗口底色。
          color:
              backdropActive && routePath == DesktopRoutes.home
                  ? Colors.transparent
                  : skin.bg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!backdropActive) _AmbientLayer(imageUrl: ambientImage),
              DesktopBackdropLayer(path: path),
              Column(
                children: [
                  DesktopTitleBar(path: path),
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
              const DesktopPanelLayer(),
              const DesktopToasts(),
              const DesktopContextMenu(),
              if (shell.commandPaletteOpen) const DesktopCommandPalette(),
              if (shell.shortcutsOpen) const DesktopShortcutsSheet(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 沉浸路由仍属于桌面窗口画布；壁纸层放在页面内容下方，范围切换与常规工作区一致。
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
