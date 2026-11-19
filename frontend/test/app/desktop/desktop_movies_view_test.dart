import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_movies_page.dart';
import 'package:omninest/features/video/video_dashboard.dart';

import 'desktop_test_harness.dart';

/// 收藏与历史来自影视中心状态；只覆盖 build，动作仍用真实实现。
class _SeededMovieCenter extends MovieCenterController {
  _SeededMovieCenter(this.seed);

  final MovieCenterState seed;

  @override
  Future<MovieCenterState> build() async => seed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMovies(
    WidgetTester tester, {
    bool empty = false,
    DesktopMoviesTab tab = DesktopMoviesTab.forYou,
    List<Override> extra = const <Override>[],
  }) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final overrides = desktopSeedOverrides(empty: empty);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides, ...extra],
        child: wrapDesktop(DesktopMoviesPage(initialTab: tab)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('影院轮播、分页、排序与轨道都读真实门面数据', (tester) async {
    await pumpMovies(tester);

    // 影院首帧：眉标、衬线片名、元信息与两个动作。分辨率徽标随源字段
    // 回落到编码名，种子没有 resolutionWidth，这里不锁它的具体文案。
    // 原型 `Movies.tsx:52`：有进度时眉标换成 Continue · N% · N min left。
    expect(find.textContaining('CONTINUE WATCHING · 36%'), findsWidgets);
    expect(find.text('Aperture'), findsWidgets);
    expect(find.textContaining('★ 8.4'), findsWidgets);
    expect(find.text('Resume'), findsWidgets);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('HD'), findsWidgets);

    // 页头计数来自 stats/continueWatching，而不是写死。
    expect(find.textContaining('128 TITLES'), findsOneWidget);

    // 分页与排序。
    expect(find.text('For you'), findsWidgets);
    expect(find.text('Continue watching'), findsWidgets);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);

    // 继续观看轨道：进度百分比来自真实进度。
    expect(find.textContaining('36%'), findsWidgets);
  });

  testWidgets('切到影视分页后只留海报网格', (tester) async {
    await pumpMovies(tester, tab: DesktopMoviesTab.movies);

    expect(find.text('Aperture'), findsWidgets);
    // 样例 Seg 没有 Continue watching 这一档，切换分档后该文案只属于 For you。
    expect(find.text('Continue watching'), findsNothing);
  });

  testWidgets('收藏分页读影视中心的收藏列表', (tester) async {
    await pumpMovies(
      tester,
      tab: DesktopMoviesTab.favorites,
      extra: [
        movieCenterControllerProvider.overrideWith(
          () => _SeededMovieCenter(
            MovieCenterState(
              dashboard: seededMovieDashboard,
              movies: const [],
              recentItems: const [],
              continueWatching: const [],
              favoriteItems: [seededMovie],
              watchHistory: const [],
              collections: const [],
              tasks: const [],
            ),
          ),
        ),
      ],
    );

    expect(find.text('Aperture'), findsWidgets);
  });

  testWidgets('历史分页给出上次观看与进度', (tester) async {
    await pumpMovies(
      tester,
      tab: DesktopMoviesTab.history,
      extra: [
        movieCenterControllerProvider.overrideWith(
          () => _SeededMovieCenter(
            MovieCenterState(
              dashboard: seededMovieDashboard,
              movies: const [],
              recentItems: const [],
              continueWatching: const [],
              favoriteItems: const [],
              watchHistory: [
                MovieWatchHistory(
                  id: 'h-1',
                  videoItemId: 'v-1',
                  title: 'Aperture',
                  positionSeconds: 2280,
                  durationSeconds: 6360,
                  completed: false,
                  playedAt: DateTime(2026, 11, 14, 9, 30),
                ),
              ],
              collections: const [],
              tasks: const [],
            ),
          ),
        ),
      ],
    );

    expect(find.text('Aperture'), findsWidgets);
    expect(find.textContaining('36%'), findsWidgets);
  });

  testWidgets('空库时落到空态而不是空白页', (tester) async {
    await pumpMovies(tester, empty: true, tab: DesktopMoviesTab.movies);

    expect(find.text('Nothing to watch yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('查询参数映射到桌面分页', () {
    expect(desktopMoviesTabFromSection('history'), DesktopMoviesTab.history);
    expect(
      desktopMoviesTabFromSection('favorites'),
      DesktopMoviesTab.favorites,
    );
    expect(
      desktopMoviesTabFromSection('watchlist'),
      DesktopMoviesTab.watchlist,
    );
    expect(desktopMoviesTabFromSection('series'), DesktopMoviesTab.series);
    expect(desktopMoviesTabFromSection('anime'), DesktopMoviesTab.anime);
    expect(desktopMoviesTabFromSection('library'), DesktopMoviesTab.movies);
    expect(desktopMoviesTabFromSection(null), DesktopMoviesTab.forYou);
  });

  test('Seg 档位与样例七档一致，不含 Continue watching', () {
    expect(desktopMoviesSegTabs, <DesktopMoviesTab>[
      DesktopMoviesTab.forYou,
      DesktopMoviesTab.movies,
      DesktopMoviesTab.series,
      DesktopMoviesTab.anime,
      DesktopMoviesTab.favorites,
      DesktopMoviesTab.watchlist,
      DesktopMoviesTab.history,
    ]);
  });

  testWidgets('待看清单分档有独立空态', (tester) async {
    await pumpMovies(tester, tab: DesktopMoviesTab.watchlist);

    expect(find.text('Watchlist'), findsWidgets);
    expect(find.text('Your watchlist is empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
