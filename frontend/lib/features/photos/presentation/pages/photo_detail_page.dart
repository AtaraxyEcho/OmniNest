import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_trash_view.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/navigation/navigation_extensions.dart';
import 'package:omninest/features/photos/platform/photo_batch_web_download.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart';
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

  /// 当前查看的照片：浏览序列中按下标取，并叠加详情数据的静默刷新。
  PhotoItem get _current {
    final base = _pages[_currentPage.clamp(0, _pages.length - 1)];
    return ref.watch(photoDetailProvider(base.id)).asData?.value ?? base;
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
                            child: _ExifPanel(photo: currentFresh),
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
                        child: _ExifPanel(photo: currentFresh),
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
            child: _DetailTopBar(
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
                  child: _SlideshowBadge(
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
            _ViewerArrowButton(
              icon: Icons.chevron_left_rounded,
              tooltip: AppLocalizations.of(context).photosPrevPhoto,
              alignRight: false,
              onTap: () => _goToPage(index - 1),
            ),
          if (index < total - 1)
            _ViewerArrowButton(
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

/// 详情页顶部栏：设计稿 PhotoViewer 样式的半透明浮层。
class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.photo,
    required this.onClose,
    required this.onToggleFavorite,
    required this.onDelete,
    required this.onToggleInfo,
    required this.onAddToAlbum,
    required this.onEdit,
    required this.onToggleSlideshow,
    required this.onDownload,
    required this.showInfo,
    required this.slideshowPlaying,
    required this.compact,
  });

  final PhotoItem photo;
  final VoidCallback onClose;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;
  final VoidCallback onToggleInfo;
  final VoidCallback onAddToAlbum;
  final VoidCallback onEdit;
  final VoidCallback onToggleSlideshow;
  final VoidCallback onDownload;
  final bool showInfo;
  final bool slideshowPlaying;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor =
        isDark
            ? Colors.black.withValues(alpha: 0.38)
            : context.photosColors.surfaceContainer.withValues(alpha: 0.92);
    final iconColor =
        isDark
            ? Colors.white.withValues(alpha: 0.70)
            : context.photosColors.onSurfaceVariant;
    final activeColor = context.frameColors.accent;
    final titleColor =
        isDark
            ? Colors.white.withValues(alpha: 0.90)
            : context.photosColors.onSurface;
    final dateColor =
        isDark
            ? Colors.white.withValues(alpha: 0.50)
            : context.photosColors.onSurfaceVariant;
    final centerTitle =
        photo.locationDisplay(preferZh: _isZhLocale(context)) ?? photo.title;
    final date = photo.dateTaken ?? photo.createdAt;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: barColor,
        border:
            isDark
                ? null
                : Border(
                  bottom: BorderSide(
                    color: context.photosColors.outlineVariant.withValues(
                      alpha: 0.32,
                    ),
                  ),
                ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: AppLocalizations.of(context).coreClose,
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, color: iconColor),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  centerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (date != null)
                  Text(
                    _formatShortDate(date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: dateColor, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (compact)
            PopupMenuButton<_PhotoMenuAction>(
              tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
              color: context.photosColors.surfaceContainerHigh,
              icon: Icon(Icons.more_vert_rounded, color: iconColor),
              onSelected: (action) {
                switch (action) {
                  case _PhotoMenuAction.info:
                    onToggleInfo();
                  case _PhotoMenuAction.edit:
                    onEdit();
                  case _PhotoMenuAction.slideshow:
                    onToggleSlideshow();
                  case _PhotoMenuAction.addToAlbum:
                    onAddToAlbum();
                  case _PhotoMenuAction.download:
                    onDownload();
                  case _PhotoMenuAction.delete:
                    onDelete();
                }
              },
              itemBuilder:
                  (context) => [
                    PopupMenuItem(
                      value: _PhotoMenuAction.info,
                      child: Text(
                        showInfo
                            ? AppLocalizations.of(context).photosHideInfo
                            : AppLocalizations.of(context).photosShowInfo,
                      ),
                    ),
                    PopupMenuItem(
                      value: _PhotoMenuAction.edit,
                      child: Text(AppLocalizations.of(context).photosEdit),
                    ),
                    PopupMenuItem(
                      value: _PhotoMenuAction.slideshow,
                      child: Text(AppLocalizations.of(context).photosSlideshow),
                    ),
                    PopupMenuItem(
                      value: _PhotoMenuAction.addToAlbum,
                      child: Text(
                        AppLocalizations.of(context).photosAddToAlbum,
                      ),
                    ),
                    PopupMenuItem(
                      value: _PhotoMenuAction.download,
                      child: Text(
                        AppLocalizations.of(context).photosDownloadPhoto,
                      ),
                    ),
                    PopupMenuItem(
                      value: _PhotoMenuAction.delete,
                      child: Text(
                        AppLocalizations.of(context).photosDelete,
                        style: TextStyle(color: context.photosColors.danger),
                      ),
                    ),
                  ],
            )
          else ...[
            IconButton(
              tooltip:
                  photo.favorite
                      ? AppLocalizations.of(context).photosUnfavorite
                      : AppLocalizations.of(context).photosFavorite,
              onPressed: onToggleFavorite,
              icon: Icon(
                photo.favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: photo.favorite ? activeColor : iconColor,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip:
                  showInfo
                      ? AppLocalizations.of(context).photosHideInfo
                      : AppLocalizations.of(context).photosShowInfo,
              onPressed: onToggleInfo,
              icon: Icon(
                Icons.info_outline_rounded,
                color: showInfo ? activeColor : iconColor,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).photosEdit,
              onPressed: onEdit,
              icon: Icon(Icons.edit_outlined, color: iconColor, size: 20),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).photosSlideshow,
              onPressed: onToggleSlideshow,
              icon: Icon(
                slideshowPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: slideshowPlaying ? activeColor : iconColor,
                size: 22,
              ),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).photosAddToAlbum,
              onPressed: onAddToAlbum,
              icon: Icon(
                Icons.create_new_folder_outlined,
                color: iconColor,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).photosDownloadPhoto,
              onPressed: onDownload,
              icon: Icon(Icons.download_outlined, color: iconColor, size: 20),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).photosDelete,
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                color: iconColor,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

/// 幻灯片播放状态徽章：底部居中，黑色半透明胶囊。
class _SlideshowBadge extends StatelessWidget {
  const _SlideshowBadge({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.play_arrow_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: 0.80),
          ),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context).photosSlideshowBadge(current, total),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

enum _PhotoMenuAction { info, edit, slideshow, addToAlbum, download, delete }

/// EXIF 信息侧栏：设计稿 w-72 独立全高侧栏，堆叠式标签/数值行。
class _ExifPanel extends ConsumerWidget {
  const _ExifPanel({required this.photo});

  final PhotoItem photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark
            ? FramePalette.viewerPanel
            : context.photosColors.surfaceContainer;
    final headerColor =
        isDark
            ? Colors.white.withValues(alpha: 0.90)
            : context.photosColors.onSurface;
    final sectionColor =
        isDark
            ? Colors.white.withValues(alpha: 0.50)
            : context.photosColors.onSurfaceVariant;
    final labelColor =
        isDark
            ? Colors.white.withValues(alpha: 0.35)
            : context.photosColors.onSurfaceVariant.withValues(alpha: 0.7);
    final valueColor =
        isDark
            ? Colors.white.withValues(alpha: 0.80)
            : context.photosColors.onSurface;
    final dividerColor =
        isDark
            ? Colors.white.withValues(alpha: 0.08)
            : context.photosColors.outlineVariant.withValues(alpha: 0.24);
    final pillBackground =
        isDark
            ? Colors.white.withValues(alpha: 0.10)
            : context.photosColors.surfaceContainerHighest;
    final pillColor =
        isDark
            ? Colors.white.withValues(alpha: 0.60)
            : context.photosColors.onSurfaceVariant;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(left: BorderSide(color: dividerColor)),
      ),
      child: SingleChildScrollView(
        // 顶部留白避开浮层顶栏（设计稿 pt-16）。
        padding: const EdgeInsets.fromLTRB(20, 68, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).photosPhotoInfo,
              style: TextStyle(
                color: headerColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 20),
            _ExifSection(
              title: AppLocalizations.of(context).photosBasicInfo,
              sectionColor: sectionColor,
              children: [
                if (photo.format.isNotEmpty)
                  _ExifEntry(
                    label: AppLocalizations.of(context).photosFormat,
                    value: photo.format.toUpperCase(),
                    labelColor: labelColor,
                    valueColor: valueColor,
                  ),
                _ExifEntry(
                  label: AppLocalizations.of(context).photosFileSize,
                  value: photo.fileSizeDisplay,
                  labelColor: labelColor,
                  valueColor: valueColor,
                ),
                if (photo.resolutionDisplay != null)
                  _ExifEntry(
                    label: AppLocalizations.of(context).photosResolution,
                    value: photo.resolutionDisplay!,
                    labelColor: labelColor,
                    valueColor: valueColor,
                  ),
                if (photo.dateTaken != null)
                  _ExifEntry(
                    label: AppLocalizations.of(context).photosDateTaken,
                    value: _formatDate(photo.dateTaken!),
                    labelColor: labelColor,
                    valueColor: valueColor,
                  ),
              ],
            ),
            if (photo.hasExif) ...[
              const SizedBox(height: 20),
              _ExifSection(
                title: AppLocalizations.of(context).photosCameraInfo,
                sectionColor: sectionColor,
                children: [
                  if (photo.cameraMake != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosBrand,
                      value: photo.cameraMake!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.cameraModel != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosModel,
                      value: photo.cameraModel!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.lensModel != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosLens,
                      value: photo.lensModel!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.aperture != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosAperture,
                      value: 'f/${photo.aperture}',
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.shutterSpeed != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosShutterSpeed,
                      value: photo.shutterSpeed!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.iso != null)
                    _ExifEntry(
                      label: 'ISO',
                      value: '${photo.iso}',
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.focalLength != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosFocalLength,
                      value: '${photo.focalLength}mm',
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                ],
              ),
            ],
            if (photo.hasAdvancedExif) ...[
              const SizedBox(height: 20),
              _ExifSection(
                title: AppLocalizations.of(context).photosShootingParams,
                sectionColor: sectionColor,
                children: [
                  if (photo.flash != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosFlash,
                      value: photo.flash!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.whiteBalance != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosWhiteBalance,
                      value: photo.whiteBalance!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.meteringMode != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosMeteringMode,
                      value: photo.meteringMode!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                ],
              ),
            ],
            if (photo.hasGps) ...[
              const SizedBox(height: 20),
              _ExifSection(
                title: AppLocalizations.of(context).photosLocationInfo,
                sectionColor: sectionColor,
                children: [
                  if (photo.locationDisplay(preferZh: _isZhLocale(context)) !=
                      null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosPlace,
                      value:
                          photo.locationDisplay(
                            preferZh: _isZhLocale(context),
                          )!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  _ExifEntry(
                    label: AppLocalizations.of(context).photosCoordinates,
                    value:
                        '${photo.gpsLatitude!.toStringAsFixed(6)}, ${photo.gpsLongitude!.toStringAsFixed(6)}',
                    labelColor: labelColor,
                    valueColor: valueColor,
                  ),
                ],
              ),
            ],
            if (photo.contentAnalysis?.labels.isNotEmpty == true) ...[
              const SizedBox(height: 20),
              Text(
                AppLocalizations.of(context).photosAIRecognition,
                style: TextStyle(
                  color: sectionColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final entry
                  in photo.contentAnalysis!.labelsByNamespace.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _localizedPhotoAnalysisNamespace(context, entry.key),
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in entry.value)
                      _InfoPill(
                        text: _localizedPhotoContentLabel(context, label.code),
                        background: pillBackground,
                        foreground: pillColor,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
            if (photo.description != null && photo.description!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                AppLocalizations.of(context).photosDescription,
                style: TextStyle(
                  color: sectionColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                photo.description!,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 13,
                  height: 18 / 13,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context).photosTag,
              style: TextStyle(
                color: sectionColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in photo.tags)
                  _InfoPill(
                    text: _localizedPhotoAiCategory(context, tag),
                    background: pillBackground,
                    foreground: pillColor,
                    onRemoved: () async {
                      try {
                        await ref
                            .read(photoCenterControllerProvider.notifier)
                            .removeTag(photo.id, tag);
                        if (!context.mounted) return;
                        ref.invalidate(photoDetailProvider(photo.id));
                      } on Exception {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLocalizations.of(
                                  context,
                                ).photosDeleteTagFailed,
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                _InfoPill(
                  text: AppLocalizations.of(context).photosAddTag,
                  background: context.frameColors.accent.withValues(
                    alpha: 0.12,
                  ),
                  foreground: context.frameColors.accent,
                  icon: Icons.add,
                  onRemoved: () => _showAddTagDialog(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddTagDialog(BuildContext context, WidgetRef ref) async {
    final tag = await showDialog<String>(
      context: context,
      builder:
          (ctx) => PhotoDialogTextField(
            builder:
                (ctx, controller) => AlertDialog(
                  backgroundColor: context.photosColors.surfaceContainerHigh,
                  title: Text(
                    AppLocalizations.of(context).photosAddTag,
                    style: TextStyle(color: context.photosColors.onSurface),
                  ),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    style: TextStyle(color: context.photosColors.onSurface),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).photosTagNameInput,
                      hintStyle: TextStyle(
                        color: context.photosColors.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: context.photosColors.outlineVariant.withValues(
                            alpha: 0.32,
                          ),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: context.photosColors.primaryContainer,
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(AppLocalizations.of(context).photosCancel),
                    ),
                    FilledButton(
                      onPressed:
                          () => Navigator.pop(ctx, controller.text.trim()),
                      child: Text(AppLocalizations.of(context).photosAdd),
                    ),
                  ],
                ),
          ),
    );
    if (tag != null && tag.isNotEmpty && context.mounted) {
      try {
        await ref
            .read(photoCenterControllerProvider.notifier)
            .addTag(photo.id, tag);
        if (!context.mounted) return;
        ref.invalidate(photoDetailProvider(photo.id));
      } on Exception {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).photosAddTagFailed),
            ),
          );
        }
      }
    }
  }
}

/// EXIF 分组标题。
class _ExifSection extends StatelessWidget {
  const _ExifSection({
    required this.title,
    required this.sectionColor,
    required this.children,
  });

  final String title;
  final Color sectionColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: sectionColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

/// 设计稿 EXIF 行：标签在上、数值在下，行间 14px。
class _ExifEntry extends StatelessWidget {
  const _ExifEntry({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: labelColor, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 设计稿标签胶囊：全圆角、半透明底、可带关闭或加号动作。
class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.text,
    required this.background,
    required this.foreground,
    this.icon,
    this.onRemoved,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final VoidCallback? onRemoved;

  @override
  Widget build(BuildContext context) {
    final action = onRemoved;
    return Material(
      color: background,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 4),
              ],
              Text(text, style: TextStyle(color: foreground, fontSize: 12)),
              if (action != null && icon == null) ...[
                const SizedBox(width: 4),
                Icon(Icons.close_rounded, size: 14, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

/// 当前界面语言是否为中文，用于地名等双语数据的选择。
bool _isZhLocale(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'zh';
}

String _formatShortDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _localizedPhotoAiCategory(BuildContext context, String category) {
  final l10n = AppLocalizations.of(context);
  return switch (category) {
    'Person' => l10n.photosAiCategoryPerson,
    'Cat' => l10n.photosAiCategoryCat,
    'Dog' => l10n.photosAiCategoryDog,
    'Animal' => l10n.photosAiCategoryAnimal,
    'Nature' || 'Landscape' => l10n.photosAiCategoryNature,
    'Architecture' => l10n.photosAiCategoryArchitecture,
    'Indoor' => l10n.photosAiCategoryIndoor,
    'Food' => l10n.photosAiCategoryFood,
    'Vehicle' => l10n.photosAiCategoryVehicle,
    'Plant' => l10n.photosAiCategoryPlant,
    'Sport' => l10n.photosAiCategorySport,
    'Night' => l10n.photosAiCategoryNight,
    'Art' => l10n.photosAiCategoryArt,
    'Document' => l10n.photosAiCategoryDocument,
    _ => category,
  };
}

String _localizedPhotoContentLabel(BuildContext context, String code) {
  return _localizedPhotoAiCategory(context, switch (code) {
    'person' => 'Person',
    'cat' => 'Cat',
    'dog' => 'Dog',
    'bird' => 'Animal',
    'horse' ||
    'sheep' ||
    'cow' ||
    'elephant' ||
    'bear' ||
    'zebra' ||
    'giraffe' => 'Animal',
    'nature' ||
    'beach' ||
    'mountain' ||
    'forest' ||
    'lake' ||
    'ocean' ||
    'river' => 'Nature',
    'indoor' ||
    'office' ||
    'restaurant' ||
    'kitchen' ||
    'bedroom' ||
    'classroom' => 'Indoor',
    'vehicle' => 'Vehicle',
    'food' => 'Food',
    'plant' => 'Plant',
    'document' || 'screenshot' => 'Document',
    'illustration' || 'anime' || 'artwork' => 'Art',
    _ => code,
  });
}

String _localizedPhotoAnalysisNamespace(
  BuildContext context,
  String namespace,
) {
  final l10n = AppLocalizations.of(context);
  return switch (namespace) {
    'SUBJECT' => l10n.photosAnalysisSubject,
    'SCENE' => l10n.photosAnalysisScene,
    'STYLE' => l10n.photosAnalysisStyle,
    _ => l10n.photosAIRecognition,
  };
}

/// Frame 查看器左右切换按钮：42px 方形、圆角 8、35% 黑底、白色 60% 线形图标。
class _ViewerArrowButton extends StatelessWidget {
  const _ViewerArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.alignRight,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scrim =
        isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.35);
    final border =
        isDark
            ? Colors.white.withValues(alpha: 0.24)
            : Colors.white.withValues(alpha: 0.10);
    final iconColor =
        isDark
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.88);
    return Positioned.fill(
      child: Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: scrim,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Tooltip(
                message: tooltip,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(icon, size: 22, color: iconColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
