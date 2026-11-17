package com.omninest.modules.task.service;

import java.time.Instant;
import java.util.UUID;

/**
 * 任务 Outbox 发布失败后的脱敏死信载荷。
 *
 * @param taskId 任务 ID
 * @param dispatchId Outbox 记录 ID
 * @param originalExchange 原交换机
 * @param originalRoutingKey 原路由键
 * @param sanitizedPayload 脱敏后的原任务载荷
 * @param attemptCount 总投递次数
 * @param errorCode 稳定错误码
 * @param failureType 失败类型摘要
 * @param publisherInstanceId 发布实例标识
 * @param failedAt 失败时间
 * @author OmniNest
 */
public record TaskDispatchDeadLetter(
        UUID taskId,
        UUID dispatchId,
        String originalExchange,
        String originalRoutingKey,
        Object sanitizedPayload,
        int attemptCount,
        String errorCode,
        String failureType,
        String publisherInstanceId,
        Instant failedAt
) {
}
