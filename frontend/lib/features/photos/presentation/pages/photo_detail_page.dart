import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_exif_sidebar.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_viewer_chrome.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_trash_view.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/navigation/navigation_extensions.dart';
import 'package:omninest/features/photos/platform/photo_batch_web_download.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 桌面端 EXIF 侧栏宽度：设计稿 w-72（288px）。
const double _kExifPanelWidth = 288;

/// 照片详情/查看器页面
class PhotoDetailPage extends ConsumerWidget {
  const PhotoDetailPage({required this.photoId, super.key});

  final String photoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(photoDetailProvider(photoId));
    return Scaffold(
      backgroundColor: context.photosColors.surface,
      body: photoAsync.when(
        data: (photo) => _PhotoDetailBody(photo: photo),
        error:
            (error, stackTrace) => Column(
              children: [
                SafeArea(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: AppLocalizations.of(context).photosBackToPhotos,
                      onPressed: () => context.popOrGo('/photos'),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                ),
                Expanded(
                  child: AppErrorView(
                    message: describeUserFacingError(error).message,
                    onRetry: () => ref.invalidate(photoDetailProvider(photoId)),
                  ),
                ),
              ],
            ),
        loading: () => const AppLoading.detail(),
      ),
    );
  }
}

class _PhotoDetailBody extends ConsumerStatefulWidget {
  const _PhotoDetailBody({required this.photo});

  final PhotoItem photo;

  @override
  ConsumerState<_PhotoDetailBody> createState() => _PhotoDetailBodyState();
}

class _PhotoDetailBodyState extends ConsumerState<_PhotoDetailBody> {
  static const Duration _slideshowInterval = Duration(seconds: 3);

  bool get _showInfo => ref.watch(photoInfoPanelVisibleProvider);
  List<PhotoItem> _pages = const <PhotoItem>[];
  late PageController _pageController;
  int _currentPage = 0;
  String? _currentPhotoId;
  final Set<String> _locationBackfillAttempted = {};
  Timer? _slideshowTimer;

  @override
  void initState() {
    super.initState();
    _pages = _resolveInitialPages();
    final entryIndex = _pages.indexWhere((p) => p.id == widget.photo.id);
    _currentPage = entryIndex < 0 ? 0 : entryIndex;
    _currentPhotoId = _pages[_currentPage].id;
    _pageController = PageController(initialPage: _currentPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _backfillLocationIfNeeded(_pages[_currentPage]);
      _precacheNeighbors(_currentPage);
      if (ref.read(photoSlideshowPlayingProvider)) {
        _startSlideshow();
      }
    });
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  /// 解析进入时的浏览序列：浏览范围优先，回退中心列表，最后退化为单张。
  List<PhotoItem> _resolveInitialPages() {
    final entry = widget.photo;
    final scope = ref.read(photoBrowseScopeProvider);
    if (scope.length > 1 && scope.any((p) => p.id == entry.id)) {
      return scope;
    }
    final center =
        ref.read(photoCenterControllerProvider).asData?.value.photos ??
        const <PhotoItem>[];
    if (center.length > 1 && center.any((p) => p.id == entry.id)) {
      return center;
    }
    return [entry];
  }

  /// 序列变化（浏览范围/中心列表晚到）时保持当前照片位置并同步分页控制器。
  List<PhotoItem> _resolvePages(
    List<PhotoItem> browseScope,
    List<PhotoItem> centerPhotos,
  ) {
    if (browseScope.length > 1 &&
        browseScope.any((p) => p.id == widget.photo.id)) {
      return browseScope;
    }
    if (centerPhotos.length > 1 &&
        centerPhotos.any((p) => p.id == widget.photo.id)) {
      return centerPhotos;
    }
    return [widget.photo];
  }

  void _backfillLocationIfNeeded(PhotoItem photo) {
    if (_locationBackfillAttempted.contains(photo.id)) return;
    _locationBackfillAttempted.add(photo.id);
    if (!photo.hasGps) return;
    final location = photo.gpsLocation;
    if (location != null && location.isNotEmpty) return;
    unawaited(_backfillGeocode(photo.id));
  }

  Future<void> _backfillGeocode(String photoId) async {
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .backfillGeocode(photoId);
      if (!mounted) return;
      ref.invalidate(photoDetailProvider(photoId));
    } on Exception {
      // 逆地理编码失败时静默降级：位置信息仅在成功时展示。
    }
  }

  /// 相邻页原图预取，消除切换时的占位等待。
  void _precacheNeighbors(int index) {
    for (final neighbor in [index - 1, index + 1]) {
      if (neighbor < 0 || neighbor >= _pages.length) continue;
      final item = _pages[neighbor];
      final url = item.sourceUrl ?? item.coverUrl;
      if (url == null || url.isEmpty) continue;
      precacheImage(
        CachedNetworkImageProvider(
          url,
          cacheKey:
              item.sourceUrl != null ? item.sourceCacheKey : item.coverCacheKey,
        ),
        context,
      );
    }
  }

  // ─── 幻灯片（设计稿 PhotoViewer 内嵌播放模式） ───

  void _startSlideshow() {
    _slideshowTimer?.cancel();
    _slideshowTimer = null;
    if (_pages.length < 2) return;
    _slideshowTimer = Timer.periodic(_slideshowInterval, (_) {
      _slideshowAdvance();
    });
  }

  void _stopSlideshow() {
    _slideshowTimer?.cancel();
    _slideshowTimer = null;
  }

  /// 播放/暂停切换；无可播放序列时给出可见反馈，绝不静默。
  void _toggleSlideshow() {
    if (ref.read(photoSlideshowPlayingProvider)) {
      ref.read(photoSlideshowPlayingProvider.notifier).stop();
      return;
    }
    if (_pages.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).photosSlideshowUnavailable,
          ),
        ),
      );
      return;
    }
    ref.read(photoSlideshowPlayingProvider.notifier).start();
  }

  /// 播放到序列末尾后无动画回卷到第一张，避免长距离快速扫页。
  void _slideshowAdvance() {
    if (!mounted) return;
    final page =
        _pageController.hasClients
            ? (_pageController.page?.round() ?? 0)
            : _currentPage;
    if (page >= _pages.length - 1) {
      _pageController.jumpToPage(0);
      return;
    }
    _goToPage(page + 1);
  }

  /// 切换到指定页；相邻切换带滑动动画。
  void _goToPage(int index, {bool animate = true}) {
    if (!_pageController.hasClients) return;
    final target = index.clamp(0, _pages.length - 1);
    if (animate) {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _pageController.jumpToPage(target);
    }
  }

  /// 当前查看的照片：浏览序列中按下标取，并叠加详情数据的最新值。
  ///
  /// 供回调读取，使用 ref.read；build 内的响应式渲染由调用方另行 watch。
  PhotoItem get _current {
    final base = _pages[_currentPage.clamp(0, _pages.length - 1)];
    return ref.read(photoDetailProvider(base.id)).asData?.value ?? base;
  }

  // ─── 下载原片 ───

  Future<void> _downloadPhoto() async {
    final photo = _current;
    final sourceUrl = photo.sourceUrl;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (sourceUrl == null || sourceUrl.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.photosDownloadSourceUnavailable)),
      );
      return;
    }
    final fileName = photo.downloadFileName;
    try {
      if (kIsWeb) {
        await downloadPhotoBatchInBrowser(url: sourceUrl, fileName: fileName);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.photosDownloadStarted)),
        );
        return;
      }
      final savedPath = await ref
          .read(photoCenterControllerProvider.notifier)
          .savePhotoFileToDisk(
            url: sourceUrl,
            sizeBytes: photo.fileSize,
            suggestedName: fileName,
          );
      if (savedPath == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.photosDownloadSaved(savedPath))),
      );
    } on Exception {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.photosDownloadFailed)),
      );
    }
  }

  /// 关闭查看器：复位幻灯片播放后返回照片列表。
  ///
  /// 深链进入时路由栈内没有上级页面，popOrGo 会退化为 go()，
  /// PopScope 不触发，因此这里显式停止播放。
  void _closeViewer() {
    ref.read(photoSlideshowPlayingProvider.notifier).stop();
    context.popOrGo('/photos');
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFrameConfirmDialog(
      context,
      title: l10n.photosMoveToTrashTitle,
      body: l10n.photosMoveToTrashBodyOne,
      confirmLabel: l10n.photosMoveToTrashAction,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .movePhotoToTrash(_current.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.photosTrashMoved)));
      _closeViewer();
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).photosDeleteFailed),
        ),
      );
    }
  }

  Future<void> _showAddToAlbumDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final albums =
        await ref.read(photoCenterControllerProvider.notifier).listAlbums();
    if (!context.mounted) return;

    final selected = await showDialog<String>(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            backgroundColor: context.photosColors.surfaceContainerHigh,
            title: Text(
              AppLocalizations.of(context).photosSelectAlbum,
              style: TextStyle(color: context.photosColors.onSurface),
            ),
            children:
                albums.isEmpty
                    ? [
                      Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          AppLocalizations.of(
                            context,
                          ).photosNoAlbumsCreateFirst,
                          style: TextStyle(
                            color: context.photosColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ]
                    : albums
                        .map(
                          (album) => SimpleDialogOption(
                            onPressed: () => Navigator.pop(ctx, album.id),
                            child: Text(
                              album.name,
                              style: TextStyle(
                                color: context.photosColors.onSurface,
                              ),
                            ),
                          ),
                        )
                        .toList(),
          ),
    );

    if (selected != null && context.mounted) {
      try {
        await ref
            .read(photoCenterControllerProvider.notifier)
            .addPhotosToAlbum(albumId: selected, photoIds: [_current.id]);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).photosAddedToAlbum),
            ),
          );
        }
      } on Exception {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).photosAddFailed),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    // 响应式解析浏览序列：浏览范围或照片列表晚到时页面集合随之扩展，
    // 当前照片以 id 锚定，不因序列变化丢失位置。
    final browseScope = ref.watch(photoBrowseScopeProvider);
    final centerPhotos =
        ref.watch(photoCenterControllerProvider).asData?.value.photos ??
        const <PhotoItem>[];
    final pages = _resolvePages(browseScope, centerPhotos);
    _pages = pages;
    final index = pages.indexWhere(
      (p) => p.id == (_currentPhotoId ?? widget.photo.id),
    );
    _currentPage = index < 0 ? 0 : index.clamp(0, pages.length - 1);
    final current = _pages[_currentPage];
    final currentFresh =
        ref.watch(photoDetailProvider(current.id)).asData?.value ?? current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      if (_pageController.page?.round() != _currentPage) {
        _pageController.jumpToPage(_currentPage);
      }
    });

    // 幻灯片开关由 Provider 承载，单路由内跨页面切换保持播放。
    ref.listen(photoSlideshowPlayingProvider, (_, playing) {
      if (playing) {
        _startSlideshow();
      } else {
        _stopSlideshow();
      }
    });

    return PopScope(
      // 路由真实退出（关闭/系统返回/删除后返回）时复位播放状态。
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        ref.read(photoSlideshowPlayingProvider.notifier).stop();
      },
      child: Stack(
        children: [
          // 主体：照片舞台（PageView 支持左右滑动切换）+ 桌面端信息侧栏
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                      _currentPhotoId = _pages[index].id;
                    });
                    _backfillLocationIfNeeded(_pages[index]);
                    _precacheNeighbors(index);
                  },
                  itemBuilder: (context, index) {
                    final base = _pages[index];
                    return Consumer(
                      builder: (context, pageRef, _) {
                        final item =
                            pageRef
                                .watch(photoDetailProvider(base.id))
                                .asData
                                ?.value ??
                            base;
                        return _buildPhotoStage(
                          context,
                          item,
                          index,
                          _pages.length,
                        );
                      },
                    );
                  },
                ),
              ),
              if (!compact)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.ease,
                  alignment: Alignment.centerRight,
                  child:
                      _showInfo
                          ? SizedBox(
                            width: _kExifPanelWidth,
                            child: PhotoExifPanel(photo: currentFresh),
                          )
                          : const SizedBox.shrink(),
                ),
            ],
          ),
          // 紧凑端信息侧栏：全高右抽屉 + 遮罩
          if (compact && _showInfo)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = (constraints.maxWidth * 0.86).clamp(
                    288.0,
                    360.0,
                  );
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onTap:
                              () =>
                                  ref
                                      .read(
                                        photoInfoPanelVisibleProvider.notifier,
                                      )
                                      .toggle(),
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.40),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        width: width,
                        child: PhotoExifPanel(photo: currentFresh),
                      ),
                    ],
                  );
                },
              ),
            ),
          // 顶部操作栏：设计稿样式，半透明浮层横贯照片与侧栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: PhotoViewerTopBar(
              photo: currentFresh,
              onClose: _closeViewer,
              onToggleFavorite: () async {
                try {
                  if (!mounted) return;
                  await ref
                      .read(photoCenterControllerProvider.notifier)
                      .toggleFavorite(
                        currentFresh.id,
                        currentFavorite: currentFresh.favorite,
                      );
                  if (!mounted) return;
                  // 刷新详情
                  ref.invalidate(photoDetailProvider(currentFresh.id));
                } on Exception {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context).photosOperationFailed,
                        ),
                      ),
                    );
                  }
                }
              },
              onDelete: _confirmDelete,
              onToggleInfo:
                  () =>
                      ref.read(photoInfoPanelVisibleProvider.notifier).toggle(),
              onAddToAlbum: () => _showAddToAlbumDialog(context, ref),
              onEdit: () {
                // 进入编辑器前停止幻灯片，避免定时器在编辑页下继续换图。
                ref.read(photoSlideshowPlayingProvider.notifier).stop();
                context.push('/photos/${currentFresh.id}/edit');
              },
              onToggleSlideshow: _toggleSlideshow,
              onDownload: () => unawaited(_downloadPhoto()),
              showInfo: _showInfo,
              slideshowPlaying: ref.watch(photoSlideshowPlayingProvider),
              compact: compact,
            ),
          ),
          // 幻灯片播放徽章：底部居中
          if (ref.watch(photoSlideshowPlayingProvider) && _pages.length >= 2)
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: IgnorePointer(
                child: Center(
                  child: PhotoViewerSlideshowBadge(
                    current: _currentPage + 1,
                    total: _pages.length,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoStage(
    BuildContext context,
    PhotoItem photo,
    int index,
    int total,
  ) {
    final imageUrl = photo.sourceUrl ?? photo.coverUrl;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewBackground =
        isDark
            ? FramePalette.viewerBg
            : context.photosColors.surfaceContainerLow;
    return ColoredBox(
      // 暗色使用设计稿查看器底色，亮色跟随主题浅色底。
      color: viewBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              // 设计稿照片区四周留白 40px，顶部避开浮层顶栏。
              padding: const EdgeInsets.fromLTRB(40, 56, 40, 24),
              child: Center(
                child:
                    imageUrl != null && imageUrl.isNotEmpty
                        ? Hero(
                          tag: 'photo-cover-${photo.id}',
                          child: InteractiveViewer(
                            minScale: 1,
                            maxScale: 5,
                            child: SizedBox.expand(
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                cacheKey:
                                    photo.sourceUrl != null
                                        ? photo.sourceCacheKey
                                        : photo.coverCacheKey,
                                fit: BoxFit.contain,
                                placeholder:
                                    (context, url) => Center(
                                      child: CircularProgressIndicator(
                                        color:
                                            context
                                                .photosColors
                                                .primaryContainer,
                                      ),
                                    ),
                                errorWidget:
                                    (context, url, error) => Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.broken_image_outlined,
                                            color: context
                                                .photosColors
                                                .onSurfaceVariant
                                                .withValues(alpha: 0.4),
                                            size: 48,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            ).photosImageLoadFailed,
                                            style: TextStyle(
                                              color:
                                                  context
                                                      .photosColors
                                                      .onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        )
                        : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.photo_outlined,
                              color: context.photosColors.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                              size: 64,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              photo.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.photosColors.onSurfaceVariant,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
              ),
            ),
          ),
          if (index > 0)
            PhotoViewerArrowButton(
              icon: Icons.chevron_left_rounded,
              tooltip: AppLocalizations.of(context).photosPrevPhoto,
              alignRight: false,
              onTap: () => _goToPage(index - 1),
            ),
          if (index < total - 1)
            PhotoViewerArrowButton(
              icon: Icons.chevron_right_rounded,
              tooltip: AppLocalizations.of(context).photosNextPhoto,
              alignRight: true,
              onTap: () => _goToPage(index + 1),
            ),
        ],
      ),
    );
  }
}
