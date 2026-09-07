import 'dart:async';
import 'dart:ui' show ImageFilter;

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
const _maxReadyWait = Duration(seconds: 2);

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

  /// 已完成解码进入图片缓存的幻灯片 id；切换前必须就绪，动画不携带占位图。
  final Set<String> _readyImageIds = {};
  bool _transitioning = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _windowChromeLease = ref
          .read(windowChromeControllerProvider.notifier)
          .acquireImmersive(owner: 'photos.slideshow');
      _precacheNeighbors();
    });
    _progressController.forward(from: 0);
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

  Future<void> _goTo(int index, {required bool next}) async {
    if (_transitioning || _photos.isEmpty) return;
    final target = ((index % _photos.length) + _photos.length) % _photos.length;
    if (target == _current) return;
    // 提前置位：等待目标图就绪期间忽略重复触发。
    _transitioning = true;
    // 主流幻灯片策略：目标原图完成解码前不启动动画（当前帧保持等待，
    // 超时兜底强制推进），动画全程不携带占位图——消除"切换后二次加载"。
    await _ensureReady(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _leaving = _current;
      _directionNext = next;
      _current = target;
    });
    _progressController.forward(from: 0);
    Timer(_transitionDuration, () {
      if (!mounted) return;
      setState(() => _leaving = null);
      _transitioning = false;
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

  /// 确保目标原图完成解码进入图片缓存；超时或失败也标记就绪（动画带占位图兜底推进）。
  Future<void> _ensureReady(int index) async {
    final item = _photos[index];
    if (_readyImageIds.contains(item.id)) return;
    final provider = _rendererProvider(item, context);
    if (provider == null) {
      _readyImageIds.add(item.id);
      return;
    }
    try {
      await precacheImage(provider, context).timeout(_maxReadyWait);
    } catch (_) {
      // 失败/超时同样标记，避免每次切换重复等待同一张失败图
    }
    _readyImageIds.add(item.id);
  }

  void _precacheNeighbors() {
    for (final index in [_current + 1, _current - 1]) {
      if (index < 0 || index >= _photos.length) continue;
      unawaited(_ensureReady(index));
    }
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
                _buildBackdrop(photo),
                _buildSlides(photo),
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
            imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
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
              leaving: true,
              directionNext: _directionNext,
            ),
          ),
        Positioned.fill(
          child: _SlideLayer(
            key: ValueKey('current-${photo.id}'),
            item: photo,
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

/// 与渲染层逐字节一致的图片 provider（ResizeImage 包装，内存缓存 key 一致）。
///
/// 预取（_ensureReady）与渲染（_SlideLayer）必须共用本构造，否则内存缓存
/// key 不一致会导致预取失效、每次切换都走"占位图→原图"两段显示。
ImageProvider? _rendererProvider(PhotoItem item, BuildContext context) {
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
    required this.leaving,
    required this.directionNext,
    super.key,
  });

  final PhotoItem item;
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
    // 原图按屏宽降采样解码：contain 显示不会超过屏宽像素，
    // 全尺寸解码位图（4K 照片约 45MB/张）会把图片缓存预算挤爆，
    // 邻居预取互相驱逐导致每次切换重新下载解码（表现为闪烁）。
    final provider = _rendererProvider(widget.item, context);
    final imageUrl = widget.item.sourceUrl ?? widget.item.coverUrl;
    final thumbUrl = widget.item.coverUrl;
    // 原图尚未进缓存时以模糊缩略图兜底，避免入场瞬间闪黑；
    // 模糊后的缩略图与背景氛围一致，原图就绪时仅清晰度提升、不产生跳变。
    Widget? placeholder;
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      placeholder = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: CachedNetworkImage(
          imageUrl: thumbUrl,
          cacheKey: widget.item.coverCacheKey,
          fit: BoxFit.contain,
          fadeInDuration: Duration.zero,
          errorWidget:
              (context, url, error) => const ColoredBox(color: Colors.black),
        ),
      );
    }
    final image = CachedNetworkImage(
      imageUrl: imageUrl ?? '',
      cacheKey:
          widget.item.sourceUrl != null
              ? widget.item.sourceCacheKey
              : widget.item.coverCacheKey,
      memCacheWidth:
          provider == null
              ? null
              : (MediaQuery.devicePixelRatioOf(context) *
                      MediaQuery.sizeOf(context).width)
                  .round()
                  .clamp(1, 8192),
      // medium（mipmap 三线性）：大位图随动画缩放时 low 双线性会产生采样伪影闪烁
      filterQuality: FilterQuality.medium,
      fit: BoxFit.contain,
      fadeInDuration: Duration.zero,
      placeholder:
          placeholder == null
              ? (context, url) => const ColoredBox(color: Colors.black)
              : (context, url) => placeholder!,
      errorWidget:
          placeholder == null
              ? (context, url, error) => const ColoredBox(color: Colors.black)
              : (context, url, error) => placeholder!,
    );
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
