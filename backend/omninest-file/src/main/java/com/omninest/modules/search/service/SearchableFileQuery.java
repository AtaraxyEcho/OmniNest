package com.omninest.modules.search.service;

import java.util.Collection;
import java.util.Map;
import java.util.UUID;

/**
 * 定义搜索模块复核文件当前可见状态的查询端口。
 *
 * @author OmniNest
 */
public interface SearchableFileQuery {

    /**
     * 查询当前用户仍可搜索的文件名称。
     *
     * @param ownerUserId 当前用户 ID
     * @param candidateIds Lucene 返回的候选文件 ID
     * @return 以文件 ID 为键的当前文件名称
     */
    Map<UUID, String> findCurrentNames(UUID ownerUserId, Collection<UUID> candidateIds);

    /**
     * 查询共享空间中仍然活动的文件名称。
     *
     * <p>共享索引是全局目录，命中后的可见性由调用方按共享空间角色权限统一判定；
     * 该查询只复核节点状态。</p>
     *
     * @param candidateIds Lucene 返回的候选文件 ID
     * @return 以文件 ID 为键的当前文件名称
     */
    Map<UUID, String> findCurrentSharedNames(Collection<UUID> candidateIds);
}
