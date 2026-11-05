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
     * 按内容对象标识解析当前仍可搜索的文件节点。
     *
     * <p>正文索引只存不可变的内容对象标识，节点标识、文件名与空间归属都以数据库
     * 实时状态为准：同一对象可能被复制成多个节点，也可能已经进入回收站或永久删除，
     * 这些都必须在这里过滤掉。</p>
     *
     * @param ownerUserId 当前用户 ID
     * @param fileObjectIds 正文命中的内容对象标识
     * @param includePersonal 是否包含个人空间
     * @param includeShared 是否包含共享空间
     * @return 当前可搜索的文件节点
     */
    Collection<SearchableFileNode> findSearchableNodesByObjectIds(
            UUID ownerUserId,
            Collection<UUID> fileObjectIds,
            boolean includePersonal,
            boolean includeShared);

    /**
     * 按当前数据库文件名实时匹配活动文件。
     *
     * <p>文件名是可变元数据，只存在于数据库；重命名后无需等正文重解析即可命中。</p>
     *
     * @param ownerUserId 当前用户 ID
     * @param query 用户输入关键词
     * @param includePersonal 是否包含个人空间
     * @param includeShared 是否包含共享空间
     * @param limit 最多返回条数
     * @return 以文件 ID 为键的当前文件名称
     */
    Map<UUID, String> searchActiveFilesByName(
            UUID ownerUserId,
            String query,
            boolean includePersonal,
            boolean includeShared,
            int limit
    );

    /**
     * 可搜索的文件节点即时快照。
     *
     * @param fileId 文件节点 ID
     * @param fileObjectId 内容对象 ID
     * @param name 当前文件名
     */
    record SearchableFileNode(UUID fileId, UUID fileObjectId, String name) {
    }
}
