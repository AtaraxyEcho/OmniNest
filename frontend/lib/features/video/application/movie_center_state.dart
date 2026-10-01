import 'package:omninest/features/video/domain/movie_models.dart';

class SeasonKey {
  const SeasonKey({required this.seriesId, required this.seasonNumber});

  final String seriesId;
  final int seasonNumber;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeasonKey &&
          seriesId == other.seriesId &&
          seasonNumber == other.seasonNumber;

  @override
  int get hashCode => Object.hash(seriesId, seasonNumber);
}

enum MovieSection {
  movies,
  tvShows,
  anime,
  collections,
  recent,
  continueWatching,
  favorites,
  history,
  management,
}

enum MovieLibraryFilter { all, matched, pending, failed, recent }

enum MovieSortBy { dateAdded, releaseDate, rating, title }

enum MovieViewMode { grid, list }

class MovieCenterState {
  const MovieCenterState({
    required this.dashboard,
    required this.movies,
    this.tvSeries = const [],
    this.animeSeries = const [],
    required this.recentItems,
    required this.continueWatching,
    required this.favoriteItems,
    this.favoriteSeries = const [],
    this.favoriteSeriesPaging = const ListPaging(),
    this.favoritesPaging = const ListPaging(),
    this.historyPaging = const ListPaging(),
    this.tvSeriesPaging = const ListPaging(),
    this.animeSeriesPaging = const ListPaging(),
    required this.watchHistory,
    required this.collections,
    required this.tasks,
    this.section = MovieSection.movies,
    this.searchQuery = '',
    this.filter = MovieLibraryFilter.all,
    this.lastTask,
    this.selectedGenres = const {},
    this.yearFrom,
    this.yearTo,
    this.minRating,
    this.sortBy = MovieSortBy.dateAdded,
    this.sortAscending = false,
    this.viewMode = MovieViewMode.grid,
    this.moviePage = 0,
    this.movieHasMore = false,
    this.movieLoadingMore = false,
    this.episodePage = -1,
    this.episodeHasMore = true,
    this.episodeLoadingMore = false,
    this.loadedSections = const {MovieSection.movies},
    this.loadingSections = const {},
    this.errorMessage,
  });

  final MovieDashboard dashboard;
  final List<MovieVideoItem> movies;
  final List<MovieSeries> tvSeries;
  final List<MovieSeries> animeSeries;
  final List<MovieVideoItem> recentItems;
  final List<MovieContinueWatching> continueWatching;
  final List<MovieVideoItem> favoriteItems;
  final List<MovieSeries> favoriteSeries;

  /// 各列表滚动加载分页状态：page 为已加载末页（-1 表示未加载）。
  final ListPaging favoriteSeriesPaging;
  final ListPaging favoritesPaging;
  final ListPaging historyPaging;
  final ListPaging tvSeriesPaging;
  final ListPaging animeSeriesPaging;
  final List<MovieWatchHistory> watchHistory;
  final List<MovieCollection> collections;
  final List<MovieTask> tasks;
  final MovieSection section;
  final String searchQuery;
  final MovieLibraryFilter filter;
  final ScrapeTask? lastTask;
  final Set<String> selectedGenres;
  final int? yearFrom;
  final int? yearTo;
  final double? minRating;
  final MovieSortBy sortBy;
  final bool sortAscending;
  final MovieViewMode viewMode;
  final int moviePage;
  final bool movieHasMore;
  final bool movieLoadingMore;
  final int episodePage;
  final bool episodeHasMore;
  final bool episodeLoadingMore;
  final Set<MovieSection> loadedSections;
  final Set<MovieSection> loadingSections;
  final String? errorMessage;

  bool get hasFilters =>
      selectedGenres.isNotEmpty ||
      yearFrom != null ||
      yearTo != null ||
      minRating != null;

  Set<String> get availableGenres {
    if (section == MovieSection.anime) {
      return animeSeries.expand((s) => s.genres).toSet();
    }
    final source = switch (section) {
      MovieSection.movies => movies.where((item) => item.mediaType == 'MOVIE'),
      MovieSection.tvShows => movies.where((item) => item.mediaType != 'MOVIE'),
      _ => movies,
    };
    return source.expand((item) => item.genres).toSet();
  }

  Set<int> get availableYears {
    if (section == MovieSection.anime) {
      return animeSeries
          .map((s) => s.firstAirDate?.year)
          .whereType<int>()
          .toSet();
    }
    final source = switch (section) {
      MovieSection.movies => movies.where((item) => item.mediaType == 'MOVIE'),
      MovieSection.tvShows => movies.where((item) => item.mediaType != 'MOVIE'),
      _ => movies,
    };
    return source
        .map((item) => int.tryParse(item.year))
        .whereType<int>()
        .toSet();
  }

  List<MovieSeries> get filteredSeries => _filterAndSortSeries(tvSeries);

  List<MovieSeries> get filteredAnimeSeries =>
      _filterAndSortSeries(animeSeries);

  List<MovieSeries> _filterAndSortSeries(List<MovieSeries> source) {
    var result = source.toList();
    if (selectedGenres.isNotEmpty) {
      result =
          result.where((s) => s.genres.any(selectedGenres.contains)).toList();
    }
    if (yearFrom != null) {
      result =
          result.where((s) {
            final y = s.firstAirDate?.year;
            return y != null && y >= yearFrom!;
          }).toList();
    }
    if (yearTo != null) {
      result =
          result.where((s) {
            final y = s.firstAirDate?.year;
            return y != null && y <= yearTo!;
          }).toList();
    }
    result = switch (filter) {
      MovieLibraryFilter.all => result,
      MovieLibraryFilter.matched =>
        result.where((s) => s.metadataStatus == 'MATCHED').toList(),
      MovieLibraryFilter.pending =>
        result.where((s) => s.metadataStatus == 'PENDING').toList(),
      MovieLibraryFilter.failed =>
        result.where((s) => s.metadataStatus == 'FAILED').toList(),
      MovieLibraryFilter.recent => [...result]..sort((a, b) {
        final ad = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      }),
    };
    return _sortSeries(result);
  }

  List<MovieSeries> _sortSeries(List<MovieSeries> items) {
    final sorted = List<MovieSeries>.from(items);
    final sign = sortAscending ? 1 : -1;
    switch (sortBy) {
      case MovieSortBy.dateAdded:
        sorted.sort((a, b) {
          final aDate = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return sign * aDate.compareTo(bDate);
        });
      case MovieSortBy.releaseDate:
        sorted.sort((a, b) {
          final aDate =
              a.firstAirDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate =
              b.firstAirDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          return sign * aDate.compareTo(bDate);
        });
      case MovieSortBy.rating:
        sorted.sort(
          (a, b) => sign * ((a.rating ?? 0).compareTo(b.rating ?? 0)),
        );
      case MovieSortBy.title:
        sorted.sort(
          (a, b) =>
              sign * a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return sorted;
  }

  List<MovieVideoItem> get filteredMovies {
    final query = searchQuery.trim().toLowerCase();
    final source = switch (section) {
      MovieSection.movies =>
        movies.where((item) => item.mediaType == 'MOVIE').toList(),
      MovieSection.tvShows =>
        movies.where((item) {
          if (item.mediaType == 'MOVIE') return false;
          if (item.seriesId == null) return true;
          return !animeSeries.any((s) => s.id == item.seriesId);
        }).toList(),
      MovieSection.anime =>
        movies.where((item) {
          if (item.mediaType != 'EPISODE' || item.seriesId == null) {
            return false;
          }
          return animeSeries.any((s) => s.id == item.seriesId);
        }).toList(),
      MovieSection.recent => recentItems,
      MovieSection.favorites => favoriteItems,
      // 影片管理展示全部条目（电影 + 剧集/动漫分集）。
      MovieSection.management => movies,
      _ => movies,
    };
    var filtered = switch (filter) {
      MovieLibraryFilter.all => source,
      MovieLibraryFilter.matched =>
        source.where((item) => item.metadataStatus == 'MATCHED').toList(),
      MovieLibraryFilter.pending =>
        source.where((item) => item.metadataStatus == 'PENDING').toList(),
      MovieLibraryFilter.failed =>
        source.where((item) => item.metadataStatus == 'FAILED').toList(),
      MovieLibraryFilter.recent => recentItems,
    };
    // 类型筛选
    if (selectedGenres.isNotEmpty) {
      filtered =
          filtered
              .where((item) => item.genres.any(selectedGenres.contains))
              .toList();
    }
    // 年份筛选
    if (yearFrom != null) {
      filtered =
          filtered.where((item) {
            final y = int.tryParse(item.year);
            return y != null && y >= yearFrom!;
          }).toList();
    }
    if (yearTo != null) {
      filtered =
          filtered.where((item) {
            final y = int.tryParse(item.year);
            return y != null && y <= yearTo!;
          }).toList();
    }
    // 评分筛选
    if (minRating != null) {
      filtered =
          filtered.where((item) => (item.rating ?? 0) >= minRating!).toList();
    }
    // 排序
    filtered = _sortItems(filtered);
    if (query.isEmpty) {
      return filtered;
    }
    return filtered
        .where(
          (item) =>
              item.title.toLowerCase().contains(query) ||
              (item.originalTitle ?? '').toLowerCase().contains(query) ||
              item.mediaType.toLowerCase().contains(query) ||
              item.year.toLowerCase().contains(query),
        )
        .toList();
  }

  List<MovieVideoItem> _sortItems(List<MovieVideoItem> items) {
    final sorted = List<MovieVideoItem>.from(items);
    final sign = sortAscending ? 1 : -1;
    switch (sortBy) {
      case MovieSortBy.dateAdded:
        sorted.sort((a, b) {
          final aDate = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return sign * aDate.compareTo(bDate);
        });
      case MovieSortBy.releaseDate:
        sorted.sort((a, b) {
          final aDate = a.releaseDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.releaseDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          return sign * aDate.compareTo(bDate);
        });
      case MovieSortBy.rating:
        sorted.sort(
          (a, b) => sign * ((a.rating ?? 0).compareTo(b.rating ?? 0)),
        );
      case MovieSortBy.title:
        sorted.sort(
          (a, b) =>
              sign * a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return sorted;
  }

  MovieCenterState copyWith({
    MovieDashboard? dashboard,
    List<MovieVideoItem>? movies,
    List<MovieSeries>? tvSeries,
    List<MovieSeries>? animeSeries,
    List<MovieVideoItem>? recentItems,
    List<MovieContinueWatching>? continueWatching,
    List<MovieVideoItem>? favoriteItems,
    List<MovieSeries>? favoriteSeries,
    ListPaging? favoriteSeriesPaging,
    ListPaging? favoritesPaging,
    ListPaging? historyPaging,
    ListPaging? tvSeriesPaging,
    ListPaging? animeSeriesPaging,
    List<MovieWatchHistory>? watchHistory,
    List<MovieCollection>? collections,
    List<MovieTask>? tasks,
    MovieSection? section,
    String? searchQuery,
    MovieLibraryFilter? filter,
    ScrapeTask? lastTask,
    Set<String>? selectedGenres,
    int? yearFrom,
    int? yearTo,
    double? minRating,
    bool clearYearFrom = false,
    bool clearYearTo = false,
    bool clearMinRating = false,
    MovieSortBy? sortBy,
    bool? sortAscending,
    MovieViewMode? viewMode,
    int? moviePage,
    bool? movieHasMore,
    bool? movieLoadingMore,
    int? episodePage,
    bool? episodeHasMore,
    bool? episodeLoadingMore,
    Set<MovieSection>? loadedSections,
    Set<MovieSection>? loadingSections,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MovieCenterState(
      dashboard: dashboard ?? this.dashboard,
      movies: movies ?? this.movies,
      tvSeries: tvSeries ?? this.tvSeries,
      animeSeries: animeSeries ?? this.animeSeries,
      recentItems: recentItems ?? this.recentItems,
      continueWatching: continueWatching ?? this.continueWatching,
      favoriteItems: favoriteItems ?? this.favoriteItems,
      favoriteSeries: favoriteSeries ?? this.favoriteSeries,
      favoriteSeriesPaging: favoriteSeriesPaging ?? this.favoriteSeriesPaging,
      favoritesPaging: favoritesPaging ?? this.favoritesPaging,
      historyPaging: historyPaging ?? this.historyPaging,
      tvSeriesPaging: tvSeriesPaging ?? this.tvSeriesPaging,
      animeSeriesPaging: animeSeriesPaging ?? this.animeSeriesPaging,
      watchHistory: watchHistory ?? this.watchHistory,
      collections: collections ?? this.collections,
      tasks: tasks ?? this.tasks,
      section: section ?? this.section,
      searchQuery: searchQuery ?? this.searchQuery,
      filter: filter ?? this.filter,
      lastTask: lastTask ?? this.lastTask,
      selectedGenres: selectedGenres ?? this.selectedGenres,
      yearFrom: clearYearFrom ? null : (yearFrom ?? this.yearFrom),
      yearTo: clearYearTo ? null : (yearTo ?? this.yearTo),
      minRating: clearMinRating ? null : (minRating ?? this.minRating),
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
      viewMode: viewMode ?? this.viewMode,
      moviePage: moviePage ?? this.moviePage,
      movieHasMore: movieHasMore ?? this.movieHasMore,
      movieLoadingMore: movieLoadingMore ?? this.movieLoadingMore,
      episodePage: episodePage ?? this.episodePage,
      episodeHasMore: episodeHasMore ?? this.episodeHasMore,
      episodeLoadingMore: episodeLoadingMore ?? this.episodeLoadingMore,
      loadedSections: loadedSections ?? this.loadedSections,
      loadingSections: loadingSections ?? this.loadingSections,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 列表滚动加载分页状态：page 记录已加载末页，-1 表示尚未加载。
class ListPaging {
  const ListPaging({
    this.page = -1,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  final int page;
  final bool hasMore;
  final bool isLoadingMore;

  ListPaging copyWith({int? page, bool? hasMore, bool? isLoadingMore}) {
    return ListPaging(
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}
