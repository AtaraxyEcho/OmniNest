package com.omninest.common.sync;

/**
 * 客户端数据同步动作。
 *
 * @author OmniNest
 */
public enum SyncAction {
    CREATED,
    UPDATED,
    DELETED,
    RESTORED,
    PROGRESS,
    COMPLETED,
    FAILED,
    INVALIDATED,
    PERMISSION_CHANGED
}
