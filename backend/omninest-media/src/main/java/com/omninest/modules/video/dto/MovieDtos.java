package com.omninest.modules.video.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

public final class MovieDtos {
    private MovieDtos() {
    }

    public record CastMemberDto(
            String name,
            String character,
            String profilePath,
            Integer order
    ) {
    }

    public record CrewMemberDto(
            String name,
            String job,
            String department,
            String profilePath
    ) {
    }

    /**
     * 影视库统计聚合。
     *
     * <p>收藏、历史、合集与继续观看计数来自服务端权威统计，
     * 供客户端侧边栏在不加载对应分区列表时也能展示准确徽标。</p>
     */
    public record MovieStatsDto(
            long movieCount,
            long episodeCount,
            long seriesCount,
            long scrapeFailedCount,
            long favoritesCount,
            long historyCount,
            long collectionsCount,
            long continueWatchingCount
    ) {
    }

    public record MovieContentAssetDto(
            UUID id,
            String assetType,
            UUID fileNodeId,
            String url,
            String provider,
            String language,
            boolean primary,
            Map<String, Object> metadata
    ) {
    }

    public record MovieVideoFileDto(
            UUID videoItemId,
            UUID fileNodeId,
            String fileName,
            long sizeBytes,
            String mimeType,
            String versionLabel,
            boolean primary,
            String videoCodec,
            String audioCodec,
            String containerFormat,
            Integer resolutionWidth,
            Integer resolutionHeight
    ) {
    }

    public record MovieFilesDto(
            List<MovieVideoFileDto> files,
            boolean transcodingEnabled
    ) {
    }

    public record MovieVideoItemDto(
            UUID id,
            UUID fileNodeId,
            String mediaType,
            String title,
            String originalTitle,
            LocalDate releaseDate,
            String overview,
            UUID posterFileId,
            UUID backdropFileId,
            Integer runtimeSeconds,
            String metadataStatus,
            String nfoStatus,
            Instant updatedAt,
            Map<String, Object> metadata,
            String posterUrl,
            String backdropUrl,
            Map<String, MovieContentAssetDto> assets,
            List<String> genres,
            List<CastMemberDto> castMembers,
            List<CrewMemberDto> crewMembers,
            Double rating,
            Integer voteCount,
            String contentRating,
            String tagline,
            String videoCodec,
            String audioCodec,
            String containerFormat,
            Integer resolutionWidth,
            Integer resolutionHeight,
            UUID seriesId,
            UUID seasonId,
            Integer seasonNumber,
            Integer episodeNumber,
            UUID movieId,
            UUID episodeId,
            String versionLabel,
            boolean isDefaultVersion,
            String availabilityStatus,
            boolean writable
    ) {
    }

    public record MovieLibraryItemDto(
            UUID id,
            UUID fileNodeId,
            String mediaType,
            String title,
            String originalTitle,
            LocalDate releaseDate,
            UUID posterFileId,
            Integer runtimeSeconds,
            String metadataStatus,
            Instant updatedAt,
            String posterUrl,
            List<String> genres,
            Double rating,
            UUID seriesId,
            Integer seasonNumber,
            Integer episodeNumber,
            String availabilityStatus
    ) {
    }

    public record MovieContinueWatchingDto(
            UUID id,
            String title,
            UUID posterFileId,
            String posterUrl,
            long positionSeconds,
            long durationSeconds,
            double progressPercent,
            Instant updatedAt,
            String mediaType,
            UUID seriesId,
            Integer seasonNumber,
            Integer episodeNumber,
            UUID movieId
    ) {
        public MovieContinueWatchingDto(
                UUID id,
                String title,
                UUID posterFileId,
                String posterUrl,
                long positionSeconds,
                long durationSeconds,
                double progressPercent,
                Instant updatedAt,
                String mediaType,
                UUID seriesId,
                Integer seasonNumber,
                Integer episodeNumber
        ) {
            this(id, title, posterFileId, posterUrl, positionSeconds, durationSeconds,
                    progressPercent, updatedAt, mediaType, seriesId, seasonNumber, episodeNumber, null);
        }
    }

    public record MovieSeriesDto(
            UUID id,
            String title,
            String originalTitle,
            LocalDate firstAirDate,
            String overview,
            UUID posterFileId,
            UUID backdropFileId,
            String metadataStatus,
            Instant updatedAt,
            Map<String, Object> metadata,
            String posterUrl,
            String backdropUrl,
            Map<String, MovieContentAssetDto> assets,
            List<String> genres,
            List<CastMemberDto> castMembers,
            List<CrewMemberDto> crewMembers,
            Double rating,
            Integer voteCount,
            String contentRating,
            String seriesType,
            boolean isFavorite
    ) {
    }

    public record MovieSeasonDto(
            UUID id,
            Integer seasonNumber,
            String title,
            String overview,
            LocalDate airDate,
            Integer episodeCount,
            UUID posterFileId,
            Double rating,
            String posterUrl
    ) {
    }

    public record MovieSeasonDetailDto(
            MovieSeasonDto season,
            List<MovieVideoItemDto> episodes
    ) {
    }

    public record MovieSeriesDetailDto(
            MovieSeriesDto series,
            List<MovieSeasonDto> seasons,
            List<CastMemberDto> cast,
            List<CrewMemberDto> crew,
            boolean writable
    ) {
    }

    public record MovieDashboardDto(
            MovieStatsDto stats,
            List<MovieVideoItemDto> recentlyAdded,
            List<MovieContinueWatchingDto> continueWatching,
            List<MovieSeriesDto> series,
            long itemsAddedToday
    ) {
    }

    public record PlaybackSubtitleDto(
            UUID id,
            String language,
            String label,
            String kind,
            String url,
            Integer streamIndex
    ) {
    }

    public record PlaybackPlanDto(
            UUID videoItemId,
            String mode,
            String url,
            Instant expiresAt,
            long positionSeconds,
            long durationSeconds,
            String container,
            String videoCodec,
            String audioCodec,
            List<PlaybackSubtitleDto> subtitles,
            String streamUrl,
            boolean hasAudioCache
    ) {
    }

    public record PlaybackProgressRequest(
            long positionSeconds,
            long durationSeconds,
            boolean completed,
            Instant clientUpdatedAt,
            String deviceId
    ) {
    }

    public record SubtitleTrackDto(
            UUID id,
            String language,
            String label,
            String kind,
            String url,
            boolean embedded,
            Integer streamIndex,
            Instant createdAt
    ) {
    }

    public record SubtitleUpdateRequest(
            String language,
            String label,
            String kind
    ) {
    }

    public record SubtitleUploadRequest(
            UUID fileNodeId,
            String language,
            String label,
            String kind
    ) {
    }

    public record VideoPosterUploadDto(
            UUID fileNodeId
    ) {
    }

    public record MovieMetadataUpdateRequest(
            String title,
            String originalTitle,
            LocalDate releaseDate,
            String overview,
            UUID posterFileId,
            UUID backdropFileId,
            Integer runtimeSeconds,
            String metadataStatus,
            List<String> genres,
            Double rating,
            List<String> cast,
            String posterUrl,
            Boolean restoreOriginal,
            Boolean clearRuntime,
            Boolean clearPoster
    ) {
        public MovieMetadataUpdateRequest(
                String title,
                String originalTitle,
                LocalDate releaseDate,
                String overview,
                UUID posterFileId,
                UUID backdropFileId,
                Integer runtimeSeconds,
                String metadataStatus
        ) {
            this(title, originalTitle, releaseDate, overview, posterFileId, backdropFileId, runtimeSeconds,
                    metadataStatus, null, null, null, null, false, false, false);
        }

        public MovieMetadataUpdateRequest(
                String title,
                String originalTitle,
                LocalDate releaseDate,
                String overview,
                UUID posterFileId,
                UUID backdropFileId,
                Integer runtimeSeconds,
                String metadataStatus,
                List<String> genres,
                Double rating,
                List<String> cast,
                String posterUrl,
                Boolean restoreOriginal,
                Boolean clearRuntime
        ) {
            this(title, originalTitle, releaseDate, overview, posterFileId, backdropFileId, runtimeSeconds,
                    metadataStatus, genres, rating, cast, posterUrl, restoreOriginal, clearRuntime, false);
        }
    }

    /**
     * 手动更新剧集元数据的请求。
     *
     * <p>剧集没有自己的时长字段，手填值随 posterUrl 一起放在 provider_metadata
     * 里；其余字段对应 MediaTvSeries 的实体列。所有字段可空，未给出的保持原值。
     */
    public record UpdateSeriesMetadataRequest(
            String title,
            String overview,
            String seriesType,
            LocalDate firstAirDate,
            Double rating,
            List<String> genres,
            List<String> cast,
            String runtime,
            String posterUrl,
            UUID posterFileId,
            Boolean clearPoster,
            Boolean restoreOriginal
    ) {
        public UpdateSeriesMetadataRequest(
                String title,
                String overview,
                String seriesType,
                LocalDate firstAirDate,
                Double rating,
                List<String> genres,
                List<String> cast,
                String runtime,
                String posterUrl
        ) {
            this(title, overview, seriesType, firstAirDate, rating, genres, cast, runtime, posterUrl,
                    null, false, false);
        }
    }

    public record MovieWatchHistoryDto(
            UUID id,
            UUID videoItemId,
            String title,
            UUID posterFileId,
            String posterUrl,
            long positionSeconds,
            long durationSeconds,
            boolean completed,
            Instant playedAt,
            String mediaType,
            UUID seriesId
    ) {
    }

    public record MovieFavoriteStateDto(
            UUID videoItemId,
            boolean favorite
    ) {
    }

    public record MovieWatchlistStateDto(
            UUID videoItemId,
            boolean watchlisted
    ) {
    }

    public record MovieCollectionDto(
            UUID id,
            String name,
            String description,
            UUID coverFileId,
            String collectionType,
            long itemCount,
            Instant updatedAt
    ) {
    }

    public record MovieCollectionRequest(
            String name,
            String description,
            UUID coverFileId
    ) {
    }

    public record MovieCollectionItemRequest(
            UUID videoItemId,
            int sortOrder
    ) {
    }

    public record MovieTaskDto(
            UUID id,
            String taskType,
            String status,
            int progress,
            String routingKey,
            String errorSummary,
            Instant updatedAt
    ) {
    }

    public record MovieScanRequest(
            UUID rootFolderId,
            boolean incremental
    ) {
    }

    /**
     * 创建刮削任务请求。
     *
     * @param fileNodeId 视频文件节点 ID
     * @param force 是否强制重建已有元数据
     * @param provider 指定元数据提供器；与 externalId 同时给出时按用户选中的候选刮削
     * @param externalId 指定候选的外部 ID；空表示走标题自动匹配
     */
    public record ScrapeRequest(
            UUID fileNodeId,
            boolean force,
            String provider,
            String externalId
    ) {
    }

    /**
     * 系列级刮削任务请求。
     */
    public record SeriesScrapeRequest(
            boolean force,
            String provider,
            String externalId
    ) {
    }

    public record ScrapeTaskDto(
            UUID taskId,
            String status,
            String message
    ) {
    }

    public record ScrapeCandidateDto(
            String provider,
            String externalId,
            String title,
            String originalTitle,
            LocalDate releaseDate,
            Integer year,
            String overview,
            String posterUrl,
            String backdropUrl,
            Integer runtimeMinutes,
            Double voteAverage,
            String imdbId,
            List<String> genres,
            List<CastMemberDto> castMembers,
            List<CrewMemberDto> crewMembers,
            Integer voteCount,
            String contentRating,
            String tagline,
            Double popularity,
            String originalLanguage,
            List<Map<String, Object>> studios,
            List<Map<String, Object>> countries,
            List<String> screenshotUrls
    ) {
    }

    public record NfoExportDto(
            UUID id,
            UUID videoItemId,
            String status,
            String exportPath,
            Instant exportedAt,
            String content
    ) {
    }
}
