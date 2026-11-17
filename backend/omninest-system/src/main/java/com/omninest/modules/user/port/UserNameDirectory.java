package com.omninest.modules.user.port;

import java.util.Collection;
import java.util.Map;
import java.util.UUID;

/**
 * 跨模块用户显示名查询端口：业务模块按用户 ID 批量解析展示名，
 * 避免在各模块直连用户仓储或对外泄露内部用户 DTO。
 *
 * @author OmniNest
 */
public interface UserNameDirectory {

    /**
     * 批量解析用户显示名：优先 displayName，为空回退 username。
     * 未知用户不产生条目（调用方按缺省呈现），绝不出错抛出。
     *
     * @param userIds 用户 ID 集合
     * @return userId -&gt; 显示名
     */
    Map<UUID, String> resolveDisplayNames(Collection<UUID> userIds);
}
