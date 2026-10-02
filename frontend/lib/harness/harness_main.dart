// 双实况对照 harness：独立入口，渲染三模块页 hosted 形态 + 通知中心，
// 与样例 5200 同视口截图对照。不进正式构建（路径 lib/harness/ 下，
// build web 时以 -t 指定）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_shell.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_page.dart';
import 'package:omninest/features/search/presentation/pages/mobile_search_page.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';

void main() {
  runApp(const ProviderScope(child: _HarnessApp()));
}

class _HarnessApp extends StatelessWidget {
  const _HarnessApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Harness',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: OmniNestTheme.from(AppThemePalette.light),
      home: const _HarnessShell(),
    );
  }
}

const _harnessCaps = UserCapabilities(
  canBrowseContent: true,
  canContributeContent: true,
  canManageOwnActivity: true,
  canManagePreferences: true,
  canManageAccount: true,
  canUseBackdropLibrary: true,
  canUploadBackdrop: true,
  canViewOwnTasks: true,
  canAdminTasks: true,
  canManageMediaLibrary: true,
  canManagePhotos: true,
  canAdminUsers: true,
  canReadSystemConfig: true,
  canManageSystemConfig: true,
  canAccessAdminConsole: true,
  canSharedBrowse: true,
  canSharedUpload: true,
  canReadWeather: true,
  canReportLocation: true,
  canManageTwoFactor: true,
  canReadActivity: true,
);

class _HarnessShell extends ConsumerStatefulWidget {
  const _HarnessShell();

  @override
  ConsumerState<_HarnessShell> createState() => _HarnessShellState();
}

class _HarnessShellState extends ConsumerState<_HarnessShell> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    // 底部切换栏：0=通知 1=音乐 2=照片 3=影视 4=搜索
    // 页面经 MobileHostedRoute（生产真实链，勿手动挂 scope）。
    final pages = <Widget>[
      const MobileHostedRoute(child: NotificationPage()),
      const MobileHostedRoute(child: MusicDeckShell()),
      const MobileHostedRoute(child: PhotosPage()),
      const MobileHostedRoute(child: MovieCenterPage()),
      const MobileHostedRoute(child: MobileSearchPage()),
    ];
    return ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        userCapabilitiesProvider.overrideWithValue(_harnessCaps),
        notificationControllerProvider.overrideWith(
          () => _HarnessNotificationController(),
        ),
        unreadCountProvider.overrideWith(() => _HarnessUnreadCountNotifier()),
        musicCenterControllerProvider.overrideWith(
          () => _HarnessMusicCenterController(),
        ),
        photoCenterControllerProvider.overrideWith(
          () => _HarnessPhotoCenterController(),
        ),
        movieCenterControllerProvider.overrideWith(
          () => _HarnessMovieCenterController(),
        ),
      ],
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1110),
        body: pages[_page],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _page,
          onDestinationSelected: (v) => setState(() => _page = v),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.notifications),
              label: '通知',
            ),
            NavigationDestination(icon: Icon(Icons.music_note), label: '音乐'),
            NavigationDestination(icon: Icon(Icons.photo), label: '照片'),
            NavigationDestination(icon: Icon(Icons.movie), label: '影视'),
            NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          ],
        ),
      ),
    );
  }
}

class _HarnessNotificationController extends NotificationController {
  @override
  NotificationState build() => NotificationState(
    items: [
      NotificationDto(
        id: 'n-1',
        type: 'SYSTEM_MESSAGE',
        title: '42 张照片加入了金色黄昏',
        message: '今晚上传的照片已完成导入。',
        read: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      NotificationDto(
        id: 'n-2',
        type: 'TASK_EVENT',
        title: 'Aperture 已就绪',
        message: '转码完成 · 1h 46m · 4K HDR。',
        read: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
      ),
      NotificationDto(
        id: 'n-3',
        type: 'SYSTEM_MESSAGE',
        title: '备份进行中',
        message: '春季之旅 · 剩余 1.2 GB。',
        read: false,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ],
    total: 6,
  );

  @override
  Future<void> load({int page = 0, int size = 20}) async {}

  @override
  Future<void> refreshForRealtime({int size = 20}) async {}

  @override
  Future<void> markAllRead() async {}
}

class _HarnessUnreadCountNotifier extends UnreadCountNotifier {
  @override
  int build() => 3;
}

/// 样例同款曲库数据：供 hosted 首页渲染 NOW PLAYING 卡、每日推荐横滑
/// 与续听列表，供 390×844 截图对照。
MusicTrack _track(
  String id,
  String title,
  String artist,
  int durationSeconds,
) {
  return MusicTrack(
    id: id,
    fileNodeId: id,
    title: title,
    artistName: artist,
    albumTitle: 'Evening Drift',
    format: 'AUDIO',
    favorite: false,
    durationSeconds: durationSeconds,
  );
}

class _HarnessMusicCenterController extends MusicCenterController {
  @override
  Future<MusicCenterState> build() async {
    final tracks = [
      _track('t1', 'Weightless', 'Marconi Union', 402),
      _track('t2', 'An Ending', 'Brian Eno', 266),
      _track('t3', 'Says', 'Nils Frahm', 484),
      _track('t4', 'Near Light', 'Ólafur Arnalds', 249),
      _track('t5', 'Blue Current', 'Ryuichi', 318),
    ];
    final playables = [
      for (final track in tracks) MusicPlayableItem.local(track),
    ];
    return MusicCenterState(
      dashboard: MusicDashboard(
        trackCount: 312,
        albumCount: 24,
        artistCount: 9,
        playHistoryCount: 128,
        recentTracks: tracks.take(3).toList(growable: false),
        recentAlbums: const [],
        featuredArtists: const [],
      ),
      tracks: tracks,
      albums: const [
        MusicAlbum(
          id: 'a1',
          title: 'Evening Drift',
          artistName: 'Ambient mix',
          trackCount: 42,
        ),
        MusicAlbum(
          id: 'a2',
          title: 'Soft Geometry',
          artistName: 'Lea Sen',
          trackCount: 18,
        ),
        MusicAlbum(
          id: 'a3',
          title: 'Blue Current',
          artistName: 'Ryuichi',
          trackCount: 24,
        ),
      ],
      artists: const [
        MusicArtist(
          id: 'ar1',
          name: 'Marconi Union',
          trackCount: 12,
          albumCount: 3,
        ),
        MusicArtist(
          id: 'ar2',
          name: 'Nils Frahm',
          trackCount: 8,
          albumCount: 2,
        ),
        MusicArtist(
          id: 'ar3',
          name: 'Ólafur Arnalds',
          trackCount: 15,
          albumCount: 4,
        ),
      ],
      playlists: const [
        MusicPlaylist(
          id: 'p1',
          name: 'Evening Drift',
          playlistType: 'CUSTOM',
          trackCount: 42,
        ),
        MusicPlaylist(
          id: 'p2',
          name: 'Focus chamber',
          playlistType: 'CUSTOM',
          trackCount: 18,
        ),
        MusicPlaylist(
          id: 'p3',
          name: 'Rainy commutes',
          playlistType: 'CUSTOM',
          trackCount: 31,
        ),
        MusicPlaylist(
          id: 'p4',
          name: 'Blue hours',
          playlistType: 'CUSTOM',
          trackCount: 24,
        ),
      ],
      recentItems: playables,
      currentItem: playables.first,
      isPlaying: false,
      playbackItems: playables,
      playbackIndex: 0,
    );
  }
}


/// 样例同款图库数据：126 照片 / 4 影集的 hosted 首屏对照。
class _HarnessPhotoCenterController extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async {
    PhotoItem photo(String id, String title, {bool favorite = false}) {
      return PhotoItem(
        id: id,
        fileNodeId: id,
        title: title,
        format: 'IMAGE',
        fileSize: 2400000,
        metadataStatus: 'READY',
        favorite: favorite,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );
    }

    final photos = [
      photo('p1', 'West Lake dusk'),
      photo('p2', 'Boat silhouette'),
      photo('p3', 'Reeds and light'),
      photo('p4', 'Bridge at golden hour'),
      photo('p5', 'Quiet water'),
      photo('p6', 'Evening walk'),
    ];
    final albums = [
      PhotoAlbum(
        id: 'al1',
        name: '金色黄昏',
        description: '',
        photoCount: 18,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      PhotoAlbum(
        id: 'al2',
        name: '湖边的安静周末',
        description: '',
        photoCount: 24,
        createdAt: DateTime.now().subtract(const Duration(days: 9)),
        updatedAt: DateTime.now().subtract(const Duration(days: 8)),
      ),
      PhotoAlbum(
        id: 'al3',
        name: '春季之旅',
        description: '',
        photoCount: 12,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        updatedAt: DateTime.now().subtract(const Duration(days: 28)),
      ),
    ];
    return PhotoCenterState(
      dashboard: PhotoDashboard.empty(),
      photos: photos,
      tab: PhotoTab.all,
      favorites: photos.take(2).toList(growable: false),
      albums: albums,
      timeline: PhotoTimeline(
        years: [
          PhotoYearGroup(
            year: 2026,
            months: [
              PhotoMonthGroup(month: 10, photoCount: 6, previewPhotos: photos),
              PhotoMonthGroup(
                month: 9,
                photoCount: 4,
                previewPhotos: photos.take(4).toList(growable: false),
              ),
            ],
          ),
          PhotoYearGroup(
            year: 2025,
            months: [
              PhotoMonthGroup(
                month: 8,
                photoCount: 3,
                previewPhotos: photos.take(3).toList(growable: false),
              ),
            ],
          ),
        ],
      ),
      photoTotalElements: 126,
      favoriteTotalElements: 2,
    );
  }
}


/// 样例同款影视数据：For you 英雄图 + 继续观看横滑 + 影片列表对照。
class _HarnessMovieCenterController extends MovieCenterController {
  @override
  Future<MovieCenterState> build() async {
    MovieVideoItem film(
      String id,
      String title,
      int year,
      int runtimeMinutes,
      double rating, {
      String genre = 'Drama',
    }) {
      return MovieVideoItem(
        id: id,
        fileNodeId: id,
        mediaType: 'MOVIE',
        title: title,
        metadataStatus: 'READY',
        nfoStatus: 'NONE',
        updatedAt: DateTime.now(),
        metadata: const <String, dynamic>{},
        releaseDate: DateTime(year, 3, 12),
        runtimeSeconds: runtimeMinutes * 60,
        rating: rating,
        genres: [genre],
      );
    }

    final films = [
      film('v1', 'Aperture', 2025, 106, 8.7, genre: 'Sci-Fi'),
      film('v2', 'Edge of Quiet', 2025, 106, 8.1, genre: 'Drama'),
      film('v3', 'Northern Light', 2024, 123, 7.9, genre: 'Adventure'),
      film('v4', 'The Long Coast', 2024, 98, 7.4, genre: 'Drama'),
    ];
    final continueWatching = [
      for (final (index, item) in films.indexed)
        MovieContinueWatching(
          id: item.id,
          title: item.title,
          positionSeconds: (item.runtimeSeconds ?? 6000) * (index + 2) ~/ 10,
          durationSeconds: item.runtimeSeconds ?? 6000,
          progressPercent: 0.28 + index * 0.1,
          updatedAt: DateTime.now().subtract(Duration(days: index)),
        ),
    ];
    return MovieCenterState(
      dashboard: MovieDashboard(
        stats: const MovieStats(
          movieCount: 128,
          episodeCount: 64,
          seriesCount: 12,
          scrapeFailedCount: 0,
        ),
        recentlyAdded: films,
        continueWatching: continueWatching,
        series: const [],
      ),
      movies: films,
      recentItems: films,
      continueWatching: continueWatching,
      favoriteItems: films.take(2).toList(growable: false),
      watchHistory: const [],
      collections: const [],
      tasks: const [],
      section: MovieSection.continueWatching,
    );
  }

  @override
  Future<void> refresh() async {}
}
