part of 'desktop_shell.dart';

/// 工作区三姿态装配：桌面壳 Body、路径 Scope 与内容槽。
/// 方案 A 之后路由分层在 router 侧完成，这里只管壳内布局。
class _DesktopShellBody extends ConsumerStatefulWidget {
  const _DesktopShellBody({
    required this.path,
    required this.scaffoldBackgroundColor,
    required this.bodyTextStyle,
    required this.workspaceManagedByRouter,
    required this.child,
  });

  final String path;
  final Color scaffoldBackgroundColor;
  final TextStyle bodyTextStyle;
  final bool workspaceManagedByRouter;
  final Widget child;

  @override
  ConsumerState<_DesktopShellBody> createState() => _DesktopShellBodyState();
}

class _DesktopShellBodyState extends ConsumerState<_DesktopShellBody> {
  Timer? _immersiveExitTimer;
  bool _holdingImmersiveExit = false;
  bool _suppressNextRouteEnter = false;

  static String _extractRoutePath(String location) =>
      Uri.tryParse(location)?.path ?? location.split('?').first;

  @override
  void didUpdateWidget(covariant _DesktopShellBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.workspaceManagedByRouter) {
      if (_holdingImmersiveExit || _suppressNextRouteEnter) {
        _immersiveExitTimer?.cancel();
        _immersiveExitTimer = null;
        _holdingImmersiveExit = false;
        _suppressNextRouteEnter = false;
      }
      return;
    }
    if (oldWidget.path == widget.path) {
      return;
    }
    final prevMode = desktopShellModeForPath(_extractRoutePath(oldWidget.path));
    final nextMode = desktopShellModeForPath(_extractRoutePath(widget.path));
    if (prevMode == DesktopShellMode.immersive &&
        nextMode == DesktopShellMode.chrome) {
      // 从沉浸页返回工作区：抑制 `_RouteEnter` 180ms 淡入避免与退场动画对冲，
      // 并在 320ms 退场过渡期间保持满屏画布，防止退场中的沉浸页被硬塞进缩窄工作区重排。
      _immersiveExitTimer?.cancel();
      _suppressNextRouteEnter = true;
      final disableAnimations =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnimations) {
        _holdingImmersiveExit = false;
      } else {
        _holdingImmersiveExit = true;
        _immersiveExitTimer = Timer(DesktopMotion.immersiveViewerEnter, () {
          _immersiveExitTimer = null;
          if (!mounted) {
            return;
          }
          setState(() => _holdingImmersiveExit = false);
        });
      }
    } else if (nextMode != DesktopShellMode.chrome) {
      _immersiveExitTimer?.cancel();
      _immersiveExitTimer = null;
      _holdingImmersiveExit = false;
      _suppressNextRouteEnter = false;
    } else if (!_holdingImmersiveExit) {
      _suppressNextRouteEnter = false;
    }
  }

  @override
  void dispose() {
    _immersiveExitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routePath = _extractRoutePath(widget.path);
    final rawMode = desktopShellModeForPath(routePath);
    final mode =
        !widget.workspaceManagedByRouter &&
                rawMode == DesktopShellMode.chrome &&
                _holdingImmersiveExit
            ? DesktopShellMode.immersive
            : rawMode;
    final backdropConfigured = ref.watch(
      appBackdropControllerProvider.select(
        (async) => async.asData?.value.hasActiveBackdrop ?? false,
      ),
    );
    final backdropScope = ref.watch(desktopBackdropScopeProvider);
    final backdropActive =
        backdropConfigured &&
        desktopBackdropAppliesToRoute(backdropScope, routePath);

    final skin = DesktopSkin.of(context);
    final hostedOrImmersive =
        mode == DesktopShellMode.chrome || mode == DesktopShellMode.immersive;
    final routerManaged = widget.workspaceManagedByRouter;

    return DesktopShellScope(
      // 双层 Navigator 模式下工作区壳层由 `DesktopWorkspaceShell` 自行声明
      // `hosted: true`，外层保持 `hosted: false` 供根 Navigator 沉浸路由继承，
      // 推入沉浸页时不会翻转底层工作区的 hosted 标记。
      hosted: !routerManaged && mode == DesktopShellMode.chrome,
      backdropActive: backdropActive,
      // 壳层与沉浸页都是自绘表面，没有 Scaffold/Card：Material 控件
      // （TextField、Chip、Checkbox…）要求最近的 Material 祖先，缺了
      // 会抛 “No Material widget found.”。这里补一层透明 Material，
      // 并显式透传 DefaultTextStyle，避免 Material 自带 bodyMedium
      // 改掉未指定 style 的文字尺寸。
      child: Material(
        type: MaterialType.transparency,
        textStyle: widget.bodyTextStyle,
        child: Overlay.wrap(
          child:
              hostedOrImmersive
                  // 将 BackdropGroup / DesktopWindowFrame / _AmbientLayer 稳定挂载在
                  // chrome 与 immersive 共享底层，避免进出沉浸页时环境光双缓冲销毁重建。
                  ? BackdropGroup(
                    child: DesktopWindowFrame(
                      child: ColoredBox(
                        color:
                            mode == DesktopShellMode.chrome &&
                                    backdropActive &&
                                    routePath == DesktopRoutes.home
                                ? Colors.transparent
                                : skin.bg,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Offstage(
                              offstage: backdropActive,
                              child: TickerMode(
                                enabled: !backdropActive,
                                child: _AmbientLayer(
                                  key: const ValueKey('desktop-shared-ambient'),
                                  path: widget.path,
                                ),
                              ),
                            ),
                            if (routerManaged ||
                                backdropActive ||
                                mode == DesktopShellMode.chrome)
                              DesktopBackdropLayer(path: widget.path),
                            if (routerManaged)
                              widget.child
                            else if (mode == DesktopShellMode.chrome)
                              _Workspace(
                                path: widget.path,
                                suppressRouteEnter: _suppressNextRouteEnter,
                                child: widget.child,
                              )
                            else
                              _DesktopImmersiveCanvas(
                                path: widget.path,
                                child: widget.child,
                              ),
                          ],
                        ),
                      ),
                    ),
                  )
                  : DesktopWindowChrome(
                    child: ColoredBox(
                      color: widget.scaffoldBackgroundColor,
                      child: widget.child,
                    ),
                  ),
        ),
      ),
    );
  }
}

/// 将工作区专属路径通知器下传给 `ShellRoute` 内的 [DesktopWorkspaceShell]。
class _DesktopWorkspacePathScope extends InheritedWidget {
  const _DesktopWorkspacePathScope({
    required this.notifier,
    required super.child,
  });

  final ValueListenable<String> notifier;

  static ValueListenable<String>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DesktopWorkspacePathScope>()
        ?.notifier;
  }

  @override
  bool updateShouldNotify(_DesktopWorkspacePathScope oldWidget) =>
      oldWidget.notifier != notifier;
}

/// 桌面工作区路由壳层：挂载于 `router.dart` 的桌面工作区 `ShellRoute` 内。
///
/// 沉浸式全窗路由通过 `parentNavigatorKey: rootNavigatorKey` 推入根 `Navigator`
/// 覆盖在本层之上，因此进出沉浸页时底层工作区（顶栏、侧栏、详情页、详情坞、
/// 播放条）完全不卸载、尺寸零变化、零重排；退出沉浸页时工作区路径保持不变，
/// 不会触发 `_RouteEnter` 180ms 反向淡入对冲。
class DesktopWorkspaceShell extends StatelessWidget {
  const DesktopWorkspaceShell({
    required this.path,
    required this.child,
    super.key,
  });

  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 仅在外层 `DesktopShellHost` 已就绪（提供 DesktopRouterScope 与 DesktopSkin）
    // 时渲染工作区 chrome；登出过渡帧或无桌面壳宿主测试直接透传 child。
    final hasDesktopHost =
        context.dependOnInheritedWidgetOfExactType<DesktopRouterScope>() !=
            null &&
        Theme.of(context).extension<DesktopSkin>() != null;
    if (!hasDesktopHost) {
      return child;
    }
    final workspacePathNotifier = _DesktopWorkspacePathScope.maybeOf(context);
    if (workspacePathNotifier != null) {
      return ValueListenableBuilder<String>(
        valueListenable: workspacePathNotifier,
        child: child,
        builder:
            (context, workspacePath, child) =>
                _DesktopWorkspaceContent(path: workspacePath, child: child!),
      );
    }
    return _DesktopWorkspaceContent(path: path, child: child);
  }
}

class _DesktopWorkspaceContent extends ConsumerWidget {
  const _DesktopWorkspaceContent({required this.path, required this.child});

  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      hosted: true,
      backdropActive: backdropActive,
      child: _Workspace(path: path, child: child),
    );
  }
}

class _Workspace extends ConsumerWidget {
  const _Workspace({
    required this.path,
    required this.child,
    this.suppressRouteEnter = false,
  });

  final String path;
  final Widget child;
  final bool suppressRouteEnter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    // 细粒度订阅：仅关注工作区自身渲染的命令面板与快捷键表开关，
    // 侧栏折叠、详情坞开关、右键菜单与顶栏浮层变化均不再触发工作区整树重建。
    final commandPaletteOpen = ref.watch(
      desktopShellProvider.select((s) => s.commandPaletteOpen),
    );
    final shortcutsOpen = ref.watch(
      desktopShellProvider.select((s) => s.shortcutsOpen),
    );
    final offline = ref.watch(
      appOnlineStatusProvider.select((async) => async.asData?.value == false),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
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
                    Icon(DesktopIcons.wifiOff, size: 14, color: skin.text),
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
                  Expanded(
                    child: _RouteEnter(
                      path: path,
                      suppressEnter: suppressRouteEnter,
                      child: child,
                    ),
                  ),
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
        if (commandPaletteOpen) const DesktopCommandPalette(),
        if (shortcutsOpen) const DesktopShortcutsSheet(),
      ],
    );
  }
}

/// 沉浸路由仍属于桌面窗口画布；壁纸层放在页面内容下方，范围切换与常规工作区一致。
