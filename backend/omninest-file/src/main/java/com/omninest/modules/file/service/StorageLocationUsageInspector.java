package com.omninest.modules.file.service;

import java.util.UUID;

/**
 * 跨模块检查存储位置是否仍被业务资源引用。
 *
 * @author OmniNest
 */
public interface StorageLocationUsageInspector {

    /**
     * 判断存储位置是否仍被当前业务模块使用。
     *
     * @param storageLocationId 存储位置 ID
     * @return 仍被使用时返回 true
     */
    boolean isInUse(UUID storageLocationId);
}
