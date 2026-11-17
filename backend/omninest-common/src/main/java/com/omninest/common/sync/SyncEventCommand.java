package com.omninest.common.sync;

import java.util.Map;
import java.util.UUID;

/**
 * 业务服务写入用户同步事件时使用的命令。
 *
 * @param recipientUserId 接收事件的用户标识
 * @param scope 业务作用域
 * @param resourceType 资源类型
 * @param resourceId 资源标识
 * @param action 事件动作
 * @param resourceVersion 资源版本
 * @param hints 非敏感刷新提示
 * @author OmniNest
 */
public record SyncEventCommand(
        UUID recipientUserId,
        SyncScope scope,
        String resourceType,
        String resourceId,
        SyncAction action,
        Long resourceVersion,
        Map<String, Object> hints
) {
}
