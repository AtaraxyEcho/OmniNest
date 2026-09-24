package com.omninest.modules.backdrop.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.backdrop.domain.BackdropAsset;
import com.omninest.modules.backdrop.domain.BackdropAssetStatus;
import com.omninest.modules.backdrop.domain.BackdropMediaType;
import com.omninest.modules.backdrop.repository.BackdropAssetRepository;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * 以 mock 数据驱动背景库对账语义:orphan 清理、缺失对象标记、卡死自愈与 10 分钟阈值。
 *
 * @author OmniNest
 */
class BackdropReconciliationServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");

    private BackdropAssetRepository backdropAssetRepository;
    private DerivedAssetStorageService derivedAssetStorageService;
    private BackdropScanTaskService backdropScanTaskService;
    private BackdropReconciliationService service;

    @BeforeEach
    void setUp() {
        backdropAssetRepository = mock(BackdropAssetRepository.class);
        derivedAssetStorageService = mock(DerivedAssetStorageService.class);
        backdropScanTaskService = mock(BackdropScanTaskService.class);
        when(derivedAssetStorageService.listOwnerIdsByDerivedPathPrefix("BACKDROP"))
                .thenReturn(List.of(OWNER_ID));
        when(backdropScanTaskService.hasActiveScanTask(any(UUID.class), any(UUID.class))).thenReturn(false);
        service = new BackdropReconciliationService(
                backdropAssetRepository, derivedAssetStorageService, backdropScanTaskService);
    }

    @Test
    void stuckProcessingWithActiveScanTaskIsSkipped() {
        BackdropAsset asset = asset(BackdropAssetStatus.PROCESSING, Instant.now().minusSeconds(1200));
        when(backdropAssetRepository.findByOwnerUserIdOrderByUpdatedAtDesc(OWNER_ID))
                .thenReturn(List.of(asset));
        when(backdropScanTaskService.hasActiveScanTask(OWNER_ID, asset.getId())).thenReturn(true);

        service.reconcile();

        assertThat(asset.getStatus()).isEqualTo(BackdropAssetStatus.PROCESSING);
        verify(backdropAssetRepository, never()).save(any());
        verify(derivedAssetStorageService, never()).deleteOwnedBatch(any(), anyList());
    }

    @Test
    void stuckProcessingWithoutObjectIsMarkedFailed() {
        BackdropAsset asset = asset(BackdropAssetStatus.PROCESSING, Instant.now().minusSeconds(1200));
        UUID orphanNodeId = UUID.randomUUID();
        when(derivedAssetStorageService.listDerivedNodeRefs(OWNER_ID, "BACKDROP"))
                .thenReturn(List.of(nodeRef(orphanNodeId, UUID.randomUUID())));
        when(backdropAssetRepository.findByOwnerUserIdOrderByUpdatedAtDesc(OWNER_ID))
                .thenReturn(List.of(asset));

        service.reconcile();

        assertThat(asset.getStatus()).isEqualTo(BackdropAssetStatus.FAILED);
        assertThat(asset.getFailReason()).contains("原始对象缺失");
        verify(backdropAssetRepository).save(asset);
        verify(derivedAssetStorageService).deleteOwnedBatch(OWNER_ID, List.of(orphanNodeId));
    }

    @Test
    void stuckProcessingWithObjectSelfHealsToReady() {
        BackdropAsset asset = asset(BackdropAssetStatus.PROCESSING, Instant.now().minusSeconds(1200));
        UUID nodeId = UUID.randomUUID();
        when(derivedAssetStorageService.listDerivedNodeRefs(OWNER_ID, "BACKDROP"))
                .thenReturn(List.of(nodeRef(nodeId, asset.getId())));
        when(backdropAssetRepository.findByOwnerUserIdOrderByUpdatedAtDesc(OWNER_ID))
                .thenReturn(List.of(asset));

        service.reconcile();

        assertThat(asset.getStatus()).isEqualTo(BackdropAssetStatus.READY);
        assertThat(asset.getFailReason()).isNull();
        verify(backdropAssetRepository).save(asset);
        verify(derivedAssetStorageService, never()).deleteOwnedBatch(any(), anyList());
    }

    @Test
    void readyAssetMissingObjectIsMarkedFailedImmediately() {
        BackdropAsset asset = asset(BackdropAssetStatus.READY, Instant.now());
        when(derivedAssetStorageService.listDerivedNodeRefs(OWNER_ID, "BACKDROP"))
                .thenReturn(List.of());
        when(backdropAssetRepository.findByOwnerUserIdOrderByUpdatedAtDesc(OWNER_ID))
                .thenReturn(List.of(asset));

        service.reconcile();

        assertThat(asset.getStatus()).isEqualTo(BackdropAssetStatus.FAILED);
        verify(backdropAssetRepository).save(asset);
    }

    @Test
    void freshProcessingAssetWithinThresholdIsUntouched() {
        BackdropAsset asset = asset(BackdropAssetStatus.PROCESSING, Instant.now());
        when(derivedAssetStorageService.listDerivedNodeRefs(OWNER_ID, "BACKDROP"))
                .thenReturn(List.of());
        when(backdropAssetRepository.findByOwnerUserIdOrderByUpdatedAtDesc(OWNER_ID))
                .thenReturn(List.of(asset));

        service.reconcile();

        assertThat(asset.getStatus()).isEqualTo(BackdropAssetStatus.PROCESSING);
        verify(backdropAssetRepository, never()).save(any());
    }

    @Test
    void nodesNotReferencedByAnyAssetAreDeletedAsOrphans() {
        BackdropAsset asset = asset(BackdropAssetStatus.READY, Instant.now());
        UUID orphanNodeId = UUID.randomUUID();
        when(derivedAssetStorageService.listDerivedNodeRefs(OWNER_ID, "BACKDROP"))
                .thenReturn(List.of(nodeRef(orphanNodeId, UUID.randomUUID())));
        when(backdropAssetRepository.findByOwnerUserIdOrderByUpdatedAtDesc(OWNER_ID))
                .thenReturn(List.of(asset));

        service.reconcile();

        verify(derivedAssetStorageService).deleteOwnedBatch(OWNER_ID, List.of(orphanNodeId));
    }

    @Test
    void referencedNodesAreNeverDeletedAsOrphans() {
        BackdropAsset asset = asset(BackdropAssetStatus.READY, Instant.now());
        UUID originalNodeId = UUID.randomUUID();
        UUID thumbNodeId = UUID.randomUUID();
        when(derivedAssetStorageService.listDerivedNodeRefs(OWNER_ID, "BACKDROP"))
                .thenReturn(List.of(nodeRef(originalNodeId, asset.getId()),
                        nodeRef(thumbNodeId, asset.getId())));
        when(backdropAssetRepository.findByOwnerUserIdOrderByUpdatedAtDesc(OWNER_ID))
                .thenReturn(List.of(asset));

        service.reconcile();

        verify(derivedAssetStorageService, never()).deleteOwnedBatch(any(), anyList());
    }

    private BackdropAsset asset(BackdropAssetStatus status, Instant updatedAt) {
        BackdropAsset asset = new BackdropAsset();
        asset.setId(UUID.randomUUID());
        asset.setOwnerUserId(OWNER_ID);
        asset.setTitle("mock");
        asset.setMediaType(BackdropMediaType.IMAGE);
        asset.setFileNodeId(UUID.randomUUID());
        asset.setFileSize(1024);
        asset.setSha256("mock-sha");
        asset.setStatus(status);
        asset.setUpdatedAt(updatedAt);
        asset.setCreatedAt(updatedAt);
        return asset;
    }

    private DerivedAssetStorageService.DerivedNodeRef nodeRef(UUID fileNodeId, UUID assetId) {
        return new DerivedAssetStorageService.DerivedNodeRef(
                fileNodeId, "/.metadata/BACKDROP/" + assetId + "/ORIGINAL/original.png", Instant.now());
    }
}
