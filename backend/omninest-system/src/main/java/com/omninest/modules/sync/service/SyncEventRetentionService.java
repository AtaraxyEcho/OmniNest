package com.omninest.modules.sync.service;

import com.omninest.modules.sync.config.SyncEventProperties;
import com.omninest.modules.sync.domain.SyncEventCheckpoint;
import com.omninest.modules.sync.repository.SyncEventCheckpointRepository;
import com.omninest.modules.sync.repository.SyncEventRepository;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import com.omninest.modules.task.runtime.ConditionalOnSchedulerRuntime;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Scheduler 角色中运行的已发布同步事件保留清理服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnSchedulerRuntime
public class SyncEventRetentionService {

    private static final String RETENTION_FLOOR_KEY = "retention_floor";

    private final SyncEventRepository syncEventRepository;
    private final SyncEventCheckpointRepository checkpointRepository;
    private final SyncEventProperties properties;

    /**
     * 更新保留水位后批量删除达到保留期限的已发布事件。
     */
    @Scheduled(cron = "${omninest.sync.retention.cleanup-cron:0 15 2 * * *}")
    @Transactional(rollbackFor = Exception.class)
    public void cleanup() {
        if (!properties.getRetention().isEnabled()) {
            return;
        }
        int retentionDays = Math.max(1, properties.getRetention().getDays());
        Instant cutoff = Instant.now().minus(retentionDays, ChronoUnit.DAYS);
        SyncEventCheckpoint checkpoint = checkpointRepository
                .findForUpdateByCheckpointKey(RETENTION_FLOOR_KEY)
                .orElseGet(this::newCheckpoint);
        long cleanupFloor = resolveCleanupFloor(cutoff);
        if (cleanupFloor <= checkpoint.getSequenceNo()) {
            return;
        }
        checkpoint.setSequenceNo(Math.max(checkpoint.getSequenceNo(), cleanupFloor));
        checkpointRepository.saveAndFlush(checkpoint);
        int deleted = syncEventRepository.deletePublishedBefore(cutoff, cleanupFloor);
        log.info("同步事件保留清理完成: deleted={}, retentionFloor={}", deleted, checkpoint.getSequenceNo());
    }

    private long resolveCleanupFloor(Instant cutoff) {
        Long firstProtectedSequence = syncEventRepository.findFirstProtectedSequence(cutoff);
        if (firstProtectedSequence == null) {
            return syncEventRepository.findLatestSequenceNo();
        }
        return Math.max(0L, firstProtectedSequence - 1L);
    }

    private SyncEventCheckpoint newCheckpoint() {
        SyncEventCheckpoint checkpoint = new SyncEventCheckpoint();
        checkpoint.setId(UUID.randomUUID());
        checkpoint.setCheckpointKey(RETENTION_FLOOR_KEY);
        checkpoint.setSequenceNo(0L);
        return checkpoint;
    }
}
