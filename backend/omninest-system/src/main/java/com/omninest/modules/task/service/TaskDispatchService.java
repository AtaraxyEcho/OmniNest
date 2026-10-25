package com.omninest.modules.task.service;

import com.omninest.common.json.JsonSupport;
import com.omninest.modules.task.config.TaskOutboxProperties;
import com.omninest.modules.task.domain.TaskDispatch;
import com.omninest.modules.task.repository.TaskDispatchRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 管理任务 Outbox 创建、租约和发布状态。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class TaskDispatchService {
    private static final int MAX_RETRY_ATTEMPTS = 3;
    private static final Duration DEAD_LETTER_RETRY_DELAY = Duration.ofMinutes(15);
    private static final String DEAD_LETTER_PENDING_PREFIX = "DLQ_PENDING:";

    private final TaskDispatchRepository repository;
    private final TaskOutboxProperties properties;
    private final TaskRecordService taskRecordService;

    /**
     * 分批删除超过保留期的已发布投递记录。
     *
     * <p>只清 PUBLISHED：PENDING 与 PUBLISHING 仍在重试链上。原始载荷是重试时的
     * 首选投递来源，保留期不得短于任务记录保留期，否则只剩事件子载的任务类型
     * 退回按路由键重建，个别类型会因此无法重投。</p>
     *
     * @param cutoff 发布时间截止点
     * @param batchSize 单批数量
     * @return 删除记录数
     */
    @Transactional(rollbackFor = Exception.class)
    public int deletePublishedBatchBefore(Instant cutoff, int batchSize) {
        List<UUID> ids = repository.findPublishedIdsBefore(
                cutoff, PageRequest.of(0, Math.max(1, Math.min(batchSize, 5000))));
        if (ids.isEmpty()) {
            return 0;
        }
        repository.deleteAllByIdInBatch(ids);
        return ids.size();
    }

    /**
     * 在当前业务事务内创建待发布记录。
     *
     * @param taskId 任务 ID
     * @param exchangeName 交换机名称
     * @param routingKey 路由键
     * @param payload 消息载荷
     */
    @Transactional(rollbackFor = Exception.class)
    public void enqueue(UUID taskId, String exchangeName, String routingKey, Object payload) {
        enqueueAt(taskId, exchangeName, routingKey, payload, Instant.now());
    }

    /**
     * 在当前业务事务内创建指定时间后可发布的记录。
     *
     * @param taskId 任务 ID
     * @param exchangeName 交换机名称
     * @param routingKey 路由键
     * @param payload 消息载荷
     * @param nextAttemptAt 最早发布时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void enqueueAt(
            UUID taskId,
            String exchangeName,
            String routingKey,
            Object payload,
            Instant nextAttemptAt
    ) {
        TaskDispatch dispatch = new TaskDispatch();
        dispatch.setTaskId(taskId);
        dispatch.setExchangeName(exchangeName);
        dispatch.setRoutingKey(routingKey);
        dispatch.setPayload(JsonSupport.toJson(payload));
        dispatch.setNextAttemptAt(nextAttemptAt);
        repository.save(dispatch);
    }

    /**
     * 在当前业务事务内批量创建待发布记录。
     *
     * <p>同一批共用交换机与路由键，{@code saveAll} 由 Hibernate 按配置的
     * {@code jdbc.batch_size} 合并插入；全站重建等一次投递数百条的场景
     * 不再逐条提交事务。</p>
     *
     * @param exchangeName 交换机名称
     * @param routingKey 路由键
     * @param items 批量记录
     */
    @Transactional(rollbackFor = Exception.class)
    public void enqueueAll(String exchangeName, String routingKey, List<TaskDispatchItem> items) {
        if (items.isEmpty()) {
            return;
        }
        Instant nextAttemptAt = Instant.now();
        List<TaskDispatch> dispatches = new ArrayList<>(items.size());
        for (TaskDispatchItem item : items) {
            TaskDispatch dispatch = new TaskDispatch();
            dispatch.setTaskId(item.taskId());
            dispatch.setExchangeName(exchangeName);
            dispatch.setRoutingKey(routingKey);
            dispatch.setPayload(JsonSupport.toJson(item.payload()));
            dispatch.setNextAttemptAt(nextAttemptAt);
            dispatches.add(dispatch);
        }
        repository.saveAll(dispatches);
    }

    /**
     * 领取一批可发布记录。
     *
     * @param now 当前时间
     * @return 已领取快照
     */
    @Transactional(rollbackFor = Exception.class)
    public List<ClaimedTaskDispatch> claimBatch(Instant now) {
        int batchSize = Math.max(1, Math.min(properties.getBatchSize(), 500));
        Instant lockedUntil = now.plusSeconds(Math.max(1L, properties.getLeaseSeconds()));
        List<TaskDispatch> records = repository.findClaimable(now, batchSize);
        records.forEach(record -> {
            record.setStatus("PUBLISHING");
            record.setLockedBy(properties.getInstanceId());
            record.setLockedUntil(lockedUntil);
        });
        repository.flush();
        return records.stream()
                .map(record -> new ClaimedTaskDispatch(
                        record.getId(),
                        record.getTaskId(),
                        record.getExchangeName(),
                        record.getRoutingKey(),
                        record.getPayload(),
                        record.getAttemptCount(),
                        record.getLastErrorCode()
                ))
                .toList();
    }

    /**
     * 标记发布成功。
     *
     * @param dispatchId 投递记录 ID
     * @param publishedAt 发布时间
     * @return 是否更新成功
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean markPublished(UUID dispatchId, Instant publishedAt) {
        return repository.markPublished(dispatchId, properties.getInstanceId(), publishedAt) == 1;
    }

    /**
     * 记录发布失败并设置退避。
     *
     * @param dispatch 投递快照
     * @param failedAt 失败时间
     * @param errorCode 稳定错误码
     * @return 是否更新成功
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean markFailed(ClaimedTaskDispatch dispatch, Instant failedAt, String errorCode) {
        int attempts = dispatch.attemptCount() + 1;
        Instant nextAttemptAt = failedAt.plus(retryDelay(attempts));
        return repository.markFailed(
                dispatch.id(),
                properties.getInstanceId(),
                attempts,
                nextAttemptAt,
                errorCode,
                failedAt
        ) == 1;
    }

    /**
     * 判断当前失败是否必须转入死信流程。
     *
     * @param dispatch 投递快照
     * @param retryable 本次错误是否可重试
     * @return 需要发布死信时返回 true
     */
    public boolean requiresDeadLetter(ClaimedTaskDispatch dispatch, boolean retryable) {
        return isDeadLetterPending(dispatch)
                || !retryable
                || dispatch.attemptCount() >= MAX_RETRY_ATTEMPTS;
    }

    /**
     * 判断记录是否已进入仅等待死信发布的恢复流程。
     *
     * @param dispatch 投递快照
     * @return 等待死信发布时返回 true
     */
    public boolean isDeadLetterPending(ClaimedTaskDispatch dispatch) {
        return dispatch.lastErrorCode() != null
                && dispatch.lastErrorCode().startsWith(DEAD_LETTER_PENDING_PREFIX);
    }

    /**
     * 解析死信恢复记录保存的原始错误码。
     *
     * @param dispatch 投递快照
     * @return 原始错误码
     */
    public String deadLetterErrorCode(ClaimedTaskDispatch dispatch) {
        if (!isDeadLetterPending(dispatch)) {
            return "PUBLISH_RETRY_EXHAUSTED";
        }
        return dispatch.lastErrorCode().substring(DEAD_LETTER_PENDING_PREFIX.length());
    }

    /**
     * 在死信获得 Broker 确认后结束 Outbox 并将任务标记为 DLQ。
     *
     * @param dispatch 投递快照
     * @param publishedAt 死信发布时间
     * @param errorCode 原始投递错误码
     * @return 是否完成状态更新
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean markDeadLetterPublished(
            ClaimedTaskDispatch dispatch,
            Instant publishedAt,
            String errorCode
    ) {
        int attempts = dispatch.attemptCount() + 1;
        int updated = repository.markDeadLetterPublished(
                dispatch.id(),
                properties.getInstanceId(),
                attempts,
                publishedAt,
                errorCode
        );
        if (updated != 1) {
            return false;
        }
        taskRecordService.markDeadLetter(dispatch.taskId(), "任务消息投递失败: " + errorCode);
        return true;
    }

    /**
     * 死信发布失败时释放租约，并延迟下一次死信发布。
     *
     * @param dispatch 投递快照
     * @param failedAt 失败时间
     * @param originalErrorCode 原始投递错误码
     * @return 是否完成状态更新
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean markDeadLetterPublishFailed(
            ClaimedTaskDispatch dispatch,
            Instant failedAt,
            String originalErrorCode
    ) {
        String pendingErrorCode = DEAD_LETTER_PENDING_PREFIX + normalizeErrorCode(originalErrorCode);
        return repository.markFailed(
                dispatch.id(),
                properties.getInstanceId(),
                Math.max(dispatch.attemptCount(), MAX_RETRY_ATTEMPTS),
                failedAt.plus(DEAD_LETTER_RETRY_DELAY),
                pendingErrorCode,
                failedAt
        ) == 1;
    }

    private Duration retryDelay(int attempts) {
        return switch (attempts) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            case 3 -> Duration.ofMinutes(15);
            default -> throw new IllegalArgumentException("投递重试次数超过上限");
        };
    }

    private String normalizeErrorCode(String errorCode) {
        if (errorCode == null || errorCode.isBlank()) {
            return "UNKNOWN";
        }
        int maxLength = 64 - DEAD_LETTER_PENDING_PREFIX.length();
        return errorCode.length() <= maxLength ? errorCode : errorCode.substring(0, maxLength);
    }
}
