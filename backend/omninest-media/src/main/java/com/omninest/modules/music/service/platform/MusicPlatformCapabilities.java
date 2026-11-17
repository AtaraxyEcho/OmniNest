package com.omninest.modules.music.service.platform;

import java.util.List;

/**
 * 在线音乐平台能力声明。
 *
 * @param search 是否支持歌曲搜索
 * @param playlists 是否支持账号歌单
 * @param likedTracks 是否支持喜欢歌曲
 * @param lyrics 是否支持歌词
 * @param dailyRecommendations 是否支持每日推荐歌曲
 * @param qualityLevels 支持的音质等级
 * @author OmniNest
 */
public record MusicPlatformCapabilities(
        boolean search,
        boolean playlists,
        boolean likedTracks,
        boolean lyrics,
        boolean dailyRecommendations,
        List<String> qualityLevels
) {
    /**
     * 创建不可变能力声明。
     */
    public MusicPlatformCapabilities {
        qualityLevels = qualityLevels == null ? List.of() : List.copyOf(qualityLevels);
    }
}
