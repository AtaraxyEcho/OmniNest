import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_info_panel.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_panel_host.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_motion_player.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_panel.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_viewer_chrome.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_dialogs.dart';
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

/// 桌面端信息侧栏宽度：与幻灯片信息面板及分享侧栏一致。
/// 照片详情/查看器页面
class PhotoDetailPage extends ConsumerWidget {
  const PhotoDetailPage({required this.photoId, super.key});

  final String photoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(photoDetailProvider(photoId));
    // 查看器为沉浸暗色场景（与幻灯片一致）：整页子树强制暗色主题，
    // 顶栏/箭头/徽标/对话框/加载与错误态自动使用暗色变体。
    return Theme(
      data: OmniNestTheme.from(AppThemePalette.dark),
      child: Scaffold(
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
                        tooltip:
                            AppLocalizations.of(context).photosBackToPhotos,
                        onPressed: () => context.popOrGo('/photos'),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AppErrorView(
                      message: describeUserFacingError(error).message,
                      onRetry:
                          () => ref.invalidate(photoDetailProvider(photoId)),
                    ),
                  ),
                ],
              ),
          loading: () => const AppLoading.detail(),
        ),
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
  bool get _showInfo => ref.watch(photoInfoPanelVisibleProvider);
  List<PhotoItem> _pages = const <PhotoItem>[];
  late PageController _pageController;
  int _currentPage = 0;
  String? _currentPhotoId;

  /// 动态照片长按预览中；松手复位。
  bool _motionHoldPlaying = false;

  /// 动态照片常驻播放开关；点按 LIVE 徽标切换，切页/点播放层复位。
  bool _motionPinnedPlaying = false;

  /// 分享侧栏开合；与幻灯片共用 PhotoSharePanel。
  bool _showSharePanel = false;
  final Set<String> _locationBackfillAttempted = {};

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
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 解析进入时的浏览序列：浏览范围优先，回退中心列表，最后退化为单张。
  List<PhotoItem> _resolveInitialPages() {
    final entry = widget.photo;
    final scope = ref.read(photoBrowseScopeProvider);
    if (scope.photos.isNotEmpty && scope.photos.any((p) => p.id == entry.id)) {
      return scope.photos;
    }
    final center =
        ref.read(photoCenterControllerProvider).asData?.value.photos ??
        const <PhotoItem>[];
    if (center.isNotEmpty && center.any((p) => p.id == entry.id)) {
      return center;
    }
    return [entry];
  }

  /// 序列变化（浏览范围/中心列表晚到）时保持当前照片位置并同步分页控制器。
  List<PhotoItem> _resolvePages(
    PhotoBrowseScope browseScope,
    List<PhotoItem> centerPhotos,
  ) {
    if (browseScope.photos.isNotEmpty &&
        browseScope.photos.any((p) => p.id == widget.photo.id)) {
      return browseScope.photos;
    }
    if (centerPhotos.isNotEmpty &&
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

  void _setMotionHold(bool playing) {
    if (!mounted || _motionHoldPlaying == playing) return;
    setState(() => _motionHoldPlaying = playing);
  }

  void _setMotionPinned(bool playing) {
    if (!mounted || _motionPinnedPlaying == playing) return;
    setState(() => _motionPinnedPlaying = playing);
  }

  void _handleMotionPlayError() {
    if (!mounted) return;
    setState(() {
      _motionHoldPlaying = false;
      _motionPinnedPlaying = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).photosMotionPlayFailed),
      ),
    );
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

  /// 启动沉浸幻灯片页；关闭后按回传结果恢复查看器位置。
  Future<void> _launchSlideshow() async {
    final scope = ref.read(photoBrowseScopeProvider);
    final result = await context.push<Object>(
      '/photos/slideshow',
      extra: {
        'photos': _pages,
        'initialIndex': _currentPage,
        'source': scope.source,
        'sourceKey': scope.sourceKey,
      },
    );
    if (!mounted || result is! Map) return;
    final restored = result['photoId'];
    if (restored is String && restored.isNotEmpty) {
      setState(() => _currentPhotoId = restored);
    }
  }

  /// 关闭查看器，返回照片列表。
  void _closeViewer() {
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

    final selected = await showFrameChoiceDialog<String>(
      context,
      title: AppLocalizations.of(context).photosSelectAlbum,
      choices: [
        for (final album in albums)
          FrameChoice(
            value: album.id,
            title: album.name,
            subtitle: AppLocalizations.of(
              context,
            ).photosAlbumPhotoCountLabel(album.photoCount),
          ),
      ],
      emptyMessage: AppLocalizations.of(context).photosNoAlbumsCreateFirst,
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

    return Stack(
      children: [
        // 照片舞台：PageView 支持左右滑动切换（信息侧栏以覆盖层滑入，不挤压舞台）。
        Positioned.fill(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
                _currentPhotoId = _pages[index].id;
                _motionHoldPlaying = false;
                _motionPinnedPlaying = false;
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
                  return _buildPhotoStage(context, item, index, _pages.length);
                },
              );
            },
          ),
        ),
        // 信息侧栏：与幻灯片一致的右滑入覆盖层，透明遮罩点击关闭。
        if (_showInfo)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap:
                  () =>
                      ref.read(photoInfoPanelVisibleProvider.notifier).toggle(),
            ),
          ),
        PhotoPanelHost(
          visible: _showInfo,
          onClose:
              () => ref.read(photoInfoPanelVisibleProvider.notifier).toggle(),
          child: PhotoInfoPanel(photo: currentFresh, onShare: _openSharePanel),
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
                () => ref.read(photoInfoPanelVisibleProvider.notifier).toggle(),
            onAddToAlbum: () => _showAddToAlbumDialog(context, ref),
            onEdit: () {
              context.push('/photos/${currentFresh.id}/edit');
            },
            onSlideshow: _launchSlideshow,
            onDownload: () => unawaited(_downloadPhoto()),
            onShare: _openSharePanel,
            showInfo: _showInfo,
            compact: compact,
          ),
        ),
        // 分享侧栏：与幻灯片共用组件，scrim 在面板之下。
        if (_showSharePanel)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showSharePanel = false),
            ),
          ),
        if (_showSharePanel)
          PhotoSharePanel(
            visible: true,
            photo: currentFresh,
            onDone: () => setState(() => _showSharePanel = false),
          ),
      ],
    );
  }

  /// 打开分享侧栏；桌面端信息侧栏与其互斥。
  void _openSharePanel() {
    if (ref.read(photoInfoPanelVisibleProvider)) {
      ref.read(photoInfoPanelVisibleProvider.notifier).toggle();
    }
    setState(() => _showSharePanel = true);
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
            child: GestureDetector(
              // 动态照片：长按快速预览运动视频，松手回到静态帧。
              onLongPressStart:
                  photo.isMotionReady ? (_) => _setMotionHold(true) : null,
              onLongPressEnd:
                  photo.isMotionReady ? (_) => _setMotionHold(false) : null,
              onLongPressCancel:
                  photo.isMotionReady ? () => _setMotionHold(false) : null,
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
                                  fontSize: AppTypography.titleMedium,
                                ),
                              ),
                            ],
                          ),
                ),
              ),
            ),
          ),
          // 动态照片：运动视频播放层（长按或点按徽标触发），盖在照片上方、箭头之下。
          if (photo.isMotionReady &&
              (_motionHoldPlaying || _motionPinnedPlaying))
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _setMotionPinned(false),
                child: PhotoMotionPlayer(
                  key: ValueKey('motion-${photo.id}'),
                  url: photo.motionVideoUrl!,
                  onError: _handleMotionPlayError,
                ),
              ),
            ),
          // LIVE 徽标：常驻播放开关。
          if (photo.isMotionReady)
            Positioned(
              left: 24,
              bottom: 24,
              child: _MotionBadge(
                active: _motionPinnedPlaying,
                label: AppLocalizations.of(context).photosLiveBadge,
                tooltip: AppLocalizations.of(context).photosLiveBadgeTooltip,
                onTap: () => _setMotionPinned(!_motionPinnedPlaying),
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

/// LIVE 徽标：胶囊样式，激活时高亮，点按切换常驻播放。
class _MotionBadge extends StatelessWidget {
  const _MotionBadge({
    required this.active,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final bool active;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        active
            ? context.photosColors.primaryContainer
            : isDark
            ? Colors.black.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.78);
    final foreground =
        active
            ? context.photosColors.onPrimaryContainer
            : isDark
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.black.withValues(alpha: 0.78);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.motion_photos_on_rounded,
                  size: 16,
                  color: foreground,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
