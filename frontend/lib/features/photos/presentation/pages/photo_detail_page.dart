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
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/navigation/navigation_extensions.dart';
import 'package:omninest/core/services/app_image_cache_policy.dart';
import 'package:omninest/core/utils/image_decode_width.dart';
import 'package:omninest/features/photos/platform/photo_batch_web_download.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_hosted_chrome.dart';

part 'photo_detail_page_image.dart';

/// 桌面端信息侧栏宽度：与幻灯片信息面板及分享侧栏一致。
/// 照片详情/查看器页面
class PhotoDetailPage extends ConsumerWidget {
  const PhotoDetailPage({required this.photoId, super.key});

  final String photoId;

  /// 列表侧已持有的种子数据：浏览范围优先，其次中心列表/收藏/回收站，最后内存缓存。
  ///
  /// 使点击缩略图后立刻用已解码封面渲染查看器，不再阻塞在详情接口上。
  PhotoItem? _resolveSeedPhoto(WidgetRef ref, String photoId) {
    final scope = ref.read(photoBrowseScopeProvider);
    for (final photo in scope.photos) {
      if (photo.id == photoId) {
        return photo;
      }
    }
    final center = ref.read(photoCenterControllerProvider).asData?.value;
    if (center != null) {
      for (final photo in [
        ...center.photos,
        ...center.favorites,
        ...center.trashPhotos,
      ]) {
        if (photo.id == photoId) {
          return photo;
        }
      }
    }
    return ref.read(photoDetailMemoryCacheProvider).get(photoId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(photoDetailProvider(photoId));
    final seed = _resolveSeedPhoto(ref, photoId);
    final photo = photoAsync.asData?.value ?? seed;
    final hosted = photosHostedForm(context);
    // 查看器为沉浸暗色场景（与幻灯片一致）：整页子树强制暗色主题，
    // 顶栏/箭头/徽标/对话框/加载与错误态自动使用暗色变体。
    return Theme(
      data: OmniNestTheme.from(AppThemePalette.dark),
      child: PhotoHostedScope(
        child: Scaffold(
          backgroundColor:
              hosted
                  ? photoViewerHostedStageColor
                  : context.photosColors.surface,
          body:
              photo != null
                  ? _PhotoDetailBody(photo: photo)
                  : photoAsync.when(
                    data: (resolved) => _PhotoDetailBody(photo: resolved),
                    error:
                        (error, stackTrace) => Column(
                          children: [
                            SafeArea(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: IconButton(
                                  tooltip:
                                      AppLocalizations.of(
                                        context,
                                      ).photosBackToPhotos,
                                  onPressed: () => context.popOrGo('/photos'),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                              ),
                            ),
                            Expanded(
                              child: AppErrorView(
                                message: describeUserFacingError(error).message,
                                onRetry:
                                    () => ref.invalidate(
                                      photoDetailProvider(photoId),
                                    ),
                              ),
                            ),
                          ],
                        ),
                    loading: () => const AppLoading(),
                  ),
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

/// 中文语境下地点名优先取中文回写字段（与工位查看器口径一致）。
bool _prefersZhLocation(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'zh';
}

class _PhotoDetailBodyState extends ConsumerState<_PhotoDetailBody> {
  bool get _showInfo => ref.watch(photoInfoPanelVisibleProvider);
  List<PhotoItem> _pages = const <PhotoItem>[];
  late PageController _pageController;
  int _currentPage = 0;
  String? _currentPhotoId;

  /// 上次对齐 PageView 的照片 id；仅锚点变化时 jump，避免手势中抢页。
  String? _lastPageAnchorId;

  /// 动态照片长按预览中；松手复位。
  bool _motionHoldPlaying = false;

  /// 动态照片常驻播放开关；点按 LIVE 徽标切换，切页/点播放层复位。
  bool _motionPinnedPlaying = false;

  /// 分享侧栏开合；与幻灯片共用 PhotoSharePanel。
  bool _showSharePanel = false;
  final Set<String> _locationBackfillAttempted = {};

  /// 已触发过详情预取的相邻页，避免往复翻页时重复请求。
  final Set<String> _detailPrefetchAttempted = {};

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
      _ensureImageCacheBudget();
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

  /// 相邻页预取：原图/封面按渲染层同键预解码，签名 URL 缺失时预取详情补齐。
  ///
  /// 图片缓存键含 ResizeImage 解码宽度；裸 provider 预取只暖下载/磁盘缓存，
  /// 页面滑入时仍会现场解码。两层宽度须与渐进图层的分支一致：有原图时
  /// 封面按封面档解码，无原图回退时封面按原图档解码。
  void _precacheNeighbors(int index) {
    final widths = viewerDecodeWidths(context);
    for (final neighbor in [index - 1, index + 1]) {
      if (neighbor < 0 || neighbor >= _pages.length) {
        continue;
      }
      final item = _pages[neighbor];
      final sourceUrl = item.sourceUrl;
      final coverUrl = item.coverUrl;
      final hasSource = sourceUrl != null && sourceUrl.isNotEmpty;
      if (hasSource) {
        _precacheViewerImage(
          sourceUrl,
          cacheKey: item.sourceCacheKey,
          decodeWidth: widths.source,
        );
      }
      if (coverUrl != null && coverUrl.isNotEmpty) {
        _precacheViewerImage(
          coverUrl,
          cacheKey: item.coverCacheKey,
          decodeWidth: hasSource ? widths.cover : widths.source,
        );
      }
      if (!hasSource) {
        unawaited(_prefetchNeighborDetail(item.id));
      }
    }
  }

  /// 与渲染层同键预解码一张查看器图片，键不匹配的预取不会命中图片缓存。
  void _precacheViewerImage(
    String url, {
    required String cacheKey,
    required int decodeWidth,
  }) {
    precacheImage(
      ResizeImage(
        CachedNetworkImageProvider(url, cacheKey: cacheKey),
        width: decodeWidth,
      ),
      context,
      // 预取失败静默降级：页面可见时仍走常规加载与错误链路。
      onError: (_, _) {},
    );
  }

  /// 无签名原图 URL 的相邻页（首页最近/收藏条带路径）预取详情：
  /// 写入详情内存缓存并按匹配键预解码，页面滑入时经内存缓存种子直出。
  /// 失败静默降级为页面可见时的常规详情加载。
  Future<void> _prefetchNeighborDetail(String photoId) async {
    if (_detailPrefetchAttempted.contains(photoId)) {
      return;
    }
    _detailPrefetchAttempted.add(photoId);
    final widths = viewerDecodeWidths(context);
    final repository = ref.read(photoRepositoryProvider);
    final memoryCache = ref.read(photoDetailMemoryCacheProvider);
    try {
      final detail = await repository.getPhoto(photoId);
      memoryCache.put(detail);
      if (!mounted) {
        return;
      }
      final sourceUrl = detail.sourceUrl;
      if (sourceUrl == null || sourceUrl.isEmpty) {
        return;
      }
      _precacheViewerImage(
        sourceUrl,
        cacheKey: detail.sourceCacheKey,
        decodeWidth: widths.source,
      );
    } on Object {
      // 预取属尽力而为：任何失败都不影响相邻页可见后的常规加载。
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
        curve: Curves.fastOutSlowIn,
      );
    } else {
      _pageController.jumpToPage(target);
    }
  }

  /// 声明查看器解码工作集的缓存预算下限：当前页与两侧相邻预取共约
  /// 3 张原图档 + 3 张封面档位图（按正方形位图保守估算，另留 30% 余量）。
  /// 宽屏平板等档位下若超过平台预算，先抬预算再预取，避免预取互相驱逐、
  /// 回滑时重新解码。
  void _ensureImageCacheBudget() {
    final widths = viewerDecodeWidths(context);
    const bytesPerPixel = 4;
    const workingSetImages = 3;
    const margin = 1.3;
    final bytes =
        (widths.source * widths.source + widths.cover * widths.cover) *
        bytesPerPixel *
        workingSetImages *
        margin;
    AppImageCachePolicy.ensureMinimumBytes(bytes.round());
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
    showOmniFeedback(
      context,
      AppLocalizations.of(context).photosMotionPlayFailed,
      severity: OmniFeedbackSeverity.error,
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
    final l10n = AppLocalizations.of(context);
    final photoId = _current.id;
    // 下载必须使用详情接口新签发的 sourceUrl：列表种子无 sourceUrl，
    // 内存缓存与会话内旧详情都可能持有已过期的预签名地址。
    final PhotoItem photo;
    try {
      ref.invalidate(photoDetailProvider(photoId));
      photo = await ref.read(photoDetailProvider(photoId).future);
    } on Exception {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.photosDownloadFailed,
        severity: OmniFeedbackSeverity.error,
      );
      return;
    }
    if (!mounted) return;
    final sourceUrl = photo.sourceUrl;
    if (sourceUrl == null || sourceUrl.isEmpty) {
      showOmniFeedback(context, l10n.photosDownloadSourceUnavailable);
      return;
    }
    final fileName = photo.downloadFileName;
    try {
      if (kIsWeb) {
        await downloadPhotoBatchInBrowser(url: sourceUrl, fileName: fileName);
        if (!mounted) {
          return;
        }
        showOmniFeedback(
          context,
          l10n.photosDownloadStarted,
          severity: OmniFeedbackSeverity.success,
        );
        return;
      }
      final exportResult = await ref
          .read(photoCenterControllerProvider.notifier)
          .savePhotoFileToDisk(
            url: sourceUrl,
            sizeBytes: photo.fileSize,
            suggestedName: fileName,
          );
      if (!mounted || exportResult is PhotoExportCancelled) return;
      final message = switch (exportResult) {
        PhotoExportSaved(:final path) => l10n.photosDownloadSaved(path),
        PhotoExportShared() => l10n.photosExportShared,
        PhotoExportCancelled() => null,
      };
      if (message != null) {
        showOmniFeedback(context, message);
      }
    } on Exception {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.photosDownloadFailed,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  /// 启动沉浸幻灯片页；关闭后按回传结果恢复查看器位置。
  Future<void> _launchSlideshow() async {
    final scope = ref.read(photoBrowseScopeProvider);
    final startIndex = _currentPage.clamp(
      0,
      _pages.isEmpty ? 0 : _pages.length - 1,
    );
    final startPhoto = _pages.isEmpty ? _current : _pages[startIndex];
    final result = await context.push<Object>(
      '/photos/slideshow',
      extra: {
        'photos': _pages,
        'initialIndex': startIndex,
        'initialPhotoId': startPhoto.id,
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
      showOmniFeedback(
        context,
        l10n.photosTrashMoved,
        severity: OmniFeedbackSeverity.success,
      );
      _closeViewer();
    } on Exception {
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(context).photosDeleteFailed,
        severity: OmniFeedbackSeverity.error,
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
          showOmniFeedback(
            context,
            AppLocalizations.of(context).photosAddedToAlbum,
            severity: OmniFeedbackSeverity.success,
          );
        }
      } on Exception {
        if (context.mounted) {
          showOmniFeedback(
            context,
            AppLocalizations.of(context).photosAddFailed,
            severity: OmniFeedbackSeverity.error,
          );
        }
      }
    }
  }

  /// 查看器收藏切换（头部与紧凑底部动作行共用）。
  Future<void> _toggleViewerFavorite(PhotoItem photo) async {
    // 无 activity:write 的角色：按钮保留但点击明确提示无权限。
    if (!ref.read(userCapabilitiesProvider).canManageOwnActivity) {
      if (mounted) {
        showOmniFeedback(
          context,
          AppLocalizations.of(context).errorForbidden,
          severity: OmniFeedbackSeverity.error,
        );
      }
      return;
    }
    try {
      final wasFavorite = photo.favorite;
      await ref
          .read(photoCenterControllerProvider.notifier)
          .toggleFavorite(photo.id, currentFavorite: photo.favorite);
      if (!mounted) return;
      showOmniFeedback(
        context,
        wasFavorite
            ? AppLocalizations.of(context).favoriteRemoved
            : AppLocalizations.of(context).favoriteAdded,
        severity: OmniFeedbackSeverity.success,
      );
      ref.invalidate(photoDetailProvider(photo.id));
    } on Exception {
      if (mounted) {
        showOmniFeedback(
          context,
          AppLocalizations.of(context).photosOperationFailed,
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final hosted = photosHostedForm(context);
    final l10n = AppLocalizations.of(context);
    // 响应式解析浏览序列：浏览范围或照片列表晚到时页面集合随之扩展，
    // 当前照片以 id 锚定，不因序列变化丢失位置。
    // 仅订阅 photos 列表本身，避免多选/分页等无关变更重建查看器。
    final browseScope = ref.watch(photoBrowseScopeProvider);
    final centerPhotos =
        ref.watch(
          photoCenterControllerProvider.select(
            (value) => value.asData?.value.photos,
          ),
        ) ??
        const <PhotoItem>[];
    final pages = _resolvePages(browseScope, centerPhotos);
    _pages = pages;
    final anchorId = _currentPhotoId ?? widget.photo.id;
    final index = pages.indexWhere((p) => p.id == anchorId);
    _currentPage = index < 0 ? 0 : index.clamp(0, pages.length - 1);
    final current = _pages[_currentPage];
    final currentFresh =
        ref.watch(photoDetailProvider(current.id)).asData?.value ?? current;
    // 仅在 id 锚点变化时对齐 PageView，避免手势翻页过程中被 post-frame 抢页。
    if (_lastPageAnchorId != anchorId) {
      _lastPageAnchorId = anchorId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        if (_pageController.page?.round() != _currentPage) {
          _pageController.jumpToPage(_currentPage);
        }
      });
    }

    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // 托管态（样例 photo-viewer）：横幅常驻、底部动作行在信息面板展开时
    // 让位；工位态保持原有顶栏 + 紧凑档底部行的留白口径。
    final actionsVisible = !_showInfo && (hosted || compact);
    final stagePadding =
        hosted
            ? EdgeInsets.fromLTRB(
              10,
              96,
              10,
              (actionsVisible ? 62 : 24) + safeBottom,
            )
            : const EdgeInsets.fromLTRB(40, 56, 40, 24);
    final badgeBottom = hosted ? stagePadding.bottom + 10 : 24 + safeBottom;
    final stageImageRadius = hosted ? 10.0 : 0.0;
    final date = currentFresh.dateTaken ?? currentFresh.createdAt;
    final viewerTitle =
        currentFresh.locationDisplay(preferZh: _prefersZhLocation(context)) ??
        currentFresh.title;
    final viewerSubtitle =
        date == null
            ? l10n.photosViewerPosition(_currentPage + 1, _pages.length)
            : l10n.photosViewerPositionTime(
              _currentPage + 1,
              _pages.length,
              viewerShortDate(date),
            );

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
                _lastPageAnchorId = _pages[index].id;
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
                  // 首页条带等列表项缺签名原图 URL：用相邻页详情预取写入的
                  // 内存缓存作种子，原图可立即走磁盘缓存，不必等详情往返。
                  final seed =
                      pageRef
                          .watch(photoDetailMemoryCacheProvider)
                          .get(base.id) ??
                      base;
                  final item =
                      pageRef
                          .watch(photoDetailProvider(base.id))
                          .asData
                          ?.value ??
                      seed;
                  return _buildPhotoStage(
                    context,
                    item,
                    index,
                    _pages.length,
                    stagePadding: stagePadding,
                    badgeBottom: badgeBottom,
                    imageRadius: stageImageRadius,
                    hosted: hosted,
                  );
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
        // 顶部横幅：托管态用样例玻璃横幅（地名 + N of M · 时间 + 幻灯片），
        // 工位态保留原半透明浮层。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child:
              hosted
                  ? PhotoViewerHostedHeader(
                    title: viewerTitle,
                    subtitle: viewerSubtitle,
                    onBack: _closeViewer,
                    onSlideshow: _launchSlideshow,
                  )
                  : PhotoViewerTopBar(
                    photo: currentFresh,
                    onClose: _closeViewer,
                    onToggleFavorite:
                        () => unawaited(_toggleViewerFavorite(currentFresh)),
                    onDelete: _confirmDelete,
                    onToggleInfo:
                        () =>
                            ref
                                .read(photoInfoPanelVisibleProvider.notifier)
                                .toggle(),
                    onAddToAlbum: () => _showAddToAlbumDialog(context, ref),
                    onEdit: () {
                      context.push('/photos/${currentFresh.id}/edit');
                    },
                    onSlideshow: _launchSlideshow,
                    onDownload: () => unawaited(_downloadPhoto()),
                    onShare: _openSharePanel,
                    showInfo: _showInfo,
                    compact: compact,
                    countText: '${_currentPage + 1} / ${_pages.length}',
                  ),
        ),
        // 底部七钮动作行（样例 photo-actions）：信息面板以底部 sheet
        // 呈现时不渲染，避免两层叠底。
        if (actionsVisible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child:
                hosted
                    ? PhotoViewerHostedActions(
                      photo: currentFresh,
                      onToggleFavorite:
                          () => unawaited(_toggleViewerFavorite(currentFresh)),
                      onShare: _openSharePanel,
                      onDownload: () => unawaited(_downloadPhoto()),
                      onEdit:
                          () => context.push('/photos/${currentFresh.id}/edit'),
                      onAddToAlbum: () => _showAddToAlbumDialog(context, ref),
                      onToggleInfo:
                          () =>
                              ref
                                  .read(photoInfoPanelVisibleProvider.notifier)
                                  .toggle(),
                      onDelete: _confirmDelete,
                      showInfo: _showInfo,
                    )
                    : PhotoViewerBottomActions(
                      photo: currentFresh,
                      onToggleFavorite:
                          () => unawaited(_toggleViewerFavorite(currentFresh)),
                      onShare: _openSharePanel,
                      onDownload: () => unawaited(_downloadPhoto()),
                      onEdit:
                          () => context.push('/photos/${currentFresh.id}/edit'),
                      onAddToAlbum: () => _showAddToAlbumDialog(context, ref),
                      onToggleInfo:
                          () =>
                              ref
                                  .read(photoInfoPanelVisibleProvider.notifier)
                                  .toggle(),
                      onDelete: _confirmDelete,
                      showInfo: _showInfo,
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
    int total, {
    required EdgeInsets stagePadding,
    required double badgeBottom,
    required double imageRadius,
    required bool hosted,
  }) {
    final imageUrl = photo.sourceUrl ?? photo.coverUrl;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewBackground =
        hosted
            ? photoViewerHostedStageColor
            : isDark
            ? FramePalette.viewerBg
            : context.photosColors.surfaceContainerLow;
    return ColoredBox(
      // 托管态取样例 photo-viewer 实底，工位暗色取设计稿查看器底色，
      // 亮色跟随主题浅色底。
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
                // 舞台留白由调用方按形态给定：工位四周 40/56/40/24，
                // 托管按样例 photo-stage 窄留白并避开横幅与动作行。
                padding: stagePadding,
                child: Center(
                  child:
                      imageUrl != null && imageUrl.isNotEmpty
                          ? Hero(
                            tag: 'photo-cover-${photo.id}',
                            // Default Material flight + InteractiveViewer
                            // Transform can leave a diagonal white seam.
                            // Fly the destination child without extra chrome.
                            flightShuttleBuilder:
                                (
                                  flightContext,
                                  animation,
                                  flightDirection,
                                  fromHeroContext,
                                  toHeroContext,
                                ) => (toHeroContext.widget as Hero).child,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(imageRadius),
                              clipBehavior: Clip.hardEdge,
                              child: InteractiveViewer(
                                minScale: 1,
                                maxScale: 5,
                                clipBehavior: Clip.hardEdge,
                                child: SizedBox.expand(
                                  child: _ProgressivePhotoImage(photo: photo),
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
              left: hosted ? 16 : 24,
              bottom: badgeBottom,
              child: _MotionBadge(
                active: _motionPinnedPlaying,
                label: AppLocalizations.of(context).photosLiveBadge,
                tooltip: AppLocalizations.of(context).photosLiveBadgeTooltip,
                onTap: () => _setMotionPinned(!_motionPinnedPlaying),
              ),
            ),
          // 圆形翻页钮（样例 photo-nav）：各宽度档常驻，仅首尾页隐藏。
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
