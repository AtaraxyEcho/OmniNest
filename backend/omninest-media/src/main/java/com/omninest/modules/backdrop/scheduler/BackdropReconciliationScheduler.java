package com.omninest.modules.backdrop.scheduler;

import com.omninest.modules.backdrop.service.BackdropReconciliationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 背景库对账调度器。
 * 每日凌晨执行孤儿清理、缺失对象标记与卡死任务自愈,仅在 scheduler 运行角色节点生效。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(prefix = "omninest.runtime", name = "role", havingValue = "scheduler")
public class BackdropReconciliationScheduler {

    private final BackdropReconciliationService backdropReconciliationService;

    /**
     * 每天凌晨 3:40 执行背景库对账。
     */
    @Scheduled(cron = "0 40 3 * * *")
    public void reconcile() {
        log.info("背景库对账调度开始");
        backdropReconciliationService.reconcile();
        log.info("背景库对账调度结束");
    }
}
