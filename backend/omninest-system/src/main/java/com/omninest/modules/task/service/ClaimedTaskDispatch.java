package com.omninest.modules.task.service;

import java.util.UUID;

/**
 * 已领取的任务投递记录快照。
 *
 * @param id 投递记录 ID
 * @param taskId 任务 ID
 * @param exchangeName 交换机名称
 * @param routingKey 路由键
 * @param payload JSON 载荷
 * @param attemptCount 已尝试次数
 * @param lastErrorCode 最近一次投递错误码
 * @author OmniNest
 */
public record ClaimedTaskDispatch(
        UUID id,
        UUID taskId,
        String exchangeName,
        String routingKey,
        String payload,
        int attemptCount,
        String lastErrorCode
) {
}
