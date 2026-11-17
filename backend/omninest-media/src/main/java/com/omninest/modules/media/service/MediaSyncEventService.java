package com.omninest.modules.media.service;

import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 媒体模块同步事件协议适配服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MediaSyncEventService {

    private final UserSyncEventRecorder syncEventRecorder;

    /**
     * 在当前业务事务中记录媒体同步事件。
     *
     * @param recipientUserId 接收用户标识
     * @param scope 媒体业务作用域
     * @param resourceType 资源类型
     * @param resourceId 资源标识
     * @param action 变更动作
     * @param resourceVersion 资源版本
     * @param hints 非敏感刷新提示
     */
    public void record(
            UUID recipientUserId,
            SyncScope scope,
            String resourceType,
            String resourceId,
            SyncAction action,
            Long resourceVersion,
            Map<String, Object> hints
    ) {
        syncEventRecorder.record(new SyncEventCommand(
                recipientUserId,
                scope,
                resourceType,
                resourceId,
                action,
                resourceVersion,
                hints
        ));
    }

    /**
     * 记录媒体库级失效事件。
     *
     * @param recipientUserId 接收用户标识
     * @param scope 媒体业务作用域
     * @param resourceType 资源类型
     * @param hints 非敏感刷新提示
     */
    public void invalidate(
            UUID recipientUserId,
            SyncScope scope,
            String resourceType,
            Map<String, Object> hints
    ) {
        record(
                recipientUserId,
                scope,
                resourceType,
                null,
                SyncAction.INVALIDATED,
                null,
                hints
        );
    }
}
