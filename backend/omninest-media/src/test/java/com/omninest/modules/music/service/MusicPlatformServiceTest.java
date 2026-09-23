package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.api.PageResponse;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.music.dto.OnlineMusicDtos.DailyRecommendedTracksDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlinePlaylistDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlineTrackDto;
import com.omninest.modules.music.service.platform.MusicPlatform;
import com.omninest.modules.music.service.platform.MusicPlatformCapabilities;
import com.omninest.modules.music.service.platform.MusicPlatformProvider;
import com.omninest.modules.music.service.platform.NeteaseMusicProxy;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Supplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;

/**
 * 在线音乐平台聚合服务测试。
 *
 * @author OmniNest
 */
class MusicPlatformServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final NeteaseMusicProxy neteaseProvider = mock(NeteaseMusicProxy.class);
    private final MusicRuntimeConfigService configService = mock(MusicRuntimeConfigService.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class);
    private final MusicPlatformService service = new MusicPlatformService(
            List.of(neteaseProvider),
            configService,
            readThroughCache
    );

    @BeforeEach
    void setUp() {
        when(neteaseProvider.platform()).thenReturn(MusicPlatform.NETEASE);
        when(neteaseProvider.capabilities()).thenReturn(new MusicPlatformCapabilities(
                true,
                true,
                true,
                true,
                true,
                List.of("lossless")
        ));
        when(configService.onlineEnabled()).thenReturn(true);
        when(configService.neteaseEnabled()).thenReturn(true);
        when(readThroughCache.getOrLoad(
                ArgumentMatchers.anyString(),
                ArgumentMatchers.any(),
                ArgumentMatchers.any(),
                ArgumentMatchers.any()
        )).thenAnswer(invocation -> {
            Supplier<?> loader = invocation.getArgument(2);
            return loader.get();
        });
    }

    @Test
    void searchPropagatesCurrentUserToProvider() {
        OnlineTrackDto track = onlineTrack("song-1");
        when(neteaseProvider.search(OWNER_ID, "song", 20)).thenReturn(List.of(track));

        List<OnlineTrackDto> result = service.search(OWNER_ID, "song", 20);

        assertThat(result).containsExactly(track);
        verify(neteaseProvider).search(OWNER_ID, "song", 20);
    }

    @Test
    void playlistsPropagateCurrentUserAndPlatformIdentifier() {
        OnlinePlaylistDto playlist = new OnlinePlaylistDto(
                "netease",
                "playlist-1",
                "Favorites",
                null,
                null,
                20,
                "Music User",
                false,
                null,
                null
        );
        when(neteaseProvider.isLoggedIn(OWNER_ID)).thenReturn(true);
        when(neteaseProvider.playlists(OWNER_ID)).thenReturn(List.of(playlist));

        PageResponse<OnlinePlaylistDto> page = service.playlists(OWNER_ID, "netease", 0, 100);

        assertThat(page.items()).containsExactly(playlist);
        assertThat(page.totalElements()).isEqualTo(1);

        verify(neteaseProvider).playlists(OWNER_ID);
    }

    @Test
    void playlistTrackPageDefaultsToTheWholeCachedList() {
        // 不传 size 的旧客户端必须仍然拿到整表，分页只作为新客户端的载荷优化。
        InMemoryLibraryCache cache = new InMemoryLibraryCache();
        MusicPlatformService cachedService = new MusicPlatformService(
                List.of(neteaseProvider),
                configService,
                cache
        );
        when(neteaseProvider.isLoggedIn(OWNER_ID)).thenReturn(true);
        when(neteaseProvider.playlistTracks(OWNER_ID, "playlist-1")).thenReturn(List.of(
                onlineTrack("first"),
                onlineTrack("second")
        ));

        PageResponse<OnlineTrackDto> page = cachedService.playlistTracks(
                OWNER_ID,
                "netease",
                "playlist-1",
                0,
                1000
        );

        assertThat(page.items()).extracting(OnlineTrackDto::songId)
                .containsExactly("first", "second");
        assertThat(page.totalElements()).isEqualTo(2);
    }

    @Test
    void accountListsSliceTheCachedListWithoutRefetching() {
        InMemoryLibraryCache cache = new InMemoryLibraryCache();
        MusicPlatformService cachedService = new MusicPlatformService(
                List.of(neteaseProvider),
                configService,
                cache
        );
        when(neteaseProvider.isLoggedIn(OWNER_ID)).thenReturn(true);
        when(neteaseProvider.likedTracks(OWNER_ID)).thenReturn(List.of(
                onlineTrack("liked-1"),
                onlineTrack("liked-2"),
                onlineTrack("liked-3")
        ));

        PageResponse<OnlineTrackDto> first = cachedService.likedTracks(OWNER_ID, "netease", 0, 2);
        PageResponse<OnlineTrackDto> second = cachedService.likedTracks(OWNER_ID, "netease", 1, 2);
        PageResponse<OnlineTrackDto> beyond = cachedService.likedTracks(OWNER_ID, "netease", 2, 2);

        assertThat(first.items()).extracting(OnlineTrackDto::songId).containsExactly("liked-1", "liked-2");
        assertThat(first.totalElements()).isEqualTo(3);
        assertThat(second.items()).extracting(OnlineTrackDto::songId).containsExactly("liked-3");
        assertThat(second.totalElements()).isEqualTo(3);
        assertThat(beyond.items()).isEmpty();
        assertThat(beyond.totalElements()).isEqualTo(3);
        // 分页只切分已缓存的全量列表，不增加第三方回源次数。
        verify(neteaseProvider).likedTracks(OWNER_ID);
    }

    private static OnlineTrackDto onlineTrack(String songId) {
        return new OnlineTrackDto(
                "netease",
                songId,
                "Song",
                "Artist",
                "Album",
                null,
                180,
                null,
                null,
                null
        );
    }

    @Test
    void accountLibraryIsCachedPerOwnerAndEvictedOnRebind() {
        InMemoryLibraryCache cache = new InMemoryLibraryCache();
        MusicPlatformService cachedService = new MusicPlatformService(
                List.of(neteaseProvider),
                configService,
                cache
        );
        OnlinePlaylistDto playlist = new OnlinePlaylistDto(
                "netease",
                "playlist-1",
                "Favorites",
                null,
                null,
                20,
                "Music User",
                false,
                null,
                null
        );
        when(neteaseProvider.isLoggedIn(OWNER_ID)).thenReturn(true);
        when(neteaseProvider.playlists(OWNER_ID)).thenReturn(List.of(playlist));

        assertThat(cachedService.playlists(OWNER_ID, "netease", 0, 100).items())
                .containsExactly(playlist);
        assertThat(cachedService.playlists(OWNER_ID, "netease", 0, 100).items())
                .containsExactly(playlist);

        // 命中缓存不再打第三方接口，键按用户与平台归属。
        verify(neteaseProvider).playlists(OWNER_ID);
        assertThat(cache.loadedKeys()).containsExactly(
                "omninest:music:playlists:" + OWNER_ID + ":netease"
        );

        MusicPlatformLibraryCache.evict(cache, OWNER_ID, MusicPlatform.NETEASE);

        assertThat(cachedService.playlists(OWNER_ID, "netease", 0, 100).items())
                .containsExactly(playlist);
        verify(neteaseProvider, Mockito.times(2)).playlists(OWNER_ID);
        assertThat(cache.loadedKeys()).hasSize(2);
    }

    @Test
    void playlistTracksCacheKeepsPlaylistsApart() {
        InMemoryLibraryCache cache = new InMemoryLibraryCache();
        MusicPlatformService cachedService = new MusicPlatformService(
                List.of(neteaseProvider),
                configService,
                cache
        );
        when(neteaseProvider.isLoggedIn(OWNER_ID)).thenReturn(true);
        when(neteaseProvider.playlistTracks(ArgumentMatchers.eq(OWNER_ID), ArgumentMatchers.anyString()))
                .thenReturn(List.of());

        cachedService.playlistTracks(OWNER_ID, "netease", "playlist-1", 0, 50);
        cachedService.playlistTracks(OWNER_ID, "netease", "playlist-1", 0, 50);
        cachedService.playlistTracks(OWNER_ID, "netease", "playlist-2", 0, 50);

        assertThat(cache.loadedKeys()).containsExactly(
                "omninest:music:playlist-tracks:" + OWNER_ID + ":netease:playlist-1",
                "omninest:music:playlist-tracks:" + OWNER_ID + ":netease:playlist-2"
        );
    }

    @Test
    void unsupportedPlatformIsRejectedByWhitelist() {
        assertThatThrownBy(() -> service.search(OWNER_ID, "song", 20, "unknown"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不支持的音乐平台");
    }

    @Test
    void lyricsDoNotReusePlatformSpecificSongIdAcrossProviders() {
        MusicPlatformProvider.LyricsResult lyrics = new MusicPlatformProvider.LyricsResult(null, null);
        when(neteaseProvider.getLyrics(OWNER_ID, "song-1")).thenReturn(lyrics);

        assertThat(service.getLyrics(OWNER_ID, "netease", "song-1")).isEqualTo(lyrics);

        verify(neteaseProvider).getLyrics(OWNER_ID, "song-1");
    }

    @Test
    void dailyRecommendationRequiresConnectionAndUsesCurrentUser() {
        OnlineTrackDto track = new OnlineTrackDto(
                "netease",
                "daily-1",
                "Daily Song",
                "Daily Artist",
                "Daily Album",
                null,
                200,
                null,
                null,
                null
        );
        when(neteaseProvider.isLoggedIn(OWNER_ID)).thenReturn(true);
        when(neteaseProvider.dailyRecommendedTracks(OWNER_ID)).thenReturn(List.of(track));

        DailyRecommendedTracksDto result = service.dailyRecommendedTracks(OWNER_ID, "netease");

        assertThat(result.platform()).isEqualTo("netease");
        assertThat(result.tracks()).containsExactly(track);
        verify(neteaseProvider).dailyRecommendedTracks(OWNER_ID);
    }


    /**
     * 记录回源键的最小读通缓存替身，用于断言命中缓存后不再打第三方接口。
     */
    private static final class InMemoryLibraryCache implements ReadThroughCache {
        private final Map<String, Object> values = new HashMap<>();
        private final List<String> loadedKeys = new ArrayList<>();

        @Override
        public boolean invalidate(String key) {
            return values.remove(key) != null;
        }

        @Override
        @SuppressWarnings("unchecked")
        public <T> T getOrLoad(String key, Duration ttl, Supplier<T> loader, Class<T> type) {
            if (values.containsKey(key)) {
                return (T) values.get(key);
            }
            T value = loader.get();
            loadedKeys.add(key);
            if (value != null) {
                values.put(key, value);
            }
            return value;
        }

        @Override
        public void evictPattern(String pattern) {
            String prefix = pattern.endsWith("*")
                    ? pattern.substring(0, pattern.length() - 1)
                    : pattern;
            values.keySet().removeIf(key -> key.startsWith(prefix));
        }

        private List<String> loadedKeys() {
            return List.copyOf(loadedKeys);
        }
    }
}
