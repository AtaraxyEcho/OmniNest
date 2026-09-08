import 'package:omninest/features/video/domain/movie_model_json.dart';

class MovieStats {
  const MovieStats({
    required this.movieCount,
    required this.episodeCount,
    required this.seriesCount,
    required this.scrapeFailedCount,
    this.favoritesCount = 0,
    this.historyCount = 0,
    this.collectionsCount = 0,
    this.continueWatchingCount = 0,
  });

  final int movieCount;
  final int episodeCount;
  final int seriesCount;
  final int scrapeFailedCount;
  final int favoritesCount;
  final int historyCount;
  final int collectionsCount;
  final int continueWatchingCount;

  factory MovieStats.fromJson(Map<String, dynamic> json) {
    return MovieStats(
      movieCount: MovieJson.asInt(json['movieCount']),
      episodeCount: MovieJson.asInt(json['episodeCount']),
      seriesCount: MovieJson.asInt(json['seriesCount']),
      scrapeFailedCount: MovieJson.asInt(json['scrapeFailedCount']),
      favoritesCount: MovieJson.asInt(json['favoritesCount']),
      historyCount: MovieJson.asInt(json['historyCount']),
      collectionsCount: MovieJson.asInt(json['collectionsCount']),
      continueWatchingCount: MovieJson.asInt(json['continueWatchingCount']),
    );
  }
}

class MovieVideoItem {
  const MovieVideoItem({
    required this.id,
    required this.fileNodeId,
    required this.mediaType,
    required this.title,
    required this.metadataStatus,
    required this.nfoStatus,
    required this.updatedAt,
    required this.metadata,
    this.originalTitle,
    this.releaseDate,
    this.overview,
    this.posterFileId,
    this.backdropFileId,
    this.posterUrl,
    this.backdropUrl,
    this.assets = const {},
    this.runtimeSeconds,
    this.genres = const [],
    this.castMembers = const [],
    this.crewMembers = const [],
    this.rating,
    this.voteCount,
    this.contentRating,
    this.tagline,
    this.videoCodec,
    this.audioCodec,
    this.containerFormat,
    this.resolutionWidth,
    this.resolutionHeight,
    this.seriesId,
    this.seasonId,
    this.seasonNumber,
    this.episodeNumber,
    this.movieId,
    this.episodeId,
    this.versionLabel,
    this.isDefaultVersion = false,
    this.availabilityStatus = 'AVAILABLE',
  });

  final String id;
  final String fileNodeId;
  final String mediaType;
  final String title;
  final String? originalTitle;
  final DateTime? releaseDate;
  final String? overview;
  final String? posterFileId;
  final String? backdropFileId;
  final String? posterUrl;
  final String? backdropUrl;
  final Map<String, MovieContentAsset> assets;
  final int? runtimeSeconds;
  final String metadataStatus;
  final String nfoStatus;
  final DateTime? updatedAt;
  final Map<String, dynamic> metadata;
  final List<String> genres;
  final List<MovieCastMember> castMembers;
  final List<MovieCrewMember> crewMembers;
  final double? rating;
  final int? voteCount;
  final String? contentRating;
  final String? tagline;
  final String? videoCodec;
  final String? audioCodec;
  final String? containerFormat;
  final int? resolutionWidth;
  final int? resolutionHeight;
  final String? seriesId;
  final String? seasonId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? movieId;
  final String? episodeId;
  final String? versionLabel;
  final bool isDefaultVersion;
  final String availabilityStatus;

  bool get available => availabilityStatus == 'AVAILABLE';

  factory MovieVideoItem.fromJson(Map<String, dynamic> json) {
    return MovieVideoItem(
      id: json['id']?.toString() ?? '',
      fileNodeId: json['fileNodeId']?.toString() ?? '',
      mediaType: json['mediaType']?.toString() ?? 'MOVIE',
      title: json['title']?.toString() ?? '未命名影片',
      originalTitle: json['originalTitle']?.toString(),
      releaseDate:
          DateTime.tryParse(json['releaseDate']?.toString() ?? '')?.toLocal(),
      overview: json['overview']?.toString(),
      posterFileId: json['posterFileId']?.toString(),
      backdropFileId: json['backdropFileId']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
      backdropUrl: json['backdropUrl']?.toString(),
      assets: _assetMap(json['assets']),
      runtimeSeconds:
          json['runtimeSeconds'] == null
              ? null
              : MovieJson.asInt(json['runtimeSeconds']),
      metadataStatus: json['metadataStatus']?.toString() ?? 'PENDING',
      nfoStatus: json['nfoStatus']?.toString() ?? 'DISABLED',
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal(),
      metadata:
          json['metadata'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(json['metadata'] as Map)
              : const {},
      genres: MovieJson.stringList(json['genres']),
      castMembers:
          MovieJson.asList(
            json['castMembers'],
          ).map(MovieCastMember.fromJson).toList(),
      crewMembers:
          MovieJson.asList(
            json['crewMembers'],
          ).map(MovieCrewMember.fromJson).toList(),
      rating:
          json['rating'] == null ? null : MovieJson.asDouble(json['rating']),
      voteCount:
          json['voteCount'] == null ? null : MovieJson.asInt(json['voteCount']),
      contentRating: json['contentRating']?.toString(),
      tagline: json['tagline']?.toString(),
      videoCodec: json['videoCodec']?.toString(),
      audioCodec: json['audioCodec']?.toString(),
      containerFormat: json['containerFormat']?.toString(),
      resolutionWidth:
          json['resolutionWidth'] == null
              ? null
              : MovieJson.asInt(json['resolutionWidth']),
      resolutionHeight:
          json['resolutionHeight'] == null
              ? null
              : MovieJson.asInt(json['resolutionHeight']),
      seriesId: json['seriesId']?.toString(),
      seasonId: json['seasonId']?.toString(),
      seasonNumber:
          json['seasonNumber'] == null
              ? null
              : MovieJson.asInt(json['seasonNumber']),
      episodeNumber:
          json['episodeNumber'] == null
              ? null
              : MovieJson.asInt(json['episodeNumber']),
      movieId: json['movieId']?.toString(),
      episodeId: json['episodeId']?.toString(),
      versionLabel: json['versionLabel']?.toString(),
      isDefaultVersion: json['isDefaultVersion'] == true,
      availabilityStatus: json['availabilityStatus']?.toString() ?? 'AVAILABLE',
    );
  }

  String get year {
    final date = releaseDate;
    if (date != null) {
      return date.year.toString();
    }
    final raw = metadata['year'];
    return raw == null ? '待识别' : raw.toString();
  }

  String get runtimeText {
    final seconds =
        runtimeSeconds ?? MovieJson.asInt(metadata['runtimeSeconds']);
    if (seconds <= 0) {
      return '未知时长';
    }
    final minutes = (seconds / 60).round();
    return '$minutes 分钟';
  }

  String? get posterImageUrl =>
      _firstNonBlank([posterUrl, assets['POSTER']?.url]);

  String? get backdropImageUrl =>
      _firstNonBlank([backdropUrl, assets['BACKDROP']?.url]);

  /// Hero 大图：背景图缺失时回退海报，保证封面可回显。
  String? get heroImageUrl => backdropImageUrl ?? posterImageUrl;
}

class MovieContentAsset {
  const MovieContentAsset({
    required this.assetType,
    required this.primary,
    required this.metadata,
    this.id,
    this.fileNodeId,
    this.url,
    this.provider,
    this.language,
  });

  final String? id;
  final String assetType;
  final String? fileNodeId;
  final String? url;
  final String? provider;
  final String? language;
  final bool primary;
  final Map<String, dynamic> metadata;

  factory MovieContentAsset.fromJson(Map<String, dynamic> json) {
    return MovieContentAsset(
      id: json['id']?.toString(),
      assetType: json['assetType']?.toString() ?? '',
      fileNodeId: json['fileNodeId']?.toString(),
      url: json['url']?.toString(),
      provider: json['provider']?.toString(),
      language: json['language']?.toString(),
      primary: json['primary'] == true,
      metadata: MovieJson.asMap(json['metadata']),
    );
  }
}

class MovieContinueWatching {
  const MovieContinueWatching({
    required this.id,
    required this.title,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.progressPercent,
    this.posterFileId,
    this.posterUrl,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String? posterFileId;
  final String? posterUrl;
  final int positionSeconds;
  final int durationSeconds;
  final double progressPercent;
  final DateTime? updatedAt;

  factory MovieContinueWatching.fromJson(Map<String, dynamic> json) {
    return MovieContinueWatching(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名影片',
      posterFileId: json['posterFileId']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
      positionSeconds: MovieJson.asInt(json['positionSeconds']),
      durationSeconds: MovieJson.asInt(json['durationSeconds']),
      progressPercent: MovieJson.asDouble(json['progressPercent']),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal(),
    );
  }
}

class MovieWatchHistory {
  const MovieWatchHistory({
    required this.id,
    required this.videoItemId,
    required this.title,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.completed,
    this.posterFileId,
    this.posterUrl,
    this.playedAt,
  });

  final String id;
  final String videoItemId;
  final String title;
  final String? posterFileId;
  final String? posterUrl;
  final int positionSeconds;
  final int durationSeconds;
  final bool completed;
  final DateTime? playedAt;

  factory MovieWatchHistory.fromJson(Map<String, dynamic> json) {
    return MovieWatchHistory(
      id: json['id']?.toString() ?? '',
      videoItemId: json['videoItemId']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名影片',
      posterFileId: json['posterFileId']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
      positionSeconds: MovieJson.asInt(json['positionSeconds']),
      durationSeconds: MovieJson.asInt(json['durationSeconds']),
      completed: json['completed'] == true,
      playedAt:
          DateTime.tryParse(json['playedAt']?.toString() ?? '')?.toLocal(),
    );
  }

  double get progressPercent {
    if (durationSeconds <= 0) {
      return 0;
    }
    return (positionSeconds * 100 / durationSeconds).clamp(0, 100);
  }
}

class MovieCollection {
  const MovieCollection({
    required this.id,
    required this.name,
    required this.collectionType,
    required this.itemCount,
    this.description,
    this.coverFileId,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final String? coverFileId;
  final String collectionType;
  final int itemCount;
  final DateTime? updatedAt;

  factory MovieCollection.fromJson(Map<String, dynamic> json) {
    return MovieCollection(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名合集',
      description: json['description']?.toString(),
      coverFileId: json['coverFileId']?.toString(),
      collectionType: json['collectionType']?.toString() ?? 'MANUAL',
      itemCount: MovieJson.asInt(json['itemCount']),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal(),
    );
  }
}

class MovieFavoriteState {
  const MovieFavoriteState({required this.videoItemId, required this.favorite});

  final String videoItemId;
  final bool favorite;

  factory MovieFavoriteState.fromJson(Map<String, dynamic> json) {
    return MovieFavoriteState(
      videoItemId: json['videoItemId']?.toString() ?? '',
      favorite: json['favorite'] == true,
    );
  }
}

class MovieSeries {
  const MovieSeries({
    required this.id,
    required this.title,
    required this.metadataStatus,
    required this.metadata,
    this.originalTitle,
    this.firstAirDate,
    this.overview,
    this.posterFileId,
    this.backdropFileId,
    this.posterUrl,
    this.backdropUrl,
    this.assets = const {},
    this.genres = const [],
    this.rating,
    this.voteCount,
    this.contentRating,
    this.seriesType = 'TV',
    this.updatedAt,
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String? originalTitle;
  final DateTime? firstAirDate;
  final String? overview;
  final String? posterFileId;
  final String? backdropFileId;
  final String? posterUrl;
  final String? backdropUrl;
  final Map<String, MovieContentAsset> assets;
  final List<String> genres;
  final double? rating;
  final int? voteCount;
  final String? contentRating;
  final String seriesType;
  final String metadataStatus;
  final DateTime? updatedAt;
  final Map<String, dynamic> metadata;
  final bool isFavorite;

  factory MovieSeries.fromJson(Map<String, dynamic> json) {
    return MovieSeries(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名剧集',
      originalTitle: json['originalTitle']?.toString(),
      firstAirDate:
          DateTime.tryParse(json['firstAirDate']?.toString() ?? '')?.toLocal(),
      overview: json['overview']?.toString(),
      posterFileId: json['posterFileId']?.toString(),
      backdropFileId: json['backdropFileId']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
      backdropUrl: json['backdropUrl']?.toString(),
      assets: _assetMap(json['assets']),
      genres: MovieJson.stringList(json['genres']),
      rating:
          json['rating'] == null ? null : MovieJson.asDouble(json['rating']),
      voteCount:
          json['voteCount'] == null ? null : MovieJson.asInt(json['voteCount']),
      contentRating: json['contentRating']?.toString(),
      seriesType: json['seriesType']?.toString() ?? 'TV',
      metadataStatus: json['metadataStatus']?.toString() ?? 'PENDING',
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal(),
      metadata:
          json['metadata'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(json['metadata'] as Map)
              : const {},
      isFavorite: json['isFavorite'] == true,
    );
  }

  String get year {
    final date = firstAirDate;
    if (date != null) return date.year.toString();
    return '待识别';
  }

  String? get posterImageUrl =>
      _firstNonBlank([posterUrl, assets['POSTER']?.url]);

  String? get backdropImageUrl =>
      _firstNonBlank([backdropUrl, assets['BACKDROP']?.url]);

  /// Hero 大图：背景图缺失时回退海报，保证封面可回显。
  String? get heroImageUrl => backdropImageUrl ?? posterImageUrl;
}

class MovieCastMember {
  const MovieCastMember({
    required this.name,
    this.character,
    this.profilePath,
    this.order,
  });

  final String name;
  final String? character;
  final String? profilePath;
  final int? order;

  factory MovieCastMember.fromJson(Map<String, dynamic> json) {
    return MovieCastMember(
      name: json['name']?.toString() ?? '',
      character: json['character']?.toString(),
      profilePath: json['profilePath']?.toString(),
      order: json['order'] == null ? null : MovieJson.asInt(json['order']),
    );
  }
}

class MovieCrewMember {
  const MovieCrewMember({
    required this.name,
    this.job,
    this.department,
    this.profilePath,
  });

  final String name;
  final String? job;
  final String? department;
  final String? profilePath;

  factory MovieCrewMember.fromJson(Map<String, dynamic> json) {
    return MovieCrewMember(
      name: json['name']?.toString() ?? '',
      job: json['job']?.toString(),
      department: json['department']?.toString(),
      profilePath: json['profilePath']?.toString(),
    );
  }
}

class MovieSeason {
  const MovieSeason({
    required this.id,
    required this.seasonNumber,
    this.title,
    this.overview,
    this.airDate,
    this.episodeCount,
    this.posterFileId,
    this.rating,
    this.posterUrl,
  });

  final String id;
  final int seasonNumber;
  final String? title;
  final String? overview;
  final DateTime? airDate;
  final int? episodeCount;
  final String? posterFileId;
  final double? rating;
  final String? posterUrl;

  factory MovieSeason.fromJson(Map<String, dynamic> json) {
    return MovieSeason(
      id: json['id']?.toString() ?? '',
      seasonNumber: MovieJson.asInt(json['seasonNumber']),
      title: json['title']?.toString(),
      overview: json['overview']?.toString(),
      airDate: DateTime.tryParse(json['airDate']?.toString() ?? '')?.toLocal(),
      episodeCount:
          json['episodeCount'] == null
              ? null
              : MovieJson.asInt(json['episodeCount']),
      posterFileId: json['posterFileId']?.toString(),
      rating:
          json['rating'] == null ? null : MovieJson.asDouble(json['rating']),
      posterUrl: json['posterUrl']?.toString(),
    );
  }
}

class MovieSeasonDetail {
  const MovieSeasonDetail({required this.season, required this.episodes});

  final MovieSeason season;
  final List<MovieVideoItem> episodes;

  factory MovieSeasonDetail.fromJson(Map<String, dynamic> json) {
    return MovieSeasonDetail(
      season: MovieSeason.fromJson(MovieJson.asMap(json['season'])),
      episodes:
          MovieJson.asList(
            json['episodes'],
          ).map(MovieVideoItem.fromJson).toList(),
    );
  }
}

class MovieSeriesDetail {
  const MovieSeriesDetail({
    required this.series,
    required this.seasons,
    required this.cast,
    required this.crew,
  });

  final MovieSeries series;
  final List<MovieSeason> seasons;
  final List<MovieCastMember> cast;
  final List<MovieCrewMember> crew;

  factory MovieSeriesDetail.fromJson(Map<String, dynamic> json) {
    return MovieSeriesDetail(
      series: MovieSeries.fromJson(MovieJson.asMap(json['series'])),
      seasons:
          MovieJson.asList(json['seasons']).map(MovieSeason.fromJson).toList(),
      cast:
          MovieJson.asList(json['cast']).map(MovieCastMember.fromJson).toList(),
      crew:
          MovieJson.asList(json['crew']).map(MovieCrewMember.fromJson).toList(),
    );
  }
}

class MovieDashboard {
  const MovieDashboard({
    required this.stats,
    required this.recentlyAdded,
    required this.continueWatching,
    required this.series,
  });

  final MovieStats stats;
  final List<MovieVideoItem> recentlyAdded;
  final List<MovieContinueWatching> continueWatching;
  final List<MovieSeries> series;

  factory MovieDashboard.empty() {
    return const MovieDashboard(
      stats: MovieStats(
        movieCount: 0,
        episodeCount: 0,
        seriesCount: 0,
        scrapeFailedCount: 0,
      ),
      recentlyAdded: [],
      continueWatching: [],
      series: [],
    );
  }

  factory MovieDashboard.fromJson(Map<String, dynamic> json) {
    return MovieDashboard(
      stats: MovieStats.fromJson(MovieJson.asMap(json['stats'])),
      recentlyAdded:
          MovieJson.asList(
            json['recentlyAdded'],
          ).map(MovieVideoItem.fromJson).toList(),
      continueWatching:
          MovieJson.asList(
            json['continueWatching'],
          ).map(MovieContinueWatching.fromJson).toList(),
      series:
          MovieJson.asList(json['series']).map(MovieSeries.fromJson).toList(),
    );
  }
}

Map<String, MovieContentAsset> _assetMap(Object? value) {
  final raw = MovieJson.asMap(value);
  return raw.map((key, item) {
    return MapEntry(
      key,
      item is Map
          ? MovieContentAsset.fromJson(Map<String, dynamic>.from(item))
          : const MovieContentAsset(
            assetType: '',
            primary: false,
            metadata: {},
          ),
    );
  });
}

String? _firstNonBlank(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}
