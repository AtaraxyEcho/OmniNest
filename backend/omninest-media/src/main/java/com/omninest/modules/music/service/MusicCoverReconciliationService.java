package com.omninest.modules.music.service;

import com.omninest.modules.file.service.DerivedAssetStorageService;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 音乐封面派生资产对账服务。
 *
 * <p>封面替换与删除已在写入时回收资产（{@link MusicCoverRetentionService}），但两类遗留仍需兜底：
 * 按需派生的缩略图由首次访问生成，键指向生成当时的封面标识，封面被重新入库或刮削替换后它就无人
 * 引用；进程在"对象已落库、引用尚未写入"之间中断时，封面本体会成为无主节点。</p>
 *
 * <p>封面是"先提交派生对象、后写业务引用"，因此只处理创建已超过宽限期的节点：正在写入的封面
 * 尚未被任何业务行引用，缺时间门槛会把它误删，让曲目永久缺图。缩略图删错只会在下次访问重新派生。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicCoverReconciliationService {

    private static final String RESOURCE_TYPE = "MUSIC_COVER";
    private static final String THUMBNAIL_ASSET_TYPE = "THUMBNAIL";
    /** 派生路径形如 {@code /.metadata/MUSIC_COVER/{coverFileId}/THUMBNAIL/cover_300.jpg}。 */
    private static final int RESOURCE_ID_SEGMENT = 3;
    private static final int ASSET_TYPE_SEGMENT = 4;

    /** 封面写入是"先落对象再写引用"，创建未超过该时长的节点一律跳过。 */
    private static final Duration CREATION_GRACE = Duration.ofMinutes(10);

    private final DerivedAssetStorageService derivedAssetStorageService;
    private final MusicCoverRetentionService coverRetentionService;

    /**
     * 执行一轮对账，按用户隔离失败，单个用户异常不影响其余用户。
     */
    public void reconcile() {
        for (UUID ownerUserId : derivedAssetStorageService.listOwnerIdsByDerivedPathPrefix(RESOURCE_TYPE)) {
            try {
                reconcileOwner(ownerUserId);
            } catch (RuntimeException ex) {
                log.error("音乐封面资产对账失败: userId={}", ownerUserId, ex);
            }
        }
    }

    private void reconcileOwner(UUID ownerUserId) {
        Instant cutoff = Instant.now().minus(CREATION_GRACE);
        List<DerivedAssetStorageService.DerivedNodeRef> candidates = new ArrayList<>();
        List<UUID> sourceCoverIds = new ArrayList<>();
        for (DerivedAssetStorageService.DerivedNodeRef nodeRef
                : derivedAssetStorageService.listDerivedNodeRefs(ownerUserId, RESOURCE_TYPE)) {
            if (nodeRef.createdAt().isAfter(cutoff)) {
                continue;
            }
            UUID sourceCoverId = sourceCoverIdOf(nodeRef);
            if (sourceCoverId == null) {
                continue;
            }
            candidates.add(nodeRef);
            sourceCoverIds.add(sourceCoverId);
        }
        if (candidates.isEmpty()) {
            return;
        }
        Set<UUID> referenced = coverRetentionService.filterReferenced(ownerUserId, sourceCoverIds);
        List<UUID> orphanIds = candidates.stream()
                .filter(nodeRef -> !referenced.contains(sourceCoverIdOf(nodeRef)))
                .map(DerivedAssetStorageService.DerivedNodeRef::fileNodeId)
                .toList();
        if (orphanIds.isEmpty()) {
            return;
        }
        int deleted = derivedAssetStorageService.deleteOwnedBatch(ownerUserId, orphanIds);
        log.info("已清理失效音乐封面派生资产: userId={}, candidates={}, deleted={}",
                ownerUserId, orphanIds.size(), deleted);
    }

    /**
     * 解析节点依赖哪张封面仍然存活：缩略图看路径里的源封面标识，封面本体看自身标识。
     */
    private UUID sourceCoverIdOf(DerivedAssetStorageService.DerivedNodeRef nodeRef) {
        String[] segments = nodeRef.normalizedPath().split("/");
        if (segments.length <= ASSET_TYPE_SEGMENT) {
            return null;
        }
        if (THUMBNAIL_ASSET_TYPE.equals(segments[ASSET_TYPE_SEGMENT])) {
            return parseUuid(segments[RESOURCE_ID_SEGMENT]);
        }
        return nodeRef.fileNodeId();
    }

    private UUID parseUuid(String value) {
        try {
            return UUID.fromString(value);
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }
}
