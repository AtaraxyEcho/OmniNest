package com.omninest.modules.backdrop.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.backdrop.config.BackdropRuntimeConfigService;
import com.omninest.modules.backdrop.domain.BackdropAsset;
import com.omninest.modules.backdrop.domain.BackdropAssetStatus;
import com.omninest.modules.backdrop.dto.BackdropDtos.BackdropAssetDto;
import com.omninest.modules.backdrop.repository.BackdropAssetRepository;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileIngressStagingService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionSynchronizationUtils;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 背景素材应用服务测试。
 *
 * @author OmniNest
 */
class BackdropAssetServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");

    private BackdropAssetRepository backdropAssetRepository;
    private BackdropRuntimeConfigService runtimeConfigService;
    private DerivedAssetStorageService derivedAssetStorageService;
    private FileQueryService fileQueryService;
    private StorageQuotaService storageQuotaService;
    private UserStorageCommand userStorageCommand;
    private FileIngressStagingService ingressStagingService;
    private BackdropScanTaskService backdropScanTaskService;
    private RateLimitService rateLimitService;
    private BackdropVideoThumbnailExtractor videoThumbnailExtractor;
    private BackdropAssetService service;
    private final AtomicReference<BackdropAsset> storedAsset = new AtomicReference<>();

    @BeforeEach
    void setUp() {
        backdropAssetRepository = mock(BackdropAssetRepository.class);
        runtimeConfigService = mock(BackdropRuntimeConfigService.class);
        derivedAssetStorageService = mock(DerivedAssetStorageService.class);
        fileQueryService = mock(FileQueryService.class);
        storageQuotaService = mock(StorageQuotaService.class);
        userStorageCommand = mock(UserStorageCommand.class);
        ingressStagingService = mock(FileIngressStagingService.class);
        backdropScanTaskService = mock(BackdropScanTaskService.class);
        rateLimitService = mock(RateLimitService.class);
        videoThumbnailExtractor = mock(BackdropVideoThumbnailExtractor.class);
        when(videoThumbnailExtractor.extractFirstFrame(any(), any(), any(), any()))
                .thenReturn(java.util.Optional.empty());

        when(runtimeConfigService.uploadRatePerHour()).thenReturn(20);
        when(runtimeConfigService.maxAssetsPerUser()).thenReturn(30);
        when(runtimeConfigService.maxImageBytes()).thenReturn(20 * 1024 * 1024);
        when(runtimeConfigService.maxVideoBytes()).thenReturn(64 * 1024 * 1024);
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(true);
        when(backdropAssetRepository.save(any())).thenAnswer(invocation -> {
            storedAsset.set(invocation.getArgument(0));
            return invocation.getArgument(0);
        });
        when(backdropAssetRepository.countByOwnerUserIdAndStatusNot(any(), any())).thenReturn(0L);
        when(fileQueryService.createDownloadUrl(any(), any())).thenAnswer(invocation -> new FileDownloadUrlDto(
                invocation.getArgument(1), "file", "https://signed/" + invocation.getArgument(1),
                Instant.now().plusSeconds(900)));

        service = new BackdropAssetService(
                backdropAssetRepository,
                runtimeConfigService,
                derivedAssetStorageService,
                fileQueryService,
                storageQuotaService,
                userStorageCommand,
                ingressStagingService,
                backdropScanTaskService,
                rateLimitService,
                videoThumbnailExtractor,
                afterCommitFiringTransactionManager()
        );
    }

    /**
     * 迷你事务管理器:注册同步器并在 commit 时触发 afterCommit,模拟真实提交语义。
     */
    private PlatformTransactionManager afterCommitFiringTransactionManager() {
        return new PlatformTransactionManager() {
            @Override
            public TransactionStatus getTransaction(TransactionDefinition definition) {
                if (!TransactionSynchronizationManager.isSynchronizationActive()) {
                    TransactionSynchronizationManager.initSynchronization();
                }
                return new SimpleTransactionStatus();
            }

            @Override
            public void commit(TransactionStatus status) {
                try {
                    TransactionSynchronizationUtils.triggerAfterCommit();
                } finally {
                    if (TransactionSynchronizationManager.isSynchronizationActive()) {
                        TransactionSynchronizationManager.clearSynchronization();
                    }
                }
            }

            @Override
            public void rollback(TransactionStatus status) {
                if (TransactionSynchronizationManager.isSynchronizationActive()) {
                    TransactionSynchronizationManager.clearSynchronization();
                }
            }
        };
    }

    @Test
    void uploadImageStagesAndDispatchesSecurityScan() throws IOException {
        stubFreshInsert();
        UUID ingressItemId = UUID.randomUUID();
        UUID scanTaskId = UUID.randomUUID();
        when(ingressStagingService.stage(any(), anyString(), any(UUID.class), anyString(), anyString(),
                any(java.nio.file.Path.class))).thenReturn(ingressItemId);
        when(backdropScanTaskService.enqueueScanTask(any(), any(UUID.class), any(UUID.class), anyString()))
                .thenReturn(scanTaskId);

        BackdropAssetDto dto = service.uploadAsset(OWNER_ID, pngUpload());

        assertThat(storedAsset.get().getStatus()).isEqualTo(BackdropAssetStatus.PROCESSING);
        assertThat(storedAsset.get().getFileNodeId()).isNull();
        assertThat(dto.status()).isEqualTo("PROCESSING");
        verify(storageQuotaService).reserve(eq(OWNER_ID), eq("BACKDROP_UPLOAD"), any(UUID.class),
                anyLong(), any(Instant.class));
        verify(storageQuotaService).extendReservation(eq("BACKDROP_UPLOAD"), any(UUID.class), any(Instant.class));
        verify(backdropScanTaskService).enqueueScanTask(eq(OWNER_ID), any(UUID.class), eq(ingressItemId), anyString());
        verify(derivedAssetStorageService, never()).store(any(), anyString(), any(), anyString(), anyString(),
                anyString(), any(java.nio.file.Path.class));
        verify(ingressStagingService, never()).markAvailable(any(), any());
    }

    @Test
    void duplicateReadyAssetReturnsExistingWithoutRestoring() throws IOException {
        BackdropAsset existing = readyAsset();
        when(backdropAssetRepository.findByOwnerUserIdAndSha256(any(), any()))
                .thenReturn(Optional.of(existing));

        BackdropAssetDto dto = service.uploadAsset(OWNER_ID, pngUpload());

        assertThat(dto.id()).isEqualTo(existing.getId());
        verify(derivedAssetStorageService, never()).store(any(), anyString(), any(), anyString(), anyString(),
                anyString(), any(java.nio.file.Path.class));
        verify(storageQuotaService, never()).reserve(any(), anyString(), any(), anyLong(), any(Instant.class));
        verify(ingressStagingService, never()).stage(any(), anyString(), any(), anyString(), anyString(),
                any(java.nio.file.Path.class));
    }

    @Test
    void duplicateFailedAssetIsRestagedForSecurityScan() throws IOException {
        BackdropAsset failed = readyAsset();
        failed.setStatus(BackdropAssetStatus.FAILED);
        failed.setFailReason("原始对象缺失，对账标记");
        UUID oldNodeId = failed.getFileNodeId();
        UUID ingressItemId = UUID.randomUUID();
        when(backdropAssetRepository.findByOwnerUserIdAndSha256(any(), any()))
                .thenReturn(Optional.of(failed));
        when(ingressStagingService.stage(any(), anyString(), any(UUID.class), anyString(), anyString(),
                any(java.nio.file.Path.class))).thenReturn(ingressItemId);
        when(backdropScanTaskService.enqueueScanTask(any(), any(UUID.class), any(UUID.class), anyString()))
                .thenReturn(UUID.randomUUID());

        BackdropAssetDto dto = service.uploadAsset(OWNER_ID, pngUpload());

        verify(derivedAssetStorageService).deleteOwned(OWNER_ID, oldNodeId);
        assertThat(failed.getStatus()).isEqualTo(BackdropAssetStatus.PROCESSING);
        assertThat(failed.getFailReason()).isNull();
        assertThat(failed.getFileNodeId()).isNull();
        assertThat(dto.status()).isEqualTo("PROCESSING");
    }

    @Test
    void countLimitExceededFailsFastBeforeReservation() throws IOException {
        when(backdropAssetRepository.countByOwnerUserIdAndStatusNot(any(), any())).thenReturn(30L);

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, pngUpload()))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8003));

        verify(storageQuotaService, never()).reserve(any(), anyString(), any(), anyLong(), any(Instant.class));
        verify(storageQuotaService, never()).releaseReservation(anyString(), any());
        verify(derivedAssetStorageService, never()).store(any(), anyString(), any(), anyString(), anyString(),
                anyString(), any(java.nio.file.Path.class));
    }

    @Test
    void stageFailureCompensatesRowAndReservation() throws IOException {
        stubFreshInsert();
        when(ingressStagingService.stage(any(), anyString(), any(UUID.class), anyString(), anyString(),
                any(java.nio.file.Path.class)))
                .thenThrow(new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "派生资源保存失败"));

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, pngUpload()))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(4001));

        verify(storageQuotaService).releaseReservation("BACKDROP_UPLOAD", storedAsset.get().getId());
        verify(backdropAssetRepository).delete(storedAsset.get());
        verify(backdropScanTaskService, never()).enqueueScanTask(any(), any(), any(), anyString());
    }

    @Test
    void unknownMagicIsRejected() {
        byte[] garbage = new byte[1024];
        garbage[0] = 0x00;
        garbage[1] = 0x11;

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID,
                        new MockMultipartFile("file", "wallpaper.png", "image/png", garbage)))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8002));
    }

    @Test
    void oversizedVideoIsRejected() {
        byte[] bigVideo = new byte[128 * 1024 * 1024];
        bigVideo[4] = 'f';
        bigVideo[5] = 't';
        bigVideo[6] = 'y';
        bigVideo[7] = 'p';
        when(runtimeConfigService.maxVideoBytes()).thenReturn(1024 * 1024);

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID,
                        new MockMultipartFile("file", "clip.mp4", "video/mp4", bigVideo)))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8004));
    }

    @Test
    void extensionMagicMismatchIsRejected() {
        byte[] fakePng = new byte[1024];
        fakePng[0] = (byte) 0x89;
        fakePng[1] = 0x50;
        fakePng[2] = 0x4E;
        fakePng[3] = 0x47;

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID,
                        new MockMultipartFile("file", "clip.mp4", "video/mp4", fakePng)))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8002));
    }

    @Test
    void rateLimitedUploadIsRejected() throws IOException {
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(false);

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, pngUpload()))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(429));
        verify(derivedAssetStorageService, never()).store(any(), anyString(), any(), anyString(), anyString(),
                anyString(), any(java.nio.file.Path.class));
        verify(ingressStagingService, never()).stage(any(), anyString(), any(), anyString(), anyString(),
                any(java.nio.file.Path.class));
    }

    @Test
    void deleteReadyAssetReleasesQuotaAndCleansDerivedAfterCommit() {
        BackdropAsset asset = readyAsset();
        when(backdropAssetRepository.findByIdAndOwnerUserId(asset.getId(), OWNER_ID))
                .thenReturn(Optional.of(asset));

        service.deleteAsset(OWNER_ID, asset.getId());

        verify(backdropAssetRepository).delete(asset);
        verify(userStorageCommand).decrementUsage(OWNER_ID, asset.getFileSize());
        verify(storageQuotaService, never()).releaseReservation(anyString(), any());
        verify(derivedAssetStorageService).deleteOwned(OWNER_ID, asset.getFileNodeId());
        verify(derivedAssetStorageService).deleteOwned(OWNER_ID, asset.getThumbFileId());
    }

    @Test
    void deleteProcessingAssetReleasesReservationInsteadOfUsage() {
        BackdropAsset asset = readyAsset();
        asset.setStatus(BackdropAssetStatus.PROCESSING);
        when(backdropAssetRepository.findByIdAndOwnerUserId(asset.getId(), OWNER_ID))
                .thenReturn(Optional.of(asset));

        service.deleteAsset(OWNER_ID, asset.getId());

        verify(storageQuotaService).releaseReservation("BACKDROP_UPLOAD", asset.getId());
        verify(userStorageCommand, never()).decrementUsage(any(), anyLong());
    }

    @Test
    void deleteForeignOrMissingAssetReturnsNotFound() {
        when(backdropAssetRepository.findByIdAndOwnerUserId(any(), any())).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.deleteAsset(OWNER_ID, UUID.randomUUID()))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8001));
    }

    @Test
    void deleteAllAssetsRemovesEveryOwnedAsset() {
        BackdropAsset first = readyAsset();
        BackdropAsset second = readyAsset();
        when(backdropAssetRepository.findByOwnerUserIdOrderByUpdatedAtDesc(OWNER_ID))
                .thenReturn(List.of(first, second));
        when(backdropAssetRepository.findByIdAndOwnerUserId(first.getId(), OWNER_ID))
                .thenReturn(Optional.of(first));
        when(backdropAssetRepository.findByIdAndOwnerUserId(second.getId(), OWNER_ID))
                .thenReturn(Optional.of(second));

        BackdropAssetService.DeleteAllResult result = service.deleteAllAssets(OWNER_ID);

        assertThat(result.deleted()).isEqualTo(2);
        assertThat(result.failed()).isZero();
        verify(backdropAssetRepository).delete(first);
        verify(backdropAssetRepository).delete(second);
        verify(userStorageCommand, org.mockito.Mockito.times(2))
                .decrementUsage(eq(OWNER_ID), anyLong());
    }

    @Test
    void completeStagedAssetPublishesAndMarksAvailable() throws IOException {
        BackdropAsset processing = readyAsset();
        processing.setStatus(BackdropAssetStatus.PROCESSING);
        processing.setFileNodeId(null);
        processing.setThumbFileId(null);
        UUID ingressItemId = UUID.randomUUID();
        UUID publishedNodeId = UUID.randomUUID();
        UUID thumbFileId = UUID.randomUUID();
        java.nio.file.Path tempFile = java.nio.file.Files.createTempFile("staged-test", ".png");
        java.nio.file.Files.write(tempFile, pngBytes());
        when(ingressStagingService.copyToTempFile(ingressItemId)).thenReturn(tempFile);
        when(backdropAssetRepository.findById(processing.getId()))
                .thenReturn(Optional.of(processing));
        when(derivedAssetStorageService.store(
                eq(OWNER_ID), anyString(), eq(processing.getId()), anyString(), anyString(), anyString(),
                any(java.nio.file.Path.class)))
                .thenReturn(publishedNodeId, thumbFileId);

        service.completeStagedAsset(OWNER_ID, processing.getId(), ingressItemId, "original.png");

        assertThat(processing.getStatus()).isEqualTo(BackdropAssetStatus.READY);
        assertThat(processing.getFileNodeId()).isEqualTo(publishedNodeId);
        assertThat(processing.getThumbFileId()).isEqualTo(thumbFileId);
        verify(storageQuotaService).settleReservation("BACKDROP_UPLOAD", processing.getId(), 1024L);
        verify(ingressStagingService).markAvailable(ingressItemId, publishedNodeId);
        verify(derivedAssetStorageService, never()).deleteOwned(any(), any());
    }

    @Test
    void completeStagedAssetFailureMarksFailedAndReleasesReservation() throws IOException {
        BackdropAsset processing = readyAsset();
        processing.setStatus(BackdropAssetStatus.PROCESSING);
        processing.setFileNodeId(null);
        UUID ingressItemId = UUID.randomUUID();
        java.nio.file.Path tempFile = java.nio.file.Files.createTempFile("staged-test", ".png");
        java.nio.file.Files.write(tempFile, pngBytes());
        when(ingressStagingService.copyToTempFile(ingressItemId)).thenReturn(tempFile);
        when(backdropAssetRepository.findById(processing.getId()))
                .thenReturn(Optional.of(processing));
        when(derivedAssetStorageService.store(
                eq(OWNER_ID), anyString(), eq(processing.getId()), anyString(), anyString(), anyString(),
                any(java.nio.file.Path.class)))
                .thenThrow(new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "派生资源保存失败"));

        assertThatThrownBy(() -> service.completeStagedAsset(
                OWNER_ID, processing.getId(), ingressItemId, "original.png"))
                .isInstanceOf(BusinessException.class);

        assertThat(processing.getStatus()).isEqualTo(BackdropAssetStatus.FAILED);
        assertThat(processing.getFileNodeId()).isNull();
        verify(storageQuotaService).releaseReservation("BACKDROP_UPLOAD", processing.getId());
        verify(ingressStagingService, never()).markAvailable(any(), any());
    }

    private UUID stubFreshInsert() {
        when(backdropAssetRepository.findById(any(UUID.class))).thenAnswer(
                invocation -> Optional.ofNullable(storedAsset.get()));
        when(backdropAssetRepository.findByOwnerUserIdAndSha256(any(), any())).thenReturn(Optional.empty());
        return UUID.randomUUID();
    }

    private BackdropAsset readyAsset() {
        BackdropAsset asset = new BackdropAsset();
        asset.setId(UUID.randomUUID());
        asset.setOwnerUserId(OWNER_ID);
        asset.setTitle("mock");
        asset.setMediaType(com.omninest.modules.backdrop.domain.BackdropMediaType.IMAGE);
        asset.setFileNodeId(UUID.randomUUID());
        asset.setThumbFileId(UUID.randomUUID());
        asset.setFileSize(1024);
        asset.setSha256("mock-sha");
        asset.setStatus(BackdropAssetStatus.READY);
        asset.setCreatedAt(Instant.now());
        asset.setUpdatedAt(Instant.now());
        return asset;
    }

    private MockMultipartFile pngUpload() throws IOException {
        return new MockMultipartFile("file", "wallpaper.png", "image/png", pngBytes());
    }

    private byte[] pngBytes() throws IOException {
        java.awt.image.BufferedImage image =
                new java.awt.image.BufferedImage(8, 8, java.awt.image.BufferedImage.TYPE_INT_RGB);
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        ImageIO.write(image, "png", output);
        return output.toByteArray();
    }
}
