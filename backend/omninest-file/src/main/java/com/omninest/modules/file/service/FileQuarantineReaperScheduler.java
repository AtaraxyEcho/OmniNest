package com.omninest.modules.file.service;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.FileIngressItem;
import com.omninest.modules.file.domain.FileIngressStatus;
import com.omninest.modules.file.repository.FileIngressItemRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * 在 Scheduler 角色中回收滞留隔离对象:扫描终态失败或长期停留在在途状态的入库记录,
 * 到达保留期后删除隔离对象并清理记录;关联的上传会话仍处于未完成状态时一并取消,
 * 由会话取消路径释放配额预留。保留期通过配置中心 security.quarantine.retention-days 调整。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(prefix = "omninest.runtime", name = "role", havingValue = "scheduler")
public class FileQuarantineReaperScheduler {
    private static final String RETENTION_DAYS_KEY = "security.quarantine.retention-days";
    private static final int DEFAULT_RETENTION_DAYS = 7;

    private final FileIngressItemRepository ingressItemRepository;
    private final ObjectStorageClient objectStorageClient;
    private final FileUploadSessionService fileUploadSessionService;
    private final FileUploadSessionRepository uploadSessionRepository;
    private final ConfigValueProvider configValueProvider;
    private final RuntimeConfigCache runtimeConfigCache;

    /**
     * 每日回收滞留隔离对象。
     */
    @Scheduled(cron = "0 40 4 * * *")
    public void reapExpiredQuarantineItems() {
        Instant cutoff = Instant.now().minus(retentionDays(), ChronoUnit.DAYS);
        List<FileIngressItem> expired = ingressItemRepository.findByStatusInAndUpdatedAtBefore(
                List.of(
                        FileIngressStatus.PENDING_SCAN,
                        FileIngressStatus.SCANNING,
                        FileIngressStatus.REJECTED,
                        FileIngressStatus.FAILED
                ),
                cutoff);
        if (expired.isEmpty()) {
            return;
        }
        int reaped = 0;
        for (FileIngressItem item : expired) {
            try {
                reapOne(item);
                reaped++;
            } catch (Exception exception) {
                log.warn("隔离对象回收失败: ingressItemId={}, errorType={}",
                        item.getId(), exception.getClass().getSimpleName());
            }
        }
        log.info("隔离滞留对象回收完成: candidates={}, reaped={}", expired.size(), reaped);
    }

    private void reapOne(FileIngressItem item) {
        objectStorageClient.removeObject(
                new ObjectStorageKey(item.getQuarantineBucket(), item.getQuarantineObjectKey()));
        ingressItemRepository.delete(item);
        cancelLinkedSessionQuietly(item);
        log.info("隔离滞留对象已回收: ingressItemId={}, sourceType={}", item.getId(), item.getSourceType());
    }

    private void cancelLinkedSessionQuietly(FileIngressItem item) {
        if (item.getUploadSessionId() == null) {
            return;
        }
        uploadSessionRepository.findById(item.getUploadSessionId())
                .filter(session -> !"COMPLETED".equals(session.getStatus()))
                .ifPresent(session -> {
                    try {
                        fileUploadSessionService.cancelSession(session.getOwnerUserId(), session.getUploadId());
                    } catch (Exception exception) {
                        log.warn("滞留上传会话取消失败: uploadId={}, errorType={}",
                                session.getUploadId(), exception.getClass().getSimpleName());
                    }
                });
    }

    private int retentionDays() {
        Optional<String> configured = runtimeConfigCache.get(RETENTION_DAYS_KEY)
                .or(() -> configValueProvider.findByKey(RETENTION_DAYS_KEY));
        return configured
                .map(value -> {
                    try {
                        return Integer.parseInt(value.trim());
                    } catch (RuntimeException exception) {
                        return DEFAULT_RETENTION_DAYS;
                    }
                })
                .filter(days -> days >= 1 && days <= 90)
                .orElse(DEFAULT_RETENTION_DAYS);
    }
}
