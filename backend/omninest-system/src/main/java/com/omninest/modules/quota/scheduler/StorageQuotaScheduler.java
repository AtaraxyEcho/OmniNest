package com.omninest.modules.quota.scheduler;

import com.omninest.modules.quota.port.SharedSpaceUsageReconcile;
import com.omninest.modules.quota.service.StorageQuotaService;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 在 Scheduler 角色中定时校准用户存储配额与共享空间用量账本。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
@ConditionalOnExpression("'${omninest.runtime.role:api}' == 'scheduler' || "
        + "('${omninest.runtime.role:api}' == 'api' && ${omninest.runtime.embedded-scheduler-enabled:false})")
public class StorageQuotaScheduler {

    private final StorageQuotaService storageQuotaService;
    private final SharedSpaceUsageReconcile sharedSpaceUsageReconcile;

    /**
     * 每天凌晨 5 点执行存储用量校准。
     *
     * <p>两张账本同批对账：个人配额按用户重算，共享空间按单行账本重算，
     * 缺一侧都会让偏差永久累积到判满。</p>
     */
    @Scheduled(cron = "0 0 5 * * *")
    public void reconcileQuotaUsage() {
        storageQuotaService.reconcileQuotaUsage();
        sharedSpaceUsageReconcile.reconcileUsage();
    }

    /**
     * 每十分钟有界回收过期的存储配额预留。
     */
    @Scheduled(fixedDelay = 600_000L)
    public void reclaimExpiredReservations() {
        storageQuotaService.reclaimExpiredReservations();
    }
}
