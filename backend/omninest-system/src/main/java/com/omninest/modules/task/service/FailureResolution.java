package com.omninest.modules.task.service;

import java.time.Instant;

/**
 * 消费者失败裁决结果。
 *
 * @param resolved 任务是否存在且仍可裁决
 * @param deadLetter 是否已进入死信终态
 * @param retryCount 当前重试次数
 * @param nextRetryAt 下次执行时间；进入死信或忽略时为 null
 * @author OmniNest
 */
public record FailureResolution(
        boolean resolved,
        boolean deadLetter,
        int retryCount,
        Instant nextRetryAt
) {
    /**
     * 创建未执行裁决的结果。
     *
     * @return 忽略结果
     */
    public static FailureResolution ignored() {
        return new FailureResolution(false, false, 0, null);
    }
}
