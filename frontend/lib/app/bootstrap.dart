import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/services/app_image_cache_policy.dart';
import 'package:omninest/core/window/window_geometry_service.dart';
import 'package:omninest/features/photos/application/photo_backup_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omninest/app/bootstrap_stub.dart'
    if (dart.library.js_interop) 'package:omninest/app/bootstrap_web.dart'
    as impl;

typedef AppBootstrapLoader = Future<AppBootstrapData> Function();

void bootstrap(Widget Function(AppBootstrapData data) builder) {
  if (kIsWeb) {
    impl.suppressCanvasKitErrors();
  }

  FlutterError.onError = (details) {
    if (impl.isEngineNoise(details.exception)) {
      return;
    }
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    if (impl.isEngineNoise(error)) {
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
    // Android 照片后台备份：按用户偏好恢复 WorkManager 周期任务（Web 为空实现）。
    unawaited(restorePhotoBackupSchedulingFromPreferences());
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
    try {
      final data = await widget.loader();
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _data = data);
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      if (kDebugMode) {
        debugPrint('应用运行依赖初始化失败: $error');
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child:
              error == null
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : ConstrainedBox(
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
                  ),
        ),
      ),
    );
  }
}
