package com.omninest.modules.music.dto;

import com.omninest.modules.music.service.platform.MusicPlatformCapabilities;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * 在线音乐相关 DTO 定义。
 * 包含在线搜索、播放URL、QR登录和平台用户信息等数据传输对象。
 *
 * @author OmniNest
 */
public final class OnlineMusicDtos {

    private OnlineMusicDtos() {
    }

    /**
     * 在线搜索结果曲目。
     */
    public record OnlineTrackDto(
            String platform,
            String songId,
            String title,
            String artistName,
            String albumTitle,
            String coverUrl,
            Integer durationSeconds,
            String quality,
            Map<String, Object> extra,
            String thumbUrl
    ) {
    }

    /**
     * 播放URL结果。
     */
    public record PlaybackUrlResult(
            String url,
            String quality,
            String format,
            String restriction
    ) {
    }

    /**
     * QR 登录会话。
     */
    public record QrLoginSession(
            String loginKey,
            String qrUrl,
            String qrImageBase64
    ) {
    }

    /**
     * QR 登录状态。
     */
    public record QrLoginStatus(
            String status,
            PlatformUserInfo userInfo
    ) {
    }

    /**
     * 在线平台歌单。
     */
    public record OnlinePlaylistDto(
            String platform,
            String playlistId,
            String name,
            String description,
            String coverUrl,
            Integer trackCount,
            String ownerName,
            boolean subscribed,
            Map<String, Object> extra,
            String thumbUrl
    ) {
    }

    /**
     * 外部平台每日推荐歌曲。
     *
     * @param platform 平台标识
     * @param recommendationDate 推荐所属日期
     * @param tracks 推荐歌曲
     */
    public record DailyRecommendedTracksDto(
            String platform,
            LocalDate recommendationDate,
            List<OnlineTrackDto> tracks
    ) {
        /**
         * 规范化推荐歌曲列表。
         */
        public DailyRecommendedTracksDto {
            tracks = tracks == null ? List.of() : List.copyOf(tracks);
        }
    }

    /**
     * 在线平台歌单列表载荷，用于短期缓存第三方回源结果。
     *
     * @param items 歌单列表
     */
    public record OnlinePlaylistList(List<OnlinePlaylistDto> items) {
        /**
         * 规范化歌单列表。
         */
        public OnlinePlaylistList {
            items = items == null ? List.of() : List.copyOf(items);
        }
    }

    /**
     * 在线平台曲目列表载荷，用于短期缓存第三方回源结果。
     *
     * @param items 曲目列表
     */
    public record OnlineTrackList(List<OnlineTrackDto> items) {
        /**
         * 规范化曲目列表。
         */
        public OnlineTrackList {
            items = items == null ? List.of() : List.copyOf(items);
        }
    }

    /**
     * 平台用户信息。
     */
    public record PlatformUserInfo(
            String platform,
            String userId,
            String nickname,
            String avatarUrl,
            boolean vip
    ) {
    }

    /**
     * 在线平台连接状态和能力。
     */
    public record MusicPlatformStatusDto(
            String platform,
            String displayName,
            boolean enabled,
            boolean connected,
            PlatformUserInfo userInfo,
            MusicPlatformCapabilities capabilities,
            Instant lastVerifiedAt,
            List<String> recoverableErrors
    ) {
        /**
         * 规范化可恢复错误列表。
         */
        public MusicPlatformStatusDto {
            recoverableErrors = recoverableErrors == null ? List.of() : List.copyOf(recoverableErrors);
        }
    }
}
