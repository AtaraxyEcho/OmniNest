import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_video_session.dart';

/// IO 平台(桌面/移动)的背景视频视图,基于 media_kit 播放会话。
/// source 可以是本机文件路径(内置壁纸)或服务端签名 URL。
class AppBackdropVideoView extends ConsumerStatefulWidget {
  const AppBackdropVideoView({
    required this.source,
    required this.fit,
    required this.playing,
    required this.muted,
    super.key,
  });

  final String source;
  final BoxFit fit;
  final bool playing;
  final bool muted;

  @override
  ConsumerState<AppBackdropVideoView> createState() =>
      _AppBackdropVideoViewState();
}

class _AppBackdropVideoViewState extends ConsumerState<AppBackdropVideoView>
    with WidgetsBindingObserver {
  bool? _lastLayoutUsable;
  String? _lastSessionSignature;

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
        _syncSession(
          source: widget.source,
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
