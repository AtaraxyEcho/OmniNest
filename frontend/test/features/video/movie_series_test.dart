import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_category_bars.dart';
import 'package:omninest/features/video/presentation/widgets/movie_series.dart';

void main() {
  testWidgets('空剧集轮播在紧凑视口稳定显示占位内容', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: OmniNestTheme.from(AppThemePalette.dark),
        home: const Scaffold(
          body: SizedBox(width: 390, child: SeriesHeroCarousel(items: [])),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SeriesHeroCarousel), findsOneWidget);
  });

  testWidgets('影视分类栏生成类型分组并回传查看全部选择', (tester) async {
    String? selectedGenre;
    final items = <MovieVideoItem>[
      _movie('movie-1', '影片一', rating: 8.8),
      _movie('movie-2', '影片二', rating: 8.5),
      _movie('movie-3', '影片三', rating: 8.2),
    ];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: OmniNestTheme.from(AppThemePalette.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MovieCategoryBars(
              items: items,
              viewMode: MovieViewMode.list,
              onViewMore: (genre) => selectedGenre = genre,
            ),
          ),
        ),
      ),
    );

    expect(find.text('剧情'), findsOneWidget);
    expect(find.text('影片一'), findsWidgets);
    final viewMore = find.text(
      AppLocalizations.of(
        tester.element(find.byType(MovieCategoryBars)),
      ).videoViewMore,
    );
    expect(viewMore, findsOneWidget);

    await tester.ensureVisible(viewMore);
    await tester.pumpAndSettle();
    await tester.tap(viewMore);
    await tester.pump();

    expect(selectedGenre, '剧情');
    expect(tester.takeException(), isNull);
  });
}

MovieVideoItem _movie(String id, String title, {required double rating}) {
  return MovieVideoItem(
    id: id,
    fileNodeId: 'file-$id',
    mediaType: 'MOVIE',
    title: title,
    metadataStatus: 'MATCHED',
    nfoStatus: 'NONE',
    updatedAt: DateTime.utc(2026, 7, 1),
    releaseDate: DateTime.utc(2026, 6, 1),
    metadata: const <String, dynamic>{},
    genres: const <String>['剧情'],
    runtimeSeconds: 7200,
    rating: rating,
  );
}
