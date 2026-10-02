package com.omninest.common.runtime;

import com.omninest.common.json.JsonSupport;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ZSetOperations;
import org.springframework.stereotype.Component;

/**
 * 使用 Redis 短期实例键和过期索引保存 Worker 运行状态。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class RedisWorkerRuntimeRegistry implements WorkerRuntimeRegistry {

    private static final String INSTANCE_KEY_PREFIX = "omninest:runtime:worker:instance:";
    private static final String INSTANCE_INDEX_KEY = "omninest:runtime:worker:instances";
    private static final long MAX_ACTIVE_INSTANCES = 100;

    private final StringRedisTemplate redisTemplate;

    /**
     * {@inheritDoc}
     */
    @Override
    public void publish(WorkerRuntimeState state, Duration ttl) {
        if (state == null || state.instanceId() == null || state.instanceId().isBlank()) {
            throw new IllegalArgumentException("Worker 实例标识不能为空");
        }
        if (ttl == null || ttl.isZero() || ttl.isNegative()) {
            throw new IllegalArgumentException("Worker 状态有效期必须大于零");
        }
        long nowEpochMillis = System.currentTimeMillis();
        long expiresAtEpochMillis = nowEpochMillis + ttl.toMillis();
        try {
            String value = JsonSupport.toJson(StoredWorkerRuntimeState.from(state));
            redisTemplate.opsForValue().set(instanceKey(state.instanceId()), value, ttl);
            ZSetOperations<String, String> indexOperations = redisTemplate.opsForZSet();
            indexOperations.add(INSTANCE_INDEX_KEY, state.instanceId(), expiresAtEpochMillis);
            indexOperations.removeRangeByScore(
                    INSTANCE_INDEX_KEY,
                    Double.NEGATIVE_INFINITY,
                    nowEpochMillis
            );
        } catch (RuntimeException exception) {
            log.warn("发布 Worker 运行状态失败: instanceId={}", state.instanceId(), exception);
        }
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public List<WorkerRuntimeState> activeInstances() {
        long nowEpochMillis = System.currentTimeMillis();
        try {
            ZSetOperations<String, String> indexOperations = redisTemplate.opsForZSet();
            indexOperations.removeRangeByScore(
                    INSTANCE_INDEX_KEY,
                    Double.NEGATIVE_INFINITY,
                    nowEpochMillis
            );
            Set<String> instanceIds = indexOperations.reverseRangeByScore(
                    INSTANCE_INDEX_KEY,
                    nowEpochMillis,
                    Double.POSITIVE_INFINITY,
                    0,
                    MAX_ACTIVE_INSTANCES
            );
            if (instanceIds == null || instanceIds.isEmpty()) {
                return List.of();
            }
            List<String> orderedInstanceIds = List.copyOf(instanceIds);
            List<String> keys = orderedInstanceIds.stream()
                    .map(this::instanceKey)
                    .toList();
            List<String> values = redisTemplate.opsForValue().multiGet(keys);
            if (values == null || values.isEmpty()) {
                return List.of();
            }
            List<WorkerRuntimeState> states = new ArrayList<>();
            int valueCount = Math.min(orderedInstanceIds.size(), values.size());
            for (int index = 0; index < valueCount; index++) {
                WorkerRuntimeState state = parseState(orderedInstanceIds.get(index), values.get(index));
                if (state != null) {
                    states.add(state);
                }
            }
            states.sort((left, right) -> right.reportedAt().compareTo(left.reportedAt()));
            return List.copyOf(states);
        } catch (RuntimeException exception) {
            log.warn("读取 Worker 运行状态失败", exception);
            return List.of();
        }
    }

    private WorkerRuntimeState parseState(String instanceId, String value) {
        if (value == null || value.isBlank()) {
            removeInvalidIndex(instanceId);
            return null;
        }
        try {
            StoredWorkerRuntimeState stored = JsonSupport.fromJson(value, StoredWorkerRuntimeState.class);
            WorkerRuntimeState state = stored.toRuntimeState();
            if (!instanceId.equals(state.instanceId())) {
                removeInvalidIndex(instanceId);
                return null;
            }
            return state;
        } catch (RuntimeException exception) {
            log.warn("解析 Worker 运行状态失败: instanceId={}", instanceId);
            removeInvalidIndex(instanceId);
            return null;
        }
    }

    private void removeInvalidIndex(String instanceId) {
        redisTemplate.opsForZSet().remove(INSTANCE_INDEX_KEY, instanceId);
    }

    private String instanceKey(String instanceId) {
        return INSTANCE_KEY_PREFIX + instanceId;
    }

    /**
     * 使用基础 JSON 类型保存 Worker 状态，避免基础设施模块依赖 Java Time 序列化扩展。
     *
     * @param instanceId Worker 实例标识
     * @param reportedAt ISO-8601 上报时间
     * @param capabilities 能力状态
     * @author OmniNest
     */
    private record StoredWorkerRuntimeState(
            String instanceId,
            String reportedAt,
            Map<String, WorkerRuntimeState.CapabilityStatus> capabilities
    ) {

        private static StoredWorkerRuntimeState from(WorkerRuntimeState state) {
            return new StoredWorkerRuntimeState(
                    state.instanceId(),
                    state.reportedAt().toString(),
                    state.capabilities()
            );
        }

        private WorkerRuntimeState toRuntimeState() {
            return new WorkerRuntimeState(instanceId, Instant.parse(reportedAt), capabilities);
        }
    }
}
