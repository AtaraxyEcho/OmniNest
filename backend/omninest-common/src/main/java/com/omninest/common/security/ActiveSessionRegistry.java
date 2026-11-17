package com.omninest.common.security;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

/**
 * 定义用户各客户端平台的活动会话注册能力。
 *
 * @author OmniNest
 */
public interface ActiveSessionRegistry {

    /**
     * 注册指定平台的活动会话。
     *
     * @param userId 用户标识
     * @param platform 客户端平台
     * @param sessionId 会话标识
     * @param ttl 注册信息保留时间
     */
    void register(UUID userId, String platform, UUID sessionId, Duration ttl);

    /**
     * 查询指定平台的活动会话。
     *
     * @param userId 用户标识
     * @param platform 客户端平台
     * @return 活动会话标识
     */
    Optional<UUID> find(UUID userId, String platform);
}
