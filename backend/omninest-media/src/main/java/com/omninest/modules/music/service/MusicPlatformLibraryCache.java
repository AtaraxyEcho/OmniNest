package com.omninest.modules.music.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.music.service.platform.MusicPlatform;
import java.util.UUID;

/**
 * 音乐平台只读回源缓存的键定义：歌单、歌单曲目、喜欢列表与每日推荐都按用户和平台归属。
 *
 * <p>键前缀由回源方和失效方共享：凭据保存（登录、换绑）与清除时必须整体失效，
 * 否则新账号会沿用上一账号的内容直到缓存自然过期。</p>
 *
 * @author OmniNest
 */
final class MusicPlatformLibraryCache {
    static final String DAILY_RECOMMENDATION_PREFIX = "omninest:music:recommendation:daily:";
    static final String PLAYLIST_PREFIX = "omninest:music:playlists:";
    static final String PLAYLIST_TRACKS_PREFIX = "omninest:music:playlist-tracks:";
    static final String LIKED_TRACKS_PREFIX = "omninest:music:liked-tracks:";

    private MusicPlatformLibraryCache() {
    }

    /**
     * 用户平台歌单列表的缓存键。
     *
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     * @return 缓存键
     */
    static String playlists(UUID ownerUserId, MusicPlatform platform) {
        return PLAYLIST_PREFIX + owner(ownerUserId, platform);
    }

    /**
     * 单个平台歌单曲目的缓存键。
     *
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     * @param playlistId 平台歌单 ID
     * @return 缓存键
     */
    static String playlistTracks(UUID ownerUserId, MusicPlatform platform, String playlistId) {
        return PLAYLIST_TRACKS_PREFIX + owner(ownerUserId, platform) + ":" + playlistId;
    }

    /**
     * 用户平台喜欢列表的缓存键。
     *
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     * @return 缓存键
     */
    static String likedTracks(UUID ownerUserId, MusicPlatform platform) {
        return LIKED_TRACKS_PREFIX + owner(ownerUserId, platform);
    }

    /**
     * 用户平台每日推荐的缓存键，日期由调用方追加。
     *
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     * @return 不含日期的缓存键前缀
     */
    static String dailyRecommendations(UUID ownerUserId, MusicPlatform platform) {
        return DAILY_RECOMMENDATION_PREFIX + owner(ownerUserId, platform) + ":";
    }

    /**
     * 清理该用户在指定平台的全部只读回源缓存。
     *
     * @param cache 读通缓存
     * @param ownerUserId 所属用户 ID
     * @param platform 平台
     */
    static void evict(ReadThroughCache cache, UUID ownerUserId, MusicPlatform platform) {
        cache.evictPattern(playlists(ownerUserId, platform));
        cache.evictPattern(PLAYLIST_TRACKS_PREFIX + owner(ownerUserId, platform) + ":*");
        cache.evictPattern(likedTracks(ownerUserId, platform));
        cache.evictPattern(dailyRecommendations(ownerUserId, platform) + "*");
    }

    private static String owner(UUID ownerUserId, MusicPlatform platform) {
        return ownerUserId + ":" + platform.apiValue();
    }
}
