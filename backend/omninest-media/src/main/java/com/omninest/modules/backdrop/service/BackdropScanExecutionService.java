package com.omninest.modules.backdrop.service;

import com.omninest.modules.backdrop.domain.BackdropAsset;
import com.omninest.modules.backdrop.domain.BackdropAssetStatus;
import com.omninest.modules.backdrop.event.BackdropSecurityScanRequestedEvent;
import com.omninest.modules.backdrop.repository.BackdropAssetRepository;
import com.omninest.modules.file.service.FileIngressStagingService;
import com.omninest.modules.file.service.FileIngressSafetyService.InspectionResult;
import com.omninest.modules.file.service.FileIngressRejectedException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 背景素材安全扫描执行服务：扫描暂存对象，通过后委托素材服务完成发布。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class BackdropScanExecutionService {
    private final BackdropAssetRepository backdropAssetRepository;
    private final FileIngressStagingService ingressStagingService;
    private final BackdropAssetService backdropAssetService;

    /**
     * 处理一条背景素材安全扫描任务消息。
     *
     * @param event 扫描任务消息
     */
    public void process(BackdropSecurityScanRequestedEvent event) {
        BackdropAsset asset = backdropAssetRepository.findById(event.assetId()).orElse(null);
        if (asset == null) {
            log.warn("背景素材安全扫描任务缺少素材行，跳过: taskId={}, assetId={}", event.taskId(), event.assetId());
            return;
        }
        if (asset.getStatus() != BackdropAssetStatus.PROCESSING) {
            log.info("背景素材不在处理中状态，跳过重复扫描: assetId={}, status={}", asset.getId(), asset.getStatus());
            return;
        }
        try {
            InspectionResult inspection = ingressStagingService.scan(event.ingressItemId());
            log.info("背景素材安全扫描通过: assetId={}, status={}", event.assetId(), inspection.status());
            backdropAssetService.completeStagedAsset(
                    event.ownerUserId(),
                    event.assetId(),
                    event.ingressItemId(),
                    event.originalFileName()
            );
        } catch (FileIngressRejectedException exception) {
            log.warn("背景素材安全扫描终态拒绝: assetId={}, detail={}", event.assetId(), exception.getMessage());
            throw exception;
        }
    }
}
