/// 影视模块提供给跨 Feature 仪表盘的只读契约。
library;

// 控制器库整份导出：`toggleFavorite` 等动作是扩展方法，`show` 白名单
// 导不出无名扩展，桌面页只能看到 build。
export 'package:omninest/features/video/application/movie_controller.dart';
export 'package:omninest/features/video/application/movie_detail_backend_actions.dart';
export 'package:omninest/features/video/application/movie_detail_action_controller.dart'
    show MovieDetailActionState, movieDetailActionProvider;
export 'package:omninest/features/video/application/movie_engagement_actions.dart'
    show MovieEngagementActions, movieEngagementActionsProvider;
export 'package:omninest/features/video/application/movie_watchlist_controller.dart'
    show MovieWatchlistController, movieWatchlistProvider;
export 'package:omninest/features/video/application/movie_metadata_commands.dart'
    show MovieMetadataCommands, movieMetadataCommandsProvider;
export 'package:omninest/features/video/application/movie_providers.dart'
    show
        movieDashboardProvider,
        movieDetailProvider,
        movieApiProvider,
        movieItemHistoryProvider,
        movieItemFilesProvider,
        activeMovieFileIdsProvider,
        movieSeasonDetailProvider,
        movieScrapeCandidatesProvider,
        movieSeriesDetailProvider,
        movieSeriesEpisodesProvider,
        movieSeriesHistoryProvider,
        seriesScrapeCandidatesProvider,
        movieSubtitlesProvider,
        seriesFavoriteProvider,
        seriesPlayIntentProvider,
        videoFavoriteStatusProvider;
export 'package:omninest/features/video/domain/movie_library_models.dart'
    show MovieWatchHistory;
export 'package:omninest/features/video/domain/movie_management_models.dart'
    show NfoExport, ScrapeTask, VideoScrapeCandidate;
export 'package:omninest/features/video/domain/movie_models.dart'
    show
        MovieContinueWatching,
        MovieDashboard,
        MovieFiles,
        MovieVideoFile,
        MovieVideoItem;
export 'package:omninest/features/video/domain/movie_library_models.dart'
    show MovieSeason, MovieSeasonDetail, MovieSeries, MovieSeriesDetail;
export 'package:omninest/features/video/application/movie_center_state.dart'
    show SeasonKey;
export 'package:omninest/features/video/domain/movie_playback_models.dart'
    show SubtitleTrack;
