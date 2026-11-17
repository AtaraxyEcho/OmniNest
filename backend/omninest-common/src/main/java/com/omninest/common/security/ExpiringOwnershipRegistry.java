package com.omninest.common.security;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

/**
 * 维护带有效期的资源键与用户归属关系。
 *
 * @author OmniNest
 */
public interface ExpiringOwnershipRegistry {

    /**
     * 登记资源键的用户归属。
     *
     * @param resourceKey 资源键
     * @param ownerUserId 所属用户标识
     * @param ttl 归属关系有效期
     */
    void register(String resourceKey, UUID ownerUserId, Duration ttl);

    /**
     * 查询资源键的所属用户。
     *
     * @param resourceKey 资源键
     * @return 所属用户标识，不存在或记录无效时返回空
     */
    Optional<UUID> findOwner(String resourceKey);

    /**
     * 删除资源键的归属关系。
     *
     * @param resourceKey 资源键
     */
    void remove(String resourceKey);
}
