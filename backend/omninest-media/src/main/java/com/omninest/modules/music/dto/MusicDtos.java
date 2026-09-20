package com.omninest.modules.music.dto;

import com.omninest.modules.music.dto.OnlineMusicDtos.OnlineTrackDto;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 定义音乐模块对外使用的请求和响应数据结构。
 *
 * @author OmniNest
 */
public final class MusicDtos {
    private MusicDtos() {
    }

    public record MusicTrackDto(
            UUID id,
            UUID fileNodeId,
            String title,
            String artistName,
            String albumTitle,
            Integer durationSeconds,
            String format,
            Integer bitrate,
            Integer sampleRate,
            Long fileSize,
            String lyricsRaw,
            String lyricsTranslation,
            String genre,
            String coverUrl,
            boolean favorite,
            Instant updatedAt
    ) {
    }

    public record MusicPlaybackPlanDto(
            UUID trackId,
            String url,
            Instant expiresAt,
            Integer durationSeconds,
            String format
    ) {
    }

    public record MusicAlbumDto(
            UUID id,
            String title,
            String artistName,
            String coverUrl,
            LocalDate releaseDate,
            Integer totalDuration,
            Integer trackCount,
            Instant updatedAt
    ) {
    }

    public record MusicArtistDto(
            UUID id,
            String name,
            String avatarUrl,
            Integer trackCount,
            Integer albumCount,
            Instant updatedAt
    ) {
    }

    public record MusicPlaylistDto(
            UUID id,
            String name,
            String description,
            String playlistType,
            UUID coverFileId,
            String coverUrl,
            long trackCount,
            Instant updatedAt
    ) {
    }

    public record MusicDashboardDto(
            long trackCount,
            long albumCount,
            long artistCount,
            long playHistoryCount,
            List<MusicTrackDto> recentTracks,
            List<MusicAlbumDto> recentAlbums,
            List<MusicArtistDto> featuredArtists
    ) {
    }

    public record MusicSearchResultDto(
            List<MusicTrackDto> tracks,
            List<MusicAlbumDto> albums,
            List<MusicArtistDto> artists
    ) {
    }

    public record MusicFavoriteRequest(boolean favorite) {
    }

    public record MusicPlayHistoryRequest(Integer playDuration) {
    }

    /** 统一音乐播放历史写入请求。 */
    public record RecordMusicPlayHistoryRequest(
            @NotBlank @Size(max = 512) String playableKey,
            @Min(0) Integer playDuration,
            @Size(max = 500) String title,
            @Size(max = 300) String artistName,
            @Size(max = 500) String albumTitle,
            @Size(max = 2048) String coverUrl,
            @Min(0) Integer durationSeconds,
            @Size(max = 255) String mediaMid
    ) {
    }

    /** 本地和在线音乐统一最近播放项。 */
    public record MusicRecentItemDto(
            String playableKey,
            MusicTrackDto localTrack,
            OnlineTrackDto onlineTrack,
            Instant playedAt
    ) {
    }

    /** 播放历史条目，覆盖本地与在线播放来源。 */
    public record MusicPlayHistoryDto(
            String playableKey,
            String title,
            String artistName,
            String albumTitle,
            String coverUrl,
            Integer durationSeconds,
            Integer playDuration,
            String platform,
            String externalSongId,
            Instant playedAt
    ) {
    }

    /** 播放队列中的稳定曲目引用和展示快照。 */
    public record MusicPlaybackQueueItemDto(
            @NotBlank @Size(max = 512) String playableKey,
            @NotBlank @Size(max = 500) String title,
            @Size(max = 300) String artistName,
            @Size(max = 500) String albumTitle,
            @Size(max = 2048) String coverUrl,
            @Min(0) Integer durationSeconds,
            @Size(max = 32) String format,
            @Size(max = 255) String mediaMid
    ) {
    }

    /** 播放队列来源引用，用于跨设备按来源重建队列。 */
    public record MusicQueueSourceDto(
            @NotNull @Pattern(regexp = "library|playlist|album|artist|transient") String kind,
            @Size(max = 64) String id,
            @Size(max = 200) String title,
            @Size(max = 4) List<@Size(max = 16) String> platforms
    ) {
    }

    /** 用户播放队列缓存响应。 */
    public record MusicPlaybackQueueDto(
            List<MusicPlaybackQueueItemDto> items,
            int currentIndex,
            String repeatMode,
            boolean shuffleEnabled,
            MusicQueueSourceDto source,
            boolean truncated,
            Instant updatedAt
    ) {
    }

    /** 保存用户播放队列的请求。 */
    public record SaveMusicPlaybackQueueRequest(
            @NotNull @Size(max = 100) List<@Valid MusicPlaybackQueueItemDto> items,
            @NotNull @Min(-1) @Max(99) Integer currentIndex,
            @NotBlank @Pattern(regexp = "off|all|one") String repeatMode,
            @NotNull Boolean shuffleEnabled,
            @Valid MusicQueueSourceDto source,
            Boolean truncated
    ) {
    }

    public record CreatePlaylistRequest(
            @NotBlank @Size(max = 300) String name,
            @Size(max = 2000) String description,
            UUID coverFileId
    ) {
    }

    public record UpdatePlaylistRequest(
            @NotBlank @Size(max = 300) String name,
            @Size(max = 2000) String description,
            UUID coverFileId
    ) {
    }

    public record MusicCoverUploadDto(UUID fileId) {
    }

    public record PlaylistItemsRequest(@NotEmpty List<UUID> trackIds) {
    }

    public record MusicScanJobDto(
            UUID id,
            String status,
            Integer progress,
            Integer scannedFiles,
            String message,
            String details,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    public record MusicScrapeCandidateDto(
            String provider,
            String externalId,
            String title,
            String artistName,
            String albumTitle,
            LocalDate releaseDate,
            Integer durationSeconds,
            Integer trackNumber,
            Integer discNumber,
            String coverUrl,
            Integer score,
            String genre,
            Map<String, Object> externalIds,
            Map<String, Object> providerMetadata
    ) {
    }

    public record MusicScrapeApplyRequest(
            @NotBlank String provider,
            @NotBlank String externalId,
            @NotBlank String title,
            @NotBlank String artistName,
            @NotBlank String albumTitle,
            LocalDate releaseDate,
            Integer durationSeconds,
            Integer trackNumber,
            Integer discNumber,
            String coverUrl,
            Integer score,
            String genre,
            Map<String, Object> externalIds,
            Map<String, Object> providerMetadata
    ) {
    }

    public record MusicScrapeRequest(boolean force) {
    }

    public record UpdateMusicTrackRequest(
            @NotBlank String title,
            String artistName,
            String albumTitle,
            String genre,
            String lyricsRaw,
            UUID coverFileId
    ) {
    }

    /** 播放位置（用于跨设备续播）。 */
    public record PlaybackPositionDto(
            UUID trackId,
            int positionSeconds
    ) {
    }

    /** 保存播放位置请求。 */
    public record SavePositionRequest(
            UUID trackId,
            int positionSeconds
    ) {
    }

    /**
     * 音乐播放进度。
     */
    public record MusicPlaybackProgressDto(
            String playableKey,
            long positionSeconds,
            long durationSeconds,
            boolean completed,
            Instant updatedAt,
            long version
    ) {
    }

    /**
     * 保存统一音乐播放进度请求。
     */
    public record SaveMusicPlaybackProgressRequest(
            @NotBlank
            @Size(max = 512)
            String playableKey,
            @Min(0)
            long positionSeconds,
            @Min(0)
            long durationSeconds,
            boolean completed,
            Instant clientUpdatedAt,
            @Size(max = 128)
            String deviceId
    ) {
    }
}
