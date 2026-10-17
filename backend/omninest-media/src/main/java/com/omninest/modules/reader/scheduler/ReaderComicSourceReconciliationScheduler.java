package com.omninest.modules.reader.scheduler;

import com.omninest.modules.reader.service.ReaderComicSourceReconciliationService;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 漫画来源排序元数据对账调度器。
 *
 * <p>仅在 scheduler 运行角色节点生效，与背景库（3:40）、音乐封面（4:10）对账错开时间。
 * 调度器只做分页与失败隔离，回正判定与落库在 service 内按条目各自成事务。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(prefix = "omninest.runtime", name = "role", havingValue = "scheduler")
public class ReaderComicSourceReconciliationScheduler {

    /** 每页条目数。 */
    private static final int PAGE_SIZE = 100;

    /** 单轮扫描页数上限，超大库留给下一轮，避免一次调度占满连接。 */
    private static final int MAX_PAGES = 100;

    private final ReaderComicSourceReconciliationService reconciliationService;

    /**
     * 每天凌晨 4:40 回正漫画来源排序元数据。
     */
    @Scheduled(cron = "0 40 4 * * *")
    public void reconcile() {
        log.info("漫画来源排序元数据对账调度开始");
        int scanned = 0;
        int healed = 0;
        for (int page = 0; page < MAX_PAGES; page++) {
            List<UUID> itemIds = reconciliationService.findReconcileCandidateIds(page, PAGE_SIZE);
            if (itemIds.isEmpty()) {
                break;
            }
            for (UUID itemId : itemIds) {
                scanned++;
                try {
                    if (reconciliationService.reconcileItem(itemId)) {
                        healed++;
                    }
                } catch (RuntimeException ex) {
                    log.error("漫画来源排序元数据对账失败: itemId={}", itemId, ex);
                }
            }
            if (itemIds.size() < PAGE_SIZE) {
                break;
            }
        }
        log.info("漫画来源排序元数据对账结束: 扫描条目={}, 回正条目={}", scanned, healed);
    }
}
