package com.omninest.modules.music.service.platform;

import com.omninest.modules.music.dto.OnlineMusicDtos.OnlinePlaylistDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlineTrackDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlaybackUrlResult;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlatformUserInfo;
import java.util.List;
import java.util.UUID;

/**
 * 音乐平台提供者接口。
 * 定义在线音乐平台的统一抽象，支持搜索、播放、歌词获取和登录状态管理。
 * 各平台（网易云、QQ音乐）实现此接口。
 *
 * @author OmniNest
 */
public interface MusicPlatformProvider {

    /**
     * 平台名称标识。
     *
     * @return 平台标识，如 "netease" 或 "qq"
     */
    MusicPlatform platform();

    /**
     * 获取平台能力声明。
     *
     * @return 平台能力
     */
    MusicPlatformCapabilities capabilities();

    /**
     * 搜索在线曲目。
     *
     * @param ownerUserId 当前用户 ID
     * @param keyword 搜索关键词
     * @param limit   返回数量上限
     * @return 搜索结果列表
     */
    List<OnlineTrackDto> search(UUID ownerUserId, String keyword, int limit);

    /**
     * 获取播放URL（含音质探测）。
     *
     * @param ownerUserId 当前用户 ID
     * @param songId   平台歌曲ID
     * @param mediaMid 媒体ID（QQ音乐专用）
     * @param quality  请求音质等级
     * @return 播放URL结果
     */
    PlaybackUrlResult getPlaybackUrl(UUID ownerUserId, String songId, String mediaMid, String quality);

    /**
     * 获取歌词。
     *
     * @param ownerUserId 当前用户 ID
     * @param songId 平台歌曲ID
     * @return 歌词结果（纯文本和同步歌词）
     */
    LyricsResult getLyrics(UUID ownerUserId, String songId);

    /**
     * 获取当前用户的平台歌单。
     *
     * @param ownerUserId 当前用户 ID
     * @return 平台歌单
     */
    List<OnlinePlaylistDto> playlists(UUID ownerUserId);

    /**
     * 获取平台歌单曲目。
     *
     * @param ownerUserId 当前用户 ID
     * @param playlistId 平台歌单 ID
     * @return 在线曲目
     */
    List<OnlineTrackDto> playlistTracks(UUID ownerUserId, String playlistId);

    /**
     * 获取当前用户喜欢的曲目。
     *
     * @param ownerUserId 当前用户 ID
     * @return 喜欢曲目
     */
    List<OnlineTrackDto> likedTracks(UUID ownerUserId);

    /**
     * 获取当前用户的每日推荐歌曲。
     *
     * @param ownerUserId 当前用户 ID
     * @return 每日推荐歌曲
     */
    default List<OnlineTrackDto> dailyRecommendedTracks(UUID ownerUserId) {
        return List.of();
    }

    /**
     * 检查是否已登录该平台。
     *
     * @param ownerUserId 当前用户 ID
     * @return 已登录返回 true
     */
    boolean isLoggedIn(UUID ownerUserId);

    /**
     * 获取当前登录用户信息。
     *
     * @param ownerUserId 当前用户 ID
     * @return 用户信息，未登录时返回默认/空信息
     */
    PlatformUserInfo getUserInfo(UUID ownerUserId);

    /**
     * 清除登录状态。
     *
     * @param ownerUserId 当前用户 ID
     */
    void clearLogin(UUID ownerUserId);

    /**
     * 歌词结果。
     *
     * @param plainLyrics 纯文本歌词（无独立翻译时作为译文回退）
     * @param syncedLyrics 同步歌词（LRC 格式）
     * @param translatedLyrics 独立翻译歌词，与同步歌词按时间轴行对齐
     */
    record LyricsResult(String plainLyrics, String syncedLyrics, String translatedLyrics) {
        public LyricsResult(String plainLyrics, String syncedLyrics) {
            this(plainLyrics, syncedLyrics, null);
        }
    }
}
