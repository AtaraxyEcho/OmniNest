part of 'file_preview_page.dart';

class _AudioPreview extends ConsumerWidget {
  const _AudioPreview({required this.file});

  final FileNode file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(filePreviewDownloadUrlProvider(file));
    return urlAsync.when(
      data: (url) {
        if (url == null || url.isEmpty) {
          return Center(
            child: Text(AppLocalizations.of(context).filesCannotLoadAudio),
          );
        }
        return _AudioPlayerBody(key: ValueKey(url), file: file, url: url);
      },
      loading: () => const AppLoading(),
      error:
          (e, st) => Center(
            child: Text(AppLocalizations.of(context).filesCannotGetAudioUrl),
          ),
    );
  }
}

class _AudioPlayerBody extends StatefulWidget {
  const _AudioPlayerBody({required this.file, required this.url, super.key});

  final FileNode file;
  final String url;

  @override
  State<_AudioPlayerBody> createState() => _AudioPlayerBodyState();
}

class _AudioPlayerBodyState extends State<_AudioPlayerBody> {
  late final Player _player;
  late final MediaPreviewLoadController _loadController;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _loadController = MediaPreviewLoadController(
      opener: (url) => _player.open(Media(url)),
    )..addListener(_handleLoadChanged);
    _playingSub = _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });
    _positionSub = _player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _durationSub = _player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    unawaited(_loadController.load(widget.url));
  }

  void _handleLoadChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _loadController
      ..removeListener(_handleLoadChanged)
      ..dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_loadController.state) {
      MediaPreviewLoadState.loading => const AppLoading(),
      MediaPreviewLoadState.failed => _MediaPreviewFailure(
        message: AppLocalizations.of(context).filesCannotLoadAudio,
        onRetry: () => unawaited(_loadController.retry()),
      ),
      MediaPreviewLoadState.ready => CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.space):
              () => _player.playOrPause(),
          const SingleActivator(LogicalKeyboardKey.arrowLeft):
              () => _seekBy(const Duration(seconds: -5)),
          const SingleActivator(LogicalKeyboardKey.arrowRight):
              () => _seekBy(const Duration(seconds: 5)),
          const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
        },
        child: Focus(
          autofocus: true,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.audiotrack,
                        size: 64,
                        color: context.filesColors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppTypography.titleMedium,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      AppSlider(
                        value:
                            _duration.inMilliseconds <= 0
                                ? 0
                                : (_position.inMilliseconds /
                                        _duration.inMilliseconds)
                                    .clamp(0.0, 1.0),
                        onChanged: (value) {
                          final pos = Duration(
                            milliseconds:
                                (value * _duration.inMilliseconds).round(),
                          );
                          _player.seek(pos);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(_position),
                              style: TextStyle(
                                fontSize: AppTypography.bodySmall,
                                color: context.filesColors.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              _formatDuration(_duration),
                              style: TextStyle(
                                fontSize: AppTypography.bodySmall,
                                color: context.filesColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip:
                                _playing
                                    ? AppLocalizations.of(context).corePause
                                    : AppLocalizations.of(context).corePlay,
                            iconSize: 48,
                            icon: Icon(
                              _playing
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              color: context.filesColors.primary,
                            ),
                            onPressed: () => _player.playOrPause(),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            tooltip:
                                _muted
                                    ? AppLocalizations.of(context).musicUnmute
                                    : AppLocalizations.of(context).musicMute,
                            iconSize: 24,
                            icon: Icon(
                              _muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: context.filesColors.onSurfaceVariant,
                            ),
                            onPressed: _toggleMute,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    };
  }

  void _seekBy(Duration delta) {
    var target = _position + delta;
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (_duration > Duration.zero && target > _duration) {
      target = _duration;
    }
    _player.seek(target);
  }

  void _toggleMute() {
    _muted = !_muted;
    _player.setVolume(_muted ? 0 : 100);
    setState(() {});
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

enum MediaPreviewLoadState { loading, ready, failed }

/// 预览打开进度的 Widget 本地编排器。
///
/// 仅承载 presentation 层 loading/ready/failed 与 generation 防串台，
/// 不持有业务领域状态；按 AGENTS 属于页面私有短生命周期控制。
class MediaPreviewLoadController extends ChangeNotifier {
  MediaPreviewLoadController({required this.opener});

  final Future<void> Function(String url) opener;
  MediaPreviewLoadState state = MediaPreviewLoadState.loading;
  String? _url;
  var _generation = 0;
  var _disposed = false;

  Future<void> load(String url) async {
    final generation = ++_generation;
    _url = url;
    state = MediaPreviewLoadState.loading;
    _notifySafely();
    try {
      await opener(url);
      if (_disposed || generation != _generation) {
        return;
      }
      state = MediaPreviewLoadState.ready;
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      state = MediaPreviewLoadState.failed;
    }
    _notifySafely();
  }

  Future<void> retry() async {
    final url = _url;
    if (url != null) {
      await load(url);
    }
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
