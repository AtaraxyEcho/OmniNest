package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.modules.user.service.AdminHealthProbeCache.HealthSnapshot;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

/**
 * 健康探测缓存测试。
 *
 * <p>监控页按秒轮询，探测本身是真实网络往返；缓存的边界是"同一波刷新只探测一次"，
 * 且探测失败不能被当成健康结果缓存下来。</p>
 *
 * @author OmniNest
 */
class AdminHealthProbeCacheTest {

    private final MutableClock clock = new MutableClock(Instant.parse("2026-11-05T08:00:00Z"));

    @Test
    void reusesTheProbeWithinTheTtl() {
        AdminHealthProbeCache cache = new AdminHealthProbeCache(Duration.ofSeconds(5), clock);
        AtomicInteger loads = new AtomicInteger();

        cache.get(() -> probe(loads));
        clock.advance(Duration.ofSeconds(4));
        Map<String, HealthSnapshot> second = cache.get(() -> probe(loads));

        assertThat(loads).hasValue(1);
        assertThat(second).containsKey("minio");
    }

    @Test
    void probesAgainAfterTheTtl() {
        AdminHealthProbeCache cache = new AdminHealthProbeCache(Duration.ofSeconds(5), clock);
        AtomicInteger loads = new AtomicInteger();

        cache.get(() -> probe(loads));
        clock.advance(Duration.ofSeconds(5));
        cache.get(() -> probe(loads));

        assertThat(loads).hasValue(2);
    }

    @Test
    void failedProbeIsNotCached() {
        AdminHealthProbeCache cache = new AdminHealthProbeCache(Duration.ofSeconds(5), clock);
        AtomicInteger attempts = new AtomicInteger();

        assertThatThrownBy(() -> cache.get(() -> {
            attempts.incrementAndGet();
            throw new IllegalStateException("probe exploded");
        })).isInstanceOf(IllegalStateException.class);

        // 同一时间窗内再次调用必须重新探测，而不是返回上一次（不存在的）快照。
        assertThatThrownBy(() -> cache.get(() -> {
            attempts.incrementAndGet();
            throw new IllegalStateException("probe exploded");
        })).isInstanceOf(IllegalStateException.class);
        assertThat(attempts).hasValue(2);
    }

    private static Map<String, HealthSnapshot> probe(AtomicInteger loads) {
        loads.incrementAndGet();
        return Map.of("minio", new HealthSnapshot("UP", "ok"));
    }

    /** 可推进的测试时钟。 */
    private static final class MutableClock extends Clock {
        private Instant now;

        private MutableClock(Instant now) {
            this.now = now;
        }

        private void advance(Duration duration) {
            now = now.plus(duration);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }
}
