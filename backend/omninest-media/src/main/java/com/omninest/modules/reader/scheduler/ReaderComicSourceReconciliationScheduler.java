package com.omninest.modules.reader.scheduler;

import com.omninest.modules.reader.service.ReaderComicSourceReconciliationService;
import com.omninest.modules.reader.service.ReaderComicSourceReconciliationService.ReconcileOutcome;
import java.time.Duration;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 漫画来源排序元数据对账调度器。
 *
 * <p>仅在 scheduler 运行角色节点生效，落在同步事件保留（2:15）与照片背景回收（3:30 起）
 * 之间的空档。调度器只做游标推进、时长预算与失败隔离，回正判定与落库在 service 内按条目
 * 各自成事务。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnExpression("'${omninest.runtime.role:api}' == 'scheduler' || "
        + "('${omninest.runtime.role:api}' == 'api' && ${omninest.runtime.embedded-scheduler-enabled:false})")
public class ReaderComicSourceReconciliationScheduler {

    /** 每段条目数。 */
    private static final int PAGE_SIZE = 100;

    /** 试运行：只统计规模，不落库、不重建清单。 */
    @Value("${omninest.reader.source-metadata-reconcile.dry-run:false}")
    private boolean dryRun;

    /** 单轮时长预算，超预算则带游标退出，下一轮从断点继续。 */
    @Value("${omninest.reader.source-metadata-reconcile.max-duration:PT5M}")
    private Duration maxDuration = Duration.ofMinutes(5);

    private final ReaderComicSourceReconciliationService reconciliationService;

    /**
     * 游标在进程内推进；重启即从头巡检，回正本身幂等，重复扫描只是空跑。
     */
    private volatile UUID cursor = ReaderComicSourceReconciliationService.FIRST_CURSOR;

    /**
     * 每天凌晨 2:50 回正漫画来源排序元数据。
     */
    @Scheduled(cron = "0 50 2 * * *")
    public void reconcile() {
        long deadlineNanos = System.nanoTime() + maxDuration.toNanos();
        int scanned = 0;
        int metadataUpdated = 0;
        int manifestRebuilt = 0;
        boolean budgetExhausted = false;
        log.info("漫画来源排序元数据对账开始: startCursor={}, dryRun={}", cursor, dryRun);
        while (true) {
            List<UUID> itemIds = reconciliationService.findReconcileCandidateIds(cursor, PAGE_SIZE);
            if (itemIds.isEmpty()) {
                cursor = ReaderComicSourceReconciliationService.FIRST_CURSOR;
                break;
            }
            for (UUID itemId : itemIds) {
                scanned++;
                cursor = itemId;
                try {
                    ReconcileOutcome outcome = dryRun
                            ? reconciliationService.previewItem(itemId)
                            : reconciliationService.reconcileItem(itemId);
                    if (outcome != ReconcileOutcome.UNCHANGED) {
                        metadataUpdated++;
                    }
                    if (outcome == ReconcileOutcome.REBUILD_REQUIRED) {
                        manifestRebuilt++;
                    }
                } catch (RuntimeException ex) {
                    log.error("漫画来源排序元数据对账失败: itemId={}", itemId, ex);
                }
                if (System.nanoTime() >= deadlineNanos) {
                    budgetExhausted = true;
                    break;
                }
            }
            if (budgetExhausted || itemIds.size() < PAGE_SIZE) {
                break;
            }
        }
        log.info("漫画来源排序元数据对账结束: 扫描条目={}, 待回正条目={}, 需重建目录={}, 触及预算={}, 下轮游标={}",
                scanned, metadataUpdated, manifestRebuilt, budgetExhausted, cursor);
    }
}
