import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 动态照片运动视频播放层：静音循环播放提取出的 MP4 派生资产。
///
/// 组件自持 Player 生命周期，退出时释放；加载或播放失败回调 [onError]。
class PhotoMotionPlayer extends StatefulWidget {
  const PhotoMotionPlayer({required this.url, this.onError, super.key});

  final String url;
  final VoidCallback? onError;

  @override
  State<PhotoMotionPlayer> createState() => _PhotoMotionPlayerState();
}

class _PhotoMotionPlayerState extends State<PhotoMotionPlayer> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration(muted: true));
    _controller = VideoController(_player);
    _errorSubscription = _player.stream.error.listen(
      (_) => widget.onError?.call(),
    );
    unawaited(_player.setPlaylistMode(PlaylistMode.loop));
    unawaited(_player.open(Media(widget.url)));
  }

  @override
  void didUpdateWidget(PhotoMotionPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      unawaited(_player.open(Media(widget.url)));
    }
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Video(
      controller: _controller,
      fit: BoxFit.contain,
      controls: NoVideoControls,
    );
  }
}
