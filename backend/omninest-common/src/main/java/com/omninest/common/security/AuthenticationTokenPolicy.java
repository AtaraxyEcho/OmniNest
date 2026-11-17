package com.omninest.common.security;

import java.time.Duration;

/**
 * 提供认证访问令牌和刷新令牌的有效期策略。
 *
 * @author OmniNest
 */
public interface AuthenticationTokenPolicy {

    /**
     * 返回访问令牌有效期。
     *
     * @return 访问令牌有效期
     */
    Duration accessTokenTtl();

    /**
     * 返回刷新令牌有效期。
     *
     * @return 刷新令牌有效期
     */
    Duration refreshTokenTtl();

    /**
     * 返回刷新会话自签发起算的绝对寿命上限，用于约束滑动续期不得无限延长。
     * 实现返回 null 或非正数时表示不设上限。
     *
     * @return 刷新会话绝对寿命上限，未配置时为 null
     */
    default Duration refreshSessionMaxLifetime() {
        return null;
    }
}
