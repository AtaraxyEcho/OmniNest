package com.omninest.modules.backdrop.service;

import com.alibaba.fastjson2.JSON;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.backdrop.domain.BackdropAsset;
import com.omninest.modules.backdrop.domain.BackdropAssetStatus;
import com.omninest.modules.backdrop.event.BackdropSecurityScanRequestedEvent;
import com.omninest.modules.backdrop.repository.BackdropAssetRepository;
import com.omninest.modules.file.service.FileIngressLifecycleService;
import com.omninest.modules.file.service.FileIngressRejectedException;
import com.omninest.modules.file.service.FileIngressStagingService;
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
 * 背景素材安全扫描失败和退避重试协调服务。
 * 终态拒绝立即进入死信；基础设施类失败按 1/5/15 分钟退避重试，超过上限进入死信。
 * 终态时素材标记 FAILED、释放配额预留并通知用户。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class BackdropScanRetryService {
    private static final int MAX_RETRIES = 3;
    private static final int FAIL_REASON_MAX_LENGTH = 200;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final FileIngressLifecycleService ingressLifecycleService;
    private final FileIngressStagingService ingressStagingService;
    private final BackdropAssetRepository backdropAssetRepository;
    private final StorageQuotaService storageQuotaService;
    private final NotificationPublisher notificationPublisher;

    /**
     * 持久化失败状态并决定重试或进入死信终态。
     *
     * @param event 扫描任务消息
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleFailure(BackdropSecurityScanRequestedEvent event, Throwable exception) {
        int currentRetries = taskRecordService.retryCount(event.taskId());
        String errorSummary = exception.getClass().getSimpleName();
        if (exception instanceof FileIngressRejectedException || currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(event.taskId(), errorSummary);
            settleTerminal(event, "安全扫描未通过", "背景素材「" + assetTitle(event.assetId())
                    + "」安全扫描未通过或重试耗尽，已释放占用量");
            log.error("背景素材安全扫描任务进入死信终态: taskId={}, retryCount={}, errorType={}",
                    event.taskId(), currentRetries, errorSummary);
            return;
        }
        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        taskRecordService.markRetryWait(event.taskId(), errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.BACKDROP_SECURITY_SCAN_ROUTING_KEY,
                event,
                nextRetryAt
        );
        log.warn("背景素材安全扫描任务等待重试: taskId={}, retryCount={}, nextRetryAt={}, errorType={}",
                event.taskId(), currentRetries, nextRetryAt, errorSummary);
    }

    /**
     * 恢复心跳超时的背景素材安全扫描任务。
     *
     * @param taskId 任务 ID
     * @param heartbeatCutoff 心跳截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void recoverStaleTask(UUID taskId, Instant heartbeatCutoff) {
        StaleTaskRecovery recovery = taskRecordService.recoverStaleTask(
                taskId,
                "BACKDROP_SECURITY_SCAN",
                heartbeatCutoff,
                Instant.now(),
                "WORKER_HEARTBEAT_TIMEOUT"
        );
        if (!recovery.recovered()) {
            return;
        }
        BackdropSecurityScanRequestedEvent event = rebuildEvent(taskId, recovery);
        if (recovery.deadLetter()) {
            settleTerminal(event, "安全扫描执行中断", "背景素材「" + assetTitle(event.assetId())
                    + "」安全扫描执行中断，已释放占用量");
            log.error("心跳超时的背景素材安全扫描任务进入死信终态: taskId={}, retryCount={}",
                    taskId, recovery.retryCount());
            return;
        }
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.BACKDROP_SECURITY_SCAN_ROUTING_KEY,
                event,
                recovery.nextRetryAt()
        );
        log.warn("心跳超时的背景素材安全扫描任务已重新排队: taskId={}, retryCount={}, nextRetryAt={}",
                taskId, recovery.retryCount(), recovery.nextRetryAt());
    }

    private void settleTerminal(BackdropSecurityScanRequestedEvent event, String title, String message) {
        ingressLifecycleService.markFailed(event.ingressItemId(), false, "BACKDROP_SCAN_DLQ", title);
        ingressStagingService.releaseObject(event.ingressItemId());
        markAssetFailed(event.assetId(), title);
        notificationPublisher.notifyOrLog(
                event.ownerUserId(),
                "BACKDROP_SECURITY",
                title,
                message,
                Map.of("assetId", event.assetId().toString())
        );
    }

    private void markAssetFailed(UUID assetId, String reason) {
        backdropAssetRepository.findById(assetId).ifPresent(asset -> {
            if (asset.getStatus() == BackdropAssetStatus.READY) {
                return;
            }
            asset.setStatus(BackdropAssetStatus.FAILED);
            asset.setFailReason(bound(reason));
            backdropAssetRepository.save(asset);
            storageQuotaService.releaseReservation("BACKDROP_UPLOAD", assetId);
        });
    }

    private BackdropSecurityScanRequestedEvent rebuildEvent(UUID taskId, StaleTaskRecovery recovery) {
        Map<String, Object> payload = Map.of();
        Optional<TaskRecord> record = taskRecordService.findTaskRecord(taskId);
        if (record.isPresent() && record.get().getPayload() != null) {
            payload = JSON.parseObject(record.get().getPayload());
        }
        UUID assetId = parseUuid(payload.get("assetId"));
        return new BackdropSecurityScanRequestedEvent(
                taskId,
                recovery.ownerUserId(),
                assetId == null ? recovery.resourceId() : assetId,
                parseUuid(payload.get("ingressItemId")),
                payload.get("originalFileName") == null ? "" : payload.get("originalFileName").toString()
        );
    }

    private UUID parseUuid(Object raw) {
        if (raw == null) {
            return null;
        }
        String value = raw.toString();
        return value.isBlank() ? null : UUID.fromString(value);
    }

    private String assetTitle(UUID assetId) {
        return backdropAssetRepository.findById(assetId)
                .map(BackdropAsset::getTitle)
                .orElse("未知素材");
    }

    private String bound(String message) {
        if (message == null || message.isBlank()) {
            return "安全扫描未完成";
        }
        return message.length() <= FAIL_REASON_MAX_LENGTH ? message : message.substring(0, FAIL_REASON_MAX_LENGTH);
    }

    private Duration retryDelay(int retryCount) {
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }
}
