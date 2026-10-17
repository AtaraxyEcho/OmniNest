import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/widgets/mobile_segment_pager.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/module_entry_refresh_listener.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/app/mobile_shell/mobile_environment_scope.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/mobile_sample_kit.dart';
import 'package:omninest/features/library/presentation/widgets/library_space_tier.dart';
import 'package:omninest/features/library/presentation/widgets/library_space_widgets.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_portal_integration.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_detail_routes.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';

/// 分段条吸顶层几何：胶囊 48 + 容器内衬 4×2，顶距 8。
const double _librarySegmentTopInset = 8;
const double _librarySegmentBarHeight = 56;
const double _librarySegmentOverlayExtent =
    _librarySegmentTopInset + _librarySegmentBarHeight;

/// Library 媒体空间：Photos/Movies/Music 的统一媒体首页。
///
/// 以真实媒体内容为主体（相册横幅、照片马赛克、海报轨、专辑轨），
/// 分段轻量切换内容族；完整模块能力经「查看全部」进入全屏模块页。
class LibrarySpacePage extends ConsumerStatefulWidget {
  const LibrarySpacePage({super.key});

  @override
  ConsumerState<LibrarySpacePage> createState() => _LibrarySpacePageState();
}

class _LibrarySpacePageState extends ConsumerState<LibrarySpacePage> {
  LibrarySegment _segment = LibrarySegment.all;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectSegment(LibrarySegment segment) {
    // 落页动画由分页器给出（外部改选 → animateToPage 280ms easeOutCubic），
    // 本页不再自己调一次，否则同一目标被排两次动画。
    setState(() => _segment = segment);
  }

  /// 回到 Library 分支时节流刷新各媒体仪表盘。
  void _refreshOnEntry() {
    unawaited(_refreshDashboardSections());
  }

  Future<void> _refreshDashboardSections() async {
    final center = ref.read(musicCenterControllerProvider.notifier);
    await Future.wait(<Future<void>>[
      ref.read(photoDashboardProvider.notifier).reload(),
      ref.refresh(photoAlbumsProvider.future),
      ref.refresh(movieDashboardProvider.future),
      center.refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final photos = ref.watch(photoDashboardProvider);
    final albums = ref.watch(photoAlbumsProvider);
    final movies = ref.watch(movieDashboardProvider);
    final musicCenter = ref.watch(musicCenterControllerProvider);
    // 整屏唯一动画：各轨的加载占位是静态块，不再各自画转圈。
    final anySectionLoading =
        photos.isLoading ||
        albums.isLoading ||
        movies.isLoading ||
        musicCenter.isLoading;
    final tier = LibrarySpaceTier.resolve(context);
    final padding = tier.horizontalPadding;

    Widget page(List<Widget> children) {
      return MobileEnvironmentScope(
        child: RefreshIndicator(
          color: context.env.accent,
          onRefresh: _refreshDashboardSections,
          // 原型 `.module-overlay > main` 限宽居中，平板与桌面宽窗下内容不摊
          // 满整幅；650 基线在 ≥980 档抬到 760（见 LibrarySpaceTier）。
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: tier.contentMaxWidth),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                // 分段条吸顶浮在内容之上，列表首屏需让出同等的顶部净高，
                // 否则横幅被永久遮住。
                padding: EdgeInsets.fromLTRB(
                  padding,
                  _librarySegmentOverlayExtent + 14,
                  padding,
                  28,
                ),
                children: [
                  if (anySectionLoading) const MobileLoadingLine(top: true),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 四段内容：顺序必须与 LibrarySegment 声明次序一致，分页器按该次序排页。
    Widget pageFor(LibrarySegment segment) => switch (segment) {
      LibrarySegment.all => page([
        _buildBanner(l10n, albums, photos),
        const SizedBox(height: 20),
        _buildPhotosSection(l10n, photos),
        const SizedBox(height: MobileLayoutTokens.sectionGap),
        _buildMoviesSection(l10n, movies),
        const SizedBox(height: MobileLayoutTokens.sectionGap),
        _buildMusicSection(l10n, musicCenter),
      ]),
      LibrarySegment.photos => page([
        _buildBanner(l10n, albums, photos),
        const SizedBox(height: 20),
        _buildPhotosSection(l10n, photos),
        const SizedBox(height: MobileLayoutTokens.sectionGap),
        _buildAlbumsRail(l10n, albums),
      ]),
      LibrarySegment.movies => page([
        _buildMoviesSection(l10n, movies),
        const SizedBox(height: MobileLayoutTokens.sectionGap),
        _buildRecentlyAddedRail(l10n, movies),
      ]),
      LibrarySegment.music => page([
        _buildNowPlayingCard(l10n, musicCenter),
        const SizedBox(height: 20),
        _buildMusicSection(l10n, musicCenter),
        const SizedBox(height: MobileLayoutTokens.sectionGap),
        _buildRecentTrackRows(l10n, musicCenter),
      ]),
    };

    return ModuleEntryRefreshListener(
      modulePath: '/library',
      onRefresh: _refreshOnEntry,
      // 阶梯：分段页不是路由，先回「全部」段；已在全部段才回门户。媒体库是
      // 分支里的唯一路由，没有 PopScope 时一次侧滑就被引擎当成无路由可退，
      // 直接结束 Activity（观感是「在媒体库侧滑→回到桌面」）。
      child: PopScope(
        canPop: !MobileShellScope.isHosted(context),
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_segment != LibrarySegment.all) {
            _selectSegment(LibrarySegment.all);
            return;
          }
          context.go('/portal');
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // 原生 PageView：手指跟手的丝滑横滑，分段点选带动画落页。
              // 控制器由本页持有——分段滑块要读连续页码，见下方 ListenableBuilder。
              Positioned.fill(
                child: MobileSegmentPager<LibrarySegment>(
                  sections: LibrarySegment.values,
                  current: _segment,
                  controller: _pageController,
                  onChanged: (segment) => setState(() => _segment = segment),
                  pageBuilder: (context, segment) => pageFor(segment),
                ),
              ),
              // 分段条吸顶浮在内容之上：原型 .segmented 为 position: sticky +
              // blur(22)，列表滚动时从条下方穿过而不是被推走。吸顶层与内容盒
              // 共用同一限宽，平板宽窗下不会出现条比内容更宽的两套边界。
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Align(
                  // 样例 `.segmented` 是 width:max-content 靠左，不居中。
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: tier.contentMaxWidth),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        _librarySegmentTopInset,
                        padding,
                        0,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                          child: ListenableBuilder(
                            // 滑块跟手：PageView 每帧通知，页码是连续值，段标签
                            // 仍在 onPageChanged 落定时才换，避免中途双高亮。
                            listenable: _pageController,
                            builder:
                                (context, _) => LibrarySegmentBar(
                                  segment: _segment,
                                  page:
                                      _pageController.hasClients
                                          ? _pageController.page
                                          : null,
                                  onChanged: _selectSegment,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 影集横滑（照片档补充内容）。
  Widget _buildAlbumsRail(
    AppLocalizations l10n,
    AsyncValue<List<PhotoAlbum>> albums,
  ) {
    final albumList = albums.asData?.value ?? const <PhotoAlbum>[];
    if (albumList.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibrarySectionHeader(
          eyebrow: l10n.libraryCollectionEyebrow,
          title: l10n.photosTabAlbums,
          actionLabel: l10n.portalMobileViewAll,
          onAction: () => context.push('/photos'),
        ),
        const SizedBox(height: 12),
        LibraryRail(
          height: libraryAlbumRailHeight(context),
          children: [
            for (final album in albumList.take(10))
              LibraryAlbumCard(
                imageUrl: album.coverUrl,
                title: album.name,
                detail: l10n.libraryBannerPhotoCount(album.photoCount),
                onTap: () => context.push('/photos/albums/${album.id}'),
              ),
          ],
        ),
      ],
    );
  }

  /// 最近上架影片轨（影视档补充内容）。
  Widget _buildRecentlyAddedRail(
    AppLocalizations l10n,
    AsyncValue<MovieDashboard> movies,
  ) {
    return movies.when(
      loading:
          () => MobileSkeletonBlock(height: libraryPosterRailHeight(context)),
      error: (_, _) => const SizedBox.shrink(),
      data: (dashboard) {
        final recent = dashboard.recentlyAdded.take(10).toList();
        if (recent.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LibrarySectionHeader(
              eyebrow: l10n.libraryJustInEyebrow,
              title: l10n.videoRedesignSubMovies,
              actionLabel: l10n.portalMobileViewAll,
              onAction: () => context.push('/video?section=continueWatching'),
            ),
            const SizedBox(height: 12),
            LibraryRail(
              height: libraryPosterRailHeight(context),
              children: [
                for (final item in recent)
                  LibraryPosterCard(
                    imageUrl: item.posterUrl,
                    title: item.title,
                    detail: item.year,
                    progress: null,
                    onTap: () => context.push(movieDetailRoute(item)),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 正在播放卡（音乐档顶部，样例 music-hero）。
  Widget _buildNowPlayingCard(
    AppLocalizations l10n,
    AsyncValue<MusicCenterState> musicCenter,
  ) {
    final center = musicCenter.asData?.value;
    final track = center?.activeTrack;
    if (track == null) {
      return const SizedBox.shrink();
    }
    return _LibraryNowPlayingCard(
      eyebrow: l10n.musicDeckNowPlaying,
      title: track.title,
      subtitle: track.artistName,
      imageUrl: track.coverUrl,
      trackId: track.id,
      metadataDuration: Duration(seconds: track.durationSeconds ?? 0),
      onTap: () => context.push('/music/now-playing'),
    );
  }

  /// 最近曲目编号行（音乐档补充内容）。
  Widget _buildRecentTrackRows(
    AppLocalizations l10n,
    AsyncValue<MusicCenterState> musicCenter,
  ) {
    final center = musicCenter.asData?.value;
    final items = center?.recentItems ?? const <MusicPlayableItem>[];
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibrarySectionHeader(
          eyebrow: l10n.libraryMadeForNowEyebrow,
          title: l10n.musicDeckContinueListening,
          actionLabel: l10n.portalMobileViewAll,
          onAction: () => context.push('/music'),
        ),
        const SizedBox(height: 4),
        for (final (index, item) in items.take(5).indexed)
          SampleSerifRow(
            number: '${index + 1}',
            title: item.track.title,
            subtitle:
                '${item.track.artistName} · ${_formatTrackDuration(Duration(seconds: item.track.durationSeconds ?? 0))}',
            onTap:
                () => unawaited(
                  ref.read(musicCenterControllerProvider.notifier).playItems([
                    item,
                  ], startIndex: index),
                ),
            trailing: Icon(
              Icons.more_horiz_rounded,
              size: 19,
              color: context.env.inkFaint,
            ),
          ),
      ],
    );
  }

  /// 记忆横幅：优先最新相册，其次最新照片；两者皆无则隐藏。
  Widget _buildBanner(
    AppLocalizations l10n,
    AsyncValue<List<PhotoAlbum>> albums,
    AsyncValue<PhotoDashboard> photos,
  ) {
    final albumList = albums.asData?.value ?? const <PhotoAlbum>[];
    final recentPhotos =
        photos.asData?.value.recentPhotos ?? const <PhotoItem>[];
    final album = albumList.isNotEmpty ? albumList.first : null;
    if (album != null && album.hasCover) {
      return LibraryFeatureBanner(
        imageUrl: album.coverUrl,
        eyebrow: l10n.libraryBannerEyebrow,
        title: album.name,
        detail: l10n.libraryBannerPhotoCount(album.photoCount),
        actionLabel: l10n.libraryOpenAlbum,
        onTap: () => context.push('/photos/albums/${album.id}'),
      );
    }
    if (recentPhotos.isNotEmpty) {
      final photo = recentPhotos.first;
      return LibraryFeatureBanner(
        imageUrl: photo.coverUrl,
        eyebrow: l10n.libraryBannerEyebrow,
        title: l10n.libraryRecentPhotosTitle,
        detail: l10n.libraryBannerPhotoCount(
          photos.asData?.value.totalPhotos ?? recentPhotos.length,
        ),
        actionLabel: l10n.portalMobileViewAll,
        onTap: () => context.push('/photos'),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildPhotosSection(
    AppLocalizations l10n,
    AsyncValue<PhotoDashboard> photos,
  ) {
    final showFavorites = _segment == LibrarySegment.photos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibrarySectionHeader(
          eyebrow:
              _segment == LibrarySegment.all
                  ? l10n.libraryJustInEyebrow
                  : l10n.libraryCollectionEyebrow,
          title:
              _segment == LibrarySegment.all
                  ? l10n.libraryRecentPhotosTitle
                  : l10n.portalDockPhotos,
          actionLabel: l10n.portalMobileViewAll,
          onAction: () => context.push('/photos'),
        ),
        const SizedBox(height: 12),
        photos.when(
          loading:
              () => MobileSkeletonBlock(
                height: LibrarySpaceTier.resolve(context).mosaicHeight,
              ),
          error:
              (_, _) => EnvEmptyState(
                icon: OmniIcons.image,
                title: l10n.libraryEmptyPhotosTitle,
                message: l10n.libraryEmptyPhotosMessage,
                actionLabel: l10n.coreRetry,
                onAction:
                    () => unawaited(
                      ref.read(photoDashboardProvider.notifier).reload(),
                    ),
              ),
          data:
              (dashboard) => LibraryPhotoMosaic(
                photos: dashboard.recentPhotos,
                onOpenModule: () => context.push('/photos'),
              ),
        ),
        if (showFavorites) ...[
          const SizedBox(height: 20),
          LibrarySectionHeader(
            eyebrow: l10n.libraryCollectionEyebrow,
            title: l10n.librarySectionFavorites,
            actionLabel: l10n.portalMobileViewAll,
            onAction: () => context.push('/photos'),
          ),
          const SizedBox(height: 12),
          photos.when(
            loading: () => const MobileSkeletonBlock(height: 118),
            error: (_, _) => const SizedBox.shrink(),
            data: (dashboard) {
              final favorites = dashboard.favoritePhotos;
              if (favorites.isEmpty) {
                return EnvEmptyState(
                  icon: OmniIcons.heart,
                  title: l10n.libraryEmptyFavoritesTitle,
                  message: l10n.libraryEmptyFavoritesMessage,
                  compact: true,
                );
              }
              return LibraryRail(
                height: 118,
                children: [
                  for (
                    var index = 0;
                    index < favorites.length && index < 12;
                    index++
                  )
                    LibraryFavoritePhotoTile(photos: favorites, index: index),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildMoviesSection(
    AppLocalizations l10n,
    AsyncValue<MovieDashboard> movies,
  ) {
    final isMoviesSegment = _segment == LibrarySegment.movies;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibrarySectionHeader(
          eyebrow:
              isMoviesSegment
                  ? l10n.libraryCollectionEyebrow
                  : l10n.libraryPickUpEyebrow,
          title:
              isMoviesSegment
                  ? l10n.portalDockMovies
                  : l10n.libraryContinueWatchingTitle,
          actionLabel: l10n.portalMobileViewAll,
          onAction: () => context.push('/video?section=continueWatching'),
        ),
        const SizedBox(height: 12),
        movies.when(
          loading:
              () =>
                  MobileSkeletonBlock(height: libraryPosterRailHeight(context)),
          error:
              (_, _) => EnvEmptyState(
                icon: OmniIcons.film,
                title: l10n.libraryEmptyMoviesTitle,
                message: l10n.libraryEmptyMoviesMessage,
                actionLabel: l10n.coreRetry,
                onAction:
                    () => unawaited(ref.refresh(movieDashboardProvider.future)),
              ),
          data: (dashboard) {
            final continueItems =
                dashboard.continueWatching
                    .take(isMoviesSegment ? 10 : 6)
                    .toList();
            final children = <Widget>[
              for (final item in continueItems)
                LibraryPosterCard(
                  imageUrl: item.posterUrl,
                  title: item.title,
                  detail: libraryContinueDetail(l10n, item),
                  progress: item.progressPercent / 100,
                  onTap: () => context.push(moviePlayRoute(item.id)),
                ),
            ];
            if (children.isNotEmpty) {
              return LibraryRail(
                height: libraryPosterRailHeight(context),
                children: children,
              );
            }
            final recent =
                dashboard.recentlyAdded.take(isMoviesSegment ? 10 : 6).toList();
            if (recent.isEmpty) {
              return EnvEmptyState(
                icon: OmniIcons.film,
                title: l10n.libraryEmptyMoviesTitle,
                message: l10n.libraryEmptyMoviesMessage,
                compact: true,
              );
            }
            return LibraryRail(
              height: libraryPosterRailHeight(context),
              children: [
                for (final item in recent)
                  LibraryPosterCard(
                    imageUrl: item.posterUrl,
                    title: item.title,
                    detail: item.year,
                    progress: null,
                    onTap: () => context.push(movieDetailRoute(item)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMusicSection(
    AppLocalizations l10n,
    AsyncValue<MusicCenterState> musicCenter,
  ) {
    final albums =
        musicCenter.asData?.value.albums.take(10).toList() ??
        const <MusicAlbum>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibrarySectionHeader(
          eyebrow:
              _segment == LibrarySegment.music
                  ? l10n.libraryCollectionEyebrow
                  : l10n.libraryMadeForNowEyebrow,
          title:
              _segment == LibrarySegment.music
                  ? l10n.mobileNavMusic
                  : l10n.libraryRecentListeningTitle,
          actionLabel: l10n.portalMobileViewAll,
          onAction: () => context.push('/music'),
        ),
        const SizedBox(height: 12),
        if (musicCenter.isLoading && albums.isEmpty)
          MobileSkeletonBlock(height: libraryAlbumRailHeight(context))
        else if (albums.isEmpty)
          EnvEmptyState(
            icon: OmniIcons.music,
            title: l10n.libraryEmptyMusicTitle,
            message: l10n.libraryEmptyMusicMessage,
            compact: true,
          )
        else
          LibraryRail(
            height: libraryAlbumRailHeight(context),
            children: [
              for (final album in albums)
                LibraryAlbumCard(
                  imageUrl: album.coverUrl,
                  title: album.title,
                  detail: album.artistName,
                  onTap: () {
                    unawaited(
                      ref.read(musicPortalActionsProvider).playAlbum(album),
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

/// 曲目时钟文案：`分:秒`，秒位补零。
String _formatTrackDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// 正在播放卡：真实播放位置的唯一持有者。
///
/// 播放位置按流自持节流刷新，只重建本卡片。不得把逐 tick 变化的位置写进
/// 页面状态或整页监听的 Provider，否则每次 tick 都会重排整个媒体库列表。
class _LibraryNowPlayingCard extends ConsumerStatefulWidget {
  const _LibraryNowPlayingCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.trackId,
    required this.metadataDuration,
    required this.onTap,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String? imageUrl;

  /// 当前曲目标识：切曲时用于归零并重新绑定播放器。
  final String trackId;

  /// 元数据时长：播放器尚未报出时长时的兜底总长。
  final Duration metadataDuration;

  final VoidCallback onTap;

  @override
  ConsumerState<_LibraryNowPlayingCard> createState() =>
      _LibraryNowPlayingCardState();
}

class _LibraryNowPlayingCardState
    extends ConsumerState<_LibraryNowPlayingCard> {
  /// 重绘节流：位置流按帧推送，卡片只需秒级观感。
  static const Duration _repaintInterval = Duration(milliseconds: 500);

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  Duration _position = Duration.zero;
  Duration? _playerDuration;
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _bindPlayer();
  }

  @override
  void didUpdateWidget(covariant _LibraryNowPlayingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackId == widget.trackId) {
      return;
    }
    _bindPlayer();
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    super.dispose();
  }

  void _bindPlayer() {
    final player = ref.read(musicPlaybackSessionProvider).player;
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    _position = player.state.position;
    _playerDuration = player.state.duration;
    _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
    _positionSubscription = player.stream.position.listen((position) {
      final now = DateTime.now();
      if (now.difference(_lastPaint) < _repaintInterval) {
        return;
      }
      _lastPaint = now;
      if (!mounted) {
        return;
      }
      setState(() => _position = position);
    });
    _durationSubscription = player.stream.duration.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() => _playerDuration = duration);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reported = _playerDuration;
    final total =
        (reported != null && reported > Duration.zero)
            ? reported
            : widget.metadataDuration;
    final position =
        total > Duration.zero && _position > total ? total : _position;
    final progress =
        total.inMilliseconds <= 0
            ? 0.0
            : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return SampleNowPlayingCard(
      eyebrow: widget.eyebrow,
      title: widget.title,
      subtitle: widget.subtitle,
      imageUrl: widget.imageUrl,
      progress: progress,
      progressText:
          '${_formatTrackDuration(position)} / ${_formatTrackDuration(total)}',
      onTap: widget.onTap,
    );
  }
}
