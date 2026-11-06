package com.omninest.modules.search.service;

import java.util.Map;
import java.util.UUID;

/**
 * 定义搜索模块复核文件当前可见状态的查询端口。
 */
public interface SearchableFileQuery {

    /**
     * 按当前数据库文件名实时匹配活动文件。
     *
     * <p>文件名是可变元数据，只存在于数据库；重命名后无需重建索引即可命中。</p>
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
}
