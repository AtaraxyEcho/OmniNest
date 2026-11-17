package com.omninest.modules.file.service;

import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 文件模块同步事件写入服务。
 * 统一收藏、分享、权限、版本等场景的客户端同步事件格式。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileSyncEventWriter {
    private final UserSyncEventRecorder syncEventRecorder;

    /**
     * 记录文件节点变更事件。
     *
     * @param ownerUserId 接收用户 ID
     * @param fileId      文件节点 ID
     * @param hints       附加提示字段
     */
    public void recordFileEvent(UUID ownerUserId, UUID fileId, Map<String, Object> hints) {
        syncEventRecorder.record(new SyncEventCommand(
                ownerUserId,
                SyncScope.FILES,
                "FILE_NODE",
                fileId.toString(),
                SyncAction.UPDATED,
                null,
                hints
        ));
    }

    /**
     * 记录文件库批量失效事件。
     *
     * @param ownerUserId 接收用户 ID
     * @param count       受影响条目数
     */
    public void recordFileLibraryInvalidation(UUID ownerUserId, int count) {
        syncEventRecorder.record(new SyncEventCommand(
                ownerUserId,
                SyncScope.FILES,
                "FILE_LIBRARY",
                null,
                SyncAction.INVALIDATED,
                null,
                Map.of("count", count)
        ));
    }

    /**
     * 记录分享变更事件。
     *
     * @param recipientUserId 接收用户 ID
     * @param shareId         分享链接 ID
     */
    public void recordShareEvent(UUID recipientUserId, UUID shareId) {
        syncEventRecorder.record(new SyncEventCommand(
                recipientUserId,
                SyncScope.FILES,
                "FILE_SHARE",
                shareId == null ? null : shareId.toString(),
                SyncAction.PERMISSION_CHANGED,
                null,
                Map.of()
        ));
    }

    /**
     * 记录权限变更事件。
     *
     * @param recipientUserId 接收用户 ID
     * @param fileId          文件节点 ID
     */
    public void recordPermissionEvent(UUID recipientUserId, UUID fileId) {
        syncEventRecorder.record(new SyncEventCommand(
                recipientUserId,
                SyncScope.FILES,
                "FILE_PERMISSION",
                fileId.toString(),
                SyncAction.PERMISSION_CHANGED,
                null,
                Map.of()
        ));
    }
}
