import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/app_min_width_guard.dart';
import 'package:omninest/app/appearance/application/composed_scaler.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/appearance/application/font_scale_scope.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/desktop_tray_locale_binding.dart';
import 'package:omninest/app/mobile_shell/mobile_app_shell.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/router.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/app/session/session_reset_coordinator.dart';
import 'package:omninest/app/app_scroll_behavior.dart';
import 'package:omninest/app/sync/app_sync_coordinator.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/fullscreen_helper.dart' as fs;
import 'package:omninest/core/window/desktop_close_action.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_host.dart';
import 'package:omninest/platform/platform_capabilities.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/search/search_ui.dart';
import 'package:omninest/features/notifications/presentation/widgets/notification_foreground_toast.dart';
import 'package:omninest/core/deep_link/deep_link_service.dart';
import 'package:omninest/features/tasks/application/task_notification_service.dart';

class OmniNestApp extends ConsumerStatefulWidget {
  const OmniNestApp({super.key});

  @override
  ConsumerState<OmniNestApp> createState() => _OmniNestAppState();
}

class _OmniNestAppState extends ConsumerState<OmniNestApp> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 初始化本地数据库单例（确保 ReaderLocalProgress / ReaderSyncQueue 可用）
    ref.watch(localDatabaseInitProvider);
    // 删除旧版明文离线缓存，确保升级后不依赖用户再次打开对应模块。
    ref.watch(offlineDataInitializationProvider);
    // 启动网络恢复监听器，重放文件、音乐和阅读离线同步队列
    ref.watch(connectivityListenerProvider);
    // 启动单一实时连接及持久失效记录的定向刷新分发。
    ref.watch(appSyncCoordinatorProvider);
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(appearanceControllerProvider);
    final fontScalePreset = ref.watch(fontScaleControllerProvider);
    final languageCode = ref.watch(localeControllerProvider);

    // 通知复用实时同步连接，仅用于副作用。
    ref.watch(notificationRealtimeSubscriptionProvider);
    // 任务终态系统通知：监听任务列表并按偏好发送系统通知。
    ref.watch(taskSystemNotificationBindingProvider);
    // 桌面托盘菜单文案跟随应用语言刷新（Web/移动端为空实现）。
    ref.watch(desktopTrayLocaleBindingProvider);
    // 登出或换号时重置全部常驻业务 provider，防止跨账号残留缓存。
    ref.watch(sessionResetCoordinatorProvider);
    // omninest:// 深链：接住冷启动与运行期链接并落位白名单路由。
    ref.watch(deepLinkServiceProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'OmniNest',
      theme: OmniNestTheme.light(),
      darkTheme: OmniNestTheme.dark(),
      themeMode: themeMode,
      themeAnimationDuration: MotionToken.resolveForPlatform(MotionToken.fast),
      scrollBehavior: const OmniNestScrollBehavior(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      locale: Locale(languageCode),
      routerConfig: router,
      builder: (context, child) {
        // 认证门控：登出瞬间路由 gate 经 listenable 转发，其页面替换晚于
        // 渲染帧，旧受保护页面会闪现一帧。此处按「已确定未认证 + 当前
        // 路径非公开」在根 builder 同帧遮挡，先于路由替换生效。
        final session = ref.watch(authSessionProvider);
        final sessionValue = session.asData?.value;
        final definitelySignedOut =
            sessionValue != null && !sessionValue.isAuthenticated;
        return UnauthenticatedRenderGate(
          // 监听 routerDelegate：redirect 完成后 delegate 同步更新
          // currentConfiguration 并 notify。routeInformationProvider 的
          // value 回报走 post-frame 且不 notify，不能用来解除遮挡。
          routeListenable: router.routerDelegate,
          shouldGate:
              () =>
                  definitelySignedOut &&
                  gatesUnauthenticatedRender(
                    isAuthenticated: false,
                    path: router.routerDelegate.currentConfiguration.uri.path,
                  ),
          child: _buildRouterContent(context, child, fontScalePreset),
        );
      },
    );
  }

  /// 根 builder 的正常内容（路由子树外的缩放、通知与桌面宽度护栏）。
  Widget _buildRouterContent(
    BuildContext context,
    Widget? child,
    FontScalePreset fontScalePreset,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final systemScaler = mediaQuery.textScaler;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget content = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Theme.of(context).colorScheme.surface,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: AppBackdropHost(child: child ?? const SizedBox.shrink()),
    );
    // 应用字体档位根部生效。缩放一律经 ComposedScaler：跟随系统档位时
    // （preset.scale == null）也要吃到 ComposedScaler.maxScale 封顶，
    // 且 scaler 类型不随档位翻转变化，整棵路由子树不会因此重挂
    // （丢失滚动状态并打断背景视频会话）。
    final effectiveScaler = ComposedScaler(
      systemScaler,
      fontScalePreset.scale ?? 1,
    );
    content = MediaQuery(
      data: mediaQuery.copyWith(textScaler: effectiveScaler),
      child: content,
    );
    // 桌面形态最小内容宽护栏：桌面浏览器缩窗低于 1024 时固定宽度横向
    // 滚动，不落入各模块与移动壳层并行的窄窗自适配分支；无 hover 指针的
    // 设备例外，让它们直接走模块窄屏布局。
    final mobileForm = shouldUseResponsiveMobileShell(
      mobilePlatform: isMobilePlatform,
      width: mediaQuery.size.width,
    );
    final hoverCapable = PlatformCapabilities.current().supportsHoverPointer;
    return FontScaleScope(
      // 供自绘排版取用的「仅系统缩放」口径同样封顶，否则阅读页测量
      // 会与实际渲染字号在超大无障碍档位下分叉。
      systemScaler: ComposedScaler(systemScaler, 1),
      child: NotificationForegroundToast(
        child: DesktopFormMinWidth(
          mobileForm: mobileForm,
          hoverCapable: hoverCapable,
          child: content,
        ),
      ),
    );
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleGlobalFullscreen();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyK &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      _openSearch();
      return true;
    }
    return false;
  }

  /// Ctrl/Cmd+K 打开全局搜索浮层；仅在明确未认证时拦截。
  void _openSearch() {
    final session = ref.read(authSessionProvider).asData?.value;
    if (session != null && !session.isAuthenticated) {
      return;
    }
    final navigatorContext = desktopCloseNavigatorKey.currentContext ?? context;
    if (!navigatorContext.mounted) {
      return;
    }
    unawaited(showGlobalSearchDialog(navigatorContext));
  }

  void _toggleGlobalFullscreen() {
    if (kIsWeb) {
      fs.toggleFullscreen();
      return;
    }
    unawaited(
      ref.read(windowChromeControllerProvider.notifier).toggleFullscreen(),
    );
  }
}

/// 根 builder 的未认证渲染门控：与 router 的公开路径口径保持一致
/// （登录/安装/引导/分享页公开），其余路径在已确定未认证时不渲染。
@visibleForTesting
bool gatesUnauthenticatedRender({
  required bool isAuthenticated,
  required String path,
}) {
  if (isAuthenticated) {
    return false;
  }
  return !(path == '/login' ||
      path == '/setup' ||
      path == '/server-setup' ||
      path == '/boot' ||
      path.startsWith('/shared/photos/') ||
      path.startsWith('/s/'));
}

/// 未认证渲染遮挡层。
///
/// 门控时必须保留 [child]（Router）在树上：若直接丢弃 child，Router 会
/// dispose，refreshListenable 触发的 redirect 无法执行，路径永不更新，
/// 遮罩将永久停在加载页。用不透明层遮挡旧受保护页画面，child 始终挂在
/// 同一 Stack 槽位，门控开关不会重挂路由子树。
///
/// [routeListenable] 通常为 GoRouter.routerDelegate。delegate 可能在子树
/// 构建过程中 notify，因此状态刷新一律延到帧后，避免构建期 markNeedsBuild。
class UnauthenticatedRenderGate extends StatefulWidget {
  const UnauthenticatedRenderGate({
    super.key,
    required this.shouldGate,
    required this.routeListenable,
    required this.child,
  });

  final bool Function() shouldGate;
  final Listenable routeListenable;
  final Widget child;

  @override
  State<UnauthenticatedRenderGate> createState() =>
      _UnauthenticatedRenderGateState();
}

class _UnauthenticatedRenderGateState extends State<UnauthenticatedRenderGate> {
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.routeListenable.addListener(_onRouteChanged);
  }

  @override
  void didUpdateWidget(UnauthenticatedRenderGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeListenable != widget.routeListenable) {
      oldWidget.routeListenable.removeListener(_onRouteChanged);
      widget.routeListenable.addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    widget.routeListenable.removeListener(_onRouteChanged);
    super.dispose();
  }

  void _onRouteChanged() {
    if (!mounted || _refreshScheduled) {
      return;
    }
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (widget.shouldGate())
          ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: const Center(child: AppLoading()),
          ),
      ],
    );
  }
}
