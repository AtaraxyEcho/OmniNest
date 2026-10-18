package com.omninest.modules.quota.scheduler;

import com.omninest.modules.quota.service.StorageQuotaService;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 在 Scheduler 角色中定时校准用户存储配额。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
@ConditionalOnExpression("'${omninest.runtime.role:api}' == 'scheduler' || "
        + "('${omninest.runtime.role:api}' == 'api' && ${omninest.runtime.embedded-scheduler-enabled:false})")
public class StorageQuotaScheduler {

    private final StorageQuotaService storageQuotaService;

    /**
     * 每天凌晨 5 点执行存储用量校准。
     */
    @Scheduled(cron = "0 0 5 * * *")
    public void reconcileQuotaUsage() {
        storageQuotaService.reconcileQuotaUsage();
    }

    /**
     * 每十分钟有界回收过期的存储配额预留。
     */
    @Scheduled(fixedDelay = 600_000L)
    public void reclaimExpiredReservations() {
        storageQuotaService.reclaimExpiredReservations();
    }
}
