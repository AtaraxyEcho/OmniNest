package com.omninest.modules.music.scheduler;

import com.omninest.modules.music.service.MusicCoverReconciliationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 音乐封面派生资产对账调度器。
 *
 * <p>仅在 scheduler 运行角色节点生效，与背景库对账错开时间，避免同一时刻集中扫描。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(prefix = "omninest.runtime", name = "role", havingValue = "scheduler")
public class MusicCoverReconciliationScheduler {

    private final MusicCoverReconciliationService musicCoverReconciliationService;

    /**
     * 每天凌晨 4:10 执行音乐封面派生资产对账。
     */
    @Scheduled(cron = "0 10 4 * * *")
    public void reconcile() {
        log.info("音乐封面资产对账调度开始");
        musicCoverReconciliationService.reconcile();
        log.info("音乐封面资产对账调度结束");
    }
}
