part of 'portal_desktop_visual_shells.dart';

class _PortalDesktopData {
  const _PortalDesktopData({
    required this.readerDashboard,
    required this.movieDashboard,
    required this.music,
    required this.photoDashboard,
    required this.storageStats,
    required this.adminSummary,
    required this.weather,
    this.weatherOverride,
  });

  factory _PortalDesktopData.from(
    WidgetRef ref, {
    WeatherData? weatherOverride,
  }) {
    return _PortalDesktopData(
      readerDashboard: ref.watch(portalReaderDashboardProvider),
      movieDashboard: ref.watch(portalMovieDashboardProvider),
      music: ref.watch(portalMusicSnapshotProvider),
      photoDashboard: ref.watch(portalPhotoDashboardProvider),
      storageStats: ref.watch(portalStorageStatsProvider),
      adminSummary: ref.watch(portalAdminSummaryProvider),
      weather: ref.watch(realtimeWeatherProvider),
      weatherOverride: weatherOverride,
    );
  }

  final AsyncValue<ReaderDashboard> readerDashboard;
  final AsyncValue<MovieDashboard> movieDashboard;
  final AsyncValue<MusicPortalSnapshot> music;
  final AsyncValue<PhotoDashboard> photoDashboard;
  final AsyncValue<FileStorageStats> storageStats;
  final AsyncValue<AdminConsoleSummary> adminSummary;
  final AsyncValue<WeatherData> weather;
  final WeatherData? weatherOverride;

  PortalDashboardSection? get firstFailedSection {
    if (readerDashboard.hasError) {
      return PortalDashboardSection.reader;
    }
    if (movieDashboard.hasError) {
      return PortalDashboardSection.video;
    }
    if (music.hasError) {
      return PortalDashboardSection.music;
    }
    if (photoDashboard.hasError) {
      return PortalDashboardSection.photos;
    }
    if (storageStats.hasError) {
      return PortalDashboardSection.storage;
    }
    if (adminSummary.hasError) {
      return PortalDashboardSection.admin;
    }
    if (weather.hasError) {
      return PortalDashboardSection.weather;
    }
    return null;
  }

  String failureMessage(BuildContext context, PortalDashboardSection section) {
    final l10n = AppLocalizations.of(context);
    return switch (section) {
      PortalDashboardSection.storage => l10n.portalLoadStorageFailed,
      PortalDashboardSection.video => l10n.portalLoadMovieFailed,
      PortalDashboardSection.music => l10n.portalLoadMusicFailed,
      PortalDashboardSection.photos => l10n.portalLoadPhotoFailed,
      PortalDashboardSection.reader => l10n.portalLoadReadingFailed,
      PortalDashboardSection.admin => l10n.portalTaskFailed,
      PortalDashboardSection.weather => l10n.portalWeatherDisconnected,
    };
  }

  ReaderItem? get primaryReaderItem {
    final dashboard = _portalAsyncValue(readerDashboard);
    if (dashboard == null) {
      return null;
    }
    if (dashboard.continueReading.isNotEmpty) {
      return dashboard.continueReading.first;
    }
    if (dashboard.recentItems.isNotEmpty) {
      return dashboard.recentItems.first;
    }
    return null;
  }

  MovieContinueWatching? get primaryWatchingItem {
    final dashboard = _portalAsyncValue(movieDashboard);
    if (dashboard == null || dashboard.continueWatching.isEmpty) {
      return null;
    }
    return dashboard.continueWatching.first;
  }

  MovieVideoItem? get primaryMovieItem {
    final dashboard = _portalAsyncValue(movieDashboard);
    if (dashboard == null || dashboard.recentlyAdded.isEmpty) {
      return null;
    }
    return dashboard.recentlyAdded.first;
  }

  PhotoItem? get primaryPhotoItem {
    final dashboard = _portalAsyncValue(photoDashboard);
    if (dashboard == null || dashboard.recentPhotos.isEmpty) {
      return null;
    }
    return dashboard.recentPhotos.first;
  }

  MusicPortalTrack? get primaryTrack => _portalAsyncValue(music)?.featuredTrack;

  MusicPortalAlbum? get primaryAlbum => _portalAsyncValue(music)?.featuredAlbum;

  String get continueTitle => primaryReaderItem?.title ?? '';

  String continueSubtitle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = primaryReaderItem;
    final progress = item?.progressPercent;
    if (progress != null) {
      final normalized = progress.clamp(0, 1).toDouble();
      final chapterTitle = item?.currentChapterTitle;
      final location =
          chapterTitle == null || chapterTitle.isEmpty
              ? l10n.portalVisualLastReadingLocation
              : chapterTitle;
      return '${(normalized * 100).round()}% · $location';
    }
    return item?.authorName ?? l10n.portalNoReadingBook;
  }

  String get movieTitle {
    final watching = primaryWatchingItem;
    if (watching != null) {
      return watching.title;
    }
    return primaryMovieItem?.title ?? '';
  }

  String movieSubtitle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final watching = primaryWatchingItem;
    final progress = watching?.progressPercent;
    if (progress != null) {
      final normalized = progress.clamp(0, 100).toDouble();
      return '${normalized.round()}% · ${l10n.portalContinueWatching}';
    }
    if (primaryMovieItem != null) {
      return l10n.videoSectionRecent;
    }
    return l10n.portalNoWatchingContent;
  }

  String exhibitSubtitle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = _portalAsyncValue(photoDashboard)?.totalPhotos;
    if (count is int && count > 0) {
      return '${l10n.portalPhotos} · $count';
    }
    return l10n.portalDockPhotos;
  }

  String? get readerImageUrl {
    return _firstPortalNonBlank([primaryReaderItem?.coverUrl]);
  }

  String? get readerCoverItemId {
    final item = primaryReaderItem;
    if (item == null || !item.hasCover) {
      return null;
    }
    return item.id;
  }

  String? get movieImageUrl {
    final movie = primaryMovieItem;
    return _firstPortalNonBlank([
      primaryWatchingItem?.posterUrl,
      movie?.backdropImageUrl,
      movie?.posterImageUrl,
    ]);
  }

  String? get photoImageUrl {
    return _firstPortalNonBlank([primaryPhotoItem?.coverUrl]);
  }

  String? get musicImageUrl {
    final track = primaryTrack;
    if (track != null) {
      return _firstPortalNonBlank([track.coverUrl]);
    }
    return _firstPortalNonBlank([primaryAlbum?.coverUrl]);
  }

  String? get heroImageUrl {
    return _firstPortalNonBlank([
      readerImageUrl,
      movieImageUrl,
      photoImageUrl,
      musicImageUrl,
    ]);
  }

  String? get atmosphericImageUrl {
    return _firstPortalNonBlank([
      photoImageUrl,
      movieImageUrl,
      readerImageUrl,
      musicImageUrl,
    ]);
  }

  List<PortalFocusItem> coverSnapshots(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final readerItem = primaryReaderItem;
    final movieItem = primaryWatchingItem;
    final photoItem = primaryPhotoItem;
    final musicTrack = primaryTrack;
    final musicAlbum = primaryAlbum;
    return [
      PortalFocusItem(
        icon: PortalFocusIcon.reader,
        module: PortalFocusModule.reader,
        title: continueTitle.isEmpty ? l10n.portalNoReadingBook : continueTitle,
        subtitle: continueSubtitle(context),
        imageUrl: readerImageUrl,
        readerItemId: readerCoverItemId,
        coverCacheKey:
            readerCoverItemId == null
                ? null
                : 'portal-cover:reader:$readerCoverItemId',
        route:
            readerItem == null
                ? '/reader'
                : readerItem.isComic
                ? '/reader/comics/${readerItem.id}/read'
                : '/reader/items/${readerItem.id}',
        actionLabel:
            readerItem == null
                ? l10n.portalDockReading
                : l10n.portalOpenReadingItem,
        heroEyebrow: l10n.portalDockReading,
        heroBody: continueSubtitle(context),
        variant: 0,
      ),
      PortalFocusItem(
        icon: PortalFocusIcon.video,
        module: PortalFocusModule.video,
        title: movieTitle.isEmpty ? l10n.portalNoWatchingContent : movieTitle,
        subtitle: movieSubtitle(context),
        imageUrl: movieImageUrl,
        coverCacheKey: () {
          final coverId = movieItem?.id ?? primaryMovieItem?.id;
          return coverId == null ? null : 'portal-cover:video:$coverId';
        }(),
        route:
            movieItem == null
                ? primaryMovieItem == null
                    ? '/video'
                    : '/video/${primaryMovieItem!.id}'
                : '/video/${movieItem.id}/play',
        actionLabel:
            movieItem == null
                ? l10n.portalDockMovies
                : l10n.portalContinueWatching,
        heroEyebrow: l10n.portalDockMovies,
        heroBody: movieSubtitle(context),
        variant: 3,
      ),
      PortalFocusItem(
        icon: PortalFocusIcon.photos,
        module: PortalFocusModule.photos,
        title: photoItem?.title ?? l10n.portalNoPhotos,
        subtitle: exhibitSubtitle(context),
        imageUrl: photoImageUrl,
        coverCacheKey:
            photoItem == null ? null : 'portal-cover:photos:${photoItem.id}',
        route: photoItem == null ? '/photos' : '/photos/${photoItem.id}',
        actionLabel:
            photoItem == null ? l10n.portalDockPhotos : l10n.portalOpenPhoto,
        heroEyebrow: l10n.portalDockPhotos,
        heroBody: exhibitSubtitle(context),
        variant: 2,
      ),
      PortalFocusItem(
        icon: PortalFocusIcon.music,
        module: PortalFocusModule.music,
        title:
            musicTrack?.title ?? musicAlbum?.title ?? l10n.portalNoPlayRecord,
        subtitle:
            musicTrack?.artistName ??
            musicAlbum?.artistName ??
            l10n.portalDockMusic,
        imageUrl: musicImageUrl,
        coverCacheKey: () {
          final trackId = musicTrack?.id;
          if (trackId != null) {
            return 'portal-cover:music:$trackId';
          }
          final album = musicAlbum;
          return album == null ? null : 'portal-cover:music:${album.title}';
        }(),
        route: '/music',
        actionLabel: l10n.portalDockMusic,
        heroEyebrow: l10n.portalDockMusic,
        heroBody:
            musicTrack?.artistName ??
            musicAlbum?.artistName ??
            l10n.portalNoPlayRecord,
        variant: 1,
      ),
    ];
  }

  PortalFocusItem primarySnapshot(BuildContext context) {
    return _firstSnapshotWithImage(coverSnapshots(context));
  }

  String weatherSummary(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final override = weatherOverride;
    if (override != null && override.updateTime.isNotEmpty) {
      return '${override.temp}° · ${override.text}';
    }
    final value = _portalAsyncValue(weather);
    if (value == null) {
      return l10n.portalWeatherTitle;
    }
    return value.updateTime.isNotEmpty
        ? '${value.temp}° · ${value.text}'
        : l10n.portalWeatherDisconnected;
  }

  WeatherData? get weatherData {
    return weatherOverride ?? _portalAsyncValue(weather);
  }

  WeatherData? get connectedWeatherData {
    final value = weatherData;
    if (value == null || value.updateTime.isEmpty) {
      return null;
    }
    return value;
  }

  String weatherDetailSummary(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = connectedWeatherData;
    if (value == null) {
      return l10n.portalWeatherDisconnected;
    }
    return l10n.portalWeatherFeelsLike(value.text, value.feelsLike);
  }

  String get taskSummary {
    final tasks = _portalAsyncValue(adminSummary)?.tasks;
    if (tasks == null) {
      return '---';
    }
    return '${tasks.running} / ${tasks.queued} / ${tasks.failed}';
  }

  String storageSummary(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final storage = _portalAsyncValue(storageStats);
    if (storage == null) {
      return '---';
    }
    if (storage.isQuotaUnlimited == true) {
      return l10n.adminUnlimited;
    }
    return '${(storage.usageRatio * 100).round()}%';
  }
}

T? _portalAsyncValue<T>(AsyncValue<T> value) {
  return value.hasValue ? value.value : null;
}

String? _firstPortalNonBlank(List<String?> values) {
  for (final value in values) {
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
  }
  return null;
}

PortalFocusItem _firstSnapshotWithImage(List<PortalFocusItem> items) {
  for (final item in items) {
    final imageUrl = item.imageUrl?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return item;
    }
  }
  return items.first;
}
