import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_movie_detail_page.dart';
import 'package:omninest/features/video/video_dashboard.dart';

import 'desktop_test_harness.dart';

/// 记录详情页动作是否真的打到后端入口。
class _FakeDetailActions implements MovieDetailBackendActions {
  final List<String> calls = <String>[];

  @override
  Future<void> reprobe(String videoItemId) async {
    calls.add('probe:$videoItemId');
  }

  @override
  Future<NfoExport> exportNfo(String videoItemId) async {
    calls.add('nfo:$videoItemId');
    return NfoExport(
      videoItemId: videoItemId,
      status: 'EXPORTED',
      exportPath: '/media/Aperture.nfo',
      content: '<movie />',
    );
  }

  @override
  Future<ScrapeTask> matchCandidate({
    required String fileNodeId,
    required String provider,
    required String externalId,
  }) async {
    calls.add('match:$fileNodeId:$provider:$externalId');
    return const ScrapeTask(
      taskId: 't-1',
      status: 'QUEUED',
      message: '刮削任务已进入队列',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final subtitle = SubtitleTrack(
    id: 'sub-1',
    language: 'zh',
    label: '简体中文',
    kind: 'SRT',
    embedded: false,
  );

  Future<void> pumpDetail(
    WidgetTester tester, {
    MovieWatchHistory? history,
    MovieVideoItem item = seededMovie,
    _FakeDetailActions? actions,
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          movieDetailProvider.overrideWith((ref, id) async => item),
          movieSubtitlesProvider.overrideWith(
            (ref, id) async => <SubtitleTrack>[subtitle],
          ),
          movieItemHistoryProvider.overrideWith((ref, id) async => history),
          videoFavoriteStatusProvider.overrideWith((ref, id) async => true),
          if (actions != null)
            movieDetailBackendActionsProvider.overrideWithValue(actions),
          ...extraOverrides,
        ],
        child: wrapDesktop(const DesktopMovieDetailPage(videoItemId: 'v-1')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('英雄区读出标题、评级与完播状态', (tester) async {
    await pumpDetail(tester);

    expect(find.text('Aperture'), findsWidgets);
    expect(find.text('★ 8.4'), findsWidgets);
    expect(find.textContaining('1h 46m'), findsWidgets);
    // 已收藏状态来自 videoFavoriteStatusProvider；原型是纯图标心形。
    expect(find.byTooltip('Favorite'), findsWidgets);
  });

  testWidgets('有观看进度时按钮变续播并展示进度条', (tester) async {
    await pumpDetail(
      tester,
      history: const MovieWatchHistory(
        id: 'h-1',
        videoItemId: 'v-1',
        title: 'Aperture',
        positionSeconds: 2280,
        durationSeconds: 6360,
        completed: false,
      ),
    );

    expect(find.text('Resume'), findsOneWidget);
    expect(find.textContaining('36%'), findsWidgets);
  });

  testWidgets('概览页给简介，字幕页列出轨与内外挂标记', (tester) async {
    await pumpDetail(tester);

    expect(find.textContaining('photographer returns'), findsWidgets);

    await tester.tap(find.text('Subtitles').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('简体中文'), findsOneWidget);
    expect(find.textContaining('External'), findsOneWidget);
    expect(find.text('UPLOAD SUBTITLE'), findsOneWidget);
    expect(find.byTooltip('Delete subtitle'), findsOneWidget);
  });

  testWidgets('概览页动作行四个按钮都在，且探测与 NFO 走应用层入口', (tester) async {
    final actions = _FakeDetailActions();
    await pumpDetail(tester, actions: actions);

    expect(find.text('Edit details'), findsOneWidget);
    expect(find.text('Re-match metadata'), findsOneWidget);
    expect(find.text('Re-probe'), findsOneWidget);
    expect(find.text('Export NFO'), findsOneWidget);

    // 动作行在概览内容下方，桌面 1000 高视口里默认在折叠线以下。
    await tester.ensureVisible(find.text('Re-probe'));
    await tester.pump();

    await tester.tap(find.text('Re-probe'));
    await tester.pump();
    expect(actions.calls, contains('probe:v-1'));

    await tester.ensureVisible(find.text('Export NFO'));
    await tester.pump();
    await tester.tap(find.text('Export NFO'));
    await tester.pump();
    expect(actions.calls, contains('nfo:v-1'));
  });

  testWidgets('短简介不显示阅读更多', (tester) async {
    await pumpDetail(tester);
    expect(find.text('Read more'), findsNothing);
  });

  testWidgets('超长简介才给展开入口并可收起', (tester) async {
    final longItem = MovieVideoItem(
      id: 'v-1',
      fileNodeId: 'f-1',
      movieId: 'm-1',
      mediaType: 'MOVIE',
      title: 'Aperture',
      metadataStatus: 'MATCHED',
      nfoStatus: 'PRESENT',
      updatedAt: null,
      metadata: const {},
      posterUrl: 'https://example.test/aperture-poster.jpg',
      overview: List<String>.filled(
        8,
        'A long line of synopsis text.',
      ).join(' '),
    );
    await pumpDetail(tester, item: longItem);
    expect(
      find.textContaining('A long line of synopsis text.'),
      findsOneWidget,
    );
    expect(find.text('Read more'), findsOneWidget);

    await tester.tap(find.text('Read more'));
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('未刮削条目显示徽章且匹配按钮为首次匹配文案', (tester) async {
    await pumpDetail(
      tester,
      item: const MovieVideoItem(
        id: 'v-1',
        fileNodeId: 'f-1',
        mediaType: 'MOVIE',
        title: 'Aperture',
        metadataStatus: 'PENDING',
        nfoStatus: 'MISSING',
        updatedAt: null,
        metadata: {},
        posterUrl: 'https://example.test/aperture-poster.jpg',
        backdropUrl: 'https://example.test/aperture-backdrop.jpg',
      ),
    );

    expect(find.text('Not scraped'), findsOneWidget);
    expect(find.text('Match metadata'), findsOneWidget);
    expect(find.text('Re-match metadata'), findsNothing);
  });

  testWidgets('匹配弹窗列出候选，选中后按该条目创建刮削任务', (tester) async {
    final actions = _FakeDetailActions();
    await pumpDetail(
      tester,
      actions: actions,
      extraOverrides: [
        movieScrapeCandidatesProvider.overrideWith(
          (ref, fileNodeId) async => const [
            VideoScrapeCandidate(
              provider: 'TMDB',
              externalId: '27205',
              title: 'Inception',
              year: 2010,
              voteAverage: 8.4,
            ),
          ],
        ),
      ],
    );

    await tester.ensureVisible(find.text('Re-match metadata'));
    await tester.pump();
    await tester.tap(find.text('Re-match metadata'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Choose the right match'), findsOneWidget);
    expect(find.text('Inception'), findsOneWidget);

    await tester.tap(find.text('Inception'));
    await tester.pump();

    expect(actions.calls, contains('match:f-1:TMDB:27205'));
  });

  testWidgets('编辑详情弹窗用条目当前值预填标题', (tester) async {
    await pumpDetail(tester);

    await tester.ensureVisible(find.text('Edit details'));
    await tester.pump();
    await tester.tap(find.text('Edit details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Genre'), findsOneWidget);
    expect(find.text('Aperture'), findsWidgets);
  });

  testWidgets('编辑抽屉给影片完整八个字段，未刮削条目不退化成单集表单', (tester) async {
    await pumpDetail(
      tester,
      item: const MovieVideoItem(
        id: 'v-1',
        fileNodeId: 'f-1',
        mediaType: 'MOVIE',
        title: 'Aperture',
        metadataStatus: 'PENDING',
        nfoStatus: 'MISSING',
        updatedAt: null,
        metadata: {},
        posterUrl: 'https://example.test/aperture-poster.jpg',
      ),
    );

    await tester.ensureVisible(find.text('Edit details'));
    await tester.pump();
    await tester.tap(find.text('Edit details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    for (final label in const <String>[
      'Title',
      'Genre',
      'Year',
      'Runtime',
      'Rating',
      'Cast',
      'Poster image URL',
      'Synopsis',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}
