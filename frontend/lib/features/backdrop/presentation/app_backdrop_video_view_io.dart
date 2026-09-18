import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_video_session.dart';
import 'package:omninest/core/log/dev_log.dart';

/// IO 平台(桌面/移动)的背景视频视图,基于 media_kit 播放会话。
/// source 可以是本机文件路径(内置壁纸)或服务端签名 URL;
/// 播放失败时切换到 [fallbackSource](内置壁纸)后重试,仍失败则收敛为空视图。
/// [onSourceStale] 在主源打开失败时回调,供上层刷新签名 URL。
class AppBackdropVideoView extends ConsumerStatefulWidget {
  const AppBackdropVideoView({
    required this.source,
    required this.fit,
    required this.playing,
    required this.muted,
    this.fallbackSource,
    this.onSourceStale,
    super.key,
  });

  final String source;
  final BoxFit fit;
  final bool playing;
  final bool muted;

  /// 主源播放失败时的备用地址(通常为内置壁纸本机文件)。
  final String? fallbackSource;

  /// 主源打开失败时通知上层签名 URL 可能过期。
  final VoidCallback? onSourceStale;

  @override
  ConsumerState<AppBackdropVideoView> createState() =>
      _AppBackdropVideoViewState();
}

class _AppBackdropVideoViewState extends ConsumerState<AppBackdropVideoView>
    with WidgetsBindingObserver {
  bool? _lastLayoutUsable;
  String? _lastSessionSignature;
  bool _usingFallback = false;
  bool _sourceStaleNotified = false;

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
  void didUpdateWidget(AppBackdropVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        AppBackdropVideoSession.sourceIdentityOf(oldWidget.source) !=
        AppBackdropVideoSession.sourceIdentityOf(widget.source);
    if (identityChanged) {
      _usingFallback = false;
      _sourceStaleNotified = false;
    }
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
    // session 是 ChangeNotifier:open 完成/失败必须驱动重建,
    // 否则 Video 会一直持有 dispose 前的旧 controller(表现为启动无背景、要点两次)。
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
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
              _notifySourceStaleOnce();
            } else if (session.openError != null &&
                !_usingFallback &&
                widget.source.startsWith('http')) {
              _notifySourceStaleOnce();
            }
            final source = _effectiveSource;
            _syncSession(
              source: source,
              muted: widget.muted,
              active: widget.playing && hasUsableLayout,
              layoutUsable: hasUsableLayout,
            );
            // 视频层保持挂载:仅用透明度门控。拆卸 Video 会在 Android 后台
            // 纹理回收后重新创建纹理,表现为恢复瞬间黑屏再“重启”。
            // 全屏/尺寸切换时若短暂 !renderable,仍保持已有 controller
            // 的透明度 1,避免露出垫底层造成默认壁纸/黑屏闪帧。
            final hasController = session.controller != null;
            final visible =
                hasController && session.ready && session.renderable;
            final keepMountedOpacity =
                hasController && (visible || session.ready);
            if (!hasController) {
              return const SizedBox.shrink();
            }
            return RepaintBoundary(
              child: AnimatedOpacity(
                opacity: keepMountedOpacity ? 1 : 0,
                duration: const Duration(milliseconds: 80),
                curve: Curves.easeOut,
                child: Video(
                  key: ValueKey(session.controller),
                  controller: session.controller!,
                  fit: widget.fit,
                  controls: NoVideoControls,
                  wakelock: false,
                  pauseUponEnteringBackgroundMode: true,
                  resumeUponEnteringForegroundMode: true,
                ),
              ),
            );
          },
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
    devLog('背景视频主源打开失败,回退内置壁纸');
  }

  void _notifySourceStaleOnce() {
    if (_sourceStaleNotified) {
      return;
    }
    _sourceStaleNotified = true;
    widget.onSourceStale?.call();
  }

  void _syncSession({
    required String source,
    required bool muted,
    required bool active,
    required bool layoutUsable,
  }) {
    final sourceIdentity = AppBackdropVideoSession.sourceIdentityOf(source);
    final signature = '$sourceIdentity:$muted:$active:$layoutUsable';
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
