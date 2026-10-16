// 托管影视分区页的水平留白回归：样例 `.module-overlay > main` 内衬为
// 8px 20px 0（Refine Light Mode Design/src/index.css:490），四档分段条与
// 档内排序胶囊行都必须坐在这 20dp 里。
//
// 桩的容器用真实入口（MobileHostedRoute + MovieCenterPage + 托管态 sliver），
// 不外包 Padding：被测缺陷正是「页面没有给这条行补左右内缩」，
// 测试侧一旦补上 20 内衬就把它盖住了。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_mobile_chips.dart';

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

class _FakeMovieCenter extends MovieCenterController {
  @override
  Future<MovieCenterState> build() async {
    final films = [
      for (var i = 0; i < 4; i++)
        MovieVideoItem(
          id: 'v$i',
          fileNodeId: 'v$i',
          mediaType: 'MOVIE',
          title: 'Aperture $i',
          metadataStatus: 'READY',
          nfoStatus: 'NONE',
          updatedAt: DateTime.now(),
          metadata: const <String, dynamic>{},
          runtimeSeconds: 6360,
          rating: 8.7,
          genres: const ['Sci-Fi'],
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
        continueWatching: const [],
        series: const [],
      ),
      movies: films,
      recentItems: films,
      continueWatching: const [],
      favoriteItems: films.take(2).toList(growable: false),
      watchHistory: const [],
      collections: const [],
      tasks: const [],
      // 直接落在电影档：档内首行就是排序胶囊行。
      section: MovieSection.movies,
    );
  }

  @override
  Future<void> refresh() async {}
}

Future<void> _pumpHostedFilms(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        userCapabilitiesProvider.overrideWithValue(_caps),
        movieCenterControllerProvider.overrideWith(() => _FakeMovieCenter()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: OmniNestTheme.dark(),
        home: MobileHostedRoute(child: MovieCenterPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('电影档排序胶囊行留在 20dp 页边距内', (tester) async {
    await _pumpHostedFilms(tester);

    final chips = find.byType(MovieRedesignMobileChips);
    expect(chips, findsOneWidget);
    final rect = tester.getRect(chips);
    expect(rect.left, 20, reason: '首枚胶囊不得贴住屏幕左缘（样例 main 内衬 20）');
    expect(rect.right, 370, reason: '尾部状态筛选钮不得贴住屏幕右缘（390 - 20）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('四档分段条同样坐在 20dp 内缩里且不出界', (tester) async {
    await _pumpHostedFilms(tester);

    final bar = find.byType(MobileSegmentedControl<MovieSection>);
    expect(bar, findsOneWidget);
    final rect = tester.getRect(bar);
    expect(rect.left, 20);
    expect(rect.right, lessThanOrEqualTo(370));
    expect(tester.takeException(), isNull);
  });
}
