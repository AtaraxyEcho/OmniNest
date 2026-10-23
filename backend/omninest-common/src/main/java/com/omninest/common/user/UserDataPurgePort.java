package com.omninest.common.user;

import java.util.UUID;

/**
 * 用户物理删除时的跨模块数据清理端口。
 *
 * <p>用户管理模块不能直接依赖 File/Media 模块的仓储；由各模块提供实现，
 * 清理仅属于该用户的授权绑定、索引状态与派生索引目录。</p>
 *
 * @author OmniNest
 */
public interface UserDataPurgePort {

    /**
     * 清理指定用户在实现模块内的关联数据。
     *
     * @param userId 被删除的用户 ID
     */
    void purgeUserData(UUID userId);
}
