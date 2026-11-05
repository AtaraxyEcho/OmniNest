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
     * 按当前数据库文件名实时匹配活动文件。
     *
     * <p>默认实现返回空映射，供只关心 Lucene 候选复核的既有测试与调用方使用。
     * 生产实现由 {@link com.omninest.modules.file.service.SearchableFileQueryService}
     * 覆盖。</p>
     *
     * @param ownerUserId 当前用户 ID
     * @param query 用户输入关键词
     * @param includePersonal 是否包含个人空间
     * @param includeShared 是否包含共享空间
     * @param limit 最多返回条数
     * @return 以文件 ID 为键的当前文件名称
     */
    default Map<UUID, String> searchActiveFilesByName(
            UUID ownerUserId,
            String query,
            boolean includePersonal,
            boolean includeShared,
            int limit
    ) {
        return Map.of();
    }

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
