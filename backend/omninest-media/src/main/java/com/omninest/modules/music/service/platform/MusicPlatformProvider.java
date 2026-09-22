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
     * @return 平台标识，如 "netease"
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
     * @param mediaMid 预留的媒体 ID 扩展参数（当前平台不使用）
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
     * <p>各字段均为平台原始载荷，后端不做词级解析，格式由客户端按平台约定处理
     * （网易云逐字为 {@code yrc} 结构 {@code [行起始,行时长](词起始,词时长,0)词…}）。</p>
     *
     * <p>回退契约：平台不支持、附加接口失败或响应字段缺失时，对应字段为 {@code null}，表示"不可用"，
     * 调用方应回退到行级歌词；本记录不抛异常，也不做非空校验，所有字段都必须按可空处理。</p>
     *
     * @param plainLyrics 纯文本歌词（无独立翻译时作为译文回退），不可用时为 null
     * @param syncedLyrics 同步歌词（LRC 格式），不可用时为 null
     * @param translatedLyrics 独立翻译歌词（LRC 格式，与同步歌词按时间轴行对齐），不可用时为 null
     * @param wordLyrics 逐字歌词原始载荷（网易云 yrc），由客户端解析，不可用时为 null
     */
    record LyricsResult(
            String plainLyrics,
            String syncedLyrics,
            String translatedLyrics,
            String wordLyrics
    ) {
        public LyricsResult(String plainLyrics, String syncedLyrics) {
            this(plainLyrics, syncedLyrics, null, null);
        }

        /**
         * 含行级歌词与翻译的便捷构造，逐字标记为不可用。
         *
         * @param plainLyrics 纯文本歌词
         * @param syncedLyrics 同步歌词（LRC 格式）
         * @param translatedLyrics 独立翻译歌词（LRC 格式）
         */
        public LyricsResult(String plainLyrics, String syncedLyrics, String translatedLyrics) {
            this(plainLyrics, syncedLyrics, translatedLyrics, null);
        }
    }
}
