package com.omninest.common.config;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.ScanOptions;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

/**
 * 使用 Redis 保存运行时配置缓存，并在进程内保留短 TTL 读缓存。
 *
 * <p>本地层消除在线请求路径上对几乎不变配置的重复 Redis 往返；TTL 短于
 * Redis 层，配置热更新 fanout（{@link ConfigRefreshConsumer}）会同时清除两层。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class RedisRuntimeConfigCache implements RuntimeConfigCache {

    private static final String KEY_PREFIX = "omninest:config:";
    private static final Duration TTL = Duration.ofMinutes(5);
    private static final Duration LOCAL_TTL = Duration.ofSeconds(45);

    /** 进程内配置缓存容量上限；配置键数量有限，超出时淘汰最早过期条目。 */
    private static final int LOCAL_CACHE_MAX_ENTRIES = 512;

    private final StringRedisTemplate redisTemplate;
    private final ConcurrentHashMap<String, LocalEntry> localCache = new ConcurrentHashMap<>();

    private record LocalEntry(String value, long expireAtMillis) {
        private boolean expired() {
            return System.currentTimeMillis() >= expireAtMillis;
        }
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public Optional<String> get(String key) {
        LocalEntry local = localCache.get(key);
        if (local != null) {
            if (!local.expired()) {
                return Optional.ofNullable(local.value());
            }
            localCache.remove(key, local);
        }
        try {
            String value = redisTemplate.opsForValue().get(KEY_PREFIX + key);
            if (value != null) {
                localCache.put(key, new LocalEntry(value, System.currentTimeMillis() + LOCAL_TTL.toMillis()));
                evictLocalIfNeeded();
            }
            return Optional.ofNullable(value);
        } catch (RuntimeException exception) {
            log.warn("读取配置缓存失败: key={}", key, exception);
            return Optional.empty();
        }
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void put(String key, String value) {
        localCache.put(key, new LocalEntry(value, System.currentTimeMillis() + LOCAL_TTL.toMillis()));
        evictLocalIfNeeded();
        try {
            redisTemplate.opsForValue().set(KEY_PREFIX + key, value, TTL);
        } catch (RuntimeException exception) {
            log.warn("写入配置缓存失败: key={}", key, exception);
        }
    }

    private void evictLocalIfNeeded() {
        if (localCache.size() <= LOCAL_CACHE_MAX_ENTRIES) {
            return;
        }
        localCache.entrySet().removeIf(entry -> entry.getValue().expired());
        if (localCache.size() <= LOCAL_CACHE_MAX_ENTRIES) {
            return;
        }
        localCache.entrySet().stream()
                .sorted((a, b) -> Long.compare(a.getValue().expireAtMillis, b.getValue().expireAtMillis))
                .limit(localCache.size() - LOCAL_CACHE_MAX_ENTRIES)
                .map(entry -> entry.getKey())
                .toList()
                .forEach(localCache::remove);
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void evict(String key) {
        localCache.remove(key);
        try {
            redisTemplate.delete(KEY_PREFIX + key);
            log.debug("已清除配置缓存: key={}", key);
        } catch (RuntimeException exception) {
            log.warn("清除配置缓存失败: key={}", key, exception);
        }
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void evictAll() {
        localCache.clear();
        try {
            ScanOptions options = ScanOptions.scanOptions()
                    .match(KEY_PREFIX + "*")
                    .count(100)
                    .build();
            List<String> keysToDelete = new ArrayList<>();
            try (var cursor = redisTemplate.scan(options)) {
                cursor.forEachRemaining(keysToDelete::add);
            }
            if (!keysToDelete.isEmpty()) {
                redisTemplate.delete(keysToDelete);
                log.info("已清除全部配置缓存: count={}", keysToDelete.size());
            }
        } catch (RuntimeException exception) {
            log.warn("清除全部配置缓存失败", exception);
        }
    }
}
