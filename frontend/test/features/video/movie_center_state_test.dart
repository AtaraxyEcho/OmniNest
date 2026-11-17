import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

void main() {
  test('影视中心状态组合类型年份评分筛选并按标题排序', () {
    final state = _state(
      movies: [
        _movie(
          id: 'older',
          title: 'Beta',
          year: 2023,
          rating: 8.5,
          genres: const ['剧情'],
        ),
        _movie(
          id: 'match',
          title: 'Alpha',
          year: 2024,
          rating: 9.1,
          genres: const ['科幻', '剧情'],
        ),
        _movie(
          id: 'low-rating',
          title: 'Gamma',
          year: 2024,
          rating: 6.0,
          genres: const ['科幻'],
        ),
      ],
    ).copyWith(
      selectedGenres: const {'科幻'},
      yearFrom: 2024,
      minRating: 8,
      sortBy: MovieSortBy.title,
      sortAscending: true,
    );

    expect(state.availableGenres, {'剧情', '科幻'});
    expect(state.filteredMovies.map((item) => item.id), ['match']);
  });

  test('copyWith 显式清空可空筛选条件', () {
    final state = _state(
      movies: const [],
    ).copyWith(yearFrom: 2020, yearTo: 2025, minRating: 7.5);

    final cleared = state.copyWith(
      clearYearFrom: true,
      clearYearTo: true,
      clearMinRating: true,
    );

    expect(cleared.yearFrom, isNull);
    expect(cleared.yearTo, isNull);
    expect(cleared.minRating, isNull);
  });
}

MovieCenterState _state({required List<MovieVideoItem> movies}) {
  return MovieCenterState(
    dashboard: MovieDashboard.empty(),
    movies: movies,
    recentItems: const [],
    continueWatching: const [],
    favoriteItems: const [],
    watchHistory: const [],
    collections: const [],
    tasks: const [],
  );
}

MovieVideoItem _movie({
  required String id,
  required String title,
  required int year,
  required double rating,
  required List<String> genres,
}) {
  return MovieVideoItem(
    id: id,
    fileNodeId: 'file-$id',
    mediaType: 'MOVIE',
    title: title,
    metadataStatus: 'MATCHED',
    nfoStatus: 'DISABLED',
    updatedAt: DateTime(2026, 7, 22),
    metadata: {'year': year},
    releaseDate: DateTime(year),
    rating: rating,
    genres: genres,
  );
}
