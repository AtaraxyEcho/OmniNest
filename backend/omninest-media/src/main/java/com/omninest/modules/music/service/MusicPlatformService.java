package com.omninest.modules.music.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.music.dto.OnlineMusicDtos.DailyRecommendedTracksDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlinePlaylistDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlineTrackDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlaybackUrlResult;
import com.omninest.modules.music.service.platform.MusicPlatform;
import com.omninest.modules.music.service.platform.MusicPlatformProvider;
import java.time.Duration;
import java.time.LocalDate;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 聚合在线音乐内容并统一执行用户隔离和平台白名单校验。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicPlatformService {
    private static final String DAILY_RECOMMENDATION_CACHE_PREFIX =
            "omninest:music:recommendation:daily:";

    private final List<MusicPlatformProvider> providers;
    private final MusicRuntimeConfigService configService;
    private final ReadThroughCache readThroughCache;

    /**
     * 跨已启用平台搜索在线曲目。
     *
     * @param ownerUserId 当前用户 ID
     * @param keyword 搜索关键词
     * @param limit 每个平台返回数量上限
     * @return 去重后的在线曲目
     */
    public List<OnlineTrackDto> search(UUID ownerUserId, String keyword, int limit) {
        List<OnlineTrackDto> allResults = new ArrayList<>();
        for (MusicPlatformProvider provider : enabledProviders()) {
            if (!provider.capabilities().search()) {
                continue;
            }
            try {
                allResults.addAll(provider.search(ownerUserId, keyword, limit));
            } catch (RuntimeException exception) {
                log.warn(
                        "在线音乐平台搜索失败: userId={}, platform={}, message={}",
                        ownerUserId,
                        provider.platform().apiValue(),
                        exception.getMessage()
                );
            }
        }
        return deduplicate(allResults);
    }

    /**
     * 在指定平台搜索在线曲目。
     *
     * @param ownerUserId 当前用户 ID
     * @param keyword 搜索关键词
     * @param limit 返回数量上限
     * @param platformValue 平台 API 标识
     * @return 在线曲目
     */
    public List<OnlineTrackDto> search(
            UUID ownerUserId,
            String keyword,
            int limit,
            String platformValue
    ) {
        MusicPlatformProvider provider = requireEnabledProvider(platformValue);
        if (!provider.capabilities().search()) {
            return List.of();
        }
        return provider.search(ownerUserId, keyword, limit);
    }

    /**
     * 获取指定平台的播放地址。
     *
     * @param ownerUserId 当前用户 ID
     * @param platformValue 平台 API 标识
     * @param songId 平台曲目 ID
     * @param mediaMid 预留的媒体 ID 扩展参数（当前平台不使用）
     * @param quality 请求音质
     * @return 播放地址结果
     */
    public PlaybackUrlResult getPlaybackUrl(
            UUID ownerUserId,
            String platformValue,
            String songId,
            String mediaMid,
            String quality
    ) {
        MusicPlatformProvider provider = requireEnabledProvider(platformValue);
        if (!provider.isLoggedIn(ownerUserId)) {
            return new PlaybackUrlResult(
                    null,
                    null,
                    null,
                    "未登录，请先登录" + provider.platform().displayName()
            );
        }
        return provider.getPlaybackUrl(ownerUserId, songId, mediaMid, quality);
    }

    /**
     * 获取指定平台的歌词。
     *
     * @param ownerUserId 当前用户 ID
     * @param platformValue 平台 API 标识
     * @param songId 平台曲目 ID
     * @return 歌词结果
     */
    public MusicPlatformProvider.LyricsResult getLyrics(
            UUID ownerUserId,
            String platformValue,
            String songId
    ) {
        MusicPlatformProvider provider = requireEnabledProvider(platformValue);
        if (!provider.capabilities().lyrics()) {
            return new MusicPlatformProvider.LyricsResult(null, null);
        }
        return provider.getLyrics(ownerUserId, songId);
    }

    /**
     * 获取当前用户的指定平台歌单。
     *
     * @param ownerUserId 当前用户 ID
     * @param platformValue 平台 API 标识
     * @return 平台歌单
     */
    public List<OnlinePlaylistDto> playlists(UUID ownerUserId, String platformValue) {
        MusicPlatformProvider provider = requireConnectedProvider(ownerUserId, platformValue);
        if (!provider.capabilities().playlists()) {
            return List.of();
        }
        return provider.playlists(ownerUserId);
    }

    /**
     * 获取指定平台歌单的曲目。
     *
     * @param ownerUserId 当前用户 ID
     * @param platformValue 平台 API 标识
     * @param playlistId 平台歌单 ID
     * @return 在线曲目
     */
    public List<OnlineTrackDto> playlistTracks(
            UUID ownerUserId,
            String platformValue,
            String playlistId
    ) {
        MusicPlatformProvider provider = requireConnectedProvider(ownerUserId, platformValue);
        if (!provider.capabilities().playlists()) {
            return List.of();
        }
        return provider.playlistTracks(ownerUserId, playlistId);
    }

    /**
     * 获取当前用户在指定平台喜欢的曲目。
     *
     * @param ownerUserId 当前用户 ID
     * @param platformValue 平台 API 标识
     * @return 喜欢曲目
     */
    public List<OnlineTrackDto> likedTracks(UUID ownerUserId, String platformValue) {
        MusicPlatformProvider provider = requireConnectedProvider(ownerUserId, platformValue);
        if (!provider.capabilities().likedTracks()) {
            return List.of();
        }
        return provider.likedTracks(ownerUserId);
    }

    /**
     * 获取当前用户在指定平台的每日推荐歌曲。
     *
     * @param ownerUserId 当前用户 ID
     * @param platformValue 平台 API 标识
     * @return 每日推荐歌曲及所属日期
     */
    public DailyRecommendedTracksDto dailyRecommendedTracks(
            UUID ownerUserId,
            String platformValue
    ) {
        MusicPlatformProvider provider = requireConnectedProvider(ownerUserId, platformValue);
        if (!provider.capabilities().dailyRecommendations()) {
            throw new BusinessException(
                    ErrorCode.BAD_REQUEST,
                    provider.platform().displayName() + "不支持每日推荐歌曲"
            );
        }
        LocalDate recommendationDate = LocalDate.now();
        String cacheKey = dailyRecommendationCacheKey(
                ownerUserId,
                provider.platform(),
                recommendationDate
        );
        DailyRecommendedTracksDto cached = readThroughCache.getOrLoad(
                cacheKey,
                dailyRecommendationCacheTtl(),
                () -> loadDailyRecommendation(provider, ownerUserId, recommendationDate),
                DailyRecommendedTracksDto.class
        );
        if (cached != null) {
            return cached;
        }
        return new DailyRecommendedTracksDto(
                provider.platform().apiValue(),
                recommendationDate,
                List.of()
        );
    }

    /**
     * 使当前用户当天的指定平台每日推荐缓存失效。
     *
     * @param ownerUserId 当前用户 ID
     * @param platformValue 平台 API 标识
     */
    public void invalidateDailyRecommendations(UUID ownerUserId, String platformValue) {
        MusicPlatform platform = MusicPlatform.fromApiValue(platformValue);
        String cacheKey = dailyRecommendationCacheKey(ownerUserId, platform, LocalDate.now());
        try {
            readThroughCache.invalidate(cacheKey);
        } catch (RuntimeException exception) {
            log.warn(
                    "清理音乐每日推荐缓存失败: userId={}, platform={}",
                    ownerUserId,
                    platform.apiValue()
            );
        }
    }

    private MusicPlatformProvider requireConnectedProvider(UUID ownerUserId, String platformValue) {
        MusicPlatformProvider provider = requireEnabledProvider(platformValue);
        if (!provider.isLoggedIn(ownerUserId)) {
            throw new BusinessException(
                    ErrorCode.BAD_REQUEST,
                    "请先连接" + provider.platform().displayName()
            );
        }
        return provider;
    }

    private MusicPlatformProvider requireEnabledProvider(String platformValue) {
        MusicPlatformProvider provider = getProvider(MusicPlatform.fromApiValue(platformValue));
        if (!isPlatformEnabled(provider)) {
            throw new BusinessException(
                    ErrorCode.BAD_REQUEST,
                    provider.platform().displayName() + "平台未启用"
            );
        }
        return provider;
    }

    private MusicPlatformProvider getProvider(MusicPlatform platform) {
        return providers.stream()
                .filter(provider -> provider.platform() == platform)
                .findFirst()
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.NOT_FOUND,
                        "音乐平台未注册: " + platform.apiValue()
                ));
    }

    private List<MusicPlatformProvider> enabledProviders() {
        if (!configService.onlineEnabled()) {
            return List.of();
        }
        return providers.stream().filter(this::isPlatformEnabled).toList();
    }

    private boolean isPlatformEnabled(MusicPlatformProvider provider) {
        if (!configService.onlineEnabled()) {
            return false;
        }
        return switch (provider.platform()) {
            case NETEASE -> configService.neteaseEnabled();
        };
    }

    private List<OnlineTrackDto> deduplicate(List<OnlineTrackDto> tracks) {
        Set<String> seen = new HashSet<>();
        List<OnlineTrackDto> deduplicated = new ArrayList<>();
        for (OnlineTrackDto track : tracks) {
            String key = track.platform() + ":" + track.songId();
            if (seen.add(key)) {
                deduplicated.add(track);
            }
        }
        return deduplicated;
    }

    private DailyRecommendedTracksDto loadDailyRecommendation(
            MusicPlatformProvider provider,
            UUID ownerUserId,
            LocalDate recommendationDate
    ) {
        List<OnlineTrackDto> tracks = deduplicate(provider.dailyRecommendedTracks(ownerUserId));
        if (tracks.isEmpty()) {
            return null;
        }
        return new DailyRecommendedTracksDto(
                provider.platform().apiValue(),
                recommendationDate,
                tracks
        );
    }

    private String dailyRecommendationCacheKey(
            UUID ownerUserId,
            MusicPlatform platform,
            LocalDate recommendationDate
    ) {
        return DAILY_RECOMMENDATION_CACHE_PREFIX
                + ownerUserId
                + ":"
                + platform.apiValue()
                + ":"
                + recommendationDate;
    }

    private Duration dailyRecommendationCacheTtl() {
        ZonedDateTime now = ZonedDateTime.now();
        ZonedDateTime nextDay = now.toLocalDate().plusDays(1).atStartOfDay(now.getZone());
        Duration remaining = Duration.between(now, nextDay);
        return remaining.isNegative() || remaining.isZero() ? Duration.ofMinutes(5) : remaining;
    }
}
