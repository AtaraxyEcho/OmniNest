import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:omninest/core/media/media_kit_ready.dart';

/// Photos 时间线视频播放器，页面离开时释放解码与网络资源。
class PhotoVideoPlayer extends StatefulWidget {
  const PhotoVideoPlayer({required this.url, this.onError, super.key});

  final String url;
  final VoidCallback? onError;

  @override
  State<PhotoVideoPlayer> createState() => _PhotoVideoPlayerState();
}

class _PhotoVideoPlayerState extends State<PhotoVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    ensureMediaKitReady();
    _player = Player();
    _controller = VideoController(_player);
    _errorSubscription = _player.stream.error.listen((_) {
      widget.onError?.call();
    });
    unawaited(_player.open(Media(widget.url), play: false));
  }

  @override
  void didUpdateWidget(PhotoVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      unawaited(_player.open(Media(widget.url), play: false));
    }
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Video(controller: _controller);
}
