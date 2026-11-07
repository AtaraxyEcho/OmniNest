package com.omninest.worker.support;

import com.omninest.common.task.DomainTaskFailureConvergence;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 死信终态下的领域表收敛分发器。
 *
 * <p>恢复调度器只裁决 {@code sys_tasks}，业务表状态由各模块自己的收敛器维护；
 * 这里按任务类型查找唯一实现。找不到实现时只记日志——那意味着该任务类型确实没有
 * 领域表（如 PHOTO_THUMBNAILS、THUMBNAIL 等纯派生任务），不是配置遗漏。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class DomainTaskFailureConverger {

    private final List<DomainTaskFailureConvergence> convergences;

    /**
     * 把领域任务行收敛为失败终态。
     *
     * @param taskType 系统任务类型
     * @param taskId 系统任务 ID
     * @param reason 失败原因摘要
     */
    public void converge(String taskType, UUID taskId, String reason) {
        for (DomainTaskFailureConvergence convergence : convergences) {
            if (convergence.supports(taskType)) {
                convergence.converge(taskId, reason);
                return;
            }
        }
        log.debug("任务类型没有领域表收敛器，跳过: taskType={}, taskId={}", taskType, taskId);
    }
}
