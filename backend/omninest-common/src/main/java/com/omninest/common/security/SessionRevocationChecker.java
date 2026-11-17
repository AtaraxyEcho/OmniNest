package com.omninest.common.security;

import java.time.Instant;
import java.util.UUID;

/**
 * 提供会话撤销状态的统一判定能力。
 *
 * @author OmniNest
 */
public interface SessionRevocationChecker {

    /**
     * 判断指定会话是否已被撤销。
     *
     * @param userId 用户标识
     * @param sessionId 会话标识
     * @return 已撤销时返回 {@code true}
     */
    boolean isRevoked(UUID userId, UUID sessionId);

    /**
     * 判断访问令牌的签发时间是否早于用户最近一次权限变更的截止时间。
     *
     * <p>保留会话的权限变更（管理员改自己的角色或所属角色权限）不会撤销 sid，
     * 但旧令牌仍携带变更前的高权限声明，必须拒绝其继续访问并要求刷新。</p>
     *
     * @param userId 用户标识
     * @param issuedAt JWT 签发时间（iat）
     * @return true 表示该令牌已因权限变更失效
     */
    default boolean isTokenStale(UUID userId, Instant issuedAt) {
        return false;
    }
}
