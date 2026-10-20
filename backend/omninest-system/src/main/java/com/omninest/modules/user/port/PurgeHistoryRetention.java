package com.omninest.modules.user.port;

import java.time.Instant;

/**
 * 文件物理删除清单的历史保留能力，由 File 模块实现。
 *
 * <p>清理动作按任务维度写入的条目行数最多，长期保留会让表体积只增不减；
 * 保留策略统一由系统历史清理调度器掌握，本端口只暴露分批删除能力。</p>
 *
 * @author OmniNest
 */
public interface PurgeHistoryRetention {

    /**
     * 分批删除截止时间前已完成的物理删除条目。
     *
     * @param cutoff 截止时间，早于该时刻创建的条目被删除
     * @param batchSize 单批数量
     * @return 删除条数
     */
    int deleteCompletedEntriesBefore(Instant cutoff, int batchSize);
}
