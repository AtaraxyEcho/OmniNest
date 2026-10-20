package com.omninest.modules.quota.port;

import java.util.UUID;

/**
 * 管理台操作者的实时撤权复核能力，由 user 模块实现。
 *
 * <p>访问令牌里的 roles/permissions 声明签发后不再更新，配额这类管理端写操作必须以
 * 库内当前绑定为准。配额侧只声明需求、不直接依赖 user 模块的实现类：
 * {@code quota -> user} 会与既有 {@code user -> quota} 组成依赖环。</p>
 *
 * @author OmniNest
 */
public interface AdminActorVerifier {

    /**
     * 校验操作者当前仍是可用的管理员，否则抛出未授权或禁止业务异常。
     *
     * @param actorUserId 操作者用户标识
     */
    void requireFreshAdminActor(UUID actorUserId);
}
