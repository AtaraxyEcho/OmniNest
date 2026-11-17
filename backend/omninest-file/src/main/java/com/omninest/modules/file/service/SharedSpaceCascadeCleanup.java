package com.omninest.modules.file.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.repository.FileNodePermissionRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 跨空间移动整棵子树时撤销其对外授权：公开分享链接与细粒度节点权限。
 *
 * <p>从 {@link SharedSpaceService} 拆出：这两类撤销只按资源集合批量处理，
 * 与空间成员资格、配额结算没有耦合，独立成职责可以避免通用仓储与服务类继续膨胀。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class SharedSpaceCascadeCleanup {

    private static final String SHARE_LINK_CACHE_PREFIX = "omninest:share:link:";

    private final ShareLinkRepository shareLinkRepository;
    private final FileNodePermissionRepository fileNodePermissionRepository;
    private final ReadThroughCache readThroughCache;

    /**
     * 撤销整棵子树的公开分享链接，并同步清掉读穿透缓存。
     *
     * <p>按资源集合一次查询、一次批量停用，避免对子树每个节点各跑一轮全表扫描。</p>
     *
     * @param fileNodeIds 子树节点 ID 集合
     */
    @Transactional(rollbackFor = Exception.class)
    public void revokeShareLinks(List<UUID> fileNodeIds) {
        if (fileNodeIds.isEmpty()) {
            return;
        }
        List<ShareLink> active = shareLinkRepository.findByResourceIdInAndDisabledAtIsNull(fileNodeIds);
        shareLinkRepository.disableByResourceIdIn(fileNodeIds, Instant.now());
        for (ShareLink link : active) {
            readThroughCache.invalidate(SHARE_LINK_CACHE_PREFIX + link.getTokenHash());
        }
    }

    /**
     * 撤销整棵子树的细粒度节点权限（移入共享空间时）。
     *
     * @param fileNodeIds 子树节点 ID 集合
     */
    @Transactional(rollbackFor = Exception.class)
    public void revokeFilePermissions(List<UUID> fileNodeIds) {
        if (!fileNodeIds.isEmpty()) {
            fileNodePermissionRepository.deleteByFileNodeIdIn(fileNodeIds);
        }
    }
}
