import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/utils/image_decode_width.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/files/application/file_download_url_provider.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_type_utils.dart';

/// 全屏文件预览页面。
class FilePreviewPage extends ConsumerStatefulWidget {
  const FilePreviewPage({required this.file, super.key});

  final FileNode file;

  @override
  ConsumerState<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends ConsumerState<FilePreviewPage> {
  @override
  Widget build(BuildContext context) {
    final previewType = classifyForPreview(
      widget.file.mimeType,
      widget.file.name,
    );
    final compact = MediaQuery.sizeOf(context).width < 600;
    final preview = switch (previewType) {
      FilePreviewType.image => _ImagePreview(file: widget.file),
      FilePreviewType.video => _VideoPreview(file: widget.file),
      FilePreviewType.audio => _AudioPreview(file: widget.file),
      FilePreviewType.text => _TextPreview(file: widget.file),
      FilePreviewType.pdf => _PdfPreview(file: widget.file),
      FilePreviewType.unsupported => _UnsupportedPreview(file: widget.file),
    };

    return Scaffold(
      backgroundColor:
          compact ? context.mobileColors.pageMask : context.filesColors.surface,
      appBar: AppBar(
        backgroundColor:
            compact
                ? context.mobileColors.pageMask.withValues(alpha: 0.98)
                : null,
        foregroundColor: compact ? context.mobileColors.textPrimary : null,
        title: Text(
          widget.file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!compact)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  formatFileSize(widget.file.sizeBytes),
                  style: TextStyle(
                    fontSize: AppTypography.bodyMedium,
                    color: context.filesColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: compact ? MobilePageSurface(child: preview) : preview,
    );
  }
}

// ---- 图片预览 ----

class _ImagePreview extends ConsumerWidget {
  const _ImagePreview({required this.file});

  final FileNode file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(fileDownloadUrlProvider(file.id));
    return urlAsync.when(
      data: (url) {
        if (url == null || url.isEmpty) {
          return Center(
            child: Text(AppLocalizations.of(context).filesCannotLoadImage),
          );
        }
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              // 预览按屏宽解码并量化档位，最大化时不反复重解码。
              memCacheWidth: quantizedDecodeWidth(
                logicalWidth: MediaQuery.sizeOf(context).width,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                step: 512,
                min: 800,
                max: 8192,
                scale: 5,
              ),
              placeholder: (context, url) => const AppLoading.simple(),
              errorWidget:
                  (context, url, error) => Center(
                    child: Text(
                      AppLocalizations.of(context).filesImageLoadFailed,
                    ),
                  ),
            ),
          ),
        );
      },
      loading: () => const AppLoading.simple(),
      error:
          (e, st) => Center(
            child: Text(AppLocalizations.of(context).filesCannotGetImageUrl),
          ),
    );
  }
}

// ---- 视频预览 ----

class _VideoPreview extends ConsumerWidget {
  const _VideoPreview({required this.file});

  final FileNode file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(fileDownloadUrlProvider(file.id));
    return urlAsync.when(
      data: (url) {
        if (url == null || url.isEmpty) {
          return Center(
            child: Text(AppLocalizations.of(context).filesCannotLoadVideo),
          );
        }
        return _VideoPlayerBody(key: ValueKey(url), url: url);
      },
      loading: () => const AppLoading.simple(),
      error:
          (e, st) => Center(
            child: Text(AppLocalizations.of(context).filesCannotGetVideoUrl),
          ),
    );
  }
}

class _VideoPlayerBody extends StatefulWidget {
  const _VideoPlayerBody({required this.url, super.key});

  final String url;

  @override
  State<_VideoPlayerBody> createState() => _VideoPlayerBodyState();
}

class _VideoPlayerBodyState extends State<_VideoPlayerBody> {
  late final Player _player;
  late final VideoController _videoController;
  late final MediaPreviewLoadController _loadController;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _loadController = MediaPreviewLoadController(
      opener: (url) => _player.open(Media(url)),
    )..addListener(_handleLoadChanged);
    unawaited(_loadController.load(widget.url));
  }

  void _handleLoadChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _loadController
      ..removeListener(_handleLoadChanged)
      ..dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_loadController.state) {
      MediaPreviewLoadState.loading => const AppLoading.simple(),
      MediaPreviewLoadState.failed => _MediaPreviewFailure(
        message: AppLocalizations.of(context).filesCannotLoadVideo,
        onRetry: () => unawaited(_loadController.retry()),
      ),
      MediaPreviewLoadState.ready => Center(
        child: Video(controller: _videoController),
      ),
    };
  }
}

// ---- 音频预览 ----

class _AudioPreview extends ConsumerWidget {
  const _AudioPreview({required this.file});

  final FileNode file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(fileDownloadUrlProvider(file.id));
    return urlAsync.when(
      data: (url) {
        if (url == null || url.isEmpty) {
          return Center(
            child: Text(AppLocalizations.of(context).filesCannotLoadAudio),
          );
        }
        return _AudioPlayerBody(key: ValueKey(url), file: file, url: url);
      },
      loading: () => const AppLoading.simple(),
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
      MediaPreviewLoadState.loading => const AppLoading.simple(),
      MediaPreviewLoadState.failed => _MediaPreviewFailure(
        message: AppLocalizations.of(context).filesCannotLoadAudio,
        onRetry: () => unawaited(_loadController.retry()),
      ),
      MediaPreviewLoadState.ready => Center(
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
                  // 进度条
                  AppSlider(
                    value:
                        _duration.inMilliseconds > 0
                            ? _position.inMilliseconds /
                                _duration.inMilliseconds
                            : 0,
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
                  // 播放/暂停按钮
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
                ],
              ),
            ),
          ),
        ),
      ),
    };
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

class _MediaPreviewFailure extends StatelessWidget {
  const _MediaPreviewFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: context.filesColors.error,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(AppLocalizations.of(context).coreRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- 文本预览 ----

class _TextPreview extends ConsumerWidget {
  const _TextPreview({required this.file});

  final FileNode file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentAsync = ref.watch(fileTextPreviewProvider(file.id));
    return contentAsync.when(
      data:
          (content) => SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                content,
                style: const TextStyle(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontSize: AppTypography.bodyMedium,
                  height: 1.5,
                ),
              ),
            ),
          ),
      loading: () => const AppLoading.simple(),
      error:
          (error, stackTrace) => Center(
            child: Text(
              AppLocalizations.of(context).filesLoadFailed(
                describeUserFacingError(
                  error,
                  l10n: AppLocalizations.of(context),
                ).displayMessage,
              ),
            ),
          ),
    );
  }
}

// ---- PDF 预览 ----

class _PdfPreview extends StatelessWidget {
  const _PdfPreview({required this.file});

  final FileNode file;

  @override
  Widget build(BuildContext context) {
    return Center(
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
                  Icons.picture_as_pdf_outlined,
                  size: 64,
                  color: context.filesColors.error,
                ),
                const SizedBox(height: 16),
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppTypography.titleMedium,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).filesPdfDownloadHint,
                  style: TextStyle(
                    fontSize: AppTypography.bodyMedium,
                    color: context.filesColors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- 不支持的文件类型 ----

class _UnsupportedPreview extends StatelessWidget {
  const _UnsupportedPreview({required this.file});

  final FileNode file;

  @override
  Widget build(BuildContext context) {
    return Center(
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
                  Icons.insert_drive_file_outlined,
                  size: 64,
                  color: context.filesColors.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppTypography.titleMedium,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _InfoRow(
                  label: AppLocalizations.of(context).filesType,
                  value:
                      file.mimeType ??
                      AppLocalizations.of(context).filesUnknown,
                ),
                _InfoRow(
                  label: AppLocalizations.of(context).filesSizeLabel,
                  value: formatFileSize(file.sizeBytes),
                ),
                _InfoRow(
                  label: AppLocalizations.of(context).filesPath,
                  value: file.normalizedPath,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                color: context.filesColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: AppTypography.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}
