package com.omninest.modules.photos.service;

import com.omninest.modules.photos.repository.PhotoItemRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import com.omninest.modules.task.runtime.ConditionalOnSchedulerRuntime;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 回收站过期清理调度：对进入回收站超过保留期的照片创建永久删除任务。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnSchedulerRuntime
public class PhotoTrashCleanupScheduler {

    /** 回收站保留天数。 */
    private static final int RETENTION_DAYS = 30;

    private final PhotoItemRepository photoItemRepository;
    private final PhotoLibraryService photoLibraryService;

    /**
     * 每天凌晨 3:30 清理超过保留期的回收站照片。
     */
    @Scheduled(cron = "0 30 3 * * *")
    public void purgeExpiredTrash() {
        Instant cutoff = Instant.now().minus(Duration.ofDays(RETENTION_DAYS));
        List<UUID> ownerIds = photoItemRepository.findOwnerIdsWithExpiredTrash(cutoff);
        for (UUID ownerId : ownerIds) {
            try {
                photoLibraryService.purgeExpiredTrashForOwner(ownerId, cutoff);
            } catch (Exception ex) {
                log.error("回收站过期照片清理失败: userId={}", ownerId, ex);
            }
        }
        if (!ownerIds.isEmpty()) {
            log.info("回收站过期清理调度完成: ownerCount={}", ownerIds.size());
        }
    }
}
