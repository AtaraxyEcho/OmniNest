package com.omninest.modules.task.service;

import java.time.Instant;
import java.util.UUID;

/**
 * 心跳超时任务恢复结果。
 *
 * @param recovered 是否完成状态裁决
 * @param deadLetter 是否进入死信终态
 * @param ownerUserId 所属用户 ID
 * @param resourceId 关联资源 ID
 * @param retryCount 当前重试次数
 * @param nextRetryAt 下次重试时间
 * @author OmniNest
 */
public record StaleTaskRecovery(
        boolean recovered,
        boolean deadLetter,
        UUID ownerUserId,
        UUID resourceId,
        int retryCount,
        Instant nextRetryAt
) {
    /**
     * 创建未执行恢复的结果。
     *
     * @return 未恢复结果
     */
    public static StaleTaskRecovery ignored() {
        return new StaleTaskRecovery(false, false, null, null, 0, null);
    }
}
