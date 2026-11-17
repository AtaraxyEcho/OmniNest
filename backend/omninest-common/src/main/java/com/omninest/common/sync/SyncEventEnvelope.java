package com.omninest.common.sync;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * RabbitMQ 内部传输使用的同步事件信封。
 *
 * @param schemaVersion 客户端契约版本
 * @param routingVersion 内部路由版本
 * @param eventId 事件标识
 * @param sequenceNo 全局事件序号
 * @param recipientUserId 接收用户标识
 * @param scope 业务作用域
 * @param resourceType 资源类型
 * @param resourceId 资源标识
 * @param action 事件动作
 * @param resourceVersion 资源版本
 * @param hints 非敏感刷新提示
 * @param occurredAt 事件发生时间
 * @param publishedAt 消息发布时间
 * @author OmniNest
 */
public record SyncEventEnvelope(
        int schemaVersion,
        int routingVersion,
        UUID eventId,
        long sequenceNo,
        UUID recipientUserId,
        SyncScope scope,
        String resourceType,
        String resourceId,
        SyncAction action,
        Long resourceVersion,
        Map<String, Object> hints,
        Instant occurredAt,
        Instant publishedAt
) {
}
