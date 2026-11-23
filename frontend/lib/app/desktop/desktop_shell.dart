import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/desktop/desktop_ambient.dart';
import 'package:omninest/app/desktop/desktop_ambient_hints.dart';
import 'package:omninest/app/desktop/desktop_ambient_mesh.dart';
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
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_frame.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_popovers.dart';
import 'package:omninest/app/desktop/desktop_title_bar.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
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
part 'desktop_shell_body.dart';

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
  // 样例的 `FilmDetail` 同时承载 Film 与 Series，剧集详情也是 `.main` 里的
  // `.page.film-page`，因此与影视详情一样保留工作区 chrome。
  // 书本详情对齐样例 Reader.tsx:37-44，渲染在工作区 .main 内容区内（保留侧栏与顶栏）。
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
    this.workspaceManagedByRouter = false,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  /// 当 `GoRouter` 已通过桌面工作区 `ShellRoute` 托管 [DesktopWorkspaceShell] 时为 true：
  /// 宿主层只负责外层窗口框、壁纸/环境光、全局快捷键与作用域，不再在
  /// `chrome` ↔ `immersive` 切换时卸载 `_Workspace` 或 reparent `Router`。
  /// 独立单测直接传入简易 `GoRouter` 时默认为 false，保持既有测试兼容。
  final bool workspaceManagedByRouter;

  @override
  ConsumerState<DesktopShellHost> createState() => _DesktopShellHostState();
}

class _DesktopShellHostState extends ConsumerState<DesktopShellHost> {
  /// 本帧是否已经排过一次历史记录同步（delegate 与 routeInformationProvider
  /// 会在同一次 go 里先后通知）。
  bool _historySyncScheduled = false;

  /// 程序化前进/后退的目标路径，用于替代单次布尔防抖，避免快速连点导致历史游标错位。
  String? _pendingProgrammaticTarget;

  /// 上一次同步到壳层的路由位置，用于在同帧内去重更新。
  String _lastSyncedPath = '';

  /// 上一次所在的主模块标识，用于主模块切换时清理详情坞旧状态。
  String? _lastModule;

  /// 用独立 ValueNotifier 向下游分发路由变化，避免每次切页在顶层
  /// `_DesktopShellHostState` 调用 `setState` 重建整棵 `Theme` / Scope 树。
  late final ValueNotifier<String> _pathNotifier = ValueNotifier<String>(_path);

  /// 仅记录常规工作区（`DesktopShellMode.chrome`）的路由位置。
  /// 当沉浸页推入根 `Navigator` 覆盖在工作区之上时本值保持冻结，
  /// 确保底层 [DesktopWorkspaceShell] 与 `_RouteEnter` 零重建、零反向淡入。
  late final ValueNotifier<String> _workspacePathNotifier =
      ValueNotifier<String>(_initialWorkspacePath(_path));

  static String _initialWorkspacePath(String path) {
    final routePath = Uri.tryParse(path)?.path ?? path.split('?').first;
    return desktopShellModeForPath(routePath) == DesktopShellMode.chrome
        ? path
        : DesktopRoutes.home;
  }

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
    _lastSyncedPath = _path;
    _lastModule = _desktopTopLevelModule(_lastSyncedPath);
    _pathNotifier.value = _lastSyncedPath;
    _workspacePathNotifier.value = _initialWorkspacePath(_lastSyncedPath);
    widget.router.routerDelegate.addListener(_onRouteChanged);
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
  void didUpdateWidget(covariant DesktopShellHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_onRouteChanged);
      widget.router.routerDelegate.addListener(_onRouteChanged);
      _lastSyncedPath = _path;
      _lastModule = _desktopTopLevelModule(_lastSyncedPath);
      _pathNotifier.value = _lastSyncedPath;
      _workspacePathNotifier.value = _initialWorkspacePath(_lastSyncedPath);
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRouteChanged);
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _pathNotifier.dispose();
    _workspacePathNotifier.dispose();
    super.dispose();
  }

  static String? _desktopTopLevelModule(String path) {
    final routePath = Uri.tryParse(path)?.path ?? path.split('?').first;
    if (routePath == '/' || routePath == DesktopRoutes.home) {
      return DesktopRoutes.home;
    }
    if (routePath == DesktopRoutes.movies ||
        routePath.startsWith('${DesktopRoutes.movies}/')) {
      return DesktopRoutes.movies;
    }
    if (routePath == DesktopRoutes.photos ||
        routePath.startsWith('${DesktopRoutes.photos}/')) {
      return DesktopRoutes.photos;
    }
    if (routePath == DesktopRoutes.music ||
        routePath.startsWith('${DesktopRoutes.music}/')) {
      return DesktopRoutes.music;
    }
    if (routePath == DesktopRoutes.reader ||
        routePath.startsWith('${DesktopRoutes.reader}/')) {
      return DesktopRoutes.reader;
    }
    if (routePath == DesktopRoutes.files ||
        routePath.startsWith('${DesktopRoutes.files}/')) {
      return DesktopRoutes.files;
    }
    if (routePath == DesktopRoutes.settings ||
        routePath.startsWith('${DesktopRoutes.settings}/')) {
      return DesktopRoutes.settings;
    }
    if (routePath == DesktopRoutes.admin ||
        routePath.startsWith('${DesktopRoutes.admin}/')) {
      return DesktopRoutes.admin;
    }
    return null;
  }

  void _onRouteChanged() {
    if (!mounted) {
      return;
    }
    final nextPath = _path;
    final phase = SchedulerBinding.instance.schedulerPhase;
    var moduleChanged = false;
    // 非持久回调构建期同步更新 `_pathNotifier`，确保 `_RouteEnter`
    // 在新页面挂载的同一帧拿到最新 path，消除 1 帧闪现。
    if (nextPath != _lastSyncedPath) {
      _lastSyncedPath = nextPath;
      final nextModule = _desktopTopLevelModule(nextPath);
      if (nextModule != null &&
          _lastModule != null &&
          nextModule != _lastModule) {
        moduleChanged = true;
      }
      if (nextModule != null) {
        _lastModule = nextModule;
      }
      final nextRoutePath =
          Uri.tryParse(nextPath)?.path ?? nextPath.split('?').first;
      final isChromeRoute =
          desktopShellModeForPath(nextRoutePath) == DesktopShellMode.chrome;
      if (phase != SchedulerPhase.persistentCallbacks) {
        _pathNotifier.value = nextPath;
        if (isChromeRoute) {
          _workspacePathNotifier.value = nextPath;
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _pathNotifier.value = _lastSyncedPath;
            final syncedRoutePath =
                Uri.tryParse(_lastSyncedPath)?.path ??
                _lastSyncedPath.split('?').first;
            if (desktopShellModeForPath(syncedRoutePath) ==
                DesktopShellMode.chrome) {
              _workspacePathNotifier.value = _lastSyncedPath;
            }
          }
        });
      }
    }
    if (moduleChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref.read(desktopShellProvider.notifier).clearDetail();
      });
    }
    if (_historySyncScheduled) {
      return;
    }
    _historySyncScheduled = true;
    // Provider 写入一律延到帧后，避免路由在构建期通知时触发 Riverpod 断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historySyncScheduled = false;
      if (!mounted) {
        return;
      }
      final currentPath = _path;
      final historyNotifier = ref.read(desktopHistoryProvider.notifier);
      final pendingTarget = _pendingProgrammaticTarget;
      if (pendingTarget != null) {
        if (currentPath == pendingTarget) {
          _pendingProgrammaticTarget = null;
          historyNotifier.record(currentPath);
          return;
        }
        final historyState = ref.read(desktopHistoryProvider);
        if (historyState.entries.contains(currentPath)) {
          // 忽略快速连点前进/后退途中到达的过期中间路由，等待最终目标路径落位。
          return;
        }
        // 已发生非历史栈跳转或重定向：清除待匹配目标并确保新路径被记录。
        _pendingProgrammaticTarget = null;
        historyNotifier.record(currentPath);
        final after = ref.read(desktopHistoryProvider);
        if (after.cursor < 0 || after.entries[after.cursor] != currentPath) {
          historyNotifier.record(currentPath);
        }
        return;
      }
      historyNotifier.record(currentPath);
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
          _pendingProgrammaticTarget = target;
          widget.router.go(target);
          return true;
        }
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        final target = history.forward();
        if (target != null) {
          _pendingProgrammaticTarget = target;
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

  @override
  Widget build(BuildContext context) {
    // 监听顶栏前进/后退引起游标移动（entries 未变），记录预期目标路径供防抖匹配。
    ref.listen<DesktopHistory>(desktopHistoryProvider, (previous, next) {
      if (previous != null &&
          identical(previous.entries, next.entries) &&
          previous.cursor != next.cursor &&
          next.cursor >= 0 &&
          next.cursor < next.entries.length) {
        _pendingProgrammaticTarget = next.entries[next.cursor];
      }
    });
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
    final bodyTextStyle = DesktopType.body(
      theme.extension<DesktopSkin>()!.text,
    );

    return Theme(
      data: theme,
      // 壳层挂在 Router 之上，拿不到路由页的 Material 与 Overlay：
      // 缺 DefaultTextStyle 时 Text 会继承 WidgetsApp 的兜底样式（黄色
      // 双下划线），缺 Overlay 时 Tooltip 直接建不起来。两者都在这里补齐。
      child: DefaultTextStyle(
        style: bodyTextStyle,
        child: DesktopSkeletonShimmerScope(
          child: DesktopToastScope(
            child: DesktopRouterScope(
              router: widget.router,
              child: _DesktopWorkspacePathScope(
                notifier: _workspacePathNotifier,
                child: ValueListenableBuilder<String>(
                  valueListenable: _pathNotifier,
                  child: widget.child,
                  builder: (context, path, child) {
                    return _DesktopShellBody(
                      path: path,
                      scaffoldBackgroundColor: theme.scaffoldBackgroundColor,
                      bodyTextStyle: bodyTextStyle,
                      workspaceManagedByRouter: widget.workspaceManagedByRouter,
                      child: child!,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
        child: DesktopSkeletonShimmerScope(
          child: Material(
            type: MaterialType.transparency,
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: DesktopWindowChrome(child: widget.child),
            ),
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
