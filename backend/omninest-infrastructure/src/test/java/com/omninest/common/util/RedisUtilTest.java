package com.omninest.common.util;

import org.mockito.ArgumentMatchers;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.data.redis.core.script.DefaultRedisScript;

/**
 * Redis 通用操作和缓存契约测试。
 *
 * @author OmniNest
 */
@SuppressWarnings("unchecked")
class RedisUtilTest {

    private final StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
    private final ValueOperations<String, String> valueOperations = mock(ValueOperations.class);
    private final RedisUtil redisUtil = new RedisUtil(redisTemplate);

    @Test
    void setWithTtlDelegatesToRedisTemplate() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        Duration ttl = Duration.ofMinutes(5);

        redisUtil.set("config:test", "enabled", ttl);

        verify(valueOperations).set("config:test", "enabled", ttl);
    }

    @Test
    void invalidateDeletesCacheKey() {
        when(redisTemplate.delete("cache:file:1")).thenReturn(Boolean.TRUE);

        boolean invalidated = redisUtil.invalidate("cache:file:1");

        assertThat(invalidated).isTrue();
        verify(redisTemplate).delete("cache:file:1");
    }

    @Test
    void expiringOwnershipRegistryStoresAndReadsOwner() {
        UUID ownerUserId = UUID.fromString("10000000-0000-0000-0000-000000000001");
        Duration ttl = Duration.ofMinutes(5);
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.get("login:session-1")).thenReturn(ownerUserId.toString());

        redisUtil.register("login:session-1", ownerUserId, ttl);
        Optional<UUID> storedOwner = redisUtil.findOwner("login:session-1");

        verify(valueOperations).set("login:session-1", ownerUserId.toString(), ttl);
        assertThat(storedOwner).contains(ownerUserId);
    }

    @Test
    void expiringOwnershipRegistryRemovesOwner() {
        when(redisTemplate.delete("login:session-1")).thenReturn(Boolean.TRUE);

        redisUtil.remove("login:session-1");

        verify(redisTemplate).delete("login:session-1");
    }

    @Test
    void tryLockUsesSetIfAbsentWithTtl() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.setIfAbsent("lock:file:1", "token-1", Duration.ofSeconds(30))).thenReturn(Boolean.TRUE);

        boolean locked = redisUtil.tryLock("lock:file:1", "token-1", Duration.ofSeconds(30));

        assertThat(locked).isTrue();
    }

    @Test
    void unlockUsesLuaCompareAndDeleteScript() {
        when(redisTemplate.execute(
                ArgumentMatchers.<DefaultRedisScript<Long>>any(),
                eq(List.of("lock:file:1")),
                eq("token-1")
        )).thenReturn(1L);
        ArgumentCaptor<DefaultRedisScript<Long>> scriptCaptor = ArgumentCaptor.forClass(DefaultRedisScript.class);

        boolean unlocked = redisUtil.unlock("lock:file:1", "token-1");

        assertThat(unlocked).isTrue();
        verify(redisTemplate).execute(scriptCaptor.capture(), eq(List.of("lock:file:1")), eq("token-1"));
        assertThat(scriptCaptor.getValue().getScriptAsString())
                .contains("redis.call('get', KEYS[1])")
                .contains("redis.call('del', KEYS[1])");
    }

    @Test
    void getOrLoadReturnsCachedValueWithoutCallingLoader() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.get("cache:music:playlists")).thenReturn("{\"name\":\"cached\"}");
        AtomicInteger loaderCalls = new AtomicInteger();

        CachePayload payload = redisUtil.getOrLoad(
                "cache:music:playlists",
                Duration.ofMinutes(5),
                () -> {
                    loaderCalls.incrementAndGet();
                    return new CachePayload("loaded");
                },
                CachePayload.class
        );

        assertThat(payload.name()).isEqualTo("cached");
        assertThat(loaderCalls).hasValue(0);
    }

    @Test
    void concurrentMissesShareOneLoadAndWriteCacheOnce() throws Exception {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.get("cache:music:playlists")).thenReturn(null);
        AtomicInteger loaderCalls = new AtomicInteger();
        CountDownLatch loaderEntered = new CountDownLatch(1);
        CountDownLatch releaseLoader = new CountDownLatch(1);
        Callable<CachePayload> call = () -> redisUtil.getOrLoad(
                "cache:music:playlists",
                Duration.ofMinutes(5),
                () -> {
                    loaderCalls.incrementAndGet();
                    loaderEntered.countDown();
                    awaitUninterruptibly(releaseLoader);
                    return new CachePayload("loaded");
                },
                CachePayload.class
        );
        ExecutorService executor = Executors.newFixedThreadPool(4);
        try {
            List<Future<CachePayload>> futures = new ArrayList<>();
            for (int index = 0; index < 4; index++) {
                futures.add(executor.submit(call));
            }

            assertThat(loaderEntered.await(5, TimeUnit.SECONDS)).isTrue();
            // 留出等待者进入等待的时间：单飞生效时它们不会各自回源。
            Thread.sleep(150);
            releaseLoader.countDown();

            List<String> names = new ArrayList<>();
            for (Future<CachePayload> future : futures) {
                names.add(future.get(5, TimeUnit.SECONDS).name());
            }
            assertThat(names).containsExactly("loaded", "loaded", "loaded", "loaded");
            assertThat(loaderCalls).hasValue(1);
            verify(valueOperations, times(1))
                    .set(eq("cache:music:playlists"), ArgumentMatchers.anyString(), eq(Duration.ofMinutes(5)));
        } finally {
            executor.shutdownNow();
        }
    }

    @Test
    void concurrentWaitersReceiveTheOriginalLoadFailure() throws Exception {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.get("cache:music:playlists")).thenReturn(null);
        BusinessException failure = new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "平台接口不可用");
        AtomicInteger loaderCalls = new AtomicInteger();
        CountDownLatch loaderEntered = new CountDownLatch(1);
        CountDownLatch releaseLoader = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        Callable<String> call = () -> {
            try {
                redisUtil.getOrLoad(
                        "cache:music:playlists",
                        Duration.ofMinutes(5),
                        () -> {
                            loaderCalls.incrementAndGet();
                            loaderEntered.countDown();
                            awaitUninterruptibly(releaseLoader);
                            throw failure;
                        },
                        CachePayload.class
                );
                return "no-error";
            } catch (BusinessException exception) {
                return exception.getMessage();
            }
        };
        try {
            Future<String> leader = executor.submit(call);
            Future<String> waiter = executor.submit(call);

            assertThat(loaderEntered.await(5, TimeUnit.SECONDS)).isTrue();
            Thread.sleep(150);
            releaseLoader.countDown();

            assertThat(leader.get(5, TimeUnit.SECONDS)).isEqualTo("平台接口不可用");
            assertThat(waiter.get(5, TimeUnit.SECONDS)).isEqualTo("平台接口不可用");
            // 失败结果不落缓存，下一次调用重新回源。
            verify(valueOperations, never()).set(
                    eq("cache:music:playlists"),
                    ArgumentMatchers.anyString(),
                    ArgumentMatchers.any(Duration.class)
            );
        } finally {
            executor.shutdownNow();
        }
    }

    @Test
    void failedLoadReleasesSingleFlightForNextAttempt() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.get("cache:music:playlists")).thenReturn(null);
        AtomicInteger loaderCalls = new AtomicInteger();

        assertThatThrownBy(() -> redisUtil.getOrLoad(
                "cache:music:playlists",
                Duration.ofMinutes(5),
                () -> {
                    loaderCalls.incrementAndGet();
                    throw new IllegalStateException("数据源不可用");
                },
                CachePayload.class
        )).isInstanceOf(IllegalStateException.class).hasMessage("数据源不可用");

        CachePayload payload = redisUtil.getOrLoad(
                "cache:music:playlists",
                Duration.ofMinutes(5),
                () -> {
                    loaderCalls.incrementAndGet();
                    return new CachePayload("loaded");
                },
                CachePayload.class
        );

        assertThat(payload.name()).isEqualTo("loaded");
        assertThat(loaderCalls).hasValue(2);
    }

    private static void awaitUninterruptibly(CountDownLatch latch) {
        try {
            latch.await(5, TimeUnit.SECONDS);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
    }

    private record CachePayload(String name) {
    }
}
