package com.omninest.modules.quota.port;

import java.util.UUID;

/**
 * 用户资料缓存驱逐端口。
 *
 * <p>资料缓存含配额字段且有 TTL，配额变更后不驱逐会让用户在缓存剩余有效期内
 * 读到旧配额。配额侧不感知用户模块的缓存实现，只通过本端口提出失效要求。</p>
 *
 * @author OmniNest
 */
public interface UserProfileCacheEvictor {

    /**
     * 驱逐指定用户的资料缓存。
     *
     * @param userId 用户标识
     */
    void evictProfileCache(UUID userId);

    /**
     * 在事务提交后驱逐指定用户的资料缓存；无事务同步时立即驱逐。
     *
     * <p>写事务体内直接驱逐会留出窗口：并发读在提交前仍能看到旧行，并把旧角色、
     * 旧状态或旧配额重新写回带 TTL 的缓存，驱逐等于白做。</p>
     *
     * @param userId 用户标识
     */
    void evictProfileCacheAfterCommit(UUID userId);
}
