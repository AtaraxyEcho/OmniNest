import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_series_detail_page.dart';
import 'package:omninest/features/video/video_dashboard.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final series = MovieSeries(
    id: 's-1',
    title: 'The Quiet Coast',
    metadataStatus: 'MATCHED',
    metadata: const {},
    firstAirDate: DateTime(2024),
    overview: 'A coast guard traces a summer of missing lights.',
    seriesType: 'SERIES',
    rating: 8.1,
    genres: const ['Drama'],
  );
  final detail = MovieSeriesDetail(
    series: series,
    seasons: const [],
    cast: const [],
    crew: const [],
  );

  Future<void> pumpSeries(WidgetTester tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          movieSeriesDetailProvider.overrideWith((ref, id) async => detail),
          seriesFavoriteProvider.overrideWith((ref, id) async => false),
        ],
        child: wrapDesktop(const DesktopSeriesDetailPage(seriesId: 's-1')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('剧集详情在内容区渲染圆角英雄区与四个分页', (tester) async {
    await pumpSeries(tester);

    expect(find.text('The Quiet Coast'), findsWidgets);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Episodes'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Subtitles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('剧集编辑抽屉提供与样例一致的手填字段', (tester) async {
    await pumpSeries(tester);

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
      expect(find.text(label), findsWidgets, reason: label);
    }
  });
}
