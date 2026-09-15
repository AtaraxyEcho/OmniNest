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
import 'package:omninest/app/session/session_reset_coordinator.dart';
import 'package:omninest/app/app_scroll_behavior.dart';
import 'package:omninest/app/sync/app_sync_coordinator.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/fullscreen_helper.dart' as fs;
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_host.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
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
        final mediaQuery = MediaQuery.of(context);
        final systemScaler = mediaQuery.textScaler;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        Widget content = AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Theme.of(context).colorScheme.surface,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
          child: AppBackdropHost(child: child ?? const SizedBox.shrink()),
        );
        // 应用字体档位根部生效。MediaQuery 包装必须结构恒定：跟随系统时
        // 写入原始系统 TextScaler（数据等价），避免档位翻转时整棵路由子树
        // 因 widget 类型变化而重挂（丢失滚动状态并打断背景视频会话）。
        final appScale = fontScalePreset.scale;
        final effectiveScaler =
            appScale == null
                ? systemScaler
                : ComposedScaler(systemScaler, appScale);
        content = MediaQuery(
          data: mediaQuery.copyWith(textScaler: effectiveScaler),
          child: content,
        );
        // 桌面形态最小内容宽护栏：桌面浏览器缩窗低于 1024 时固定宽度横向
        // 滚动，不落入各模块与移动壳层并行的窄窗自适配分支。
        final mobileForm = shouldUseResponsiveMobileShell(
          mobilePlatform: isMobilePlatform,
          width: mediaQuery.size.width,
        );
        return FontScaleScope(
          systemScaler: systemScaler,
          child: DesktopFormMinWidth(mobileForm: mobileForm, child: content),
        );
      },
    );
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.f11) {
      return false;
    }
    _toggleGlobalFullscreen();
    return true;
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
