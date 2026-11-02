package com.omninest.common.security;

import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.Optional;
import java.util.UUID;

/**
 * 定义会话撤销缓存能力。
 *
 * @author OmniNest
 */
public interface SessionRevocationCache {

    /**
     * 缓存已撤销的会话标识。
     *
     * @param userId 用户标识
     * @param sessionIds 会话标识集合
     * @param ttl 缓存保留时间
     */
    void markRevoked(UUID userId, Collection<UUID> sessionIds, Duration ttl);

    /**
     * 判断缓存中是否存在撤销标记。
     *
     * @param userId 用户标识
     * @param sessionId 会话标识
     * @return 存在撤销标记时返回 {@code true}
     */
    boolean contains(UUID userId, UUID sessionId);

    /**
     * 三态判定会话撤销状态，用于区分「缓存确认未撤销」与「缓存无法定论」。
     *
     * <p>布尔返回值无法表达这两者的差别：正常流量下绝大多数会话都未撤销，若把「没命中黑名单」
     * 等同于「无法定论」，每个请求都要回源数据库，缓存形同不存在。</p>
     *
     * @param userId 用户标识
     * @param sessionId 会话标识
     * @return {@code Optional.of(true)} 已撤销；{@code Optional.of(false)} 缓存确认未撤销，
     *         无需回源；{@code Optional.empty()} 缓存未启用或访问异常，必须回源数据库
     */
    default Optional<Boolean> checkRevoked(UUID userId, UUID sessionId) {
        return Optional.empty();
    }

    /**
     * 记录「该会话经数据库确认未被撤销」的短期判定，供后续请求跳过回源。
     *
     * <p>撤销该会话时必须一并清除本标记，否则旧标记会把撤销判定压住一个 TTL 周期。</p>
     *
     * @param userId 用户标识
     * @param sessionId 会话标识
     * @param ttl 标记保留时间
     */
    default void markNotRevoked(UUID userId, UUID sessionId, Duration ttl) {
    }

    /**
     * 记录用户级访问令牌截止时间：早于该时间签发的令牌视为陈旧。
     *
     * <p>用于权限变更时保留当前会话、但仍要立刻淘汰旧令牌声明的场景。记录保留时长
     * 不短于访问令牌有效期，过期后 JWT 自身的有效期末尾已覆盖全部旧令牌。</p>
     *
     * @param userId 用户标识
     * @param cutoff 截止时间（秒级精度）
     * @param ttl 记录保留时间
     */
    default void markAccessTokenCutoff(UUID userId, Instant cutoff, Duration ttl) {
    }

    /**
     * 读取用户级访问令牌截止时间。
     *
     * @param userId 用户标识
     * @return 截止时间；未设置、已过期或缓存不可用时返回空
     */
    default Optional<Instant> accessTokenCutoff(UUID userId) {
        return Optional.empty();
    }
}
