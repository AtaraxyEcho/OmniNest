package com.omninest.common.security;

import java.util.Optional;
import java.util.UUID;

/**
 * 活动会话注册表的持久层回退查询端口。
 *
 * <p>Redis 注册表故障时用于回退查询数据库，避免同平台互斥静默失效。
 * 由持有会话仓储的模块提供实现；基础设施层的 Redis 注册表按端口依赖，不感知实现模块。
 *
 * @author OmniNest
 */
public interface ActiveSessionFallbackLookup {

    /**
     * 查询用户在指定平台最近活跃且未撤销、未过期的会话标识。
     *
     * @param userId 用户标识
     * @param platform 客户端平台
     * @return 会话标识；无符合条件的会话时为空
     */
    Optional<UUID> findActiveSessionId(UUID userId, String platform);
}
