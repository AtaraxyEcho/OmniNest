package com.omninest.modules.file.service;

import com.alibaba.fastjson2.JSON;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.domain.UploadStatus;
import com.omninest.modules.file.event.FileSecurityScanRequestedEvent;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件安全扫描失败和退避重试协调服务。
 * 终态拒绝立即进入死信；基础设施类失败按 1/5/15 分钟退避重试，超过上限进入死信。
 * 终态时入库记录标记 FAILED、上传会话置 REJECTED 并释放配额预留。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileIngressScanRetryService {
    private static final int MAX_RETRIES = 3;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final FileIngressLifecycleService ingressLifecycleService;
    private final FileUploadSessionRepository uploadSessionRepository;
    private final StorageQuotaService storageQuotaService;
    private final NotificationPublisher notificationPublisher;

    /**
     * 持久化失败状态并决定重试或进入死信终态。
     *
     * @param event 扫描任务消息
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleFailure(FileSecurityScanRequestedEvent event, RuntimeException exception) {
        int currentRetries = taskRecordService.retryCount(event.taskId());
        String errorSummary = exception.getClass().getSimpleName();
        if (exception instanceof FileIngressRejectedException || currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(event.taskId(), errorSummary);
            settleTerminal(event, "安全扫描未完成", "文件「" + targetName(event.ingressItemId())
                    + "」安全扫描未通过或重试耗尽，请重新上传或联系管理员");
            log.error("文件安全扫描任务进入死信终态: taskId={}, retryCount={}, errorType={}",
                    event.taskId(), currentRetries, errorSummary);
            return;
        }
        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        taskRecordService.markRetryWait(event.taskId(), errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_SECURITY_SCAN_ROUTING_KEY,
                event,
                nextRetryAt
        );
        log.warn("文件安全扫描任务等待重试: taskId={}, retryCount={}, nextRetryAt={}, errorType={}",
                event.taskId(), currentRetries, nextRetryAt, errorSummary);
    }

    /**
     * 恢复心跳超时的文件安全扫描任务。
     *
     * @param taskId 任务 ID
     * @param heartbeatCutoff 心跳截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void recoverStaleTask(UUID taskId, Instant heartbeatCutoff) {
        StaleTaskRecovery recovery = taskRecordService.recoverStaleTask(
                taskId,
                "FILE_SECURITY_SCAN",
                heartbeatCutoff,
                Instant.now(),
                "WORKER_HEARTBEAT_TIMEOUT"
        );
        if (!recovery.recovered()) {
            return;
        }
        if (recovery.deadLetter()) {
            settleTerminal(rebuildEvent(taskId, recovery), "安全扫描执行中断",
                    "文件「" + targetName(recovery.resourceId()) + "」安全扫描执行中断，请重新上传或联系管理员");
            log.error("心跳超时的文件安全扫描任务进入死信终态: taskId={}, retryCount={}", taskId, recovery.retryCount());
            return;
        }
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_SECURITY_SCAN_ROUTING_KEY,
                rebuildEvent(taskId, recovery),
                recovery.nextRetryAt()
        );
        log.warn("心跳超时的文件安全扫描任务已重新排队: taskId={}, retryCount={}, nextRetryAt={}",
                taskId, recovery.retryCount(), recovery.nextRetryAt());
    }

    private void settleTerminal(FileSecurityScanRequestedEvent event, String title, String message) {
        ingressLifecycleService.markFailed(event.ingressItemId(), false, "FILE_SECURITY_SCAN_DLQ", title);
        rejectSession(event.ingressItemId());
        notificationPublisher.notifyOrLog(
                event.ownerUserId(),
                "FILE_SECURITY",
                title,
                message,
                Map.of("ingressItemId", event.ingressItemId().toString())
        );
    }

    private void rejectSession(UUID ingressItemId) {
        uploadSessionRepository.findByIngressItemId(ingressItemId).ifPresent(session -> {
            if (session.getQuotaReservationId() != null) {
                storageQuotaService.releaseReservation("UPLOAD", session.getId());
                session.setQuotaReservationId(null);
            }
            session.setStatus(UploadStatus.REJECTED.getValue());
            uploadSessionRepository.save(session);
        });
    }

    private FileSecurityScanRequestedEvent rebuildEvent(UUID taskId, StaleTaskRecovery recovery) {
        Map<String, Object> payload = Map.of();
        Optional<TaskRecord> record = taskRecordService.findTaskRecord(taskId);
        if (record.isPresent() && record.get().getPayload() != null) {
            payload = JSON.parseObject(record.get().getPayload());
        }
        return new FileSecurityScanRequestedEvent(
                taskId,
                recovery.ownerUserId(),
                recovery.resourceId(),
                parseUuid(payload.get("asVersionOfFileId")),
                payload.get("declaredSha256") == null ? null : payload.get("declaredSha256").toString()
        );
    }

    private UUID parseUuid(Object raw) {
        if (raw == null) {
            return null;
        }
        String value = raw.toString();
        return value.isBlank() ? null : UUID.fromString(value);
    }

    private String targetName(UUID ingressItemId) {
        return uploadSessionRepository.findByIngressItemId(ingressItemId)
                .map(FileUploadSession::getFileName)
                .orElse("未知文件");
    }

    private Duration retryDelay(int retryCount) {
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }
}
