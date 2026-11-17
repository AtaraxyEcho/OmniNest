package com.omninest.common.security;

import java.util.UUID;

/**
 * 管理端写操作的实时撤权复核端口。
 *
 * <p>控制器与跨模块写入口只依赖本端口，具体实现由用户模块提供；这样既能在
 * 每次敏感写入前复核数据库中的当前角色，又不会让各业务 Feature 反向依赖 user
 * 模块形成依赖环。</p>
 *
 * @author OmniNest
 */
public interface FreshAdminActorVerifier {

    /**
     * 校验操作者当前仍是可用的管理员。
     *
     * @param actorUserId 操作者用户标识
     */
    void requireFreshAdminActor(UUID actorUserId);
}
