package com.omninest.worker.file;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 文件后处理任务（THUMBNAIL / FILE_INDEX / TEXT_EXTRACTION）状态跟踪器。
 *
 * <p>此前这三个消费者只执行业务不更新 sys_tasks，任务记录永远停留在 QUEUED。
 * 本组件补齐生命周期：按 (owner, taskType, FILE_NODE, fileNodeId) 解析任务记录，
 * claim 后执行业务，完成标记 COMPLETED，失败按 1/5/15 分钟经任务 Outbox 延迟重投，
 * 超过 3 次或不可重试错误进入死信。</p>
 *
 * <p>找不到任务记录的事件（如文件恢复、历史消息）保持旧行为：只执行业务，
 * 不做任何状态更新。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FilePostProcessingTaskTracker {

    /** FilePostProcessingTaskService 创建任务时使用的资源类型。 */
    private static final String RESOURCE_TYPE = "FILE_NODE";
    private static final List<String> ACTIVE_STATUSES = List.of("QUEUED", "RETRY_WAIT");
    private static final int MAX_RETRIES = 3;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 已解析并领取的任务上下文。
     *
     * @param taskId 任务标识，无任务记录时为 null
     * @param claimed 是否成功领取（false 表示任务已被其他消费者领取或不可领取）
     */
    public record TrackedTask(UUID taskId, boolean claimed) {

        /** @return 是否应跳过执行（任务存在但领取失败，消息可能重复投递） */
        public boolean shouldSkip() {
            return taskId != null && !claimed;
        }

        /** @return 是否需要状态回写 */
        public boolean tracked() {
            return taskId != null && claimed;
        }
    }

    /**
     * 解析并领取与文件节点关联的活跃任务；不存在任务记录时返回未跟踪上下文。
     *
     * @param ownerUserId 所属用户 ID
     * @param taskType 任务类型
     * @param fileNodeId 文件节点 ID
     * @param phase 领取后进入的执行阶段
     * @return 任务上下文
     */
    public TrackedTask begin(UUID ownerUserId, String taskType, UUID fileNodeId, String phase) {
        return taskRecordService
                .findActiveResourceTask(ownerUserId, taskType, RESOURCE_TYPE, fileNodeId, ACTIVE_STATUSES)
                .map(record -> {
                    if (!taskRecordService.claimForExecution(record.getId(), phase)) {
                        return new TrackedTask(record.getId(), false);
                    }
                    return new TrackedTask(record.getId(), true);
                })
                .orElse(new TrackedTask(null, false));
    }

    /**
     * 标记任务完成。
     *
     * @param taskId 任务 ID
     * @param result 完成结果
     */
    public void complete(UUID taskId, Map<String, Object> result) {
        if (taskId != null) {
            taskRecordService.markCompleted(taskId, result);
        }
    }

    /**
     * 处理执行失败：重试期内经任务 Outbox 延迟重投，超过上限或不可重试错误进入死信。
     *
     * @param taskType 任务类型
     * @param routingKey 重投路由键
     * @param taskId 任务 ID，为 null 时仅记录日志（无任务记录的历史消息）
     * @param event 原始事件（用于延迟重投）
     * @param exception 执行异常
     */
    public void handleFailure(
            String taskType,
            String routingKey,
            UUID taskId,
            Object event,
            Throwable exception) {
        String errorSummary = errorSummary(exception);
        if (taskId == null) {
            log.warn("文件后处理失败且无任务记录，仅丢弃消息: taskType={}, errorType={}",
                    taskType, errorSummary);
            return;
        }
        if (isNonRetryable(exception)) {
            taskRecordService.markDeadLetter(taskId, errorSummary);
            log.warn("文件后处理任务因业务错误进入死信终态: taskId={}, taskType={}, errorType={}",
                    taskId, taskType, errorSummary);
            return;
        }
        int currentRetries = taskRecordService.retryCount(taskId);
        if (currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(taskId, errorSummary);
            log.error("文件后处理任务达到最大重试次数并进入死信: taskId={}, taskType={}, errorType={}",
                    taskId, taskType, errorSummary);
            return;
        }
        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        int retryCount = taskRecordService.markRetryWait(taskId, errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                routingKey,
                event,
                nextRetryAt
        );
        log.warn("文件后处理任务等待重试: taskId={}, taskType={}, retryCount={}, nextRetryAt={}, errorType={}",
                taskId, taskType, retryCount, nextRetryAt, errorSummary);
    }

    private boolean isNonRetryable(Throwable exception) {
        if (!(exception instanceof BusinessException businessException)) {
            return false;
        }
        return switch (businessException.errorCode()) {
            case PARAM_ERROR, VALIDATION_FAILED, NOT_FOUND, TASK_NOT_FOUND,
                    FORBIDDEN, FILE_NOT_FOUND, FILE_LIFECYCLE_CONFLICT, RATE_LIMITED -> true;
            default -> false;
        };
    }

    private String errorSummary(Throwable exception) {
        return exception instanceof BusinessException businessException
                ? businessException.errorCode().name()
                : exception.getClass().getSimpleName();
    }

    private Duration retryDelay(int retryCount) {
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }
}
