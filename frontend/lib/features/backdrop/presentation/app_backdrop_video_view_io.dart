import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_video_session.dart';

/// IO 平台(桌面/移动)的背景视频视图,基于 media_kit 播放会话。
/// source 可以是本机文件路径(内置壁纸)或服务端签名 URL;
/// 播放失败时切换到 [fallbackSource](内置壁纸)后重试,仍失败则收敛为空视图。
class AppBackdropVideoView extends ConsumerStatefulWidget {
  const AppBackdropVideoView({
    required this.source,
    required this.fit,
    required this.playing,
    required this.muted,
    this.fallbackSource,
    super.key,
  });

  final String source;
  final BoxFit fit;
  final bool playing;
  final bool muted;

  /// 主源播放失败时的备用地址(通常为内置壁纸本机文件)。
  final String? fallbackSource;

  @override
  ConsumerState<AppBackdropVideoView> createState() =>
      _AppBackdropVideoViewState();
}

class _AppBackdropVideoViewState extends ConsumerState<AppBackdropVideoView>
    with WidgetsBindingObserver {
  bool? _lastLayoutUsable;
  String? _lastSessionSignature;
  bool _usingFallback = false;

  String get _effectiveSource {
    if (_usingFallback && widget.fallbackSource != null) {
      return widget.fallbackSource!;
    }
    return widget.source;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appBackdropVideoSessionProvider).updateLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appBackdropVideoSessionProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasUsableLayout =
            constraints.maxWidth.isFinite &&
            constraints.maxHeight.isFinite &&
            constraints.maxWidth > 1 &&
            constraints.maxHeight > 1;
        // 主源打开失败且有备用源时切换;会话以路径变化驱动重新打开。
        if (session.openError != null &&
            !_usingFallback &&
            widget.fallbackSource != null &&
            widget.fallbackSource != widget.source) {
          _usingFallback = true;
          _lastSessionSignature = null;
          logFallbackOnce();
        }
        final source = _effectiveSource;
        _syncSession(
          source: source,
          muted: widget.muted,
          active: widget.playing && hasUsableLayout,
          layoutUsable: hasUsableLayout,
        );
        if (session.openError != null ||
            !session.ready ||
            session.controller == null) {
          return const SizedBox.shrink();
        }
        return RepaintBoundary(
          child: Video(
            controller: session.controller!,
            fit: widget.fit,
            controls: NoVideoControls,
            wakelock: false,
            pauseUponEnteringBackgroundMode: true,
            resumeUponEnteringForegroundMode: true,
          ),
        );
      },
    );
  }

  bool _fallbackLogged = false;

  void logFallbackOnce() {
    if (_fallbackLogged) {
      return;
    }
    _fallbackLogged = true;
    debugPrint('背景视频主源打开失败,回退内置壁纸');
  }

  void _syncSession({
    required String source,
    required bool muted,
    required bool active,
    required bool layoutUsable,
  }) {
    final signature = '$source:$muted:$active:$layoutUsable';
    if (_lastSessionSignature == signature &&
        _lastLayoutUsable == layoutUsable) {
      return;
    }
    _lastSessionSignature = signature;
    _lastLayoutUsable = layoutUsable;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final session = ref.read(appBackdropVideoSessionProvider);
      session.setLayoutUsable(layoutUsable);
      session.configure(path: source, muted: muted, active: active);
    });
  }
}
