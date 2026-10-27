import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:media_kit/media_kit.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/services/app_image_cache_policy.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/window/window_geometry_service.dart';
import 'package:omninest/platform/desktop/desktop_shell_bootstrap.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omninest/app/bootstrap_stub.dart'
    if (dart.library.js_interop) 'package:omninest/app/bootstrap_web.dart'
    as impl;

typedef AppBootstrapLoader = Future<AppBootstrapData> Function();

void bootstrap(Widget Function(AppBootstrapData data) builder) {
  FlutterError.onError = (details) {
    if (_isBootstrapRouteNoise(details.exception) ||
        impl.isEngineNoise(details.exception)) {
      return;
    }
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    if (_isBootstrapRouteNoise(error) || impl.isEngineNoise(error)) {
      return true;
    }
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stackTrace),
    );
    return true;
  };

  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      AppImageCachePolicy.configure(PaintingBinding.instance.imageCache);
      // 桌面端在启动前摆放窗口：记忆边界优先，首启按工作区收窄，
      // Windows 原生窗口隐藏由本服务负责展示。
      unawaited(windowGeometryService.applyStartupGeometry());
      // 桌面壳层：单实例锁 + 托盘 + 关窗隐藏（Web/移动端空实现）。
      unawaited(bootstrapDesktopShell());
      runApp(AppBootstrapGate(builder: builder, loader: _loadBootstrapData));
    },
    (error, stackTrace) {
      if (impl.isEngineNoise(error)) {
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stackTrace),
      );
    },
  );
}

Future<AppBootstrapData> _loadBootstrapData() async {
  MediaKit.ensureInitialized();
  try {
    await impl.waitForFonts().timeout(const Duration(seconds: 8));
  } on Object catch (error, stackTrace) {
    _reportRecoverableBootstrapError(error, stackTrace);
  }

  try {
    final preferences = await SharedPreferences.getInstance();
    return AppBootstrapData(
      themeModeName:
          preferences.getString(appearanceDeviceModeKey) ??
          preferences.getString(legacyGlobalThemeModeKey) ??
          'system',
      languageCode:
          preferences.getString(localeDeviceLanguageKey) ??
          preferences.getString(legacyGlobalLanguageKey) ??
          resolveSystemLanguage(),
      fontScaleName:
          preferences.getString(appearanceDeviceFontScaleKey) ??
          FontScalePreset.followSystem.name,
    );
  } on Object catch (error, stackTrace) {
    _reportRecoverableBootstrapError(error, stackTrace);
    return const AppBootstrapData();
  }
}

void _reportRecoverableBootstrapError(Object error, StackTrace stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      context: ErrorDescription('初始化非关键依赖'),
      silent: true,
    ),
  );
}

/// 启动过渡期的路由断言噪音：Flutter 3.47 起引擎把 URL hash 写入
/// defaultRouteName（Web 冷启动带 /#/portal 时为 '/portal'），过渡期
/// _BootstrapStatusApp 的普通 MaterialApp 无该命名路由，框架在 debug
/// 下抛出 "Could not navigate to initial route" 断言后回退 '/'。
/// 真实路由由 go_router 承接，此噪音可安全忽略（release 本就静默）。
bool _isBootstrapRouteNoise(Object error) {
  return error.toString().contains('Could not navigate to initial route');
}

class AppBootstrapGate extends StatefulWidget {
  const AppBootstrapGate({
    required this.builder,
    required this.loader,
    super.key,
  });

  final Widget Function(AppBootstrapData data) builder;
  final AppBootstrapLoader loader;

  @override
  State<AppBootstrapGate> createState() => _AppBootstrapGateState();
}

class _AppBootstrapGateState extends State<AppBootstrapGate> {
  AppBootstrapData? _data;
  Object? _error;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _data = null;
      _error = null;
    });
    // 数据加载通常远快于入场动画（字体已在 bootstrap_web 预热、偏好读取是
    // 本地同步量级），不设下限就会出现「品牌页闪一帧」。这里与加载并行
    // 计时，不叠加额外等待；错误路径不等，尽快把失败原因交出去。
    //
    // 关闭系统动效的用户看到的是一张静止画面，按动画时长拖住没有意义，
    // 只留一帧确认。此处读平台能力而非 MediaQuery：本方法在 initState
    // 栈内启动，尚不能建立 InheritedWidget 依赖。
    final reduceMotion =
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    final minVisible = Future<void>.delayed(
      reduceMotion ? _splashMinVisibleReduced : _splashMinVisible,
    );
    try {
      final data = await widget.loader();
      await minVisible;
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _data = data);
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      if (kDebugMode) {
        devLog('应用运行依赖初始化失败: $error');
      }
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data != null) {
      return widget.builder(data);
    }
    return _BootstrapStatusApp(error: _error, onRetry: _load);
  }
}

class _BootstrapStatusApp extends StatelessWidget {
  const _BootstrapStatusApp({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: OmniNestTheme.light(),
      darkTheme: OmniNestTheme.dark(),
      home: _BootstrapStatusBody(error: error, onRetry: onRetry),
    );
  }
}

class _BootstrapStatusBody extends StatelessWidget {
  const _BootstrapStatusBody({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final splash = error == null;
    final scheme = Theme.of(context).colorScheme;
    // 启动画面是固定深底，系统栏图标必须转浅色：浅色系统主题下沿用暗图标
    // 会压在深底上不可读。错误页跟随主题，与主界面一致。
    final lightSystemIcons = splash || scheme.brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            lightSystemIcons ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: splash ? _splashBackground : scheme.surface,
        systemNavigationBarIconBrightness:
            lightSystemIcons ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        // 加载态整页交给启动画面，安全区不留主题色边。
        backgroundColor: splash ? _splashBackground : null,
        body: SafeArea(
          child: Center(
            child: splash ? const _BootstrapSplash() : _buildError(context),
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).coreStartupFailed,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).coreStartupFailedHint,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context).coreRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// 启动阶段底色，与 Web 引擎首帧、PWA 启动屏三处同源。
///
/// 取应用内深色舞台色而非深色 `surface`：舞台是整屏承托色，surface 是面板色，
/// 启动画面属于前者。三处（本常量、`web/css/omninest-shell.css` 的
/// `--omninest-boot-bg` 缺省值、`web/manifest.json` 的 `background_color`）
/// 必须同值，否则冷启动会在纯色之间跳一次。
///
/// 刻意不跟随「当前主题」：启动画面是深色品牌页，若浅色偏好下让 Web 首帧
/// 也走浅色，就会出现「浅底 → 深色品牌页 → 浅色界面」两次跳色。
final Color _splashBackground = MobileEnvPalette.dark.stage;

/// 启动画面入场动画时长（毫秒）。
const int _splashEnterMs = 520;

/// 动画落位后的停留余量（毫秒）。
const int _splashHoldMs = 120;

const Duration _splashEnterDuration = Duration(milliseconds: _splashEnterMs);

/// 启动画面最短可见时长：入场动画 + 落位余量。
///
/// 与 [_splashEnterMs] 同源推导，调整动画时长时下限自动跟随，不会出现
/// 「动画没播完数据就到了」或「动画播完还要干等」。
const Duration _splashMinVisible = Duration(
  milliseconds: _splashEnterMs + _splashHoldMs,
);

/// 关闭系统动效时的最短可见时长：静止画面不必按动画时长拖住，只留一帧确认。
const Duration _splashMinVisibleReduced = Duration(milliseconds: 160);

/// 启动画面：应用内图形标记的主要落点，也是桌面端唯一的启动动画。
///
/// 冷启动时窗口先于首帧出现，原生层只有一个黑色背景；此前这里只有一个
/// 静止转圈，数据稍快就一帧闪过。现在改为入场动画——标记淡入并轻微放大、
/// 字标延迟上浮、进度条最后浮现——并由 [_AppBootstrapGateState] 保证最短
/// 可见时长，动画不会在播到一半时被数据打断。
class _BootstrapSplash extends StatefulWidget {
  const _BootstrapSplash();

  @override
  State<_BootstrapSplash> createState() => _BootstrapSplashState();
}

class _BootstrapSplashState extends State<_BootstrapSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _markOpacity;
  late final Animation<double> _markScale;
  late final Animation<double> _wordmarkOpacity;
  late final Animation<Offset> _wordmarkOffset;
  late final Animation<double> _indicatorOpacity;

  /// 系统「减少动效」：入场动画直接给终态，进度条也换成静态确定态，
  /// 否则整屏唯一还在动的东西就是那条不确定态进度。
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    final controller = AnimationController(
      vsync: this,
      duration: _splashEnterDuration,
    );
    _controller = controller;
    _markOpacity = CurvedAnimation(
      parent: controller,
      curve: const Interval(0, 0.62, curve: Curves.easeOutCubic),
    );
    _markScale = Tween<double>(begin: 0.94, end: 1).animate(_markOpacity);
    _wordmarkOpacity = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.24, 0.86, curve: Curves.easeOut),
    );
    // 偏移按子级高度取比例，字号档变化时位移同步。
    _wordmarkOffset = Tween<Offset>(
      begin: const Offset(0, 0.22),
      end: Offset.zero,
    ).animate(_wordmarkOpacity);
    _indicatorOpacity = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.5, 1, curve: Curves.easeOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller.value = 1;
      return;
    }
    if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _markOpacity,
          child: ScaleTransition(
            scale: _markScale,
            child: const BrandLogo(size: 72, radius: 20),
          ),
        ),
        const SizedBox(height: 20),
        FadeTransition(
          opacity: _wordmarkOpacity,
          child: SlideTransition(
            position: _wordmarkOffset,
            child: const Text(
              'OmniNest',
              style: TextStyle(
                color: Color(0xFFF1EFE8),
                fontSize: AppTypography.titleMedium,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        FadeTransition(
          opacity: _indicatorOpacity,
          child: SizedBox(
            width: 96,
            child: LinearProgressIndicator(
              // 减少动效时切成确定态：整屏不留下任何持续位移的元素。
              value: _reduceMotion ? 0.35 : null,
              minHeight: 2,
              backgroundColor: const Color(0x3DFFFFFF),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFB8D9C5),
              ),
              borderRadius: const BorderRadius.all(Radius.circular(1)),
            ),
          ),
        ),
      ],
    );
  }
}
