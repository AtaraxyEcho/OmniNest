package com.omninest.common.access;

import java.util.UUID;

/**
 * 共享空间访问能力的跨 Feature 查询端口。
 *
 * <p>搜索等模块需要判断共享空间可见性，但不能直接依赖 File Feature 的服务实现；
 * 由 File 模块提供实现，接口放在 common 以避免 Feature 依赖环。</p>
 *
 * @author OmniNest
 */
public interface SharedSpaceAccessQuery {

    /**
     * 判断用户是否具备共享空间浏览权限。
     *
     * @param userId 用户 ID
     * @return 可浏览时返回 true
     */
    boolean canBrowse(UUID userId);

    /**
     * 判断用户是否具备共享空间下载权限。
     *
     * @param userId 用户 ID
     * @return 可下载时返回 true
     */
    boolean canDownload(UUID userId);

    /**
     * 校验共享空间下载权限，无权限时抛出业务异常。
     *
     * @param userId 用户 ID
     */
    void validateDownloadPermission(UUID userId);
}
