package com.omninest.modules.file.service;

import java.util.Collection;
import java.util.UUID;

/**
 * 文件永久删除资源贡献写入器。
 *
 * @author OmniNest
 */
public interface PurgeContributionWriter {

    /**
     * 增加需要进入删除规划的派生文件节点。
     *
     * @param fileNodeIds 文件节点 ID
     */
    void addFileNodeIds(Collection<UUID> fileNodeIds);

    /**
     * 增加尚未迁移为 FileNode 的对象引用。
     *
     * @param references 历史对象引用
     */
    void addLegacyObjects(Collection<LegacyObjectReference> references);
}
