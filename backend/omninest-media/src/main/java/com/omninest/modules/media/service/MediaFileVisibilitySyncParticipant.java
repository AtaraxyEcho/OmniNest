package com.omninest.modules.media.service;

import java.util.Collection;
import java.util.UUID;

/**
 * 文件可见性变化后的媒体模块同步失效参与者。
 *
 * @author OmniNest
 */
public interface MediaFileVisibilitySyncParticipant {

    /**
     * 使引用指定文件节点的媒体客户端缓存失效。
     *
     * @param fileNodeIds 文件节点 ID
     */
    void invalidateFileVisibility(Collection<UUID> fileNodeIds);
}
