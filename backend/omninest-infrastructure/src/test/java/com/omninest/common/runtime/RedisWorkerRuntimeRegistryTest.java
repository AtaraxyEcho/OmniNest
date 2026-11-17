package com.omninest.common.runtime;

import java.time.Duration;
import java.time.Instant;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.data.redis.core.ZSetOperations;

/**
 * Redis Worker 运行状态注册表测试。
 *
 * @author OmniNest
 */
class RedisWorkerRuntimeRegistryTest {

    private static final String INSTANCE_KEY_PREFIX = "omninest:runtime:worker:instance:";
    private static final String INSTANCE_INDEX_KEY = "omninest:runtime:worker:instances";

    private StringRedisTemplate redisTemplate;
    private ValueOperations<String, String> valueOperations;
    private ZSetOperations<String, String> indexOperations;
    private RedisWorkerRuntimeRegistry registry;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() {
        redisTemplate = Mockito.mock(StringRedisTemplate.class);
        valueOperations = Mockito.mock(ValueOperations.class);
        indexOperations = Mockito.mock(ZSetOperations.class);
        Mockito.when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        Mockito.when(redisTemplate.opsForZSet()).thenReturn(indexOperations);
        registry = new RedisWorkerRuntimeRegistry(redisTemplate);
    }

    @Test
    void publishUsesInstanceTtlAndExpiryIndex() {
        WorkerRuntimeState state = state("worker-1", "2026-07-26T05:00:00Z", "照片 AI 可用");

        registry.publish(state, Duration.ofSeconds(45));

        ArgumentCaptor<String> valueCaptor = ArgumentCaptor.forClass(String.class);
        Mockito.verify(valueOperations).set(
                Mockito.eq(INSTANCE_KEY_PREFIX + "worker-1"),
                valueCaptor.capture(),
                Mockito.eq(Duration.ofSeconds(45))
        );
        Mockito.verify(indexOperations).add(
                Mockito.eq(INSTANCE_INDEX_KEY),
                Mockito.eq("worker-1"),
                Mockito.anyDouble()
        );
        Mockito.verify(indexOperations).removeRangeByScore(
                Mockito.eq(INSTANCE_INDEX_KEY),
                Mockito.eq(Double.NEGATIVE_INFINITY),
                Mockito.anyDouble()
        );
        Assertions.assertThat(valueCaptor.getValue()).contains("worker-1");
    }

    @Test
    void activeInstancesRestoresMultipleStatesInReportedOrder() {
        WorkerRuntimeState first = state("worker-1", "2026-07-26T05:00:00Z", "节点一");
        WorkerRuntimeState second = state("worker-2", "2026-07-26T05:01:00Z", "节点二");
        String firstJson = storedJson(first);
        String secondJson = storedJson(second);
        Mockito.when(indexOperations.reverseRangeByScore(
                Mockito.eq(INSTANCE_INDEX_KEY),
                Mockito.anyDouble(),
                Mockito.eq(Double.POSITIVE_INFINITY),
                Mockito.eq(0L),
                Mockito.eq(100L)
        )).thenReturn(new LinkedHashSet<>(List.of("worker-1", "worker-2")));
        Mockito.when(valueOperations.multiGet(List.of(
                INSTANCE_KEY_PREFIX + "worker-1",
                INSTANCE_KEY_PREFIX + "worker-2"
        ))).thenReturn(List.of(firstJson, secondJson));

        List<WorkerRuntimeState> states = registry.activeInstances();

        Assertions.assertThat(states).containsExactly(second, first);
    }

    @Test
    void activeInstancesFiltersMissingAndInvalidValues() {
        WorkerRuntimeState valid = state("worker-3", "2026-07-26T05:02:00Z", "节点三");
        String validJson = storedJson(valid);
        Mockito.when(indexOperations.reverseRangeByScore(
                Mockito.eq(INSTANCE_INDEX_KEY),
                Mockito.anyDouble(),
                Mockito.eq(Double.POSITIVE_INFINITY),
                Mockito.eq(0L),
                Mockito.eq(100L)
        )).thenReturn(new LinkedHashSet<>(List.of("worker-1", "worker-2", "worker-3")));
        Mockito.when(valueOperations.multiGet(Mockito.anyList())).thenReturn(Arrays.asList(
                null,
                "not-json",
                validJson
        ));

        List<WorkerRuntimeState> states = registry.activeInstances();

        Assertions.assertThat(states).containsExactly(valid);
        Mockito.verify(indexOperations).remove(INSTANCE_INDEX_KEY, "worker-1");
        Mockito.verify(indexOperations).remove(INSTANCE_INDEX_KEY, "worker-2");
    }

    @Test
    void activeInstancesTreatsRedisFailureAsNoActiveWorkers() {
        Mockito.when(indexOperations.removeRangeByScore(
                Mockito.anyString(),
                Mockito.anyDouble(),
                Mockito.anyDouble()
        )).thenThrow(new IllegalStateException("Redis unavailable"));

        List<WorkerRuntimeState> states = registry.activeInstances();

        Assertions.assertThat(states).isEmpty();
    }

    @Test
    void publishRejectsInvalidArguments() {
        WorkerRuntimeState state = new WorkerRuntimeState("worker-1", Instant.now(), Map.of());

        Assertions.assertThatThrownBy(() -> registry.publish(state, Duration.ZERO))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("有效期");
        Assertions.assertThatThrownBy(() -> registry.publish(
                new WorkerRuntimeState("", Instant.now(), Map.of()),
                Duration.ofSeconds(45)
        ))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("实例标识");
    }

    private WorkerRuntimeState state(String instanceId, String reportedAt, String detail) {
        return new WorkerRuntimeState(
                instanceId,
                Instant.parse(reportedAt),
                Map.of(
                        WorkerRuntimeState.PHOTO_AI_CAPABILITY,
                        WorkerRuntimeState.CapabilityStatus.up(detail)
                )
        );
    }

    private String storedJson(WorkerRuntimeState state) {
        registry.publish(state, Duration.ofSeconds(45));
        ArgumentCaptor<String> valueCaptor = ArgumentCaptor.forClass(String.class);
        Mockito.verify(valueOperations).set(
                Mockito.eq(INSTANCE_KEY_PREFIX + state.instanceId()),
                valueCaptor.capture(),
                Mockito.eq(Duration.ofSeconds(45))
        );
        Mockito.clearInvocations(valueOperations, indexOperations);
        return valueCaptor.getValue();
    }
}
