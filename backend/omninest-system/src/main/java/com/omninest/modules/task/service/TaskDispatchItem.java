package com.omninest.modules.task.service;

import java.util.UUID;

/**
 * 批量投递中的单条 Outbox 记录。
 *
 * <p>批量投递共用交换机与路由键，载荷逐条不同，任务标识由调用方显式给出。</p>
 *
 * @param taskId 任务标识
 * @param payload 消息载荷
 * @author OmniNest
 */
public record TaskDispatchItem(UUID taskId, Object payload) {
}
