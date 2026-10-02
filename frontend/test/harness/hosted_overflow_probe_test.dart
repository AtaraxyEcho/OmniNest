// 溢出探针：hosted 模块页在 390 逻辑宽 + textScale 1.3 下整页布局，
// 任何 RenderFlex 溢出都会以异常形式令测试失败。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_shell.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_page.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';

const _caps = UserCapabilities(
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

class _FakeNotificationController extends NotificationController {
  @override
  NotificationState build() => NotificationState(
    items: [
      for (var i = 0; i < 6; i++)
        NotificationDto(
          id: 'n-$i',
          type: 'SYSTEM_MESSAGE',
          title: '42 张照片加入了金色黄昏以及一个很长的标题场景',
          message: '今晚上传的照片已完成导入，附带较长的正文以验证多行省略。',
          read: i.isEven,
          createdAt: DateTime.now().subtract(Duration(minutes: 5 * (i + 1))),
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

class _FakeUnread extends UnreadCountNotifier {
  @override
  int build() => 3;
}

class _FakeMusicCenter extends MusicCenterController {
  @override
  Future<MusicCenterState> build() async {
    final tracks = [
      for (var i = 0; i < 5; i++)
        MusicTrack(
          id: 't$i',
          fileNodeId: 't$i',
          title: 'Weightless with a fairly long title $i',
          artistName: 'Marconi Union',
          albumTitle: 'Evening Drift',
          format: 'AUDIO',
          favorite: false,
          durationSeconds: 402,
        ),
    ];
    final playables = [
      for (final track in tracks) MusicPlayableItem.local(track),
    ];
    return MusicCenterState(
      dashboard: MusicDashboard.empty(),
      tracks: tracks,
      albums: const [
        MusicAlbum(
          id: 'a1',
          title: 'Evening Drift',
          artistName: 'Ambient mix',
          trackCount: 42,
        ),
      ],
      artists: const [],
      playlists: const [],
      recentItems: playables,
      currentItem: playables.first,
      playbackItems: playables,
      playbackIndex: 0,
    );
  }
}

class _FakePhotoCenter extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async {
    final photos = [
      for (var i = 0; i < 6; i++)
        PhotoItem(
          id: 'p$i',
          fileNodeId: 'p$i',
          title: 'West Lake dusk with long descriptive title $i',
          format: 'IMAGE',
          fileSize: 2400000,
          metadataStatus: 'READY',
          favorite: i < 2,
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
    ];
    return PhotoCenterState(
      dashboard: PhotoDashboard.empty(),
      photos: photos,
      favorites: photos.take(2).toList(growable: false),
      albums: [
        PhotoAlbum(
          id: 'al1',
          name: '金色黄昏',
          description: '',
          photoCount: 18,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      tab: PhotoTab.all,
      photoTotalElements: 126,
    );
  }
}

class _FakeMovieCenter extends MovieCenterController {
  @override
  Future<MovieCenterState> build() async {
    final films = [
      for (var i = 0; i < 4; i++)
        MovieVideoItem(
          id: 'v$i',
          fileNodeId: 'v$i',
          mediaType: 'MOVIE',
          title: 'Aperture with a long cinematic title $i',
          metadataStatus: 'READY',
          nfoStatus: 'NONE',
          updatedAt: DateTime.now(),
          metadata: const <String, dynamic>{},
          runtimeSeconds: 6360,
          rating: 8.7,
          genres: const ['Sci-Fi'],
        ),
    ];
    final continueWatching = [
      for (final (index, item) in films.indexed)
        MovieContinueWatching(
          id: item.id,
          title: item.title,
          positionSeconds: 1800 + index * 300,
          durationSeconds: 6360,
          progressPercent: 0.28 + index * 0.1,
          updatedAt: DateTime.now(),
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

Widget _host(Widget child) {
  return ProviderScope(
    overrides: [
      authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
      userCapabilitiesProvider.overrideWithValue(_caps),
      notificationControllerProvider.overrideWith(
        () => _FakeNotificationController(),
      ),
      unreadCountProvider.overrideWith(() => _FakeUnread()),
      musicCenterControllerProvider.overrideWith(() => _FakeMusicCenter()),
      photoCenterControllerProvider.overrideWith(() => _FakePhotoCenter()),
      movieCenterControllerProvider.overrideWith(() => _FakeMovieCenter()),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      builder: (context, child) {
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder:
                (context, state) => MobileShellScope(
                  hosted: true,
                  child: Scaffold(
                    backgroundColor: const Color(0xFF0B1110),
                    body: child,
                  ),
                ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  const pages = <String, Widget>{
    'notification': NotificationPage(),
    'music': MusicDeckShell(),
    'photos': PhotosPage(),
    'video': MovieCenterPage(),
  };
  for (final entry in pages.entries) {
    testWidgets('${entry.key} hosted 页 390 宽 + 1.3 倍字号无溢出', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(entry.value));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });
  }
}
