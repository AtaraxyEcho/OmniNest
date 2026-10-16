import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_sliding_segment_row.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/library/presentation/pages/library_space_page.dart';
import 'package:omninest/features/library/presentation/widgets/library_space_widgets.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';

void main() {
  testWidgets('All 视图组合三类媒体区块，分段切换收敛到单区块', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackdropControllerProvider.overrideWith(
            _EmptyBackdropController.new,
          ),
          photoDashboardProvider.overrideWith(_FakePhotoDashboard.new),
          photoAlbumsProvider.overrideWith((ref) async => _albums),
          movieDashboardProvider.overrideWith((ref) async => _movieDashboard),
          musicCenterControllerProvider.overrideWith(
            _FakeLibraryMusicCenter.new,
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const LibrarySpacePage(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 分段条与三类区块并存：横幅 + 照片 + 影视 + 音乐。
    expect(find.byType(LibrarySegmentBar), findsOneWidget);
    expect(find.byType(LibraryFeatureBanner), findsOneWidget);
    expect(find.byType(LibraryPhotoMosaic), findsOneWidget);
    expect(find.byType(LibraryPosterCard), findsNWidgets(2));
    expect(find.byType(LibraryAlbumCard), findsNWidgets(2));

    // 切到照片分段：照片区块 + 收藏轨 + 影集轨，影视与音乐区块卸载。
    await tester.tap(find.text('照片'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryPhotoMosaic), findsOneWidget);
    expect(find.byType(LibraryPosterCard), findsNothing);
    // 影集轨瓦片来自 photoAlbums（LibraryAlbumCard 复用，假体 1 本影集）。
    expect(find.byType(LibraryAlbumCard), findsOneWidget);
    // 收藏轨瓦片来自 favoritePhotos。
    expect(find.byType(LibraryFavoritePhotoTile), findsOneWidget);

    // 切到音乐分段：专辑轨仍在，照片马赛克卸载。
    await tester.tap(find.text('音乐'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryAlbumCard), findsNWidgets(2));
    expect(find.byType(LibraryPhotoMosaic), findsNothing);
  });

  testWidgets('空媒体库展示分段与空态提示，不渲染横幅与轨', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackdropControllerProvider.overrideWith(
            _EmptyBackdropController.new,
          ),
          photoDashboardProvider.overrideWith(_EmptyPhotoDashboard.new),
          photoAlbumsProvider.overrideWith((ref) async => const <PhotoAlbum>[]),
          movieDashboardProvider.overrideWith(
            (ref) async => MovieDashboard(
              stats: MovieStats(
                movieCount: 0,
                episodeCount: 0,
                seriesCount: 0,
                scrapeFailedCount: 0,
              ),
              recentlyAdded: const <MovieVideoItem>[],
              continueWatching: const <MovieContinueWatching>[],
              series: const <MovieSeries>[],
            ),
          ),
          musicCenterControllerProvider.overrideWith(_EmptyMusicCenter.new),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const LibrarySpacePage(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibrarySegmentBar), findsOneWidget);
    expect(find.byType(LibraryFeatureBanner), findsNothing);
    expect(find.byType(LibraryPosterCard), findsNothing);
    expect(find.byType(LibraryAlbumCard), findsNothing);
    // 空态文案可见。
    expect(find.text('还没有照片'), findsOneWidget);
    expect(find.text('还没有可看的影片'), findsOneWidget);
    expect(find.text('曲库还没有内容'), findsOneWidget);
  });

  testWidgets('分段胶囊达 48 且吸顶带模糊，宽视口内容限宽 650', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackdropControllerProvider.overrideWith(
            _EmptyBackdropController.new,
          ),
          photoDashboardProvider.overrideWith(_FakePhotoDashboard.new),
          photoAlbumsProvider.overrideWith((ref) async => _albums),
          movieDashboardProvider.overrideWith((ref) async => _movieDashboard),
          musicCenterControllerProvider.overrideWith(
            _FakeLibraryMusicCenter.new,
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const LibrarySpacePage(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 分段是空间内主导航，按触控裁决不低于 48（稿子的次级 40 不适用）。
    final taps = find.descendant(
      of: find.byType(LibrarySegmentBar),
      matching: find.byType(InkWell),
    );
    expect(taps, findsNWidgets(4));
    for (final candidate in taps.evaluate()) {
      expect(
        tester.getSize(find.byWidget(candidate.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
    // 选中态是**单层滑动胶囊**，不再逐段各自换底色；媒体库分段与原生 PageView
    // 同轴，滑块按页码跟手，因此滑块层不是 AnimatedPositioned 而是 Positioned。
    expect(
      find.descendant(
        of: find.byType(LibrarySegmentBar),
        matching: find.byKey(segmentPillKey),
      ),
      findsOneWidget,
    );
    // 吸顶层带真实模糊，内容从其下方穿过。
    expect(
      find.ancestor(
        of: find.byType(LibrarySegmentBar),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    // 900 宽视口下内容仍限宽 650 居中（650 为含页边距的内容盒，
    // 平板页边距 24，故可视内容宽 602）。
    expect(
      tester.getSize(find.byType(LibraryPhotoMosaic)).width,
      650 - 2 * MobileLayoutTokens.tabletHorizontalPadding,
    );
  });

  testWidgets('1.6x 字号下分段与轨道不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackdropControllerProvider.overrideWith(
            _EmptyBackdropController.new,
          ),
          photoDashboardProvider.overrideWith(_FakePhotoDashboard.new),
          photoAlbumsProvider.overrideWith((ref) async => _albums),
          movieDashboardProvider.overrideWith((ref) async => _movieDashboard),
          musicCenterControllerProvider.overrideWith(
            _FakeLibraryMusicCenter.new,
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const LibrarySpacePage(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // 媒体库是分支里的唯一路由：没有返回阶梯时，一次侧滑就被引擎当成
  // 「无路由可退」直接结束 Activity。分段（PageView 页）不是路由，
  // 返回要先把它收敲回「全部」，才轮到离站回门户。
  testWidgets('托管媒体库侧滑：先回全部分段，再回门户', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/library',
      routes: [
        GoRoute(
          path: '/library',
          builder: (context, state) => const LibrarySpacePage(),
        ),
        GoRoute(
          path: '/portal',
          builder:
              (context, state) => const Scaffold(body: Text('portal-root')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackdropControllerProvider.overrideWith(
            _EmptyBackdropController.new,
          ),
          photoDashboardProvider.overrideWith(_FakePhotoDashboard.new),
          photoAlbumsProvider.overrideWith((ref) async => _albums),
          movieDashboardProvider.overrideWith((ref) async => _movieDashboard),
          musicCenterControllerProvider.overrideWith(
            _FakeLibraryMusicCenter.new,
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: OmniNestTheme.from(AppThemePalette.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          builder:
              (context, child) => MobileShellScope(hosted: true, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    LibrarySegment selectedSegment() =>
        tester
            .widget<LibrarySegmentBar>(find.byType(LibrarySegmentBar))
            .segment;

    // 点选「照片」段：分段是页内层级（PageView 页），不是路由。
    await tester.tap(
      find.descendant(
        of: find.byType(LibrarySegmentBar),
        matching: find.text('照片'),
      ),
    );
    await tester.pumpAndSettle();
    expect(selectedSegment(), isNot(LibrarySegment.all));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('portal-root'), findsNothing, reason: '一级分段不该离站');
    expect(selectedSegment(), LibrarySegment.all);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('portal-root'), findsOneWidget, reason: '已在根才离站');
    expect(tester.takeException(), isNull);
  });
}

const _albums = <PhotoAlbum>[
  PhotoAlbum(
    id: 'album-1',
    name: '西湖周末',
    description: '',
    photoCount: 24,
    createdAt: null,
    updatedAt: null,
    coverUrl: 'https://example.com/album.jpg',
  ),
];

PhotoDashboard get _photoDashboard => PhotoDashboard(
  totalPhotos: 130,
  totalAlbums: 1,
  totalFavorites: 1,
  recentPhotos: [
    PhotoItem(
      id: 'photo-1',
      fileNodeId: 'node-1',
      title: 'recent-1.jpg',
      format: 'JPEG',
      fileSize: 100,
      metadataStatus: 'READY',
      favorite: false,
      createdAt: DateTime(2026, 10, 1),
    ),
    PhotoItem(
      id: 'photo-2',
      fileNodeId: 'node-2',
      title: 'recent-2.jpg',
      format: 'JPEG',
      fileSize: 100,
      metadataStatus: 'READY',
      favorite: false,
      createdAt: DateTime(2026, 10, 1),
    ),
  ],
  favoritePhotos: [
    PhotoItem(
      id: 'fav-1',
      fileNodeId: 'node-3',
      title: 'fav-1.jpg',
      format: 'JPEG',
      fileSize: 100,
      metadataStatus: 'READY',
      favorite: true,
      createdAt: DateTime(2026, 9, 1),
    ),
  ],
);

MovieDashboard get _movieDashboard => MovieDashboard(
  stats: MovieStats(
    movieCount: 10,
    episodeCount: 0,
    seriesCount: 1,
    scrapeFailedCount: 0,
  ),
  recentlyAdded: const <MovieVideoItem>[],
  continueWatching: const <MovieContinueWatching>[
    MovieContinueWatching(
      id: 'video-1',
      title: '光圈',
      positionSeconds: 600,
      durationSeconds: 6000,
      progressPercent: 10,
    ),
    MovieContinueWatching(
      id: 'video-2',
      title: '寂静之刃',
      positionSeconds: 0,
      durationSeconds: 6360,
      progressPercent: 0,
    ),
  ],
  series: const <MovieSeries>[],
);

class _FakePhotoDashboard extends PhotoDashboardController {
  @override
  Future<PhotoDashboard> build() async => _photoDashboard;
}

class _EmptyPhotoDashboard extends PhotoDashboardController {
  @override
  Future<PhotoDashboard> build() async => PhotoDashboard.empty();
}

class _FakeLibraryMusicCenter extends MusicCenterController {
  @override
  Future<MusicCenterState> build() async => MusicCenterState(
    dashboard: MusicDashboard.empty(),
    tracks: const <MusicTrack>[],
    albums: const <MusicAlbum>[
      MusicAlbum(
        id: 'album-1',
        title: 'Evening Drift',
        artistName: 'Marconi Union',
        trackCount: 8,
      ),
      MusicAlbum(
        id: 'album-2',
        title: 'Soft Geometry',
        artistName: 'Lea Sen',
        trackCount: 6,
      ),
    ],
    artists: const <MusicArtist>[],
    playlists: const <MusicPlaylist>[],
  );
}

class _EmptyMusicCenter extends MusicCenterController {
  @override
  Future<MusicCenterState> build() async => MusicCenterState(
    dashboard: MusicDashboard.empty(),
    tracks: const <MusicTrack>[],
    albums: const <MusicAlbum>[],
    artists: const <MusicArtist>[],
    playlists: const <MusicPlaylist>[],
  );
}

class _EmptyBackdropController extends AppBackdropController {
  @override
  Future<AppBackdropState> build() async => const AppBackdropState();
}
