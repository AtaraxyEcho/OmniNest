package com.omninest.modules.file.service;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.FileIngressItem;
import com.omninest.modules.file.domain.FileIngressStatus;
import com.omninest.modules.file.repository.FileIngressItemRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import com.omninest.modules.task.runtime.ConditionalOnSchedulerRuntime;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
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
@ConditionalOnSchedulerRuntime
public class FileQuarantineReaperScheduler {
    private static final String RETENTION_DAYS_KEY = "security.quarantine.retention-days";
    private static final int DEFAULT_RETENTION_DAYS = 7;
    private static final int REAP_BATCH_SIZE = 200;
    private static final List<FileIngressStatus> REAPABLE_STATUSES = List.of(
            FileIngressStatus.PENDING_SCAN,
            FileIngressStatus.SCANNING,
            FileIngressStatus.REJECTED,
            FileIngressStatus.FAILED
    );

    /**
     * 入库来源与配额预留来源不同名：背景素材按素材 ID 预留，上传会话由会话取消路径释放。
     * 只为逐条预留的来源建立映射，外部导入的任务级预留不得在此按条目释放。
     */
    private static final Map<String, String> RESERVATION_SOURCE_BY_INGRESS_SOURCE =
            Map.of("BACKDROP", "BACKDROP_UPLOAD");

    private final FileIngressItemRepository ingressItemRepository;
    private final ObjectStorageClient objectStorageClient;
    private final FileUploadCancellationService fileUploadCancellationService;
    private final FileUploadSessionRepository uploadSessionRepository;
    private final StorageQuotaService storageQuotaService;
    private final ConfigValueProvider configValueProvider;
    private final RuntimeConfigCache runtimeConfigCache;

    /**
     * 每日回收滞留隔离对象。
     */
    @Scheduled(cron = "0 40 4 * * *")
    public void reapExpiredQuarantineItems() {
        Instant cutoff = Instant.now().minus(retentionDays(), ChronoUnit.DAYS);
        Page<FileIngressItem> expired = ingressItemRepository.findByStatusInAndUpdatedAtBefore(
                REAPABLE_STATUSES,
                cutoff,
                PageRequest.of(0, REAP_BATCH_SIZE));
        if (expired.isEmpty()) {
            return;
        }
        int reaped = 0;
        for (FileIngressItem item : expired.getContent()) {
            try {
                if (reapOne(item)) {
                    reaped++;
                }
            } catch (Exception exception) {
                log.warn("隔离对象回收失败: ingressItemId={}, errorType={}",
                        item.getId(), exception.getClass().getSimpleName());
            }
        }
        log.info("隔离滞留对象回收完成: candidates={}, reaped={}", expired.getNumberOfElements(), reaped);
    }

    private boolean reapOne(FileIngressItem item) {
        // 查询与删除之间 Worker 可能已完成扫描并晋升为 AVAILABLE：先做带状态条件的
        // 原子删除，只有仍处于可回收状态的记录才允许删对象与释放配额。
        int deleted = ingressItemRepository.deleteByIdAndStatusIn(item.getId(), REAPABLE_STATUSES);
        if (deleted == 0) {
            log.info("隔离记录状态已变化，跳过回收: ingressItemId={}", item.getId());
            return false;
        }
        objectStorageClient.removeObject(
                new ObjectStorageKey(item.getQuarantineBucket(), item.getQuarantineObjectKey()));
        cancelLinkedSessionQuietly(item);
        releaseReservationQuietly(item);
        log.info("隔离滞留对象已回收: ingressItemId={}, sourceType={}", item.getId(), item.getSourceType());
        return true;
    }

    /**
     * 释放按条目预留的配额。上传会话的预留由会话取消路径处理，
     * 外部导入的预留由导入任务整体结算，均不在此处按条目释放。
     */
    private void releaseReservationQuietly(FileIngressItem item) {
        String reservationSource = RESERVATION_SOURCE_BY_INGRESS_SOURCE.get(item.getSourceType());
        if (reservationSource == null || item.getSourceTaskId() == null) {
            return;
        }
        try {
            storageQuotaService.releaseReservation(reservationSource, item.getSourceTaskId());
        } catch (RuntimeException exception) {
            log.warn("滞留入库记录配额释放失败: ingressItemId={}, source={}, errorType={}",
                    item.getId(), reservationSource, exception.getClass().getSimpleName());
        }
    }

    private void cancelLinkedSessionQuietly(FileIngressItem item) {
        if (item.getUploadSessionId() == null) {
            return;
        }
        uploadSessionRepository.findById(item.getUploadSessionId())
                .filter(session -> !"COMPLETED".equals(session.getStatus()))
                .ifPresent(session -> {
                    try {
                        fileUploadCancellationService.forceCancelForCleanup(session.getOwnerUserId(), session.getUploadId());
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
