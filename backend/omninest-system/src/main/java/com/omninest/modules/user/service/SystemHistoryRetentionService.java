package com.omninest.modules.user.service;

import com.omninest.modules.configcenter.service.ConfigHistoryRetentionService;
import com.omninest.modules.notification.port.NotificationMaintenance;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.user.config.SystemHistoryRetentionProperties;
import com.omninest.modules.user.port.PurgeHistoryRetention;
import com.omninest.modules.user.repository.AuditLogRetentionRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.function.IntSupplier;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 在 Scheduler 角色中分批清理终态任务、Outbox 投递记录、文件物理删除条目、
 * 审计日志、配置历史和已读站内通知。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnExpression("'${omninest.runtime.role:api}' == 'scheduler' || "
        + "('${omninest.runtime.role:api}' == 'api' && ${omninest.runtime.embedded-scheduler-enabled:false})")
public class SystemHistoryRetentionService {

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final AuditLogRetentionRepository auditLogRepository;
    private final ConfigHistoryRetentionService configHistoryRetentionService;
    private final PurgeHistoryRetention purgeHistoryRetention;
    private final NotificationMaintenance notificationMaintenance;
    private final SystemHistoryRetentionProperties properties;

    /**
     * 按配置的保留时间和批次数量清理系统历史记录。
     */
    @Scheduled(cron = "${omninest.history-retention.cleanup-cron:0 30 3 * * *}")
    @Transactional(rollbackFor = Exception.class)
    public void cleanup() {
        if (!properties.isEnabled()) {
            return;
        }
        int batchSize = Math.max(1, Math.min(properties.getBatchSize(), 5000));
        int maximumBatches = Math.max(1, Math.min(properties.getMaximumBatches(), 100));
        Instant now = Instant.now();

        int deletedTasks = cleanupTasks(now, batchSize, maximumBatches);
        int deletedDispatches = cleanupDispatches(now, batchSize, maximumBatches);
        int deletedPurgeEntries = cleanupPurgeEntries(now, batchSize, maximumBatches);
        int deletedAuditLogs = cleanupAuditLogs(now, batchSize, maximumBatches);
        int deletedConfigHistories = cleanupConfigHistories(now, batchSize, maximumBatches);
        int deletedNotifications = cleanupNotifications(now, batchSize, maximumBatches);
        log.info("系统历史保留清理完成: deletedTasks={}, deletedDispatches={}, deletedPurgeEntries={}, "
                        + "deletedAuditLogs={}, deletedConfigHistories={}, deletedNotifications={}",
                deletedTasks, deletedDispatches, deletedPurgeEntries,
                deletedAuditLogs, deletedConfigHistories, deletedNotifications);
    }

    /**
     * 清理超期的已读站内通知。
     *
     * <p>通知表带 jsonb 元数据且按用户高频写入，是站内消息类表里增长最快的一张；
     * 未读项保留到用户读过为止。</p>
     */
    private int cleanupNotifications(Instant now, int batchSize, int maximumBatches) {
        Duration maximumAge = properties.getNotificationMaximumAge();
        if (!isPositive(maximumAge)) {
            log.warn("站内通知保留时间配置无效，跳过通知清理");
            return 0;
        }
        Instant cutoff = now.minus(maximumAge);
        return deleteBatches(
                () -> notificationMaintenance.deleteReadNotificationsBefore(cutoff, batchSize),
                batchSize,
                maximumBatches
        );
    }

    /**
     * 清理超期的已发布 Outbox 投递行。
     *
     * <p>每条投递都带完整 JSON 载荷，是三类表里体积增长最快的一张。</p>
     */
    private int cleanupDispatches(Instant now, int batchSize, int maximumBatches) {
        Duration maximumAge = properties.getDispatchMaximumAge();
        if (!isPositive(maximumAge)) {
            log.warn("Outbox 投递记录保留时间配置无效，跳过投递清理");
            return 0;
        }
        Instant cutoff = now.minus(maximumAge);
        return deleteBatches(
                () -> taskDispatchService.deletePublishedBatchBefore(cutoff, batchSize),
                batchSize,
                maximumBatches
        );
    }

    /**
     * 清理超期的文件物理删除条目（仅成功终态）。
     */
    private int cleanupPurgeEntries(Instant now, int batchSize, int maximumBatches) {
        Duration maximumAge = properties.getPurgeEntryMaximumAge();
        if (!isPositive(maximumAge)) {
            log.warn("物理删除条目保留时间配置无效，跳过删除清单清理");
            return 0;
        }
        Instant cutoff = now.minus(maximumAge);
        return deleteBatches(
                () -> purgeHistoryRetention.deleteCompletedEntriesBefore(cutoff, batchSize),
                batchSize,
                maximumBatches
        );
    }

    private int cleanupTasks(Instant now, int batchSize, int maximumBatches) {
        Duration maximumAge = properties.getTaskMaximumAge();
        if (!isPositive(maximumAge)) {
            log.warn("任务历史保留时间配置无效，跳过任务清理");
            return 0;
        }
        Instant cutoff = now.minus(maximumAge);
        return deleteBatches(
                () -> taskRecordService.deleteTerminalTaskBatchUpdatedBefore(cutoff, batchSize),
                batchSize,
                maximumBatches
        );
    }

    private int cleanupAuditLogs(Instant now, int batchSize, int maximumBatches) {
        Duration maximumAge = properties.getAuditMaximumAge();
        if (!isPositive(maximumAge)) {
            log.warn("审计日志保留时间配置无效，跳过审计清理");
            return 0;
        }
        Instant cutoff = now.minus(maximumAge);
        return deleteBatches(
                () -> deleteAuditBatch(cutoff, batchSize),
                batchSize,
                maximumBatches
        );
    }

    private int deleteAuditBatch(Instant cutoff, int batchSize) {
        List<UUID> ids = auditLogRepository.findIdsCreatedBefore(
                cutoff,
                PageRequest.of(0, batchSize)
        );
        if (ids.isEmpty()) {
            return 0;
        }
        return auditLogRepository.deleteByIds(ids);
    }

    private int cleanupConfigHistories(Instant now, int batchSize, int maximumBatches) {
        Duration maximumAge = properties.getConfigMaximumAge();
        if (!isPositive(maximumAge)) {
            log.warn("配置历史保留时间配置无效，跳过配置历史清理");
            return 0;
        }
        int minimumVersions = Math.max(1, Math.min(properties.getConfigMinimumVersions(), 100));
        Instant cutoff = now.minus(maximumAge);
        return deleteBatches(
                () -> configHistoryRetentionService.deleteExpiredBatch(cutoff, minimumVersions, batchSize),
                batchSize,
                maximumBatches
        );
    }

    private int deleteBatches(IntSupplier deleteBatch, int batchSize, int maximumBatches) {
        int total = 0;
        for (int batch = 0; batch < maximumBatches; batch++) {
            int deleted = deleteBatch.getAsInt();
            total += deleted;
            if (deleted < batchSize) {
                break;
            }
        }
        return total;
    }

    private boolean isPositive(Duration duration) {
        return duration != null && !duration.isZero() && !duration.isNegative();
    }
}
