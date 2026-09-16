package com.omninest.modules.backdrop.service;

import com.omninest.modules.backdrop.domain.BackdropAsset;
import com.omninest.modules.backdrop.domain.BackdropAssetStatus;
import com.omninest.modules.backdrop.repository.BackdropAssetRepository;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import java.time.Duration;
import java.time.Instant;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 背景库对账服务。
 *
 * <p>仅作为灾难恢复与进程异常后的兜底机制,不承担正常上传链路职责。三类检查:
 * 孤儿派生节点(MinIO/节点存在但素材行不存在)立即清理;素材行存在但原始对象缺失的标记 FAILED;
 * 卡死超过阈值且无进行中安全扫描任务的 PROCESSING 依据对象存在性自愈或标记 FAILED。
 * 存在进行中扫描任务的素材一律跳过,避免把正在异步扫描的素材误判为卡死。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class BackdropReconciliationService {

    private static final String RESOURCE_TYPE = "BACKDROP";
    private static final Duration STUCK_THRESHOLD = Duration.ofMinutes(10);

    private final BackdropAssetRepository backdropAssetRepository;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final BackdropScanTaskService backdropScanTaskService;

    /**
     * 执行一轮对账。
     */
    public void reconcile() {
        List<UUID> ownerIds = derivedAssetStorageService.listOwnerIdsByDerivedPathPrefix(RESOURCE_TYPE);
        for (UUID ownerId : ownerIds) {
            try {
                reconcileOwner(ownerId);
            } catch (RuntimeException ex) {
                log.error("背景库对账失败: userId={}", ownerId, ex);
            }
        }
    }

    private void reconcileOwner(UUID ownerId) {
        List<DerivedAssetStorageService.DerivedNodeRef> nodeRefs =
                derivedAssetStorageService.listDerivedNodeRefs(ownerId, RESOURCE_TYPE);
        List<BackdropAsset> assets = backdropAssetRepository.findByOwnerUserIdOrderByUpdatedAtDesc(ownerId);
        Set<String> liveAssetIds = new HashSet<>();
        for (BackdropAsset asset : assets) {
            liveAssetIds.add(asset.getId().toString());
            reconcileAsset(asset, nodeRefs, asset.getUpdatedAt().isBefore(Instant.now().minus(STUCK_THRESHOLD)));
        }
        deleteOrphanNodes(ownerId, nodeRefs, liveAssetIds);
    }

    private void reconcileAsset(BackdropAsset asset, List<DerivedAssetStorageService.DerivedNodeRef> nodeRefs,
                                boolean beyondThreshold) {
        boolean hasOriginalObject = nodeRefs.stream()
                .anyMatch(nodeRef -> nodeRef.normalizedPath().contains("/" + asset.getId() + "/"));
        if (asset.getStatus() == BackdropAssetStatus.PROCESSING && beyondThreshold) {
            if (backdropScanTaskService.hasActiveScanTask(asset.getOwnerUserId(), asset.getId())) {
                log.debug("背景素材存在进行中安全扫描任务,跳过对账: assetId={}", asset.getId());
                return;
            }
            if (hasOriginalObject) {
                asset.setStatus(BackdropAssetStatus.READY);
                log.info("背景素材卡死自愈: assetId={} 对象存在,恢复 READY", asset.getId());
            } else {
                asset.setStatus(BackdropAssetStatus.FAILED);
                asset.setFailReason("原始对象缺失，对账标记");
                log.warn("背景素材卡死标记失败: assetId={} 对象不存在", asset.getId());
            }
            backdropAssetRepository.save(asset);
            return;
        }
        if (asset.getStatus() == BackdropAssetStatus.READY && !hasOriginalObject) {
            asset.setStatus(BackdropAssetStatus.FAILED);
            asset.setFailReason("原始对象缺失，对账标记");
            log.warn("背景素材对象缺失标记失败: assetId={}", asset.getId());
            backdropAssetRepository.save(asset);
        }
    }

    private void deleteOrphanNodes(
            UUID ownerId,
            List<DerivedAssetStorageService.DerivedNodeRef> nodeRefs,
            Set<String> liveAssetIds) {
        List<UUID> orphanIds = nodeRefs.stream()
                .filter(nodeRef -> !liveAssetIds.contains(extractAssetId(nodeRef.normalizedPath())))
                .map(DerivedAssetStorageService.DerivedNodeRef::fileNodeId)
                .toList();
        if (orphanIds.isEmpty()) {
            return;
        }
        int deleted = derivedAssetStorageService.deleteOwnedBatch(ownerId, orphanIds);
        log.info("背景库孤儿派生节点已清理: userId={}, orphanCount={}, deleted={}",
                ownerId, orphanIds.size(), deleted);
    }

    private String extractAssetId(String normalizedPath) {
        String[] segments = normalizedPath.split("/");
        return segments.length >= 4 ? segments[3] : "";
    }
}
