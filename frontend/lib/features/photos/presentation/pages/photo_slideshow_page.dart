import 'dart:async';
import 'dart:ui' as ui show Image, ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/utils/fullscreen_helper.dart' as fs;
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/platform/photo_batch_web_download.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_info_row.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_panel.dart';

const _slideshowInterval = Duration(seconds: 5);
const _transitionDuration = Duration(milliseconds: 600);
const _idleHideDuration = Duration(seconds: 3);
const _curve = Cubic(0.76, 0.0, 0.24, 1.0);
const _preloadRadius = 2;

/// 全屏沉浸幻灯片页（设计稿：Photos Management UI Design）。
///
/// 黑底满屏原图、双层交叉过渡（方向感知）、分段进度条、可折叠缩略图条、
/// Info 面板、键盘与全屏切换；控制层 3 秒无操作自动隐藏并隐藏光标。
class PhotoSlideshowPage extends ConsumerStatefulWidget {
  const PhotoSlideshowPage({
    required this.photos,
    required this.source,
    this.sourceKey,
    this.initialIndex = 0,
    super.key,
  });

  final List<PhotoItem> photos;
  final PhotoBrowseSource source;
  final String? sourceKey;
  final int initialIndex;

  @override
  ConsumerState<PhotoSlideshowPage> createState() => _PhotoSlideshowPageState();
}

class _PhotoSlideshowPageState extends ConsumerState<PhotoSlideshowPage>
    with SingleTickerProviderStateMixin {
  late List<PhotoItem> _photos;
  late int _current;
  int? _leaving;
  bool _directionNext = true;
  bool _isPlaying = true;
  bool _controlsVisible = true;
  bool _thumbnailsVisible = true;
  bool _showInfo = false;
  bool _showShare = false;
  Timer? _idleTimer;
  late AnimationController _progressController;
  WindowChromeLease? _windowChromeLease;

  /// 已解码位图缓存：SlideLayer 只接受这里的位图，禁止任何占位路径。
  final Map<String, ui.Image> _decodedImages = {};

  /// 进行中的解码任务（single-flight：同一张图只加载一次）。
  final Map<String, Future<ui.Image?>> _loadingImages = {};

  /// PREPARING 阶段：目标位图未就绪，不切换 current。
  bool _preparing = true;

  /// TRANSITIONING 阶段：交叉动画进行中。
  bool _transitioning = false;

  /// 背景层索引：独立于 current，动画完成后再跟进新图（避免背景突跳）。
  late int _backdropIndex;

  @override
  void initState() {
    super.initState();
    _photos = List.unmodifiable(widget.photos);
    _current = widget.initialIndex.clamp(0, _photos.length - 1);
    // 进度条经 ValueListenableBuilder 局部刷新，避免 30ms tick 触发整页重建。
    _progressController = AnimationController(
      vsync: this,
      duration: _slideshowInterval,
    )..addStatusListener(_onProgressStatus);
    _backdropIndex = _current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _windowChromeLease = ref
          .read(windowChromeControllerProvider.notifier)
          .acquireImmersive(owner: 'photos.slideshow');
      // 首张同样走就绪门控（否则点开即播的那张是占位）。
      unawaited(
        _loadDecodedImage(_photos[_current]).then((_) {
          if (!mounted) return;
          setState(() => _preparing = false);
          _progressController.forward(from: 0);
          _preloadNeighbors();
        }),
      );
    });
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _goNext();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _progressController.dispose();
    _windowChromeLease?.release();
    super.dispose();
  }

  PhotoItem get _currentPhoto => _photos[_current];

  /// 播放集合随来源类型实时扩展：库/收藏跟随分页控制器，影集/标签为全量查询。
  void _ensurePlaylist() {
    switch (widget.source) {
      case PhotoBrowseSource.library:
      case PhotoBrowseSource.locations:
        final live =
            ref.read(photoCenterControllerProvider).asData?.value.photos;
        if (live != null && live.length > _photos.length) _photos = live;
      case PhotoBrowseSource.favorites:
        final live =
            ref.read(photoCenterControllerProvider).asData?.value.favorites;
        if (live != null && live.length > _photos.length) _photos = live;
      case PhotoBrowseSource.album:
        final detail =
            ref.read(photoAlbumDetailProvider(widget.sourceKey!)).asData?.value;
        final photos = detail?.photos;
        if (photos != null && photos.length > _photos.length) _photos = photos;
      case PhotoBrowseSource.tag:
        final tagged =
            ref.read(photosByTagProvider(widget.sourceKey!)).asData?.value;
        if (tagged != null && tagged.length > _photos.length) _photos = tagged;
      case PhotoBrowseSource.timeline:
        // 时间线范围播放由批次 B 的 by-period 端点接入。
        break;
    }
  }

  bool _hasImage(PhotoItem item) =>
      (item.sourceUrl ?? item.coverUrl)?.isNotEmpty == true;

  Future<void> _goTo(int index, {required bool next}) async {
    if (_transitioning || _preparing || _photos.isEmpty) return;
    final target = ((index % _photos.length) + _photos.length) % _photos.length;
    if (target == _current) return;
    // 无图照片（元数据条目）：无需位图，直接切换到占位层。
    if (!_hasImage(_photos[target])) {
      setState(() {
        _leaving = _current;
        _directionNext = next;
        _current = target;
      });
      _progressController.forward(from: 0);
      Timer(_transitionDuration, () {
        if (!mounted) return;
        setState(() {
          _leaving = null;
          _transitioning = false;
          _backdropIndex = _current;
        });
        _pruneWindow();
      });
      return;
    }
    // PREPARING：目标位图就绪前不切换 current（保持当前帧等待）。
    _preparing = true;
    final image = await _loadDecodedImage(_photos[target]);
    if (!mounted) {
      _preparing = false;
      return;
    }
    if (image == null) {
      // 加载失败（网络错误等）：保持当前图，允许用户重试。
      setState(() => _preparing = false);
      return;
    }
    // TRANSITIONING：位图已就绪，动画只做合成，不触碰图片来源。
    setState(() {
      _leaving = _current;
      _directionNext = next;
      _current = target;
      _preparing = false;
      _transitioning = true;
    });
    _progressController.forward(from: 0);
    Timer(_transitionDuration, () {
      if (!mounted) return;
      setState(() {
        _leaving = null;
        _transitioning = false;
        // 动画完成后背景才跟进新图（切换期间背景保持旧图稳定）。
        _backdropIndex = _current;
      });
      _pruneWindow();
      _preloadNeighbors();
    });
  }

  void _goNext() => _goTo(_current + 1, next: true);

  void _goPrev() => _goTo(_current - 1, next: false);

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _progressController.forward(from: 0);
      } else {
        _progressController.reset();
        _idleTimer?.cancel();
      }
      _controlsVisible = true;
    });
  }

  void _resetIdle() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleHideDuration, () {
      if (!mounted) return;
      if (_isPlaying) setState(() => _controlsVisible = false);
    });
  }

  /// 统一 provider 构造：URL、cacheKey、Resize、DPR 完全由这里决定。
  ImageProvider<Object>? _imageProvider(PhotoItem item, BuildContext context) {
    final url = item.sourceUrl ?? item.coverUrl;
    if (url == null || url.isEmpty) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screenSize = MediaQuery.sizeOf(context);
    final memCacheWidth = (screenSize.width * dpr).round().clamp(1, 8192);
    return ResizeImage.resizeIfNeeded(
      memCacheWidth,
      null,
      CachedNetworkImageProvider(
        url,
        cacheKey:
            item.sourceUrl != null ? item.sourceCacheKey : item.coverCacheKey,
      ),
    );
  }

  /// 解码 provider 为位图；失败（网络错误等）返回 null 而非抛出。
  Future<ui.Image?> _decodeImage(ImageProvider<Object> provider) async {
    final completer = Completer<ui.Image?>();
    late final ImageStreamListener listener;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        // 解码完成即移除监听：位图由本页 _decodedImages 持有（窗口化缓存），
        // 不依赖永久 listener 保活。
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// Single-flight 加载：同一张图无论被请求多少次只做一次真正加载/解码。
  Future<ui.Image?> _loadDecodedImage(PhotoItem item) {
    final id = item.id;
    final cached = _decodedImages[id];
    if (cached != null) {
      return Future.value(cached);
    }
    final loading = _loadingImages[id];
    if (loading != null) {
      return loading;
    }
    final provider = _imageProvider(item, context);
    if (provider == null) {
      // 无图可解码的照片：null 由调用方按占位层处理。
      return Future.value(null);
    }
    final future = _decodeImage(provider)
        .then((image) {
          if (image != null) {
            _decodedImages[id] = image;
          }
          return image;
        })
        .whenComplete(() => _loadingImages.remove(id));
    _loadingImages[id] = future;
    return future;
  }

  /// 后台预热（不参与 UI 状态判断）。
  void _preloadImage(int index) {
    if (index < 0 || index >= _photos.length) return;
    unawaited(_loadDecodedImage(_photos[index]));
  }

  /// 预加载优先级：下一张 > 上一张 > 下下张 > 上上张。
  void _preloadNeighbors() {
    for (final offset in [1, -1, 2, -2]) {
      final index =
          ((_current + offset) % _photos.length + _photos.length) %
          _photos.length;
      _preloadImage(index);
    }
  }

  /// 窗口化缓存：只保留 current ± 半径的解码位图，释放更早的图。
  void _pruneWindow() {
    final keep = <String>{
      for (var offset = -_preloadRadius; offset <= _preloadRadius; offset++)
        _photos[((_current + offset) % _photos.length + _photos.length) %
                _photos.length]
            .id,
    };
    _decodedImages.removeWhere((id, _) => !keep.contains(id));
  }

  void _toggleFullscreen() {
    if (kIsWeb) {
      fs.toggleFullscreen();
      return;
    }
    ref.read(windowChromeControllerProvider.notifier).toggleFullscreen();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    _resetIdle();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.space) {
      _goNext();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _goPrev();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI) {
      setState(() {
        _showInfo = !_showInfo;
        if (_showInfo) _showShare = false;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && (_showInfo || _showShare)) {
      setState(() {
        _showInfo = false;
        _showShare = false;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _toggleFavorite(PhotoItem photo) async {
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .toggleFavorite(photo.id, currentFavorite: photo.favorite);
      if (!mounted) return;
      ref.invalidate(photoDetailProvider(photo.id));
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).photosOperationFailed),
        ),
      );
    }
  }

  Future<void> _downloadPhoto(PhotoItem photo) async {
    final sourceUrl = photo.sourceUrl;
    if (sourceUrl == null || sourceUrl.isEmpty) return;
    try {
      if (kIsWeb) {
        unawaited(
          downloadPhotoBatchInBrowser(
            url: sourceUrl,
            fileName: photo.downloadFileName,
          ),
        );
        return;
      }
      final savedPath = await ref
          .read(photoCenterControllerProvider.notifier)
          .savePhotoFileToDisk(
            url: sourceUrl,
            sizeBytes: photo.fileSize,
            suggestedName: photo.downloadFileName,
          );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).photosDownloadSaved(savedPath),
          ),
        ),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).photosDownloadFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensurePlaylist();
    final photo = _currentPhoto;
    final showControls = _controlsVisible || !_isPlaying;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: MouseRegion(
          cursor:
              _controlsVisible ? MouseCursor.defer : SystemMouseCursors.none,
          onHover: (_) => _resetIdle(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _resetIdle,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_decodedImages[photo.id] != null) ...[
                  _buildBackdrop(_photos[_backdropIndex]),
                  _buildSlides(photo),
                ] else
                  const Center(
                    child: SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0x66FFFFFF),
                      ),
                    ),
                  ),
                _buildGradients(showControls),
                _buildTopBar(context, photo, showControls),
                if (_photos.length > 1) ...[
                  _buildArrow(context, right: false, visible: showControls),
                  _buildArrow(context, right: true, visible: showControls),
                ],
                _buildBottomArea(context, photo, showControls),
                // 面板 scrim 在侧栏之下（zIndex 语义），点击空白处同时收起。
                if (_showInfo || _showShare)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap:
                          () => setState(() {
                            _showInfo = false;
                            _showShare = false;
                          }),
                    ),
                  ),
                _buildInfoPanel(context, photo),
                PhotoSharePanel(
                  visible: _showShare,
                  photo: photo,
                  onDone:
                      () => setState(() {
                        _showShare = false;
                      }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 幻灯片层（静态模糊背景 + 离场/入场前景交叉过渡） ───

  /// 页面级模糊背景：96px 超低分辨率缩略图放大拉伸 + RepaintBoundary。
  ///
  /// 低分辨率放大本身即强模糊，sigma 滤波只作用于 96px 小纹理（成本可忽略）；
  /// RepaintBoundary 使该层稳定数帧后进入光栅缓存——前景动画帧不触发
  /// 全屏重滤波（此前每次前景交叉都会整帧重算 sigma40 模糊，是掉帧主因）。
  Widget _buildBackdrop(PhotoItem photo) {
    final thumb = photo.coverUrl;
    if (thumb == null || thumb.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: RepaintBoundary(
        child: Transform.scale(
          scale: 1.12,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: thumb,
                  cacheKey: photo.coverCacheKey,
                  memCacheWidth: 96,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  fadeInDuration: Duration.zero,
                  errorWidget:
                      (context, url, error) =>
                          const ColoredBox(color: Colors.black),
                ),
                ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlides(PhotoItem photo) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_leaving != null && _leaving! < _photos.length)
          Positioned.fill(
            child: _SlideLayer(
              key: ValueKey('leaving-$_leaving'),
              item: _photos[_leaving!],
              decoded: _decodedImages[_photos[_leaving!].id],
              leaving: true,
              directionNext: _directionNext,
            ),
          ),
        Positioned.fill(
          child: _SlideLayer(
            key: ValueKey('current-${photo.id}'),
            item: photo,
            decoded: _decodedImages[photo.id],
            leaving: false,
            directionNext: _directionNext,
          ),
        ),
      ],
    );
  }

  // ─── 渐变遮罩 ───

  Widget _buildGradients(bool visible) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: visible ? 1 : 0.4,
            duration: const Duration(milliseconds: 500),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment(0, -0.4),
                  colors: [
                    Color(0xB8000000),
                    Color(0x2E000000),
                    Colors.transparent,
                  ],
                  stops: [0, 0.35, 0.6],
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 500),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment(0, 0.3),
                  colors: [Color(0x80000000), Colors.transparent],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 顶部栏 ───

  Widget _buildTopBar(BuildContext context, PhotoItem photo, bool visible) {
    final l10n = AppLocalizations.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -0.2),
          duration: const Duration(milliseconds: 400),
          curve: Curves.ease,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Row(
              children: [
                _ViewerIconButton(
                  tooltip: l10n.photosBackToPhotos,
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.photosModuleDisplayName,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 13,
                    letterSpacing: 0.04,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(_current + 1).toString().padLeft(2, '0')} / '
                  '${_photos.length.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 12,
                    letterSpacing: 0.08,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    _ViewerIconButton(
                      tooltip: l10n.photosFavorite,
                      icon:
                          photo.favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                      color:
                          photo.favorite
                              ? const Color(0xFFFB7185)
                              : Colors.white.withValues(alpha: 0.70),
                      onTap: () => _toggleFavorite(photo),
                    ),
                    const SizedBox(width: 16),
                    _ViewerIconButton(
                      tooltip: l10n.photosSharePhoto,
                      icon: Icons.share_rounded,
                      color:
                          _showShare
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.70),
                      onTap:
                          () => setState(() {
                            _showShare = !_showShare;
                            if (_showShare) _showInfo = false;
                          }),
                    ),
                    const SizedBox(width: 16),
                    _ViewerIconButton(
                      tooltip: l10n.photosDownloadPhoto,
                      icon: Icons.download_rounded,
                      onTap: () => unawaited(_downloadPhoto(photo)),
                    ),
                    const SizedBox(width: 16),
                    _ViewerIconButton(
                      tooltip:
                          _showInfo ? l10n.photosHideInfo : l10n.photosShowInfo,
                      icon: Icons.info_outline_rounded,
                      color:
                          _showInfo
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.70),
                      onTap: () => setState(() => _showInfo = !_showInfo),
                    ),
                    const SizedBox(width: 16),
                    _ViewerIconButton(
                      tooltip: l10n.photosFullscreen,
                      icon: Icons.fullscreen_rounded,
                      onTap: _toggleFullscreen,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 左右箭头 ───

  Widget _buildArrow(
    BuildContext context, {
    required bool right,
    required bool visible,
  }) {
    final l10n = AppLocalizations.of(context);
    return Positioned(
      left: right ? null : 20,
      right: right ? 20 : null,
      top: 0,
      bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: AnimatedSlide(
            offset: visible ? Offset.zero : Offset(right ? 0.08 : -0.08, 0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.ease,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: right ? _goNext : _goPrev,
                child: Tooltip(
                  message: right ? l10n.photosNextPhoto : l10n.photosPrevPhoto,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0),
                    ),
                    child: Icon(
                      right
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_left_rounded,
                      size: 28,
                      color: Colors.white.withValues(alpha: 0.70),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── 底部区（元信息 + 播放/暂停 + 分段进度 + 缩略图条开关 + 缩略图条） ───

  Widget _buildBottomArea(BuildContext context, PhotoItem photo, bool visible) {
    final preferZh = Localizations.localeOf(context).languageCode == 'zh';
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.12),
          duration: const Duration(milliseconds: 400),
          curve: Curves.ease,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  photo.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -0.01,
                  ),
                ),
                Text(
                  _metaLine(photo, preferZh),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    letterSpacing: 0.06,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    IconButton(
                      tooltip:
                          _isPlaying
                              ? AppLocalizations.of(context).photosPause
                              : AppLocalizations.of(context).photosPlay,
                      onPressed: _togglePlay,
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white.withValues(alpha: 0.80),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSegments()),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed:
                          () => setState(
                            () => _thumbnailsVisible = !_thumbnailsVisible,
                          ),
                      child: Text(
                        _thumbnailsVisible
                            ? AppLocalizations.of(context).photosStripHide
                            : AppLocalizations.of(context).photosStripShow,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.50),
                          fontSize: 11,
                          letterSpacing: 0.08,
                        ),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  child:
                      _thumbnailsVisible
                          ? _buildThumbnailStrip()
                          : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 分段进度条 ───

  Widget _buildSegments() {
    return SizedBox(
      height: 2,
      child: Row(
        children: [
          for (var i = 0; i < _photos.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _goTo(i, next: i > _current),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: RepaintBoundary(
                    // 隔离绘制：进度 tick 的重绘不传播到页面根。
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      // 仅当前段跟随进度逐帧刷新；其余段为静态，避免照片多时每 30ms 重建全部段。
                      child:
                          i == _current
                              ? ValueListenableBuilder<double>(
                                valueListenable: _progressController,
                                builder:
                                    (context, progress, _) => _buildSegmentBar(
                                      _progressValueFor(i, progress),
                                    ),
                              )
                              : _buildSegmentBar(_progressValueFor(i, 0)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSegmentBar(double value) {
    return LinearProgressIndicator(
      value: value,
      minHeight: 2,
      backgroundColor: Colors.white.withValues(alpha: 0.20),
      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xE6FFFFFF)),
    );
  }

  double _progressValueFor(int index, double progress) {
    if (index < _current) return 1;
    if (index > _current) return 0;
    return _isPlaying ? progress : 0;
  }

  // ─── 缩略图条 ───

  Widget _buildThumbnailStrip() {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == _current;
          final thumb = _photos[index].coverUrl;
          return Opacity(
            opacity: selected ? 1 : 0.45,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _goTo(index, next: index > _current),
              child: Container(
                width: 72,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color:
                        selected
                            ? Colors.white.withValues(alpha: 0.90)
                            : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child:
                      thumb != null && thumb.isNotEmpty
                          ? CachedNetworkImage(
                            imageUrl: thumb,
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            errorWidget:
                                (context, url, error) => ColoredBox(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                          )
                          : ColoredBox(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Info 面板 ───

  Widget _buildInfoPanel(BuildContext context, PhotoItem photo) {
    final preferZh = Localizations.localeOf(context).languageCode == 'zh';
    final l10n = AppLocalizations.of(context);
    // 与详情页信息侧栏共用同一字段集（buildPhotoInfoEntries），有值才渲染。
    final rows = buildPhotoInfoEntries(photo, l10n, preferZh: preferZh);
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: 288,
      child: AnimatedSlide(
        offset: _showInfo ? Offset.zero : const Offset(1, 0),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        child: Container(
          color: const Color(0xF00A0A0A),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).photosPhotoInfo,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.30),
                    fontSize: 10,
                    letterSpacing: 0.14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  photo.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 32),
                if (rows.isEmpty)
                  Text(
                    '—',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 12,
                    ),
                  )
                else
                  for (final row in rows)
                    PhotoInfoRow(label: row.label, value: row.value),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _InfoPanelButton(
                        icon:
                            photo.favorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                        iconColor:
                            photo.favorite
                                ? const Color(0xFFFB7185)
                                : Colors.white.withValues(alpha: 0.80),
                        label:
                            photo.favorite
                                ? AppLocalizations.of(context).photosUnfavorite
                                : AppLocalizations.of(context).photosFavorite,
                        onTap: () => unawaited(_toggleFavorite(photo)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _InfoPanelButton(
                        icon: Icons.share_rounded,
                        label: l10n.photosSharePhoto,
                        onTap:
                            () => setState(() {
                              _showInfo = false;
                              _showShare = true;
                            }),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 辅助方法 ───

  String _metaLine(PhotoItem photo, bool preferZh) {
    final location = photo.locationDisplay(preferZh: preferZh);
    final date = photo.dateTaken ?? photo.createdAt;
    final dateText =
        date == null
            ? null
            : '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}';
    return [location, dateText].whereType<String>().join(' · ');
  }
}

/// 前景幻灯片层：contain 原图，进入/离场由父级过渡驱动。
///
/// 模糊背景在页面级（_buildBackdrop），本层不再包含 ImageFiltered，
/// 避免逐帧动画触发全屏重滤波导致掉帧闪烁。
///
/// 丝滑关键：图片子树由 [RepaintBoundary] 包裹且动画全程保持同一实例
/// （光栅缓存命中后每帧只做合成级平移/缩放/淡变，不再逐帧重绘大图），
/// 动画用 FadeTransition/Transform 直接驱动 Layer 属性而非重建子树。
class _SlideLayer extends StatefulWidget {
  const _SlideLayer({
    required this.item,
    required this.decoded,
    required this.leaving,
    required this.directionNext,
    super.key,
  });

  final PhotoItem item;

  /// 已解码位图；就绪门控保证有图照片动画开始时非空（RawImage 直接绘制）。
  /// 无图照片（元数据条目）为 null，渲染为纯色占位层。
  final ui.Image? decoded;
  final bool leaving;
  final bool directionNext;

  @override
  State<_SlideLayer> createState() => _SlideLayerState();
}

class _SlideLayerState extends State<_SlideLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _transitionDuration,
    );
    _fade = Tween<double>(
      begin: widget.leaving ? 1.0 : 0.0,
      end: widget.leaving ? 0.0 : 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: _curve));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 就绪门控保证动画开始时位图必到位：本层只绘制已解码位图，
    // 渲染路径上没有任何网络/异步/占位状态机，不存在二次加载。
    final image =
        widget.decoded != null
            ? RawImage(
              image: widget.decoded,
              fit: BoxFit.contain,
              // 主图 high：缩放动画期间最高采样质量；缩略图/backdrop 仍为 medium。
              filterQuality: FilterQuality.high,
            )
            : const ColoredBox(color: Colors.black);
    return AnimatedBuilder(
      animation: _controller,
      child: RepaintBoundary(child: SizedBox.expand(child: image)),
      builder: (context, child) {
        final t = _fade.value;
        final dx =
            widget.leaving
                ? (widget.directionNext ? -4.0 : 4.0) * t
                : (widget.directionNext ? 4.0 : -4.0) * (1 - t);
        final scale = widget.leaving ? 1.0 - 0.03 * t : 1.02 - 0.02 * t;
        return FadeTransition(
          opacity: _fade,
          child: Transform(
            alignment: Alignment.center,
            transform:
                Matrix4.identity()
                  ..translateByDouble(dx, 0, 0, 1)
                  ..scaleByDouble(scale, scale, 1, 1),
            child: child,
          ),
        );
      },
    );
  }
}

/// Info 面板底部操作按钮：Like / Share。
class _InfoPanelButton extends StatelessWidget {
  const _InfoPanelButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: iconColor ?? Colors.white.withValues(alpha: 0.80),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.80),
                  fontSize: 12,
                  letterSpacing: 0.04,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 图标按钮：透明底、hover 白、跟随控制显隐。
class _ViewerIconButton extends StatelessWidget {
  const _ViewerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        size: 20,
        color: color ?? Colors.white.withValues(alpha: 0.70),
      ),
    );
  }
}
