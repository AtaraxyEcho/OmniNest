package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.error.StackSummaries;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.ExternalImportRequestedEvent;
import com.omninest.modules.file.repository.StorageImportTaskRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 外部存储导入的失败分类与标准退避重试。
 *
 * <p>导入是分钟级长任务，rclone 与远端账号的瞬时抖动是常态。此前执行侧把所有异常一律
 * 判成业务终态 FAILED 并确认消息，既绕过了 1/5/15 分钟 ×3 的重试约定，也让断点续传
 * 逻辑（{@code ExternalImportResumeDetector}）没有第二次机会被用到。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ExternalImportRetryService {

    private static final int MAX_RETRIES = 3;

    private final StorageImportTaskRepository importTaskRepository;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final NotificationPublisher notificationService;
    private final ExternalImportTaskStatusService taskStatusService;

    /**
     * 按异常类型决定终止、延后重投或转入死信。
     *
     * @param event 导入请求事件
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleFailure(ExternalImportRequestedEvent event, Throwable exception) {
        UUID systemTaskId = systemTaskId(event.taskId());
        String errorSummary = errorSummary(exception);
        String stackSummary = StackSummaries.summarize(exception);
        if (!isTransient(exception)) {
            taskRecordService.markFailed(systemTaskId, errorSummary, stackSummary);
            // 业务行必须同步收敛：否则 sys_tasks 已是 FAILED，storage_import_tasks
            // 会永久停在 SCANNING，并一直占着外导配额预占。
            markTaskRowFailed(event.taskId(), errorSummary);
            notifyFailed(event.taskId(), errorSummary);
            log.warn("外部存储导入因业务错误终止: taskId={}, error={}", event.taskId(), errorSummary);
            return;
        }
        int currentRetries = taskRecordService.retryCount(systemTaskId);
        if (currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(systemTaskId, errorSummary, stackSummary);
            markTaskRowFailed(event.taskId(), errorSummary);
            notifyFailed(event.taskId(), errorSummary);
            log.error("外部存储导入达到最大重试次数并进入死信: taskId={}, retryCount={}, error={}",
                    event.taskId(), currentRetries, errorSummary);
            return;
        }
        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        int retryCount = taskRecordService.markRetryWait(systemTaskId, errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                systemTaskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.EXTERNAL_IMPORT_ROUTING_KEY,
                event,
                nextRetryAt
        );
        log.warn("外部存储导入等待重试: taskId={}, retryCount={}, nextRetryAt={}, error={}",
                event.taskId(), retryCount, nextRetryAt, errorSummary);
    }

    /**
     * 判断这次失败是否值得按标准退避再试一次。
     *
     * <p>与媒体库扫描同口径：明确的业务错误直接终态，其余（网络、依赖不可用、未分类
     * 运行时异常）都还有救。断点续传让重试的代价只是重下一段，不是整本重来。</p>
     */
    static boolean isTransient(Throwable exception) {
        BusinessException businessException = findBusinessError(exception);
        if (businessException != null) {
            ErrorCode code = businessException.errorCode();
            return code != ErrorCode.NOT_FOUND
                    && code != ErrorCode.PARAM_ERROR
                    && code != ErrorCode.VALIDATION_FAILED
                    && code != ErrorCode.FORBIDDEN
                    && code != ErrorCode.CONFLICT
                    && code != ErrorCode.FILE_QUOTA_EXCEEDED;
        }
        return true;
    }

    /**
     * 业务表与 {@code sys_tasks} 的关联键：导入任务可能未挂系统任务。
     *
     * <p>与执行侧 {@code systemTaskId} 同一判据，两处不一致会让重试状态写在另一行上，
     * 领取守卫因此永远看不到 RETRY_WAIT。</p>
     */
    private UUID systemTaskId(UUID importTaskId) {
        return importTaskRepository.findById(importTaskId)
                .map(task -> task.getTaskId() == null ? task.getId() : task.getTaskId())
                .orElse(importTaskId);
    }

    /**
     * 死信收口时把业务行也落到失败终态并结算预留，避免停留在传输中。
     *
     * <p>执行侧 {@code markFailed}/{@code markCancelled} 都会先按实际入库字节结算，
     * 但死信路径由消息重试耗尽触发，此时执行线程早已退出，没有人再碰这条预留；
     * 漏掉结算会让 {@code EXTERNAL_IMPORT} 的预留锁死到 24 小时过期。</p>
     */
    private void markTaskRowFailed(UUID importTaskId, String errorSummary) {
        taskStatusService.markFailed(importTaskId, errorSummary);
    }

    private void notifyFailed(UUID importTaskId, String errorSummary) {
        importTaskRepository.findById(importTaskId).ifPresent(task -> notificationService.notifyOrLog(
                task.getOwnerUserId(),
                "TASK_FAILED",
                "文件导入失败",
                "导入失败: " + errorSummary,
                Map.of("taskId", importTaskId.toString())
        ));
    }

    private String errorSummary(Throwable exception) {
        BusinessException businessException = findBusinessError(exception);
        if (businessException != null) {
            return businessException.errorCode().name();
        }
        return rootCause(exception).getClass().getSimpleName();
    }

    /**
     * 沿 cause 链找第一个业务错误：瞬时故障常被 {@link ExternalImportTransientException} 包一层。
     */
    private static BusinessException findBusinessError(Throwable exception) {
        for (Throwable cursor = rootCause(exception); cursor != null; cursor = cursor.getCause()) {
            if (cursor instanceof BusinessException businessException) {
                return businessException;
            }
        }
        return null;
    }

    private static Throwable rootCause(Throwable exception) {
        Throwable cursor = exception;
        while (cursor.getCause() != null && cursor.getCause() != cursor) {
            cursor = cursor.getCause();
        }
        return cursor;
    }

    private Duration retryDelay(int retryCount) {
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }
}
