package com.omninest.common.util;

import com.alibaba.fastjson2.JSON;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.concurrency.DistributedLock;
import com.omninest.common.security.ExpiringOwnershipRegistry;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.function.Supplier;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.ScanOptions;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Component;

/**
 * Redis 常用操作工具，统一封装字符串值、过期时间、计数和轻量锁操作。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class RedisUtil implements ReadThroughCache, DistributedLock, ExpiringOwnershipRegistry {
    public static final String UNLOCK_SCRIPT = """
            if redis.call('get', KEYS[1]) == ARGV[1] then
              return redis.call('del', KEYS[1])
            end
            return 0
            """;

    private final StringRedisTemplate redisTemplate;
    private final DefaultRedisScript<Long> unlockScript = new DefaultRedisScript<>(UNLOCK_SCRIPT, Long.class);

    /**
     * 同键回源单飞表：并发未命中时只允许一个加载在途，其余调用复用其结果。
     */
    private final ConcurrentMap<String, CompletableFuture<?>> loading = new ConcurrentHashMap<>();

    /**
     * 等待他机线程回源结果的上限，覆盖第三方接口的最坏往返；超过即按失败处理，
     * 避免等待方被挂死的加载无限占用。
     */
    private static final Duration SINGLE_FLIGHT_WAIT = Duration.ofSeconds(30);

    public void set(String key, String value) {
        redisTemplate.opsForValue().set(key, value);
    }

    public void set(String key, String value, Duration ttl) {
        validateTtl(ttl);
        redisTemplate.opsForValue().set(key, value, ttl);
    }

    public String get(String key) {
        return redisTemplate.opsForValue().get(key);
    }

    public boolean hasKey(String key) {
        return Boolean.TRUE.equals(redisTemplate.hasKey(key));
    }

    public boolean delete(String key) {
        return Boolean.TRUE.equals(redisTemplate.delete(key));
    }

    /**
     * 使指定缓存项失效。
     *
     * @param key 缓存键
     * @return 缓存项存在并被删除时返回 true
     */
    @Override
    public boolean invalidate(String key) {
        return delete(key);
    }

    /**
     * 登记带有效期的资源所有者。
     *
     * @param resourceKey 资源键
     * @param ownerUserId 所属用户标识
     * @param ttl 归属关系有效期
     */
    @Override
    public void register(String resourceKey, UUID ownerUserId, Duration ttl) {
        set(resourceKey, ownerUserId.toString(), ttl);
    }

    /**
     * 查询资源键的所有者。
     *
     * @param resourceKey 资源键
     * @return 所属用户标识，不存在或记录无效时返回空
     */
    @Override
    public Optional<UUID> findOwner(String resourceKey) {
        String ownerValue = get(resourceKey);
        if (ownerValue == null || ownerValue.isBlank()) {
            return Optional.empty();
        }
        try {
            return Optional.of(UUID.fromString(ownerValue));
        } catch (IllegalArgumentException exception) {
            log.warn("临时所有权记录格式无效: key={}", resourceKey);
            return Optional.empty();
        }
    }

    /**
     * 删除资源键的所有权记录。
     *
     * @param resourceKey 资源键
     */
    @Override
    public void remove(String resourceKey) {
        delete(resourceKey);
    }

    public boolean expire(String key, Duration ttl) {
        validateTtl(ttl);
        return Boolean.TRUE.equals(redisTemplate.expire(key, ttl));
    }

    public long increment(String key, long delta) {
        Long value = redisTemplate.opsForValue().increment(key, delta);
        return value == null ? 0L : value;
    }

    public String newLockToken() {
        return UUID.randomUUID().toString();
    }

    /**
     * 创建分布式锁令牌。
     *
     * @return 唯一令牌
     */
    @Override
    public String newToken() {
        return newLockToken();
    }

    @Override
    public boolean tryLock(String key, String token, Duration ttl) {
        validateTtl(ttl);
        return Boolean.TRUE.equals(redisTemplate.opsForValue().setIfAbsent(key, token, ttl));
    }

    @Override
    public boolean unlock(String key, String token) {
        Long removed = redisTemplate.execute(unlockScript, List.of(key), token);
        return Long.valueOf(1L).equals(removed);
    }

    /**
     * 缓存旁路模式：先查缓存，miss 时执行 loader 并写入缓存；同一键的并发 miss 只回源一次。
     */
    @Override
    public <T> T getOrLoad(String key, Duration ttl, Supplier<T> loader, Class<T> type) {
        try {
            String cached = get(key);
            if (cached != null) {
                try {
                    return JSON.parseObject(cached, type);
                } catch (Exception ex) {
                    log.warn("缓存解析失败，回退到数据源: key={}", key, ex);
                }
            }
        } catch (Exception ex) {
            log.warn("读取缓存失败: key={}", key, ex);
        }

        return loadOnce(key, ttl, loader, type);
    }

    /**
     * 执行或加入一次回源。
     *
     * <p>抢到单飞位的调用执行 loader，完成后再释放单飞位并回填缓存；没抢到的调用直接等待在途
     * 结果。在途异常按原运行时异常抛给等待方，保持调用方的错误映射不变；加载失败不写缓存。
     */
    private <T> T loadOnce(String key, Duration ttl, Supplier<T> loader, Class<T> type) {
        CompletableFuture<T> future = new CompletableFuture<>();
        CompletableFuture<?> inFlight = loading.putIfAbsent(key, future);
        if (inFlight != null) {
            return type.cast(awaitInFlight(key, inFlight));
        }

        T value;
        try {
            value = loader.get();
            future.complete(value);
        } catch (RuntimeException | Error exception) {
            future.completeExceptionally(exception);
            throw exception;
        } finally {
            loading.remove(key, future);
        }
        if (value != null) {
            try {
                set(key, JSON.toJSONString(value), ttl);
            } catch (Exception ex) {
                log.warn("写入缓存失败: key={}", key, ex);
            }
        }
        return value;
    }

    private Object awaitInFlight(String key, CompletableFuture<?> inFlight) {
        try {
            return inFlight.get(SINGLE_FLIGHT_WAIT.toMillis(), TimeUnit.MILLISECONDS);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("等待缓存回源被中断: key=" + key, interrupted);
        } catch (ExecutionException | TimeoutException failed) {
            log.warn("等待缓存回源失败: key={}", key, failed);
            Throwable cause = failed.getCause() == null ? failed : failed.getCause();
            if (cause instanceof RuntimeException runtimeException) {
                throw runtimeException;
            }
            if (cause instanceof Error error) {
                throw error;
            }
            throw new IllegalStateException("缓存回源失败: key=" + key, cause);
        }
    }

    /**
     * 按模式删除缓存（使用 SCAN 避免阻塞）。
     */
    @Override
    public void evictPattern(String pattern) {
        try {
            var options = ScanOptions.scanOptions().match(pattern).count(100).build();
            List<String> keysToDelete = new ArrayList<>();
            try (var cursor = redisTemplate.scan(options)) {
                cursor.forEachRemaining(keysToDelete::add);
            }
            if (!keysToDelete.isEmpty()) {
                redisTemplate.delete(keysToDelete);
            }
        } catch (Exception ex) {
            log.warn("批量删除缓存失败: pattern={}", pattern, ex);
        }
    }

    private void validateTtl(Duration ttl) {
        if (ttl == null || ttl.isZero() || ttl.isNegative()) {
            throw new IllegalArgumentException("Redis 过期时间必须大于 0");
        }
    }
}
