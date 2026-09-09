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
import com.omninest.common.security.MalwareScanGateway;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.backdrop.config.BackdropRuntimeConfigService;
import com.omninest.modules.backdrop.domain.BackdropAsset;
import com.omninest.modules.backdrop.domain.BackdropAssetStatus;
import com.omninest.modules.backdrop.dto.BackdropDtos.BackdropAssetDto;
import com.omninest.modules.backdrop.repository.BackdropAssetRepository;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.DerivedAssetStorageService;
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
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionSynchronizationUtils;

/**
 * 以 mock 依赖驱动背景素材上传/删除链路,覆盖方案 B2 的校验、去重、配额与补偿语义。
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
    private MalwareScanGateway malwareScanGateway;
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
        malwareScanGateway = mock(MalwareScanGateway.class);
        rateLimitService = mock(RateLimitService.class);
        videoThumbnailExtractor = mock(BackdropVideoThumbnailExtractor.class);
        when(videoThumbnailExtractor.extractFirstFrame(any(), any(), any(), any()))
                .thenReturn(java.util.Optional.empty());

        when(runtimeConfigService.uploadRatePerHour()).thenReturn(20);
        when(runtimeConfigService.maxAssetsPerUser()).thenReturn(30);
        when(runtimeConfigService.maxImageBytes()).thenReturn(20 * 1024 * 1024);
        when(runtimeConfigService.maxVideoBytes()).thenReturn(64 * 1024 * 1024);
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(true);
        when(malwareScanGateway.scan(any(java.nio.file.Path.class)))
                .thenReturn(MalwareScanGateway.ScanResult.clean());
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
                malwareScanGateway,
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
    void uploadImageCompletesWholePipeline() throws IOException {
        stubFreshInsert();
        UUID fileNodeId = UUID.randomUUID();
        UUID thumbFileId = UUID.randomUUID();
        when(derivedAssetStorageService.store(
                eq(OWNER_ID), anyString(), any(UUID.class), anyString(), anyString(), anyString(),
                any(java.nio.file.Path.class)))
                .thenReturn(fileNodeId, thumbFileId);

        BackdropAssetDto dto = service.uploadAsset(OWNER_ID, pngUpload());

        assertThat(storedAsset.get().getStatus()).isEqualTo(BackdropAssetStatus.READY);
        assertThat(storedAsset.get().getFileNodeId()).isEqualTo(fileNodeId);
        assertThat(storedAsset.get().getThumbFileId()).isEqualTo(thumbFileId);
        assertThat(dto.status()).isEqualTo("READY");
        assertThat(dto.contentUrl()).contains(fileNodeId.toString());
        assertThat(dto.thumbUrl()).contains(thumbFileId.toString());
        verify(storageQuotaService).reserve(eq(OWNER_ID), eq("BACKDROP_UPLOAD"), any(UUID.class),
                anyLong(), any(Instant.class));
        verify(storageQuotaService).settleReservation(eq("BACKDROP_UPLOAD"), any(UUID.class),
                eq(pngUpload().getSize()));
        verify(derivedAssetStorageService, never()).deleteOwned(any(), any());
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
    }

    @Test
    void duplicateFailedAssetIsRebuiltToReady() throws IOException {
        BackdropAsset failed = readyAsset();
        failed.setStatus(BackdropAssetStatus.FAILED);
        failed.setFailReason("原始对象缺失，对账标记");
        UUID oldNodeId = failed.getFileNodeId();
        when(backdropAssetRepository.findByOwnerUserIdAndSha256(any(), any()))
                .thenReturn(Optional.of(failed));
        when(derivedAssetStorageService.store(
                eq(OWNER_ID), anyString(), eq(failed.getId()), anyString(), anyString(), anyString(),
                any(java.nio.file.Path.class)))
                .thenReturn(UUID.randomUUID());

        BackdropAssetDto dto = service.uploadAsset(OWNER_ID, pngUpload());

        verify(derivedAssetStorageService).deleteOwned(OWNER_ID, oldNodeId);
        assertThat(dto.status()).isEqualTo("READY");
        assertThat(failed.getFailReason()).isNull();
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
    void storeFailureCompensatesRowAndReservation() throws IOException {
        stubFreshInsert();
        when(derivedAssetStorageService.store(
                eq(OWNER_ID), anyString(), any(), anyString(), anyString(), anyString(),
                any(java.nio.file.Path.class)))
                .thenThrow(new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "派生资源保存失败"));

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, pngUpload()))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(4001));

        verify(storageQuotaService).releaseReservation("BACKDROP_UPLOAD", storedAsset.get().getId());
        verify(backdropAssetRepository).delete(storedAsset.get());
    }

    @Test
    void thumbnailStoreFailureCompensatesRowAndReservation() throws IOException {
        stubFreshInsert();
        when(derivedAssetStorageService.store(
                eq(OWNER_ID), anyString(), any(UUID.class), anyString(), anyString(), anyString(),
                any(java.nio.file.Path.class)))
                .thenReturn(UUID.randomUUID())
                .thenThrow(new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "派生资源保存失败"));

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, pngUpload()))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(4001));

        verify(storageQuotaService).releaseReservation(eq("BACKDROP_UPLOAD"), any());
        verify(backdropAssetRepository).delete(any(BackdropAsset.class));
        verify(derivedAssetStorageService).deleteOwned(eq(OWNER_ID), any(UUID.class));
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
    void malwareInfectedIsRejectedWithDistinctCode() throws IOException {
        stubFreshInsert();
        when(malwareScanGateway.scan(any(java.nio.file.Path.class)))
                .thenReturn(MalwareScanGateway.ScanResult.infected("EICAR"));

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, pngUpload()))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8006));
        verify(derivedAssetStorageService, never()).store(any(), anyString(), any(), anyString(), anyString(),
                anyString(), any(java.nio.file.Path.class));
    }

    @Test
    void scanUnavailableFailsClosed() throws IOException {
        stubFreshInsert();
        when(malwareScanGateway.scan(any(java.nio.file.Path.class)))
                .thenReturn(MalwareScanGateway.ScanResult.error("clamav down"));

        assertThatThrownBy(() -> service.uploadAsset(OWNER_ID, pngUpload()))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode().getCode()).isEqualTo(8005));
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

        int deleted = service.deleteAllAssets(OWNER_ID);

        assertThat(deleted).isEqualTo(2);
        verify(backdropAssetRepository).delete(first);
        verify(backdropAssetRepository).delete(second);
        verify(userStorageCommand, org.mockito.Mockito.times(2))
                .decrementUsage(eq(OWNER_ID), anyLong());
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
