package com.omninest.common.config;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.annotation.PostConstruct;
import java.util.Properties;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.data.redis.connection.RedisConnection;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.connection.RedisServerCommands;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 在 API 角色中采集 Redis 内存、键数量和淘汰统计。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(
        prefix = "omninest.runtime",
        name = "role",
        havingValue = "api",
        matchIfMissing = true
)
public class RedisCapacityMonitor {
    private static final String USED_MEMORY = "used_memory";
    private static final String MAX_MEMORY = "maxmemory";
    private static final String EVICTED_KEYS = "evicted_keys";
    private static final String EXPIRED_KEYS = "expired_keys";

    private final RedisConnectionFactory connectionFactory;
    private final MeterRegistry meterRegistry;
    private final RedisCapacityProperties properties;
    private final AtomicLong available = new AtomicLong();
    private final AtomicLong usedMemoryBytes = new AtomicLong(-1L);
    private final AtomicLong maximumMemoryBytes = new AtomicLong(-1L);
    private final AtomicLong keyCount = new AtomicLong(-1L);
    private final AtomicLong evictedKeys = new AtomicLong(-1L);
    private final AtomicLong expiredKeys = new AtomicLong(-1L);
    private final AtomicBoolean missingMaximumLogged = new AtomicBoolean();

    @PostConstruct
    void registerMetrics() {
        registerGauge("omninest.redis.available", "Redis 容量采样是否可用", available);
        registerGauge("omninest.redis.memory.used.bytes", "Redis 已使用内存字节数", usedMemoryBytes);
        registerGauge("omninest.redis.memory.maximum.bytes", "Redis 最大内存字节数", maximumMemoryBytes);
        registerGauge("omninest.redis.keys", "Redis 当前数据库键数量", keyCount);
        registerGauge("omninest.redis.keys.evicted.total", "Redis 累计淘汰键数量", evictedKeys);
        registerGauge("omninest.redis.keys.expired.total", "Redis 累计过期键数量", expiredKeys);
        Gauge.builder("omninest.redis.memory.utilization", this, RedisCapacityMonitor::memoryUtilization)
                .description("Redis 内存使用率")
                .register(meterRegistry);
    }

    /**
     * 采集 Redis 容量指标并记录分级告警。
     */
    @Scheduled(fixedDelayString = "${omninest.redis.capacity.poll-interval:60s}")
    public void inspect() {
        if (!properties.isMonitoringEnabled()) {
            return;
        }
        try (RedisConnection connection = connectionFactory.getConnection()) {
            RedisServerCommands commands = connection.serverCommands();
            Properties memory = commands.info("memory");
            Properties stats = commands.info("stats");
            updateMetrics(memory, stats, commands.dbSize());
            available.set(1L);
            logCapacity();
        } catch (RuntimeException exception) {
            available.set(0L);
            log.warn("Redis 容量采样失败: errorType={}", exception.getClass().getSimpleName());
        }
    }

    private void updateMetrics(Properties memory, Properties stats, Long databaseSize) {
        usedMemoryBytes.set(propertyLong(memory, USED_MEMORY));
        maximumMemoryBytes.set(propertyLong(memory, MAX_MEMORY));
        keyCount.set(databaseSize == null ? -1L : Math.max(0L, databaseSize));
        long previousEvictedKeys = evictedKeys.getAndSet(propertyLong(stats, EVICTED_KEYS));
        expiredKeys.set(propertyLong(stats, EXPIRED_KEYS));
        if (previousEvictedKeys >= 0L && evictedKeys.get() > previousEvictedKeys) {
            log.warn("Redis 发生键淘汰: delta={}, total={}",
                    evictedKeys.get() - previousEvictedKeys, evictedKeys.get());
        }
    }

    private void logCapacity() {
        long maximumBytes = maximumMemoryBytes.get();
        if (maximumBytes <= 0L) {
            if (missingMaximumLogged.compareAndSet(false, true)) {
                log.warn("Redis 未配置 maxmemory，实例内存缺少硬上限");
            }
            return;
        }
        double warningRatio = clampRatio(properties.getMemoryWarningRatio());
        double criticalRatio = Math.max(warningRatio, clampRatio(properties.getMemoryCriticalRatio()));
        double utilization = memoryUtilization();
        if (utilization >= criticalRatio) {
            log.error("Redis 内存使用率严重过高: utilization={}, usedBytes={}, maximumBytes={}",
                    utilization, usedMemoryBytes.get(), maximumBytes);
            return;
        }
        if (utilization >= warningRatio) {
            log.warn("Redis 内存使用率过高: utilization={}, usedBytes={}, maximumBytes={}",
                    utilization, usedMemoryBytes.get(), maximumBytes);
        }
    }

    private void registerGauge(String name, String description, AtomicLong value) {
        Gauge.builder(name, value, AtomicLong::get)
                .description(description)
                .register(meterRegistry);
    }

    private long propertyLong(Properties source, String key) {
        if (source == null) {
            return -1L;
        }
        String value = source.getProperty(key);
        if (value == null || value.isBlank()) {
            return -1L;
        }
        try {
            return Long.parseLong(value);
        } catch (NumberFormatException exception) {
            return -1L;
        }
    }

    private double memoryUtilization() {
        long usedBytes = usedMemoryBytes.get();
        long maximumBytes = maximumMemoryBytes.get();
        if (usedBytes < 0L || maximumBytes <= 0L) {
            return 0D;
        }
        return Math.min(1D, (double) usedBytes / maximumBytes);
    }

    private double clampRatio(double ratio) {
        return Math.max(0.01D, Math.min(ratio, 1D));
    }
}
