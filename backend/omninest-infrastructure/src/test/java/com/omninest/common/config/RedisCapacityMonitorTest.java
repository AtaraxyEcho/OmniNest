package com.omninest.common.config;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.Properties;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.data.redis.connection.RedisConnection;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.connection.RedisServerCommands;

/**
 * Redis 容量指标、可用性和只读采样测试。
 *
 * @author OmniNest
 */
class RedisCapacityMonitorTest {

    @Test
    void inspectPublishesMemoryKeyAndEvictionMetrics() {
        RedisConnectionFactory connectionFactory = Mockito.mock(RedisConnectionFactory.class);
        RedisConnection connection = Mockito.mock(RedisConnection.class);
        RedisServerCommands commands = Mockito.mock(RedisServerCommands.class);
        SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
        RedisCapacityProperties properties = new RedisCapacityProperties();
        RedisCapacityMonitor monitor = new RedisCapacityMonitor(
                connectionFactory,
                meterRegistry,
                properties
        );
        monitor.registerMetrics();
        Mockito.when(connectionFactory.getConnection()).thenReturn(connection);
        Mockito.when(connection.serverCommands()).thenReturn(commands);
        Mockito.when(commands.info("memory")).thenReturn(properties(
                "used_memory", "80",
                "maxmemory", "100"
        ));
        Mockito.when(commands.info("stats")).thenReturn(properties(
                "evicted_keys", "2",
                "expired_keys", "7"
        ));
        Mockito.when(commands.dbSize()).thenReturn(42L);

        monitor.inspect();

        Assertions.assertThat(gauge(meterRegistry, "omninest.redis.available")).isEqualTo(1D);
        Assertions.assertThat(gauge(meterRegistry, "omninest.redis.memory.used.bytes")).isEqualTo(80D);
        Assertions.assertThat(gauge(meterRegistry, "omninest.redis.memory.maximum.bytes")).isEqualTo(100D);
        Assertions.assertThat(gauge(meterRegistry, "omninest.redis.memory.utilization")).isEqualTo(0.8D);
        Assertions.assertThat(gauge(meterRegistry, "omninest.redis.keys")).isEqualTo(42D);
        Assertions.assertThat(gauge(meterRegistry, "omninest.redis.keys.evicted.total")).isEqualTo(2D);
        Assertions.assertThat(gauge(meterRegistry, "omninest.redis.keys.expired.total")).isEqualTo(7D);
        Mockito.verify(connection).close();
    }

    @Test
    void inspectReportsUnavailableWhenRedisSamplingFails() {
        RedisConnectionFactory connectionFactory = Mockito.mock(RedisConnectionFactory.class);
        SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
        RedisCapacityMonitor monitor = new RedisCapacityMonitor(
                connectionFactory,
                meterRegistry,
                new RedisCapacityProperties()
        );
        monitor.registerMetrics();
        Mockito.when(connectionFactory.getConnection())
                .thenThrow(new IllegalStateException("redis unavailable"));

        monitor.inspect();

        Assertions.assertThat(gauge(meterRegistry, "omninest.redis.available")).isZero();
    }

    @Test
    void inspectSkipsRedisWhenMonitoringDisabled() {
        RedisConnectionFactory connectionFactory = Mockito.mock(RedisConnectionFactory.class);
        RedisCapacityProperties properties = new RedisCapacityProperties();
        properties.setMonitoringEnabled(false);
        RedisCapacityMonitor monitor = new RedisCapacityMonitor(
                connectionFactory,
                new SimpleMeterRegistry(),
                properties
        );

        monitor.inspect();

        Mockito.verifyNoInteractions(connectionFactory);
    }

    @Test
    void inspectTreatsUnlimitedRedisMemoryAsUnboundedWithoutInvalidRatio() {
        RedisConnectionFactory connectionFactory = Mockito.mock(RedisConnectionFactory.class);
        RedisConnection connection = Mockito.mock(RedisConnection.class);
        RedisServerCommands commands = Mockito.mock(RedisServerCommands.class);
        SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
        RedisCapacityMonitor monitor = new RedisCapacityMonitor(
                connectionFactory,
                meterRegistry,
                new RedisCapacityProperties()
        );
        monitor.registerMetrics();
        Mockito.when(connectionFactory.getConnection()).thenReturn(connection);
        Mockito.when(connection.serverCommands()).thenReturn(commands);
        Mockito.when(commands.info("memory")).thenReturn(properties(
                "used_memory", "1024",
                "maxmemory", "0"
        ));
        Mockito.when(commands.info("stats")).thenReturn(properties(
                "evicted_keys", "0",
                "expired_keys", "0"
        ));
        Mockito.when(commands.dbSize()).thenReturn(1L);

        monitor.inspect();

        Assertions.assertThat(gauge(meterRegistry, "omninest.redis.memory.utilization")).isZero();
        Assertions.assertThat(gauge(meterRegistry, "omninest.redis.memory.maximum.bytes")).isZero();
    }

    private double gauge(SimpleMeterRegistry meterRegistry, String name) {
        return meterRegistry.get(name).gauge().value();
    }

    private Properties properties(String firstKey, String firstValue, String secondKey, String secondValue) {
        Properties properties = new Properties();
        properties.setProperty(firstKey, firstValue);
        properties.setProperty(secondKey, secondValue);
        return properties;
    }
}
