package com.omninest.modules.sync.service;

import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * Outbox 调度器持有发布租约的同步事件快照。
 *
 * @param id 事件标识
 * @param sequenceNo 全局事件序号
 * @param recipientUserId 接收用户标识
 * @param scope 业务作用域
 * @param resourceType 资源类型
 * @param resourceId 资源标识
 * @param action 事件动作
 * @param resourceVersion 资源版本
 * @param hints 非敏感刷新提示
 * @param occurredAt 事件发生时间
 * @param publishAttempts 已失败尝试次数
 * @author OmniNest
 */
public record ClaimedSyncEvent(
        UUID id,
        long sequenceNo,
        UUID recipientUserId,
        SyncScope scope,
        String resourceType,
        String resourceId,
        SyncAction action,
        Long resourceVersion,
        Map<String, Object> hints,
        Instant occurredAt,
        int publishAttempts
) {
}
