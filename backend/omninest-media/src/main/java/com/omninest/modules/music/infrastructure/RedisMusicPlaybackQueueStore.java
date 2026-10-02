package com.omninest.modules.music.infrastructure;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.omninest.common.json.JsonSupport;
import com.omninest.common.util.RedisUtil;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackQueueDto;
import com.omninest.modules.music.service.MusicPlaybackQueueStore;
import java.time.Duration;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 使用 Redis 保存播放队列，并在 Redis 故障时使用进程内缓存降级。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class RedisMusicPlaybackQueueStore implements MusicPlaybackQueueStore {

    private static final String KEY_PREFIX = "omninest:music:playback:queue:";
    private static final Duration CACHE_TTL = Duration.ofDays(30);
    private static final long MAX_FALLBACK_USER_COUNT = 50_000L;

    private final RedisUtil redisUtil;
    private final Cache<UUID, MusicPlaybackQueueDto> fallback = Caffeine.newBuilder()
            .expireAfterAccess(CACHE_TTL)
            .maximumSize(MAX_FALLBACK_USER_COUNT)
            .build();

    /**
     * 从 Redis 或进程内降级缓存查询播放队列。
     *
     * @param ownerUserId 所属用户标识
     * @return 播放队列快照
     */
    @Override
    public Optional<MusicPlaybackQueueDto> find(UUID ownerUserId) {
        try {
            String payload = redisUtil.get(key(ownerUserId));
            if (payload != null && !payload.isBlank()) {
                MusicPlaybackQueueDto snapshot = JsonSupport.fromJson(payload, MusicPlaybackQueueDto.class);
                fallback.put(ownerUserId, snapshot);
                return Optional.of(snapshot);
            }
        } catch (RuntimeException exception) {
            log.warn("读取音乐播放队列 Redis 缓存失败，使用进程内缓存: userId={}", ownerUserId);
        }
        return Optional.ofNullable(fallback.getIfPresent(ownerUserId));
    }

    /**
     * 将播放队列写入 Redis 和进程内降级缓存。
     *
     * @param ownerUserId 所属用户标识
     * @param snapshot 播放队列快照
     */
    @Override
    public void save(UUID ownerUserId, MusicPlaybackQueueDto snapshot) {
        fallback.put(ownerUserId, snapshot);
        try {
            redisUtil.set(key(ownerUserId), JsonSupport.toJson(snapshot), CACHE_TTL);
        } catch (RuntimeException exception) {
            log.warn("写入音乐播放队列 Redis 缓存失败，保留进程内缓存: userId={}", ownerUserId);
        }
    }

    private String key(UUID ownerUserId) {
        return KEY_PREFIX + ownerUserId;
    }
}
